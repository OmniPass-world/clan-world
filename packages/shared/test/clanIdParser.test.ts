import { describe, expect, it } from 'vitest';
import { parseClanId } from '../src/adapters/IChainClient';

describe('parseClanId', () => {
  it('throws for alphabetic suffix ("12abc")', () => {
    expect(() => parseClanId('12abc', 'test')).toThrow(
      "test: clanId must be a non-negative decimal integer, got '12abc'",
    );
  });

  it('throws for negative value ("-1")', () => {
    expect(() => parseClanId('-1', 'test')).toThrow(
      "test: clanId must be a non-negative decimal integer, got '-1'",
    );
  });

  it('throws for uint32 overflow ("4294967296")', () => {
    expect(() => parseClanId('4294967296', 'test')).toThrow(
      "test: clanId exceeds uint32 max (4294967295), got '4294967296'",
    );
  });

  it('throws for reserved clan ID 0 ("0")', () => {
    expect(() => parseClanId('0', 'test')).toThrow(
      "test: clanId 0 is reserved (clan IDs start at 1), got '0'",
    );
  });

  it('returns 1 for valid value ("1")', () => {
    expect(parseClanId('1', 'test')).toBe(1);
  });

  it('throws for empty string ("")', () => {
    expect(() => parseClanId('', 'test')).toThrow(
      "test: clanId must be a non-negative decimal integer, got ''",
    );
  });

  it('accepts uint32 max boundary ("4294967295")', () => {
    expect(parseClanId('4294967295', 'test')).toBe(4294967295);
  });
  it('throws for whitespace-only input ("   ")', () => {
    expect(() => parseClanId('   ', 'test')).toThrow(
      "test: clanId must be a non-negative decimal integer, got '   '",
    );
  });
  it('accepts leading zeros ("007") and parses as decimal', () => {
    expect(parseClanId('007', 'test')).toBe(7);
  });
});
