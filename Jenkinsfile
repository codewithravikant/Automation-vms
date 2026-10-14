// Automation-VMs — CI/CD pipeline (Git webhook + path routing)
// Job is Pipeline-from-SCM; workspace root is the repo checkout.
//
// Path routing (locked):
//   docs-only     → skip
//   app/ only     → lint/tests/audit/build/push/Trivy → SSH host → ansible deploy.yml + app-verify
//   automation/   → SSH host → make alchemy  (also when mixed with app/)
//   first commit  → make alchemy
// Insight-only make app-deploy (ii-* save|load) stays for non-CI demos — not used here.

pipeline {
  agent any

  parameters {
    booleanParam(
      name: 'FORCE_APP',
      defaultValue: false,
      description: 'Force app deploy path even if path detect says skip'
    )
    booleanParam(
      name: 'FORCE_INFRA',
      defaultValue: false,
      description: 'Force make alchemy on VirtualBox host'
    )
  }

  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  // Triggers: Git forge webhook (instant) + SCM poll every minute (backup if webhook misses).
  // Slack plugin: bot token credential slack-bot-token → #jenkins-builds (optional if unset).
  triggers {
    pollSCM('* * * * *')
    GenericTrigger(
      genericVariables: [
        [key: 'ref', value: '$.ref']
      ],
      causeString: 'Git push webhook',
      tokenCredentialId: 'gitea-webhook-token',
      printContributedVariables: true,
      printPostContent: false,
      silentResponse: true,
      regexpFilterText: '$ref',
      regexpFilterExpression: 'refs/heads/(main|master)'
    )
  }

  environment {
    PROJECT_ROOT = '/opt/automation-alchemy'
    REGISTRY     = '10.10.0.40:5000'
    BACKEND_IMG  = 'aa-backend'
    FRONTEND_IMG = 'aa-frontend'
    LB_URL       = 'http://10.10.0.10/'
    ANSIBLE_DIR  = '/opt/automation-alchemy/automation'
    SSH_IDENTITY = '/var/lib/jenkins/.ssh/id_ed25519'
    AIWIN_SSH_HOST = "${env.AIWIN_SSH_HOST ?: '10.10.0.1'}"
    AIWIN_SSH_USER = "${env.AIWIN_SSH_USER ?: 'labuser'}"
    AIWIN_SSH_PORT = "${env.AIWIN_SSH_PORT ?: '22'}"
    AIWIN_PROJECT  = "${env.AIWIN_PROJECT ?: '~/automation-vms'}"
    // cicd often has broken IPv6; npm then fails audit with empty "reason: undefined"
    NODE_OPTIONS = '--dns-result-order=ipv4first'
  }

  stages {
    stage('Resolve tag') {
      steps {
        sh '''#!/usr/bin/env bash
          set -euo pipefail
          git rev-parse --short HEAD > "${WORKSPACE}/GIT_SHA"
          echo "Building tag $(cat "${WORKSPACE}/GIT_SHA")"
        '''
        script {
          env.IMAGE_TAG = readFile("${env.WORKSPACE}/GIT_SHA").trim()
        }
      }
    }

    stage('Detect path changes') {
      steps {
        script {
          if (params.FORCE_INFRA) {
            env.DEPLOY_MODE = 'infra'
          } else if (params.FORCE_APP) {
            env.DEPLOY_MODE = 'app'
          } else {
            env.DEPLOY_MODE = sh(
              script: 'bash ./scripts/classify-git-changes.sh',
              returnStdout: true
            ).trim()
          }
          echo "DEPLOY_MODE=${env.DEPLOY_MODE}"
          currentBuild.description = "mode=${env.DEPLOY_MODE} tag=${env.IMAGE_TAG}"
          if (env.DEPLOY_MODE == 'skip') {
            currentBuild.result = 'SUCCESS'
          }
        }
      }
    }

    stage('Quality') {
      when { environment name: 'DEPLOY_MODE', value: 'app' }
      steps {
        dir('app/backend') {
          sh '''#!/usr/bin/env bash
            set -euo pipefail
            npm install --ignore-scripts
            npm run lint
          '''
        }
        dir('app/frontend') {
          sh '''#!/usr/bin/env bash
            set -euo pipefail
            npm install --ignore-scripts
            npm run lint
          '''
        }
      }
    }

    stage('Tests') {
      when { environment name: 'DEPLOY_MODE', value: 'app' }
      steps {
        dir('app/backend') {
          sh 'npm test --if-present'
        }
        dir('app/frontend') {
          sh 'npm test --if-present'
        }
      }
    }

    stage('Security') {
      when { environment name: 'DEPLOY_MODE', value: 'app' }
      steps {
        dir('app/backend') {
          sh '''#!/usr/bin/env bash
            set -euo pipefail
            attempt=1
            until npm audit --audit-level=high; do
              if [[ "${attempt}" -ge 3 ]]; then
                echo "npm audit failed after ${attempt} attempts (registry/network)." >&2
                exit 1
              fi
              echo "npm audit attempt ${attempt} failed; retrying..." >&2
              attempt=$((attempt + 1))
              sleep 2
            done
          '''
        }
        dir('app/frontend') {
          sh '''#!/usr/bin/env bash
            set -euo pipefail
            attempt=1
            until npm audit --audit-level=high; do
              if [[ "${attempt}" -ge 3 ]]; then
                echo "npm audit failed after ${attempt} attempts (registry/network)." >&2
                exit 1
              fi
              echo "npm audit attempt ${attempt} failed; retrying..." >&2
              attempt=$((attempt + 1))
              sleep 2
            done
          '''
        }
      }
    }

    stage('Build & Push') {
      when { environment name: 'DEPLOY_MODE', value: 'app' }
      steps {
        sh '''#!/usr/bin/env bash
          set -euo pipefail
          TAG="${IMAGE_TAG}"
          docker build -t "${REGISTRY}/${BACKEND_IMG}:${TAG}" -t "${REGISTRY}/${BACKEND_IMG}:latest" \
            "${WORKSPACE}/app/backend"
          docker build -t "${REGISTRY}/${FRONTEND_IMG}:${TAG}" -t "${REGISTRY}/${FRONTEND_IMG}:latest" \
            "${WORKSPACE}/app/frontend"
          docker push "${REGISTRY}/${BACKEND_IMG}:${TAG}"
          docker push "${REGISTRY}/${BACKEND_IMG}:latest"
          docker push "${REGISTRY}/${FRONTEND_IMG}:${TAG}"
          docker push "${REGISTRY}/${FRONTEND_IMG}:latest"
        '''
      }
    }

    stage('Image scan') {
      when { environment name: 'DEPLOY_MODE', value: 'app' }
      steps {
        sh '''#!/usr/bin/env bash
          set -euo pipefail
          if ! command -v trivy >/dev/null 2>&1; then
            echo "ERROR: Trivy not installed on cicd (re-run ansible cicd.yml)" >&2
            exit 1
          fi
          trivy image --exit-code 1 --severity HIGH,CRITICAL \
            "${REGISTRY}/${BACKEND_IMG}:${IMAGE_TAG}"
          trivy image --exit-code 1 --severity HIGH,CRITICAL \
            "${REGISTRY}/${FRONTEND_IMG}:${IMAGE_TAG}"
        '''
      }
    }

    stage('Deploy app on aiwin') {
      when { environment name: 'DEPLOY_MODE', value: 'app' }
      steps {
        sh '''#!/usr/bin/env bash
          set -euo pipefail
          chmod +x ./scripts/jenkins-remote-make.sh
          export DEPLOY_MODE=app
          export IMAGE_TAG
          export AIWIN_SSH_HOST AIWIN_SSH_USER AIWIN_SSH_PORT AIWIN_PROJECT SSH_IDENTITY
          bash ./scripts/jenkins-remote-make.sh
        '''
      }
    }

    stage('Infra on aiwin (make alchemy)') {
      when { environment name: 'DEPLOY_MODE', value: 'infra' }
      steps {
        sh '''#!/usr/bin/env bash
          set -euo pipefail
          chmod +x ./scripts/jenkins-remote-make.sh
          export DEPLOY_MODE=infra
          export AIWIN_SSH_HOST AIWIN_SSH_USER AIWIN_SSH_PORT AIWIN_PROJECT SSH_IDENTITY
          bash ./scripts/jenkins-remote-make.sh
        '''
      }
    }

    stage('Smoke') {
      when { environment name: 'DEPLOY_MODE', value: 'app' }
      steps {
        sh '''#!/usr/bin/env bash
          set -euo pipefail
          bash "${PROJECT_ROOT}/scripts/app-verify.sh"
        '''
      }
    }

    stage('Performance') {
      when { environment name: 'DEPLOY_MODE', value: 'app' }
      steps {
        sh '''#!/usr/bin/env bash
          set -euo pipefail
          bash "${PROJECT_ROOT}/scripts/perf-check.sh" "${LB_URL}"
        '''
      }
    }
  }

  post {
    failure {
      sh '''#!/usr/bin/env bash
        set -euo pipefail
        if [[ "${DEPLOY_MODE:-skip}" == "app" ]]; then
          echo "App deploy/smoke failed — attempting rollback"
          cd "${ANSIBLE_DIR}"
          export ANSIBLE_PRIVATE_KEY_FILE="${SSH_IDENTITY}"
          if [[ ! -f "${ANSIBLE_PRIVATE_KEY_FILE}" ]]; then
            ANSIBLE_PRIVATE_KEY_FILE=/opt/automation-alchemy/keys/id_ed25519
          fi
          ansible-playbook playbooks/rollback.yml --private-key "${ANSIBLE_PRIVATE_KEY_FILE}" || true
        fi
      '''
      sh '''#!/usr/bin/env bash
        set +e
        bash ./scripts/notify-build-result.sh FAILURE \
          || bash "${PROJECT_ROOT}/scripts/notify-build-result.sh" FAILURE \
          || true
      '''
    }
    aborted {
      sh '''#!/usr/bin/env bash
        set +e
        bash ./scripts/notify-build-result.sh ABORTED \
          || bash "${PROJECT_ROOT}/scripts/notify-build-result.sh" ABORTED \
          || true
      '''
    }
    success {
      sh '''#!/usr/bin/env bash
        set +e
        bash ./scripts/notify-build-result.sh SUCCESS \
          || bash "${PROJECT_ROOT}/scripts/notify-build-result.sh" SUCCESS \
          || true
      '''
    }
  }
}
