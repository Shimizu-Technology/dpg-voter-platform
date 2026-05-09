import type { SessionResponse } from '../hooks/useSession';

const LAST_ROUTE_STORAGE_PREFIX = 'campaign-tracker:last-route:';

type SessionLike = Pick<SessionResponse, 'user' | 'permissions'>;

type PermissionKey =
  | 'can_view_supporters'
  | 'can_create_staff_supporters'
  | 'can_import_supporters'
  | 'can_access_duplicates'
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
  { prefix: '/admin/reports', permission: 'can_access_reports' },
  { prefix: '/admin/duplicates', permission: 'can_access_duplicates' },
  { prefix: '/admin/users', permission: 'can_manage_users' },
  { prefix: '/admin/districts', permission: 'can_manage_configuration' },
  { prefix: '/admin/precincts', permission: 'can_manage_configuration' },
  { prefix: '/admin/outreach', permission: 'can_view_supporters' },
  { prefix: '/admin/audit-logs', permission: 'can_access_audit_logs' },
  { prefix: '/data/users', permission: 'can_manage_users' },
  { prefix: '/data/districts', permission: 'can_manage_data_configuration' },
  { prefix: '/data/precincts', permission: 'can_manage_data_configuration' },
  { prefix: '/data/supporters', permission: 'can_view_supporters' },
  { prefix: '/data/reports', permission: 'can_access_reports' },
  { prefix: '/data/import', permission: 'can_import_supporters' },
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

  if (pathname === '/team') return `/data${search}`;
  if (pathname.startsWith('/team/')) {
    return `/data/${pathname.slice('/team/'.length)}${search}`;
  }
  return `${pathname}${search}`;
}

export function isWorkspaceRoute(route: string) {
  const { pathname } = splitRoute(canonicalizeWorkspaceRoute(route));
  return pathname.startsWith('/admin') || pathname.startsWith('/data');
}

export function canAccessDataWorkspace(session: SessionLike) {
  return Boolean(session.permissions?.can_access_data_team);
}

export function isRouteAllowedForSession(route: string, session: SessionLike) {
  const normalized = canonicalizeWorkspaceRoute(route);
  const { pathname } = splitRoute(normalized);

  if (pathname.startsWith('/data') && !canAccessDataWorkspace(session)) {
    return false;
  }
  if (!pathname.startsWith('/admin') && !pathname.startsWith('/data')) {
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
  return pathname === '/admin' || pathname === '/data';
}
