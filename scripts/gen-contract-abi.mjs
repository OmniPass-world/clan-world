#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '..');
const artifactPath = path.join(repoRoot, 'packages/contracts/out/IClanWorld.sol/IClanWorld.json');
const targetPath = path.join(repoRoot, 'packages/contracts/abi/IClanWorld.json');

if (!fs.existsSync(artifactPath)) {
  throw new Error(`Missing ${path.relative(repoRoot, artifactPath)}. Run forge build first.`);
}

const artifact = JSON.parse(fs.readFileSync(artifactPath, 'utf8'));
if (!Array.isArray(artifact.abi)) {
  throw new Error(`${path.relative(repoRoot, artifactPath)} must contain an "abi" array`);
}

fs.mkdirSync(path.dirname(targetPath), { recursive: true });
fs.writeFileSync(targetPath, `${JSON.stringify({ abi: artifact.abi }, null, 2)}\n`);

console.log(`Updated ${path.relative(repoRoot, targetPath)} from ${path.relative(repoRoot, artifactPath)}.`);
