import { describe, expect, it } from 'vitest';
import { uintValue } from '../src/adapters/IChainClient';

describe('uintValue', () => {
  it('accepts bigint, safe integer numbers, and integer strings', () => {
    expect(uintValue(12n)).toBe(12n);
    expect(uintValue(12)).toBe(12n);
    expect(uintValue('12')).toBe(12n);
  });

  it('rejects non-integer numbers', () => {
    expect(() => uintValue(1.5)).toThrow('non-integer number');
  });

  it('rejects unsafe integer numbers', () => {
    expect(() => uintValue(Number.MAX_SAFE_INTEGER + 1)).toThrow(
      'unsafe integer number',
    );
  });

  it('rejects non-integer strings', () => {
    expect(() => uintValue('1e18')).toThrow('not a non-negative integer string');
    expect(() => uintValue('1.5')).toThrow('not a non-negative integer string');
  });

  it('rejects unsupported values', () => {
    expect(() => uintValue(null)).toThrow('unsupported type object');
    expect(() => uintValue(undefined)).toThrow('unsupported type undefined');
  });
});
