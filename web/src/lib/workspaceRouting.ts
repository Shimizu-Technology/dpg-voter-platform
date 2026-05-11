import type { SessionResponse } from '../hooks/useSession';

const LAST_ROUTE_STORAGE_PREFIX = 'dpg-voter-platform:last-route:';

type SessionLike = Pick<SessionResponse, 'user' | 'permissions'>;

type PermissionKey =
  | 'can_view_supporters'
  | 'can_create_staff_supporters'
  | 'can_import_supporters'
  | 'can_access_duplicates'
  | 'can_send_sms'
  | 'can_send_email'
  | 'can_manage_users'
  | 'can_manage_configuration'
  | 'can_manage_data_configuration'
  | 'can_access_audit_logs'
  | 'can_access_reports'
  | 'can_upload_gec';

type PermissionRule = {
  prefix: string;
  permission: PermissionKey;
};

const PERMISSION_RULES: PermissionRule[] = [
  { prefix: '/admin/supporters/new', permission: 'can_create_staff_supporters' },
  { prefix: '/admin/import', permission: 'can_import_supporters' },
  { prefix: '/admin/supporters', permission: 'can_view_supporters' },
  { prefix: '/admin/intake', permission: 'can_view_supporters' },
  { prefix: '/admin/reports', permission: 'can_access_reports' },
  { prefix: '/admin/duplicates', permission: 'can_access_duplicates' },
  { prefix: '/admin/sms/settings', permission: 'can_manage_configuration' },
  { prefix: '/admin/sms', permission: 'can_send_sms' },
  { prefix: '/admin/email', permission: 'can_send_email' },
  { prefix: '/admin/users', permission: 'can_manage_users' },
  { prefix: '/admin/districts', permission: 'can_manage_configuration' },
  { prefix: '/admin/precincts', permission: 'can_manage_configuration' },
  { prefix: '/admin/outreach', permission: 'can_view_supporters' },
  { prefix: '/admin/audit-logs', permission: 'can_access_audit_logs' },
];

function splitRoute(route: string) {
  const [pathWithQuery] = route.split('#', 1);
  const queryIndex = pathWithQuery.indexOf('?');
  if (queryIndex === -1) {
    return { pathname: normalizePathname(pathWithQuery), search: '' };
  }

  return {
    pathname: normalizePathname(pathWithQuery.slice(0, queryIndex)),
    search: pathWithQuery.slice(queryIndex),
  };
}

function normalizePathname(pathname: string) {
  const trimmed = pathname.trim() || '/';
  if (trimmed === '/') return '/';
  return trimmed.replace(/\/+$/, '') || '/';
}

function storageKey(userId: number) {
  return `${LAST_ROUTE_STORAGE_PREFIX}${userId}`;
}

function getPermissionForPath(pathname: string): PermissionKey | null {
  const rule = PERMISSION_RULES.find((entry) => pathname === entry.prefix || pathname.startsWith(`${entry.prefix}/`));
  return rule?.permission || null;
}

export function canonicalizeWorkspaceRoute(route: string) {
  const { pathname, search } = splitRoute(route);

  if (pathname === '/data' || pathname === '/team') return `/admin${search}`;
  if (pathname === '/data/entry' || pathname === '/team/entry') return `/admin/supporters/new${search}`;
  if (pathname === '/data/campaign-settings' || pathname === '/team/campaign-settings') return `/admin/sms/settings${search}`;
  if (pathname.startsWith('/data/')) {
    return `/admin/${pathname.slice('/data/'.length)}${search}`;
  }
  if (pathname.startsWith('/team/')) {
    return `/admin/${pathname.slice('/team/'.length)}${search}`;
  }
  return `${pathname}${search}`;
}

export function isWorkspaceRoute(route: string) {
  const { pathname } = splitRoute(canonicalizeWorkspaceRoute(route));
  return pathname.startsWith('/admin');
}

export function canAccessDataWorkspace(session: SessionLike) {
  return Boolean(session.permissions?.can_view_supporters);
}

export function isRouteAllowedForSession(route: string, session: SessionLike) {
  const normalized = canonicalizeWorkspaceRoute(route);
  const { pathname } = splitRoute(normalized);

  if (!pathname.startsWith('/admin')) {
    return false;
  }


  const permission = getPermissionForPath(pathname);
  if (!permission) return true;

  return Boolean(session.permissions?.[permission]);
}

export function rememberLastRoute(userId: number, route: string) {
  if (typeof window === 'undefined' || !isWorkspaceRoute(route)) return;

  try {
    window.localStorage.setItem(storageKey(userId), canonicalizeWorkspaceRoute(route));
  } catch {
    // Ignore storage failures and keep navigation working.
  }
}

export function getRememberedRoute(userId: number) {
  if (typeof window === 'undefined') return null;

  try {
    const saved = window.localStorage.getItem(storageKey(userId));
    return saved ? canonicalizeWorkspaceRoute(saved) : null;
  } catch {
    return null;
  }
}

export function resolvePreferredRoute(session: SessionLike, currentRoute?: string) {
  const remembered = getRememberedRoute(session.user.id);
  const normalizedCurrent = currentRoute ? canonicalizeWorkspaceRoute(currentRoute) : null;

  if (remembered && remembered !== normalizedCurrent && isRouteAllowedForSession(remembered, session)) {
    return remembered;
  }

  return canonicalizeWorkspaceRoute(session.permissions?.default_route || '/admin');
}

export function shouldAttemptInitialRouteRestore(route: string) {
  const { pathname } = splitRoute(canonicalizeWorkspaceRoute(route));
  return pathname === '/admin';
}
