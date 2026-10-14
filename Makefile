.PHONY: dashboard dashboard-dev up create destroy reset status verify review check-host \
	stop down halt shutdown \
	stretch stretch-ips stretch-vpn stretch-monitor help \
	app-deploy app-verify lb-algorithm \
	backup-now backup-restore backup-list sync-aiwin tunnels \
	alchemy rollback setup-gitea-ci verify-gitea-ci apt-upgrade apt-upgrade-bg

# Default: show help with dashboard first
help:
	@echo "Automation-VMs"
	@echo ""
	@echo "  make dashboard          Start lab dashboard UI"
	@echo "  make dashboard-dev      Dashboard in dev mode (API + Vite HMR)"
	@echo "  make check-host         Safety check: can this machine create VMs?"
	@echo "  make alchemy            One-click: 6 VMs + Ansible + Jenkins + deploy"
	@echo "  make apt-upgrade        apt update && upgrade on every VM (after alchemy)"
	@echo "  make apt-upgrade-bg     Same upgrade, detached; log in logs/apt-upgrade.log"
	@echo "  make up | make create   Safety check, then create and provision all VMs"
	@echo "  make stop | down | halt | shutdown   Power off VMs (+ dashboard); disks kept"
	@echo "  make destroy            Destroy all VMs (wipe)"
	@echo "  make reset              Destroy then create (includes safety check)"
	@echo "  make status             Vagrant status + ping/SSH"
	@echo "  make verify             Run review checks (tests/)"
	@echo "  make review             Pretty reviewer output"
	@echo ""
	@echo "  Application:"
	@echo "  make app-deploy         Insight path: docker save|load deploy (no registry)"
	@echo "  make app-verify         Check LB, frontend, /api/metrics, web alternation"
	@echo "  make rollback           Alchemy path: redeploy last-known-good tags"
	@echo "  make lb-algorithm ALG=weighted|least_conn|resource"
	@echo "  make backup-now         Run a full backup to the backup VM"
	@echo "  make backup-list        List weekly snapshots on backup (as devops)"
	@echo "  make backup-restore     Dry-run restore (nothing written unless APPLY=1; WITH_ETC=1 for /etc)"
	@echo "  make sync-aiwin         Optional rsync (legacy); prefer git push → webhook"
	@echo "  make tunnels            Laptop SSH tunnels: app + dashboard + Jenkins (+ extras)"
	@echo "  make setup-gitea-ci     Print Git deploy-key / webhook setup checklist"
	@echo "  make verify-gitea-ci    Check Git/Jenkins wiring readiness (+ optional live probes)"
	@echo ""
	@echo "  Stretch extras (opt-in — do not change default provision):"
	@echo "  make stretch-ips        Fail2Ban on all VMs"
	@echo "  make stretch-vpn        WireGuard hub-spoke overlay (10.66.0.0/24)"
	@echo "  make stretch-monitor    Netdata on all VMs (:19999, lab net only)"
	@echo "  make stretch            Run all three stretch targets"

dashboard:
	@./scripts/ensure-dashboard-host.sh
	@./scripts/ensure-dashboard-deps.sh
	@cd dashboard && npm_config_update_notifier=false npm run build && npm_config_update_notifier=false npm start

dashboard-dev:
	@./scripts/ensure-dashboard-host.sh
	@./scripts/ensure-dashboard-deps.sh
	@cd dashboard && npm_config_update_notifier=false npm run dev

check-host:
	./scripts/check-host.sh

up create:
	./scripts/create.sh

stop down halt shutdown:
	./scripts/stop.sh

destroy:
	./scripts/destroy.sh

reset:
	./scripts/reset.sh

status:
	./scripts/status.sh

verify:
	./scripts/verify.sh

review:
	./scripts/review.sh

app-deploy:
	./scripts/app-deploy.sh

app-verify:
	./scripts/app-verify.sh

alchemy:
	./scripts/alchemy.sh

apt-upgrade:
	./scripts/apt-upgrade-guests.sh

apt-upgrade-bg:
	./scripts/apt-upgrade-guests.sh --background

rollback:
	./scripts/rollback.sh

lb-algorithm:
	./scripts/lb-algorithm.sh $(ALG)

backup-now:
	./scripts/backup-now.sh

backup-list:
	./scripts/backup-list-host.sh

backup-restore:
	@flags=""; \
	  if [ "$(APPLY)" = "1" ]; then flags="$$flags --apply"; fi; \
	  if [ "$(WITH_ETC)" = "1" ]; then flags="$$flags --with-etc"; fi; \
	  ./scripts/backup-restore-host.sh $$flags

sync-aiwin:
	./scripts/sync-aiwin.sh

# From laptop: keep terminal open. Host: SYNC_HOST=labhost (default). Extras on by default.
# Core only: TUNNELS_EXTRA=0 make tunnels
tunnels:
	./scripts/tunnels-laptop.sh

setup-gitea-ci:
	./scripts/setup-gitea-ci.sh

verify-gitea-ci:
	./scripts/verify-gitea-ci.sh

stretch-ips:
	./scripts/stretch-ips.sh

stretch-vpn:
	./scripts/stretch-vpn.sh

stretch-monitor:
	./scripts/stretch-monitor.sh

stretch:
	./scripts/stretch.sh
