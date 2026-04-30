#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const checks = [];
const add = (name, ok, detail = '') => checks.push({ name, ok, detail });
const exists = (p) => fs.existsSync(path.join(root, p));
const read = (p) => fs.readFileSync(path.join(root, p), 'utf8');

add('Root README exists', exists('README.md'));
add('.env.template exists', exists('.env.template'));
add('Contract exists', exists('packages/contracts/src/GoldBridgeToken.sol'));
add('Web app exists', exists('apps/web/src/App.tsx'));
add('NTT scripts exist', exists('scripts/05-add-solana-locking.sh') && exists('scripts/06-add-base-burning.sh'));

if (exists('packages/contracts/src/GoldBridgeToken.sol')) {
  const c = read('packages/contracts/src/GoldBridgeToken.sol');
  add('Solidity pragma is 0.8.34', c.includes('pragma solidity 0.8.34;'));
  add('Contract has mint', /function\s+mint\s*\(/.test(c));
  add('Contract has burn', /function\s+burn\s*\(/.test(c));
  add('Contract has setMinter', /function\s+setMinter\s*\(/.test(c));
  add('Contract has onlyMinter guard', c.includes('onlyMinter'));
  add('Contract fixes GOLD decimals at 9', /uint8\s+public\s+constant\s+GOLD_DECIMALS\s*=\s*9\s*;/.test(c));
}

if (exists('packages/contracts/foundry.toml')) {
  const f = read('packages/contracts/foundry.toml');
  add('Foundry solc_version is 0.8.34', f.includes('solc_version = "0.8.34"'));
}

if (exists('scripts/05-add-solana-locking.sh')) {
  const s = read('scripts/05-add-solana-locking.sh');
  add('Solana add-chain uses locking mode', s.includes('--mode locking'));
}

if (exists('scripts/06-add-base-burning.sh')) {
  const s = read('scripts/06-add-base-burning.sh');
  add('Base add-chain uses burning mode', s.includes('--mode burning'));
}

let failures = 0;
for (const check of checks) {
  const mark = check.ok ? 'ok' : 'fail';
  console.log(`${mark}: ${check.name}${check.detail ? ` - ${check.detail}` : ''}`);
  if (!check.ok) failures += 1;
}

if (failures > 0) {
  console.error(`${failures} static review checks failed.`);
  process.exit(1);
}
console.log('Static review checks passed.');
