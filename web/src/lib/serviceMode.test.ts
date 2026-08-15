import { describe, expect, it } from 'vitest';
import { resolveServiceMode } from './serviceMode';

describe('resolveServiceMode', () => {
  it.each([
    ['live', 'live'],
    ['paused', 'paused'],
    ['auto', 'auto'],
    [' PAUSED ', 'paused'],
  ] as const)('normalizes %s to %s', (input, expected) => {
    expect(resolveServiceMode(input, true)).toBe(expected);
  });

  it('fails closed when a production mode is missing', () => {
    expect(resolveServiceMode(undefined, true)).toBe('paused');
  });

  it('fails closed when a production mode is invalid', () => {
    expect(resolveServiceMode('unexpected', true)).toBe('paused');
  });

  it('keeps local development live when a mode is not configured', () => {
    expect(resolveServiceMode(undefined, false)).toBe('live');
  });
});
