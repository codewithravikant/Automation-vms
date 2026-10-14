import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import YAML from "yaml";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
export const ROOT = path.resolve(__dirname, "../..");
export const INFRA_DIR = path.join(ROOT, "infrastructure");
export const KEYS_DIR = path.join(ROOT, "keys");
export const PRIVATE_KEY = path.join(KEYS_DIR, "id_ed25519");
export const MACHINES_YML = path.join(INFRA_DIR, "machines.yml");

const ROLE_LABELS = {
  loadbalancer: "Load balancer",
  web1: "Web server",
  web2: "Web server",
  appserver: "Application",
  backup: "Backup",
  cicd: "CI/CD",
};

/** VMs that expose browser HTTP on the private network (host can open / tunnel). */
const HTTP_PORTS = {
  loadbalancer: 80,
  cicd: 8080,
};

export const MEMORY_OPTIONS = [256, 512, 768, 1024, 1536, 2048, 3072, 4096];
export const CPU_OPTIONS = [1, 2, 3, 4];

export function loadMachinesDoc() {
  const raw = fs.readFileSync(MACHINES_YML, "utf8");
  return YAML.parse(raw);
}

export function loadMachines() {
  const doc = loadMachinesDoc();
  const entries = doc.machines || {};
  return Object.entries(entries).map(([name, cfg]) => ({
    name,
    ip: cfg.ip,
    memory: cfg.memory,
    cpus: cfg.cpus,
    role: ROLE_LABELS[name] || "Server",
    httpPort: HTTP_PORTS[name] || null,
  }));
}

export function getMachine(name) {
  return loadMachines().find((m) => m.name === name) || null;
}

export function hasPrivateKey() {
  return fs.existsSync(PRIVATE_KEY);
}

/**
 * Persist CPU/RAM into infrastructure/machines.yml (Vagrant source of truth).
 * Vagrantfile already reads vb.memory / vb.cpus from this file.
 */
export function updateMachineResources(name, { memory, cpus }) {
  if (!/^[a-zA-Z0-9_-]+$/.test(name)) {
    throw new Error("Invalid machine name");
  }

  const doc = loadMachinesDoc();
  if (!doc.machines?.[name]) {
    throw new Error(`Unknown machine: ${name}`);
  }

  const nextMemory =
    memory === undefined ? doc.machines[name].memory : Number(memory);
  const nextCpus = cpus === undefined ? doc.machines[name].cpus : Number(cpus);

  if (!Number.isInteger(nextMemory) || !MEMORY_OPTIONS.includes(nextMemory)) {
    throw new Error(
      `Invalid memory. Allowed: ${MEMORY_OPTIONS.join(", ")} MB`
    );
  }
  if (!Number.isInteger(nextCpus) || !CPU_OPTIONS.includes(nextCpus)) {
    throw new Error(`Invalid cpus. Allowed: ${CPU_OPTIONS.join(", ")}`);
  }

  doc.machines[name].memory = nextMemory;
  doc.machines[name].cpus = nextCpus;

  const yaml = YAML.stringify(doc, {
    indent: 2,
    lineWidth: 0,
    defaultKeyType: "PLAIN",
    defaultStringType: "PLAIN",
  });
  // Keep a short header comment so the file stays self-documenting
  const header =
    "# VM definitions — source of truth for hostnames, IPs, and resources\n";
  const body = yaml.replace(
    /^# VM definitions[^\n]*\n?/m,
    ""
  );
  fs.writeFileSync(MACHINES_YML, header + body, "utf8");

  return {
    name,
    memory: nextMemory,
    cpus: nextCpus,
    path: MACHINES_YML,
  };
}
