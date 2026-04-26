#!/usr/bin/env node
import type { WorldSnapshot } from '@clan-world/shared';

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

function main(argv: string[]): void {
  const [, , ns, cmd] = argv;
  if (ns === 'world' && cmd === 'snapshot') {
    process.stdout.write(JSON.stringify(snapshot(), null, 2) + '\n');
    return;
  }
  process.stderr.write(
    'usage: elder world snapshot\n' +
      '       elder clan submit-orders <clanId> <ordersJson>   (TBD)\n' +
      '       elder whisper send <fromClan> <toClan> <text>    (TBD)\n',
  );
  process.exit(1);
}

main(process.argv);
