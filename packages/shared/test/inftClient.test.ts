import { describe, expect, it } from 'vitest';
import { encodeAbiParameters, keccak256, parseAbiParameters, stringToHex } from 'viem';
import {
  createInftClient,
  hashIntelligentData,
  hashMemorySnapshot,
  type IntelligentDataEntry,
} from '../src/adapters/IInftClient';

describe('IInftClient helpers', () => {
  it('hashIntelligentData matches the Solidity rolling hash convention', () => {
    const data: IntelligentDataEntry[] = [
      { label: 'persona', dataHash: keccak256(stringToHex('persona')), uri: '0g://persona' },
      { label: 'memory', dataHash: keccak256(stringToHex('memory')), uri: '0g://memory' },
    ];

    let rolling = `0x${'00'.repeat(32)}` as `0x${string}`;
    for (const entry of data) {
      rolling = keccak256(
        encodeAbiParameters(
          parseAbiParameters('bytes32 rolling, string label, bytes32 dataHash, string uri'),
          [rolling, entry.label, entry.dataHash, entry.uri],
        ),
      );
    }

    expect(hashIntelligentData(data)).toBe(rolling);
  });

  it('hashMemorySnapshot is stable regardless of object insertion order', () => {
    expect(hashMemorySnapshot({ b: '2', a: '1' })).toBe(hashMemorySnapshot({ a: '1', b: '2' }));
  });

  it('stub client returns a readable token view by default', async () => {
    const client = createInftClient();
    const token = await client.getToken(7n);
    expect(token.tokenId).toBe(7n);
    expect(token.data[0]?.label).toBe('memory');
    expect(token.currentDataHash).toBe(hashIntelligentData(token.data));
  });
});
