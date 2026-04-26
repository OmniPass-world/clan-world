#!/usr/bin/env node
import fs from 'node:fs';
import type { WorldSnapshot } from '@clan-world/shared';
import type { ClanOrder } from '@clan-world/shared';
import { createChainClient } from '@clan-world/shared/adapters';

// elder CLI — toolbelt invoked by Elder Claude Code sessions per tick.
// Wave 0 stub: only `elder world snapshot` is implemented and returns mock JSON.
// Real impl reads from Convex via IConvexClient and chain via IChainClient.

function snapshot(): WorldSnapshot {
  return {
    tick: 0,
    tickEpoch: { startedAt: 0, durationMs: 20_000 },
    regions: [],
    clans: [],
  };
}

async function main(argv: string[]): Promise<void> {
  const [, , ns, cmd, ...rest] = argv;

  if (ns === 'world' && cmd === 'snapshot') {
    process.stdout.write(JSON.stringify(snapshot(), null, 2) + '\n');
    return;
  }

  if (ns === 'clan' && cmd === 'submit-orders') {
    const [clanId, ordersFile] = rest;
    if (!clanId || !ordersFile) {
      process.stderr.write('usage: elder clan submit-orders <clanId> <ordersJsonFile>\n');
      process.exit(1);
    }
    const raw = fs.readFileSync(ordersFile, 'utf8');
    const orders = JSON.parse(raw) as ClanOrder[];
    const client = createChainClient();
    const result = await client.submitOrders(clanId, orders);
    process.stdout.write(JSON.stringify(result, null, 2) + '\n');
    return;
  }

  if (ns === 'clan' && cmd === 'view') {
    const [clanId] = rest;
    if (!clanId) {
      process.stderr.write('usage: elder clan view <clanId>\n');
      process.exit(1);
    }
    const client = createChainClient();
    const result = await client.getClanFullView(clanId);
    process.stdout.write(JSON.stringify(result, null, 2) + '\n');
    return;
  }

  process.stderr.write(
    'usage: elder world snapshot\n' +
      '       elder clan submit-orders <clanId> <ordersJsonFile>\n' +
      '       elder clan view <clanId>\n' +
      '       elder whisper send <fromClan> <toClan> <text>    (TBD)\n',
  );
  process.exit(1);
}

main(process.argv).catch(err => {
  process.stderr.write(`elder: fatal: ${String(err)}\n`);
  process.exit(1);
});
