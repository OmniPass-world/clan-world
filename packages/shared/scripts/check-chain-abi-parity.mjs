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
  if (!Array.isArray(tuple.components)) throw new Error(`ABI tuple ${tuple.name} has no components`);
  return tuple.components.map(component => ({ name: component.name, type: component.type }));
}

function extractArrayBody(source, openBracketIndex) {
  let depth = 0;
  for (let i = openBracketIndex; i < source.length; i++) {
    const char = source[i];
    if (char === '[') depth++;
    if (char === ']') {
      depth--;
      if (depth === 0) return source.slice(openBracketIndex + 1, i);
    }
  }
  throw new Error('unterminated components array in IChainClient.ts');
}

function extractHardcodedMissionShapes() {
  const viewStart = chainClientSource.indexOf("name: 'getClanFullView'");
  const nextFunction = chainClientSource.indexOf("name: 'submitClanOrders'", viewStart);
  if (viewStart === -1 || nextFunction === -1) {
    throw new Error('could not isolate getClanFullView ABI fragment in IChainClient.ts');
  }

  const viewSource = chainClientSource.slice(viewStart, nextFunction);
  const shapes = [];
  let searchFrom = 0;
  while (true) {
    const missionIndex = viewSource.indexOf("name: 'activeMission'", searchFrom);
    if (missionIndex === -1) break;

    const componentsIndex = viewSource.indexOf('components: [', missionIndex);
    if (componentsIndex === -1) throw new Error('activeMission tuple missing components array');
    const openBracketIndex = viewSource.indexOf('[', componentsIndex);
    const body = extractArrayBody(viewSource, openBracketIndex);
    shapes.push([...body.matchAll(/\{\s*name: '([^']+)',\s*type: '([^']+)'\s*\}/g)].map(match => ({
      name: match[1],
      type: match[2],
    })));
    searchFrom = componentsIndex + body.length;
  }

  return shapes;
}

const canonicalMission = namedComponents(findFunction('getActiveMission').outputs[0]);
const hardcodedMissions = extractHardcodedMissionShapes();

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

console.log('getClanFullView Mission ABI parity OK');
