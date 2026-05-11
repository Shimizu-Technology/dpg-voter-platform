import posthog from 'posthog-js';

type AnalyticsProps = Record<string, string | number | boolean | null | undefined>;

export const isAnalyticsEnabled = Boolean(import.meta.env.VITE_PUBLIC_POSTHOG_KEY) &&
  (import.meta.env.PROD || import.meta.env.VITE_ENABLE_ANALYTICS_IN_DEV === 'true');

function compactProps(props: AnalyticsProps = {}) {
  return Object.fromEntries(Object.entries(props).filter(([, value]) => value !== undefined));
}

function routeArea(pathname: string) {
  if (pathname.startsWith('/admin')) return 'admin';
  if (pathname.startsWith('/data') || pathname.startsWith('/team')) return 'legacy_workspace';
  if (pathname.startsWith('/signup') || pathname === '/thank-you' || pathname === '/') return 'public';
  return 'other';
}

export function captureAnalyticsEvent(event: string, props: AnalyticsProps = {}) {
  if (!isAnalyticsEnabled) return;
  posthog.capture(event, compactProps(props));
}

export function capturePageview(pathname: string, search: string) {
  if (!isAnalyticsEnabled || typeof window === 'undefined') return;
  captureAnalyticsEvent('$pageview', {
    $current_url: window.location.href,
    $pathname: pathname,
    route_area: routeArea(pathname),
    has_query: search.length > 0,
  });
}

export function identifyStaffUser(user: {
  id: number;
  role: string;
  assigned_village_id: number | null;
  assigned_district_id: number | null;
  assigned_block_id: number | null;
}) {
  if (!isAnalyticsEnabled) return;

  posthog.identify(`staff:${user.id}`, compactProps({
    app_role: user.role,
    assigned_village_id: user.assigned_village_id,
    assigned_district_id: user.assigned_district_id,
    assigned_block_id: user.assigned_block_id,
  }));
}

export function resetAnalytics() {
  if (!isAnalyticsEnabled) return;
  posthog.reset();
}
