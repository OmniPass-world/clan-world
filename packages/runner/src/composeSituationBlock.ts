import type { IConvexClient } from '@clan-world/shared/adapters';
import type { IElderMemoryStore, IElderPeerInbox } from '@clan-world/agents/seams';
import type { ElderId } from './types';

export interface ComposeDeps {
  convex: IConvexClient;
  memory: IElderMemoryStore;
  peerInbox: IElderPeerInbox;
}

export interface ComposeArgs {
  elder: ElderId;
  clanId: string;
  tick: number;
}

/**
 * Compose the per-tick situation block for a single Elder.
 *
 * Block sections (in order — Elder prompts depend on this ordering):
 *
 *   1. Identity reminder      — "You are Elder N of Clan X"
 *   2. Tick state             — current tick + tick-epoch info
 *   3. World snapshot summary — leaderboard-relevant slice
 *   4. Clan view              — clan's own resources, regions, pending orders
 *   5. Peer messages          — whispers in this Elder's inbox
 *   6. Memory continuity      — keys saved last reasoning cycle
 *
 * Format is plain text (Markdown headings) so it pastes legibly into a Claude
 * Code session. We deliberately do NOT include Convex internal IDs or other
 * implementation noise — only fields the Elder needs to reason.
 */
export async function composeSituationBlock(
  args: ComposeArgs,
  deps: ComposeDeps,
): Promise<string> {
  const [snap, view, peers, memory] = await Promise.all([
    deps.convex.getSnapshot(),
    deps.convex.getClanFullView(args.clanId),
    deps.peerInbox.inbox(),
    deps.memory.snapshot(),
  ]);

  const lines: string[] = [];
  lines.push(`# Tick ${args.tick} — Elder ${args.elder} (Clan ${args.clanId})`);
  lines.push('');

  lines.push('## Identity');
  lines.push(
    `You are Elder ${args.elder}, ruling Clan ${args.clanId}. You reason once per tick and ` +
      `submit clan orders via the \`elder clan submit-orders\` CLI before the tick closes.`,
  );
  lines.push('');

  lines.push('## Tick state');
  lines.push(`- current tick: ${args.tick}`);
  lines.push(`- tick started at (unix s): ${snap.tickEpoch.startedAt}`);
  lines.push(`- tick duration: ${snap.tickEpoch.durationMs}ms`);
  lines.push('');

  lines.push('## World snapshot');
  if (snap.regions.length === 0 && snap.clans.length === 0) {
    lines.push('- (no world data yet — Convex stub or pre-genesis)');
  } else {
    lines.push(`- regions: ${snap.regions.length}`);
    lines.push(`- clans: ${snap.clans.length}`);
    for (const clan of snap.clans) {
      lines.push(`  - ${clan.id} (${clan.name}) — treasury: ${clan.treasury}`);
    }
  }
  lines.push('');

  lines.push('## Your clan');
  lines.push(`- id: ${view.clan.id}`);
  lines.push(`- name: ${view.clan.name}`);
  lines.push(`- treasury: ${view.clan.treasury}`);
  lines.push(`- controlled regions: ${view.controlledRegions.length}`);
  for (const r of view.controlledRegions) {
    lines.push(`  - ${r.id} (${r.name})`);
  }
  lines.push(`- pending orders for next tick: ${view.pendingOrders.length}`);
  for (const o of view.pendingOrders) {
    lines.push(`  - ${o.kind}: ${JSON.stringify(o.payload)}`);
  }
  lines.push('');

  lines.push('## Peer messages (whispers)');
  if (peers.length === 0) {
    lines.push('- (none)');
  } else {
    for (const p of peers) {
      lines.push(`- [${p.sentAt}] from clan ${p.fromClanId} (tick ${p.tick}): ${p.message}`);
    }
  }
  // Whispers visible via the convex-side feed (public/region-broadcast variant).
  if (view.whispers.length > 0) {
    lines.push('');
    lines.push('## Public whispers (region/world feed)');
    for (const w of view.whispers) {
      lines.push(`- tick ${w.tick} from clan ${w.fromClanId} → ${w.toClanId}: ${w.text}`);
    }
  }
  lines.push('');

  lines.push('## Memory (continuity)');
  const memKeys = Object.keys(memory).sort();
  if (memKeys.length === 0) {
    lines.push('- (empty — first tick, or post-clear bootstrap)');
  } else {
    for (const k of memKeys) {
      lines.push(`- ${k}: ${memory[k]}`);
    }
  }
  lines.push('');

  lines.push('## Action');
  lines.push(
    'Reason about your clan\'s next move. Use `elder peer whisper`, `elder memory save`, and ' +
      '`elder clan submit-orders` to act. The runner will heartbeat the chain after the settle ' +
      'window — get your orders in before then.',
  );

  return lines.join('\n');
}
