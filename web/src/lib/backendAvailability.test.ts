import { afterEach, describe, expect, it, vi } from 'vitest';
import { checkBackendAvailability } from './backendAvailability';

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('checkBackendAvailability', () => {
  it('returns true for a successful health response', async () => {
    const fetchMock = vi.fn().mockResolvedValue({ ok: true });
    vi.stubGlobal('fetch', fetchMock);
    const controller = new AbortController();

    await expect(checkBackendAvailability(controller.signal, 'https://example.test/up')).resolves.toBe(true);
    expect(fetchMock).toHaveBeenCalledWith('https://example.test/up', expect.objectContaining({
      cache: 'no-store',
      credentials: 'omit',
      signal: controller.signal,
    }));
  });

  it('returns false for an unsuccessful health response', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: false }));

    await expect(
      checkBackendAvailability(new AbortController().signal, 'https://example.test/up'),
    ).resolves.toBe(false);
  });

  it('returns false when the health request fails', async () => {
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new TypeError('Network unavailable')));

    await expect(
      checkBackendAvailability(new AbortController().signal, 'https://example.test/up'),
    ).resolves.toBe(false);
  });
});
