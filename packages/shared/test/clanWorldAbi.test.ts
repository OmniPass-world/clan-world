import { describe, expect, it } from 'vitest';
import { decodeFunctionResult, encodeAbiParameters } from 'viem';
import { CLAN_WORLD_ABI } from '../src/adapters/IChainClient';

const ZERO_BYTES32 = `0x${'00'.repeat(32)}` as `0x${string}`;

const worldStateTuple = [
  {
    type: 'tuple',
    components: [
      { name: 'currentTick', type: 'uint64' },
      { name: 'seasonStartTick', type: 'uint64' },
      { name: 'seasonEndTick', type: 'uint64' },
      { name: 'seasonFinalized', type: 'bool' },
      { name: 'currentSeasonNumber', type: 'uint64' },
      { name: 'nextHeartbeatAtTick', type: 'uint64' },
      { name: 'nextHeartbeatAtTs', type: 'uint64' },
      { name: 'nextBanditSpawnEligibleTick', type: 'uint64' },
      { name: 'currentBanditSpawnChanceBps', type: 'uint16' },
      { name: 'currentTickSeed', type: 'bytes32' },
      { name: 'activeBanditId', type: 'uint32' },
      { name: 'winterActive', type: 'bool' },
      { name: 'winterStartsAtTick', type: 'uint64' },
      { name: 'winterEndsAtTick', type: 'uint64' },
      { name: 'nextCommitSequence', type: 'uint64' },
    ],
  },
] as const;

const worldSnapshotTuple = [
  {
    type: 'tuple',
    components: [
      { name: 'currentTick', type: 'uint64' },
      { name: 'seasonStartTick', type: 'uint64' },
      { name: 'seasonEndTick', type: 'uint64' },
      { name: 'seasonFinalized', type: 'bool' },
      { name: 'currentSeasonNumber', type: 'uint64' },
      { name: 'nextHeartbeatAtTick', type: 'uint64' },
      { name: 'winterActive', type: 'bool' },
      { name: 'winterStartsAtTick', type: 'uint64' },
      { name: 'winterEndsAtTick', type: 'uint64' },
      { name: 'activeBanditId', type: 'uint32' },
      { name: 'currentTickSeed', type: 'bytes32' },
      {
        name: 'leaderboard',
        type: 'tuple[]',
        components: [
          { name: 'clanId', type: 'uint32' },
          { name: 'owner', type: 'address' },
          { name: 'monumentLevel', type: 'uint8' },
          { name: 'baseLevel', type: 'uint8' },
          { name: 'wallLevel', type: 'uint8' },
          { name: 'livingClansmen', type: 'uint8' },
          { name: 'state', type: 'uint8' },
          { name: 'lootValue', type: 'uint256' },
        ],
      },
    ],
  },
] as const;

describe('ClanWorld generated ABI tuple decoding', () => {
  it('decodes a known-good getWorldState() result with the current Solidity order', () => {
    const data = encodeAbiParameters(worldStateTuple, [
      {
        currentTick: 11n,
        seasonStartTick: 1n,
        seasonEndTick: 360n,
        seasonFinalized: false,
        currentSeasonNumber: 7n,
        nextHeartbeatAtTick: 12n,
        nextHeartbeatAtTs: 1_900_000_001n,
        nextBanditSpawnEligibleTick: 21n,
        currentBanditSpawnChanceBps: 3000,
        currentTickSeed: ZERO_BYTES32,
        activeBanditId: 42,
        winterActive: true,
        winterStartsAtTick: 100n,
        winterEndsAtTick: 110n,
        nextCommitSequence: 9n,
      },
    ]);

    const state = decodeFunctionResult({
      abi: CLAN_WORLD_ABI,
      functionName: 'getWorldState',
      data,
    }) as Record<string, unknown>;

    expect(state.currentSeasonNumber).toBe(7n);
    expect(state.nextHeartbeatAtTick).toBe(12n);
    expect(state.nextHeartbeatAtTs).toBe(1_900_000_001n);
    expect(state.winterActive).toBe(true);
  });

  it('decodes a known-good getWorldSnapshot() result with season fields before winter fields', () => {
    const data = encodeAbiParameters(worldSnapshotTuple, [
      {
        currentTick: 33n,
        seasonStartTick: 0n,
        seasonEndTick: 360n,
        seasonFinalized: false,
        currentSeasonNumber: 2n,
        nextHeartbeatAtTick: 34n,
        winterActive: true,
        winterStartsAtTick: 100n,
        winterEndsAtTick: 110n,
        activeBanditId: 3,
        currentTickSeed: ZERO_BYTES32,
        leaderboard: [],
      },
    ]);

    const snapshot = decodeFunctionResult({
      abi: CLAN_WORLD_ABI,
      functionName: 'getWorldSnapshot',
      data,
    }) as Record<string, unknown>;

    expect(snapshot.currentSeasonNumber).toBe(2n);
    expect(snapshot.nextHeartbeatAtTick).toBe(34n);
    expect(snapshot.winterActive).toBe(true);
    expect(snapshot.activeBanditId).toBe(3);
  });
});
