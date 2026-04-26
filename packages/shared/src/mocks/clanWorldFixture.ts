// Demo dataset for the v1 ClanWorld 2-minute showcase.
//
// Source-of-truth fixture: TS data here is canonical; Convex `seedMockState`
// inserts what's exported below. Live LLMs are wired in at runtime — this
// fixture seeds the WORLD STATE (mid-game, tick 80) and a small batch of
// "seed" agent log entries so the canvas has bubble content from t+0s before
// the four real Anthropic Claude Elder sessions ramp up.
//
// Two narrative climaxes are baked into the world state:
//   1. Aldric (clan 0) is one tick from starvation (vaultWheat 1e18, 2 living
//      clansmen consume 2e18/tick).
//   2. Brennan (clan 2) sits on iron-heavy vault with damaged wall 1; bandit
//      currently CAMPING in Mountains, exits camp tick 81 → attack incoming.
//
// Numerics align with `clanworld_v4_spec.md` §3-§8 (vault model, gathering
// yields, defense decomposition, bandit tiers). Resource amounts use 18-decimal
// wei strings, never bigint literals — consumers parse with BigInt() if arith
// is needed (round-2 fix established by PR #3).
//
// Type policy: this file does NOT extend `types.ts`. The base `Clan` /
// `Whisper` types stay minimal there; demo-only enrichment lives in local
// `*Demo` types declared in this module. Public-bulletin whispers use the
// sentinel `toClanId: '*'` to fit the existing `Whisper.toClanId: string`
// shape without inventing a parallel type.

import type {
  Clan,
  ClanFullView,
  Region,
  Tick,
  Whisper,
  WorldSnapshot,
} from '../types';

// Local demo-only types. Kept out of types.ts to preserve Wave 0 minimalism.

/** Per-clan strategic + resource state for the demo. Superset of base `Clan`. */
export interface ClanDemoState extends Clan {
  /** Numeric clanId (0-3 in v1). Distinct from `id` slug, kept for spec parity. */
  clanId: number;
  baseRegion: string;
  baseLevel: number;
  wallLevel: number;
  monumentLevel: number;
  livingClansmen: number;
  /** Cached starvation flag per v4 §4.13 (lazy starvation tracking). */
  starvingCached: boolean;
  /** Vault balances. Decimal string (18-decimal wei) — matches `treasury`. */
  vaultWood: string;
  vaultIron: string;
  vaultWheat: string;
  vaultFish: string;
  /** Clan-level purse balances (gold + blueprint fragments are not carried). */
  goldBalance: string;
  blueprintBalance: string;
}

/**
 * In-game agent log entry rendered as a speech bubble in the canvas.
 * Posted by Elder agents pre-tx so the bubble appears immediately.
 */
export interface AgentLog {
  id: string;
  clanId: string;
  tick: Tick;
  /** Up to 240 chars per frontend speech-bubble convention. */
  message: string;
  /** Wall-clock ms (Date.now()) at post time. */
  postedAt: number;
  level: 'reasoning' | 'action' | 'observation';
}

/**
 * Bandit troop state. Mirrors v4 §6 / v4.2 §7.7 — collapsed for the demo.
 */
export interface BanditState {
  banditId: string;
  state: 'CAMPING' | 'RESTING' | 'ATTACKING' | 'DEFEATED' | 'ESCAPED';
  currentRegion: string;
  /** Tick at which the troop entered its current state. */
  stateEnteredTick: Tick;
  /** Tick at which the next state transition / attack resolves. */
  nextActionTick: Tick;
  attackAttemptsMade: number;
  tier: number;
  attackPower: number;
  /** Carried loot (18-decimal wei strings). '0' when troop has not yet stolen. */
  carryWood: string;
  carryIron: string;
  carryWheat: string;
  carryFish: string;
}

/** Sentinel for `Whisper.toClanId` indicating a public bulletin. */
export const PUBLIC_WHISPER_RECIPIENT = '*';

// Regions (8-region travel graph per v4 §1.2). Ownership tracks homebase.
const REGIONS: Region[] = [
  { id: 'forest', name: 'Forest', ownerClanId: 'aldric' },
  { id: 'mountains', name: 'Mountains', ownerClanId: 'brennan' },
  { id: 'unicorn-town', name: 'Unicorn Town', ownerClanId: null },
  { id: 'west-farmland', name: 'West Farmland', ownerClanId: 'mira' },
  { id: 'east-farmland', name: 'East Farmland', ownerClanId: 'sora' },
  { id: 'west-docks', name: 'West Docks', ownerClanId: null },
  { id: 'east-docks', name: 'East Docks', ownerClanId: null },
  { id: 'deep-sea', name: 'Deep Sea', ownerClanId: null },
];

