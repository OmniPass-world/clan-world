// Minimal shared types. Wave 0 placeholders — real shapes are defined in the v4
// state schema spec (docs/planning/V1/01 Blockchain Game Spec/
// clanworld_v4_2_state_schema_interface_spec.md). Expand as streams need them.

export type Tick = number;

export interface TickEpoch {
  /** Unix seconds when this tick window started. */
  startedAt: number;
  /** Duration of one tick in milliseconds. 20000 for Submission 1, 60000 for Submission 2 live. */
  durationMs: number;
}

export interface Region {
  id: string;
  name: string;
  ownerClanId: string | null;
}

export interface Clan {
  id: string;
  name: string;
  /** Decimal string representation of wei amount; consumers parse with BigInt() if arithmetic needed. */
  treasury: string;
}

export interface WorldSnapshot {
  tick: Tick;
  tickEpoch: TickEpoch;
  regions: Region[];
  clans: Clan[];
}

export interface ClanFullView {
  clan: Clan;
  controlledRegions: Region[];
  /** Pending orders this clan submitted for the next tick. */
  pendingOrders: ClanOrder[];
  /** Inbound whispers since the last view. */
  whispers: Whisper[];
}

export interface ClanOrder {
  kind: 'mission' | 'transfer' | 'mint';
  payload: Record<string, unknown>;
}

export interface Whisper {
  fromClanId: string;
  toClanId: string;
  text: string;
  tick: Tick;
}
