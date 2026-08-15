export const SERVICE_MODES = ['live', 'paused', 'auto'] as const;

export type ServiceMode = typeof SERVICE_MODES[number];

export function resolveServiceMode(rawMode: unknown, isProduction: boolean): ServiceMode {
  if (typeof rawMode === 'string') {
    const normalizedMode = rawMode.trim().toLowerCase();

    if (SERVICE_MODES.some((mode) => mode === normalizedMode)) {
      return normalizedMode as ServiceMode;
    }
  }

  return isProduction ? 'paused' : 'live';
}

export function getServiceMode(): ServiceMode {
  return resolveServiceMode(import.meta.env.VITE_SERVICE_MODE, import.meta.env.PROD);
}

export function getHealthCheckUrl(): string {
  const apiBaseUrl = import.meta.env.VITE_API_URL?.trim().replace(/\/$/, '');
  return `${apiBaseUrl || 'http://localhost:3000'}/up`;
}