// Clans — asymmetric mid-game state showing strategic divergence.

// Aldric (clan 0) — STARVATION HOOK: 1e18 wheat + 2 clansmen = empties next tick.
const ALDRIC: ClanDemoState = {
  id: 'aldric',
  clanId: 0,
  name: 'Aldric',
  baseRegion: 'forest',
  baseLevel: 2,
  wallLevel: 2,
  monumentLevel: 3,
  livingClansmen: 2,
  starvingCached: false, // about to flip true at tick 81 settlement
  treasury: '12000000000000000000', // mirrors goldBalance for legacy consumers
  vaultWood: '15000000000000000000',
  vaultIron: '2000000000000000000',
  vaultWheat: '1000000000000000000',
  vaultFish: '500000000000000000',
  goldBalance: '12000000000000000000',
  blueprintBalance: '0',
};

// Mira (clan 1) — gold-heavy trader with wheat surplus.
const MIRA: ClanDemoState = {
  id: 'mira',
  clanId: 1,
  name: 'Mira',
  baseRegion: 'west-farmland',
  baseLevel: 3,
  wallLevel: 3,
  monumentLevel: 4,
  livingClansmen: 3,
  starvingCached: false,
  treasury: '45000000000000000000',
  vaultWood: '8000000000000000000',
  vaultIron: '1000000000000000000',
  vaultWheat: '35000000000000000000',
  vaultFish: '5000000000000000000',
  goldBalance: '45000000000000000000',
  blueprintBalance: '0',
};

// Brennan (clan 2) — BANDIT HOOK: iron-heavy loot value, wall damaged to 1.
const BRENNAN: ClanDemoState = {
  id: 'brennan',
  clanId: 2,
  name: 'Brennan',
  baseRegion: 'mountains',
  baseLevel: 2,
  wallLevel: 1, // damaged from prior bandit attack
  monumentLevel: 2,
  livingClansmen: 4,
  starvingCached: false,
  treasury: '8000000000000000000',
  vaultWood: '25000000000000000000',
  vaultIron: '12000000000000000000', // high loot value (4 pts/token per §6.9)
  vaultWheat: '18000000000000000000',
  vaultFish: '2000000000000000000',
  goldBalance: '8000000000000000000',
  blueprintBalance: '0',
};

// Sora (clan 3) — long-game monument leader, isolationist.
const SORA: ClanDemoState = {
  id: 'sora',
  clanId: 3,
  name: 'Sora',
  baseRegion: 'east-farmland',
  baseLevel: 3,
  wallLevel: 4,
  monumentLevel: 5, // monument leader
  livingClansmen: 3,
  starvingCached: false,
  treasury: '15000000000000000000',
  vaultWood: '40000000000000000000',
  vaultIron: '8000000000000000000',
  vaultWheat: '60000000000000000000',
  vaultFish: '3000000000000000000',
  goldBalance: '15000000000000000000',
  blueprintBalance: '2000000000000000000', // closing on tier-7 unlock
};

const CLANS: ClanDemoState[] = [ALDRIC, MIRA, BRENNAN, SORA];

// World snapshot — currentTick = 80, 20s tick window for Submission 1.
const WORLD_SNAPSHOT: WorldSnapshot = {
  tick: 80,
  tickEpoch: {
    startedAt: Math.floor(Date.now() / 1000) - 5, // current tick window opened ~5s ago
    durationMs: 20_000,
  },
  regions: REGIONS,
  clans: CLANS, // ClanDemoState extends Clan so this satisfies WorldSnapshot.clans.
};

// Per-clan full views. Pending orders + per-clan whispers populate live.
function controlledRegions(clanId: string): Region[] {
  return REGIONS.filter((r) => r.ownerClanId === clanId);
}

const CLAN_VIEWS: ClanFullView[] = CLANS.map((clan) => ({
  clan,
  controlledRegions: controlledRegions(clan.id),
  pendingOrders: [],
  whispers: [],
}));

