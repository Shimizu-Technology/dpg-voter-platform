import { getHealthCheckUrl } from './serviceMode';

export async function checkBackendAvailability(
  signal: AbortSignal,
  healthCheckUrl = getHealthCheckUrl(),
): Promise<boolean> {
  try {
    const response = await fetch(healthCheckUrl, {
      method: 'GET',
      cache: 'no-store',
      credentials: 'omit',
      headers: { Accept: 'text/html,application/json' },
      signal,
    });

    return response.ok;
  } catch {
    return false;
  }
}
