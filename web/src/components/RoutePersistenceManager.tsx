import { useEffect, useMemo, useRef } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { useSession } from '../hooks/useSession';
import {
  canonicalizeWorkspaceRoute,
  isRouteAllowedForSession,
  isWorkspaceRoute,
  rememberLastRoute,
  resolvePreferredRoute,
  shouldAttemptInitialRouteRestore,
} from '../lib/workspaceRouting';

export default function RoutePersistenceManager() {
  const location = useLocation();
  const navigate = useNavigate();
  const { data: sessionData, isLoading } = useSession();
  const attemptedInitialRestoreRef = useRef(false);

  const currentRoute = useMemo(
    () => canonicalizeWorkspaceRoute(`${location.pathname}${location.search}`),
    [location.pathname, location.search]
  );

  useEffect(() => {
    if (isLoading || !sessionData?.user?.id) return;
    if (!attemptedInitialRestoreRef.current && shouldAttemptInitialRouteRestore(currentRoute)) return;
    if (!isWorkspaceRoute(currentRoute)) return;
    if (!isRouteAllowedForSession(currentRoute, sessionData)) return;

    rememberLastRoute(sessionData.user.id, currentRoute);
  }, [currentRoute, isLoading, sessionData]);

  useEffect(() => {
    if (attemptedInitialRestoreRef.current || isLoading || !sessionData) return;
    attemptedInitialRestoreRef.current = true;

    if (!shouldAttemptInitialRouteRestore(currentRoute)) return;

    const preferredRoute = resolvePreferredRoute(sessionData, currentRoute);
    if (preferredRoute && preferredRoute !== currentRoute) {
      navigate(preferredRoute, { replace: true });
    }
  }, [currentRoute, isLoading, navigate, sessionData]);

  return null;
}