// Seed agent logs — frontend renders these before live Elders boot.
// Capped at 240 chars; `postedAt` offsets backwards so logs read in tick order.
const NOW = Date.now();
const AGENT_LOGS: AgentLog[] = [
  {
    id: 'log-001',
    clanId: 'aldric',
    tick: 78,
    message:
      'Wheat reserves critical. Need trade with Mira before tick 81 or workforce collapses.',
    postedAt: NOW - 40_000,
    level: 'reasoning',
  },
  {
    id: 'log-002',
    clanId: 'brennan',
    tick: 79,
    message:
      'Bandit camped Mountains. Wall already at 1. Calling all clansmen home — defend at all costs.',
    postedAt: NOW - 30_000,
    level: 'reasoning',
  },
  {
    id: 'log-003',
    clanId: 'mira',
    tick: 79,
    message:
      "Gold reserves at 45 — could buy out Aldric's wood AND outfit a mercenary for Brennan. Worth it for the alliance signal.",
    postedAt: NOW - 25_000,
    level: 'reasoning',
  },
  {
    id: 'log-004',
    clanId: 'sora',
    tick: 80,
    message:
      'Blueprint count at 2. Two more and I unlock monument tier 7. Stay isolated, let the others bleed each other.',
    postedAt: NOW - 15_000,
    level: 'reasoning',
  },
  {
    id: 'log-005',
    clanId: 'aldric',
    tick: 80,
    message:
      "Mira's whisper offer is 3 wheat per 1 wood. Steep but I'll starve without it. Accepting.",
    postedAt: NOW - 10_000,
    level: 'reasoning',
  },
  {
    id: 'log-006',
    clanId: 'brennan',
    tick: 80,
    message:
      'Two clansmen stationed defend_base, third en route from Mountains gathering. Will not be enough if bandits land tier-3+.',
    postedAt: NOW - 6_000,
    level: 'reasoning',
  },
  {
    id: 'log-007',
    clanId: 'sora',
    tick: 80,
    message:
      "Ignoring Aldric's pleas for wheat. Their problem. Monument first.",
    postedAt: NOW - 2_000,
    level: 'reasoning',
  },
];

// Seed whispers — 2 directed + 1 public bulletin (toClanId === '*').
const WHISPERS: Whisper[] = [
  {
    fromClanId: 'mira',
    toClanId: 'aldric',
    text: 'Wheat for wood, 3:1. Three ticks to ship. Take it or starve.',
    tick: 80,
  },
  {
    fromClanId: 'brennan',
    toClanId: 'aldric',
    text: 'Bandit headed your way after me — assuming I survive. Defend your base or send me your spare iron now.',
    tick: 80,
  },
  {
    fromClanId: 'sora',
    toClanId: PUBLIC_WHISPER_RECIPIENT, // public bulletin
    text: 'Monument tier 6 reached. Trading partnerships welcome — I have wheat surplus. No alliances of convenience.',
    tick: 80,
  },
];

// Bandit — CAMPING in Mountains (Brennan's region). Camp 3 ticks per v4 §6.6;
// spawned tick 78 → exits camp tick 81 → ATTACK.
const BANDIT_STATE: BanditState = {
  banditId: 'bandit-001',
  state: 'CAMPING',
  currentRegion: 'mountains',
  stateEnteredTick: 78,
  nextActionTick: 81,
  attackAttemptsMade: 0,
  tier: 2,
  attackPower: 45, // tier-2 per v4 §6.14
  carryWood: '0',
  carryIron: '0',
  carryWheat: '0',
  carryFish: '0',
};

export const WORLD_FIXTURE: {
  worldSnapshot: WorldSnapshot;
  clans: ClanFullView[];
  agentLogs: AgentLog[];
  whispers: Whisper[];
  banditState: BanditState;
} = {
  worldSnapshot: WORLD_SNAPSHOT,
  clans: CLAN_VIEWS,
  agentLogs: AGENT_LOGS,
  whispers: WHISPERS,
  banditState: BANDIT_STATE,
};

// Convenience accessors used by Convex `seedMockState` mutation.
export function seedSnapshot(): WorldSnapshot {
  return WORLD_FIXTURE.worldSnapshot;
}

export function seedAgentLogs(): AgentLog[] {
  return WORLD_FIXTURE.agentLogs;
}

export function seedWhispers(): Whisper[] {
  return WORLD_FIXTURE.whispers;
}
