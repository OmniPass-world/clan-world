import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(scriptDir, '../../..');
const canonicalAbiPath = resolve(repoRoot, 'packages/contracts/abi/IClanWorld.json');
const chainClientPath = resolve(repoRoot, 'packages/shared/src/adapters/IChainClient.ts');

const abiJson = JSON.parse(readFileSync(canonicalAbiPath, 'utf8'));
const abi = abiJson.abi ?? abiJson;
const chainClientSource = readFileSync(chainClientPath, 'utf8');

function findFunction(name) {
  const fn = abi.find(item => item.type === 'function' && item.name === name);
  if (!fn) throw new Error(`canonical ABI missing function ${name}`);
  return fn;
}

function namedComponents(tuple) {
  if (!Array.isArray(tuple.components)) throw new Error(`ABI tuple ${tuple.name ?? '<anonymous>'} has no components`);
  return tuple.components.map(component => ({
    name: component.name,
    type: component.type,
    internalType: component.internalType,
    ...(Array.isArray(component.components) ? { components: namedComponents(component) } : {}),
  }));
}

function assertSameShape(label, canonicalTuple, generatedTuple) {
  const canonical = namedComponents(canonicalTuple);
  const generated = namedComponents(generatedTuple);
  if (JSON.stringify(generated) !== JSON.stringify(canonical)) {
    throw new Error(
      `${label} tuple diverges from canonical ABI\n`
      + `canonical=${JSON.stringify(canonical)}\n`
      + `generated=${JSON.stringify(generated)}`,
    );
  }
}

function extractGeneratedAbi() {
  const match = chainClientSource.match(
    /\/\/ BEGIN GENERATED CLAN_WORLD_ABI[\s\S]*?export const CLAN_WORLD_ABI = ([\s\S]*?) as const;\n\/\/ END GENERATED CLAN_WORLD_ABI/,
  );
  if (!match) {
    throw new Error('could not isolate generated CLAN_WORLD_ABI block in IChainClient.ts');
  }

  return JSON.parse(match[1]);
}

function collectNamedTupleShapes(node, name, shapes = []) {
  if (Array.isArray(node)) {
    for (const item of node) collectNamedTupleShapes(item, name, shapes);
    return shapes;
  }

  if (!node || typeof node !== 'object') {
    return shapes;
  }

  if (node.name === name && node.type === 'tuple') {
    shapes.push(namedComponents(node));
  }

  for (const value of Object.values(node)) {
    collectNamedTupleShapes(value, name, shapes);
  }

  return shapes;
}

const canonicalMission = namedComponents(findFunction('getActiveMission').outputs[0]);
const generatedAbi = extractGeneratedAbi();
const checks = [
  { label: 'WorldState', functionName: 'getWorldState', outputIndex: 0 },
  { label: 'WorldSnapshot', functionName: 'getWorldSnapshot', outputIndex: 0 },
  { label: 'Clan', functionName: 'getClan', outputIndex: 0 },
  { label: 'Clansman', functionName: 'getClansman', outputIndex: 0 },
  { label: 'BanditTroop', functionName: 'getBanditTroop', outputIndex: 0 },
  { label: 'OrderResult', functionName: 'submitClanOrders', outputIndex: 0 },
  { label: 'ClanFullView', functionName: 'getClanFullView', outputIndex: 0 },
];

for (const { label, functionName, outputIndex } of checks) {
  const canonicalFunction = findFunction(functionName);
  const generatedFunction = generatedAbi.find(item => item.type === 'function' && item.name === functionName);
  if (!generatedFunction) {
    throw new Error(`generated CLAN_WORLD_ABI missing ${functionName}`);
  }
  assertSameShape(label, canonicalFunction.outputs[outputIndex], generatedFunction.outputs[outputIndex]);
}

const generatedClanFullView = generatedAbi.find(item => item.type === 'function' && item.name === 'getClanFullView');
if (!generatedClanFullView) {
  throw new Error('generated CLAN_WORLD_ABI missing getClanFullView');
}
const hardcodedMissions = collectNamedTupleShapes(generatedClanFullView, 'activeMission');

if (hardcodedMissions.length !== 2) {
  throw new Error(`expected 2 getClanFullView activeMission tuples, found ${hardcodedMissions.length}`);
}

for (const [index, hardcodedMission] of hardcodedMissions.entries()) {
  if (JSON.stringify(hardcodedMission) !== JSON.stringify(canonicalMission)) {
    throw new Error(
      `getClanFullView activeMission tuple ${index} diverges from canonical Mission ABI\n`
      + `canonical=${JSON.stringify(canonicalMission)}\n`
      + `hardcoded=${JSON.stringify(hardcodedMission)}`,
    );
  }
}

console.log('ClanWorld major struct ABI parity OK');
