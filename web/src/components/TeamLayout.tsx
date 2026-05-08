import { SignedIn, SignedOut, SignInButton, useAuth, useClerk } from '@clerk/clerk-react';
import { useEffect, useRef } from 'react';
import { Navigate } from 'react-router-dom';
import { useQueryClient } from '@tanstack/react-query';
import api, { getSession } from '../lib/api';
import TeamShell from './TeamShell';
import WorkspaceBrandPanel from './WorkspaceBrandPanel';
import { useSession } from '../hooks/useSession';
import { identifyStaffUser, isAnalyticsEnabled } from '../lib/analytics';
import { resolvePreferredRoute } from '../lib/workspaceRouting';

function getHttpStatus(error: unknown): number | undefined {
  const maybeAxiosError = error as { response?: { status?: number } };
  return maybeAxiosError.response?.status;
}

function isAuthError(error: unknown): boolean {
  const status = getHttpStatus(error);
  return status === 401 || status === 403;
}

function hasSufficientTokenLifetime(authHeader: string, minimumSecondsRemaining = 5): boolean {
  const token = authHeader.replace(/^Bearer\s+/i, '').trim();
  const parts = token.split('.');
  if (parts.length !== 3) return false;

  try {
    const payloadBase64 = parts[1].replace(/-/g, '+').replace(/_/g, '/');
    const decodedPayload = atob(payloadBase64.padEnd(payloadBase64.length + ((4 - (payloadBase64.length % 4)) % 4), '='));
    const payload = JSON.parse(decodedPayload) as { exp?: number };
    if (typeof payload.exp !== 'number') return false;

    const nowSeconds = Math.floor(Date.now() / 1000);
    return payload.exp - nowSeconds > minimumSecondsRemaining;
  } catch {
    return false;
  }
}

export default function TeamLayout({ children }: { children: React.ReactNode }) {
  const { getToken, userId } = useAuth();
  const { session } = useClerk();
  const queryClient = useQueryClient();
  const interceptorRef = useRef<number | null>(null);
  const readyRef = useRef(false);

  useEffect(() => {
    // Install Axios request interceptor for auth
    interceptorRef.current = api.interceptors.request.use(
      async (config) => {
        // Skip if already has a valid token
        const existing = config.headers?.Authorization as string | undefined;
        if (existing && hasSufficientTokenLifetime(existing)) return config;

        try {
          const token = await getToken();
          if (token) {
            config.headers = config.headers || {};
            config.headers.Authorization = `Bearer ${token}`;
          }
        } catch (err) {
          if (!isAuthError(err)) throw err;
          // Token refresh failed — try getting a new session
          try {
            const freshSession = await session?.reload();
            if (freshSession) {
              const token = await getToken();
              if (token) {
                config.headers = config.headers || {};
                config.headers.Authorization = `Bearer ${token}`;
              }
            }
          } catch {
            // Give up
          }
        }
        return config;
      },
      (error) => Promise.reject(error),
    );

    readyRef.current = true;

    return () => {
      if (interceptorRef.current !== null) {
        api.interceptors.request.eject(interceptorRef.current);
      }
    };
  }, [getToken, session]);

  // Pre-fetch session data
  useEffect(() => {
    if (!userId) return;
    queryClient.prefetchQuery({ queryKey: ['session', userId], queryFn: getSession });
  }, [queryClient, userId]);

  return (
    <>
      <SignedIn>
        <TeamAccessGuard>
          <TeamShell>{children}</TeamShell>
        </TeamAccessGuard>
      </SignedIn>
      <SignedOut>
        <div className="min-h-screen bg-[#f6f8fc] px-4 py-10">
          <div className="mx-auto flex min-h-[calc(100vh-5rem)] max-w-md items-center justify-center">
            <div className="w-full space-y-5">
              <WorkspaceBrandPanel
                centered
                workspaceName="Data Ops Workspace"
                workspaceDescription="Daily voter operations, imports, and supporter review."
                badge="Staff workspace"
              />
              <div className="rounded-[28px] border border-slate-200 bg-white p-8 text-center shadow-[0_24px_60px_-32px_rgba(15,42,91,0.35)]">
                <h1 className="mb-2 text-xl font-bold text-gray-900">Data Ops Sign In</h1>
                <p className="mb-6 text-sm text-gray-500">Sign in to access the daily voter operations tools.</p>
                <SignInButton mode="modal">
                  <button className="w-full rounded-xl bg-primary px-4 py-3 text-sm font-bold text-white transition-colors hover:bg-primary-dark">
                    Sign In
                  </button>
                </SignInButton>
              </div>
            </div>
          </div>
        </div>
      </SignedOut>
    </>
  );
}

function TeamAccessGuard({ children }: { children: React.ReactNode }) {
  const { data, isLoading } = useSession();
  const identifiedUserRef = useRef<string | null>(null);

  useEffect(() => {
    if (!isAnalyticsEnabled || !data?.user) return;

    const identifyKey = `${data.user.id}:${data.user.role}`;
    if (identifiedUserRef.current === identifyKey) return;

    identifyStaffUser(data.user);
    identifiedUserRef.current = identifyKey;
  }, [data]);

  if (isLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-100">
        <div className="w-8 h-8 border-[3px] border-gray-200 border-t-blue-500 rounded-full animate-spin" />
      </div>
    );
  }

  const fallbackRoute = data ? resolvePreferredRoute(data, '/data') : '/admin';
  if (!data?.permissions?.can_access_data_team) {
    return <Navigate to={fallbackRoute} replace />;
  }

  return <>{children}</>;
}
