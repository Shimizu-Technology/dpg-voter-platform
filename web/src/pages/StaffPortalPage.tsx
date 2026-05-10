import { SignedIn, SignedOut, SignInButton } from '@clerk/clerk-react';
import { Link, Navigate } from 'react-router-dom';
import WorkspaceBrandPanel from '../components/WorkspaceBrandPanel';
import { useSession } from '../hooks/useSession';
import { resolvePreferredRoute } from '../lib/workspaceRouting';

export default function StaffPortalPage() {
  const { data: sessionData, isLoading } = useSession();
  const destination = sessionData ? resolvePreferredRoute(sessionData) : '/admin';

  return (
    <>
      <SignedIn>
        {isLoading ? (
          <div className="min-h-screen flex items-center justify-center bg-(--surface-bg)">
            <div className="flex flex-col items-center gap-3">
              <div className="w-8 h-8 border-[3px] border-(--border-soft) border-t-blue-500 rounded-full animate-spin" />
              <div className="text-(--text-muted) text-sm">Loading your workspace...</div>
            </div>
          </div>
        ) : (
          <Navigate to={destination} replace />
        )}
      </SignedIn>
      <SignedOut>
        <div className="min-h-screen bg-[#f6f8fc] px-4 py-10">
          <div className="mx-auto flex min-h-[calc(100vh-5rem)] max-w-md items-center justify-center">
            <div className="w-full space-y-5">
              <WorkspaceBrandPanel
                centered
                workspaceName="Staff Portal"
                workspaceDescription="Sign in to reach DPG Operations or the Data Ops Workspace."
                badge="Internal DPG workspace"
              />
              <div className="rounded-[28px] border border-slate-200 bg-white p-8 text-center shadow-[0_24px_60px_-32px_rgba(15,42,91,0.35)]">
                <h1 className="mb-2 text-2xl font-bold text-gray-900">Staff Sign In</h1>
                <p className="mb-6 text-gray-500">Sign in to access your staff workspace</p>
                <SignInButton mode="modal">
                  <button className="w-full rounded-xl bg-primary py-3 text-lg font-bold text-white transition-all hover:bg-primary-dark">
                    Sign In
                  </button>
                </SignInButton>
                <p className="mt-4 text-xs text-gray-400">
                  Contact your DPG admin for an account
                </p>
                <Link
                  to="/"
                  className="mt-4 inline-flex items-center justify-center text-sm font-medium text-primary hover:text-primary-dark"
                >
                  Back to Home
                </Link>
              </div>
            </div>
          </div>
        </div>
      </SignedOut>
    </>
  );
}
