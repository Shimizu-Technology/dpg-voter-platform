import { publicSiteConfig } from './publicSite';

const DPG_STARTER_DISABLED_PREFIXES = [
  '/admin/events',
  '/admin/qr',
  '/admin/leaderboard',
  '/admin/poll-watcher',
  '/admin/war-room',
  '/admin/scan',
  '/admin/quotas',
  '/data/scan',
  '/data/vetting',
  '/data/public-review',
  '/data/gec',
  '/data/quotas',
];

export const isDpgDeployment = publicSiteConfig.variant === 'dpg';

export function isRouteAllowedInDeployment(pathname: string) {
  if (!isDpgDeployment) return true;
  return !DPG_STARTER_DISABLED_PREFIXES.some((prefix) => pathname === prefix || pathname.startsWith(`${prefix}/`));
}

export function filterNavItemsForDeployment<T extends { to: string }>(items: T[]) {
  return items.filter((item) => isRouteAllowedInDeployment(item.to));
}
