import { describe, expect, it } from 'vitest';
import canonicalAbi from '@clan-world/contracts/abi/IClanWorld.json' with { type: 'json' };
import { decodeFunctionResult, encodeAbiParameters, getAbiItem, type Abi, type AbiFunction } from 'viem';
import { CLAN_WORLD_ABI } from '../src/adapters/IChainClient';

const ZERO_BYTES32 = `0x${'00'.repeat(32)}` as `0x${string}`;
const abi = canonicalAbi.abi as Abi;

const getFunctionOutputs = (name: string) => (getAbiItem({ abi, name }) as AbiFunction).outputs;
const worldStateOutputs = getFunctionOutputs('getWorldState');
const worldSnapshotOutputs = getFunctionOutputs('getWorldSnapshot');

describe('ClanWorld generated ABI tuple decoding', () => {
  it('decodes a known-good getWorldState() result with the current Solidity order', () => {
    const data = encodeAbiParameters(worldStateOutputs, [
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
    const data = encodeAbiParameters(worldSnapshotOutputs, [
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
