import fs from 'node:fs';
import path from 'node:path';

export function readEnvFile(envPath) {
  const env = { ...process.env };
  if (!fs.existsSync(envPath)) return env;
  const lines = fs.readFileSync(envPath, 'utf8').split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eq = trimmed.indexOf('=');
    if (eq === -1) continue;
    const key = trimmed.slice(0, eq).trim();
    let value = trimmed.slice(eq + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    env[key] = value;
  }
  return env;
}

export function repoRootFromScript() {
  return path.resolve(path.dirname(new URL(import.meta.url).pathname), '../..');
}

export function loadDeployment(root, env) {
  const projectDir = env.NTT_PROJECT_DIR || 'ntt';
  const deploymentPath = path.join(root, projectDir, 'deployment.json');
  if (!fs.existsSync(deploymentPath)) {
    throw new Error(`Missing deployment file: ${deploymentPath}`);
  }
  return JSON.parse(fs.readFileSync(deploymentPath, 'utf8'));
}

export function chainConfig(deployment, chainName) {
  return deployment?.chains?.[chainName] || null;
}

export function transceiverAddress(chain) {
  const transceivers = chain?.transceivers;
  if (!transceivers) return '';
  if (transceivers.wormhole?.address) return transceivers.wormhole.address;
  for (const value of Object.values(transceivers)) {
    if (value && typeof value === 'object' && 'address' in value) return value.address;
  }
  return '';
}

export function fail(message) {
  console.error(message);
  process.exit(1);
}
