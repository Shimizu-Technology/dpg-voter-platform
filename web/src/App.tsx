import { lazy, Suspense } from 'react';
import { BrowserRouter, Link, Navigate, Route, Routes, useLocation } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { Shield } from 'lucide-react';
import AdminLayout from './components/AdminLayout';
import AnalyticsTracker from './components/AnalyticsTracker';
import PublicHeadManager from './components/PublicHeadManager';
import RoutePersistenceManager from './components/RoutePersistenceManager';
import TeamLayout from './components/TeamLayout';
import { useSession } from './hooks/useSession';
import { resolvePreferredRoute } from './lib/workspaceRouting';

// Public pages
import LandingPage from './pages/LandingPage';
import SignupPage from './pages/SignupPage';
import StaffPortalPage from './pages/StaffPortalPage';
import ThankYouPage from './pages/ThankYouPage';

// Core DPG workspace pages
const DashboardPage = lazy(() => import('./pages/admin/DashboardPage'));
const SupportersPage = lazy(() => import('./pages/admin/SupportersPage'));
const SupporterDetailPage = lazy(() => import('./pages/admin/SupporterDetailPage'));
const StaffEntryPage = lazy(() => import('./pages/admin/StaffEntryPage'));
const VillageDetailPage = lazy(() => import('./pages/admin/VillageDetailPage'));
const SmsPage = lazy(() => import('./pages/admin/SmsPage'));
const SmsSettingsPage = lazy(() => import('./pages/admin/SmsSettingsPage'));
const EmailPage = lazy(() => import('./pages/admin/EmailPage'));
const UsersPage = lazy(() => import('./pages/admin/UsersPage'));
const DistrictsPage = lazy(() => import('./pages/admin/DistrictsPage'));
const PrecinctSettingsPage = lazy(() => import('./pages/admin/PrecinctSettingsPage'));
const DuplicatesPage = lazy(() => import('./pages/admin/DuplicatesPage'));
const ImportPage = lazy(() => import('./pages/admin/ImportPage'));
const AuditLogsPage = lazy(() => import('./pages/admin/AuditLogsPage'));
const OutreachPage = lazy(() => import('./pages/admin/OutreachPage'));
const TeamDashboardPage = lazy(() => import('./pages/team/TeamDashboardPage'));
const TeamReportsPage = lazy(() => import('./pages/team/TeamReportsPage'));

function LazyFallback() {
  return (
    <div className="min-h-screen flex items-center justify-center bg-(--surface-bg)">
      <div className="w-8 h-8 border-[3px] border-(--border-soft) border-t-blue-500 rounded-full animate-spin" />
    </div>
  );
}

const queryClient = new QueryClient({
  defaultOptions: {
    queries: { staleTime: 30_000 },
  },
});

function AdminRoute({ children }: { children: React.ReactNode }) {
  return <AdminLayout>{children}</AdminLayout>;
}

type PermissionKey =
  | 'can_manage_users'
  | 'can_manage_configuration'
  | 'can_manage_data_configuration'
  | 'can_send_sms'
  | 'can_send_email'
  | 'can_edit_supporters'
  | 'can_view_supporters'
  | 'can_create_staff_supporters'
  | 'can_import_supporters'
  | 'can_access_reports'
  | 'can_access_duplicates'
  | 'can_access_audit_logs'
  | 'can_access_data_team';

function PermissionRoute({ permission, children }: { permission: PermissionKey; children: React.ReactNode }) {
  const { data, isLoading } = useSession();
  const location = useLocation();

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-32">
        <div className="w-8 h-8 border-[3px] border-(--border-soft) border-t-blue-500 rounded-full animate-spin" />
      </div>
    );
  }

  const defaultRoute = data?.permissions?.default_route || '/admin';
  const fallbackRoute = data ? resolvePreferredRoute(data, `${location.pathname}${location.search}`) : defaultRoute;

  if (!data?.permissions?.[permission]) {
    return (
      <div className="flex items-center justify-center py-32 px-4">
        <div className="app-card p-8 max-w-sm w-full text-center">
          <div className="w-14 h-14 mx-auto mb-4 rounded-2xl bg-red-500/10 flex items-center justify-center">
            <Shield className="w-7 h-7 text-red-400" />
          </div>
          <h1 className="text-xl font-bold text-(--text-primary) mb-2">Not Authorized</h1>
          <p className="text-sm text-(--text-secondary) mb-6 leading-relaxed">Your role does not have access to this tool.</p>
          <Link to={fallbackRoute} className="app-btn-primary">
            Back to Workspace
          </Link>
        </div>
      </div>
    );
  }

  return <>{children}</>;
}

export default function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>
        <PublicHeadManager />
        <AnalyticsTracker />
        <RoutePersistenceManager />
        <Suspense fallback={<LazyFallback />}>
          <Routes>
            {/* Public — no auth required */}
            <Route path="/" element={<LandingPage />} />
            <Route path="/signup" element={<SignupPage />} />
            <Route path="/signup/:leaderCode" element={<SignupPage />} />
            <Route path="/staff" element={<StaffPortalPage />} />
            <Route path="/thank-you" element={<ThankYouPage />} />

            {/* Admin — requires Clerk auth */}
            <Route path="/admin" element={<AdminRoute><DashboardPage /></AdminRoute>} />
            <Route path="/admin/supporters" element={<AdminRoute><PermissionRoute permission="can_view_supporters"><SupportersPage /></PermissionRoute></AdminRoute>} />
            <Route path="/admin/supporters/:id" element={<AdminRoute><PermissionRoute permission="can_view_supporters"><SupporterDetailPage /></PermissionRoute></AdminRoute>} />
            <Route path="/admin/supporters/new" element={<AdminRoute><PermissionRoute permission="can_create_staff_supporters"><StaffEntryPage /></PermissionRoute></AdminRoute>} />
            <Route path="/admin/import" element={<AdminRoute><PermissionRoute permission="can_import_supporters"><ImportPage /></PermissionRoute></AdminRoute>} />
            <Route path="/admin/reports" element={<AdminRoute><PermissionRoute permission="can_access_reports"><TeamReportsPage /></PermissionRoute></AdminRoute>} />
            <Route path="/admin/duplicates" element={<AdminRoute><PermissionRoute permission="can_access_duplicates"><DuplicatesPage /></PermissionRoute></AdminRoute>} />
            <Route path="/admin/villages/:id" element={<AdminRoute><PermissionRoute permission="can_view_supporters"><VillageDetailPage /></PermissionRoute></AdminRoute>} />
            <Route path="/admin/sms" element={<AdminRoute><PermissionRoute permission="can_send_sms"><SmsPage /></PermissionRoute></AdminRoute>} />
            <Route path="/admin/sms/settings" element={<AdminRoute><PermissionRoute permission="can_manage_configuration"><SmsSettingsPage /></PermissionRoute></AdminRoute>} />
            <Route path="/admin/email" element={<AdminRoute><PermissionRoute permission="can_send_email"><EmailPage /></PermissionRoute></AdminRoute>} />
            <Route path="/admin/users" element={<AdminRoute><PermissionRoute permission="can_manage_users"><UsersPage /></PermissionRoute></AdminRoute>} />
            <Route path="/admin/districts" element={<AdminRoute><PermissionRoute permission="can_manage_configuration"><DistrictsPage /></PermissionRoute></AdminRoute>} />
            <Route path="/admin/precincts" element={<AdminRoute><PermissionRoute permission="can_manage_configuration"><PrecinctSettingsPage /></PermissionRoute></AdminRoute>} />
            <Route path="/admin/outreach" element={<AdminRoute><PermissionRoute permission="can_view_supporters"><OutreachPage /></PermissionRoute></AdminRoute>} />
            <Route path="/admin/audit-logs" element={<AdminRoute><PermissionRoute permission="can_access_audit_logs"><AuditLogsPage /></PermissionRoute></AdminRoute>} />

            {/* Data Ops routes */}
            <Route path="/data" element={<TeamLayout><TeamDashboardPage /></TeamLayout>} />
            <Route path="/data/supporters" element={<TeamLayout><SupportersPage /></TeamLayout>} />
            <Route path="/data/supporters/:id" element={<TeamLayout><PermissionRoute permission="can_view_supporters"><SupporterDetailPage /></PermissionRoute></TeamLayout>} />
            <Route path="/data/reports" element={<TeamLayout><PermissionRoute permission="can_access_reports"><TeamReportsPage /></PermissionRoute></TeamLayout>} />
            <Route path="/data/entry" element={<TeamLayout><StaffEntryPage /></TeamLayout>} />
            <Route path="/data/import" element={<TeamLayout><PermissionRoute permission="can_import_supporters"><ImportPage /></PermissionRoute></TeamLayout>} />
            <Route path="/data/duplicates" element={<TeamLayout><DuplicatesPage /></TeamLayout>} />
            <Route path="/data/audit-logs" element={<TeamLayout><AuditLogsPage /></TeamLayout>} />
            <Route path="/data/users" element={<TeamLayout><PermissionRoute permission="can_manage_users"><UsersPage /></PermissionRoute></TeamLayout>} />
            <Route path="/data/districts" element={<TeamLayout><PermissionRoute permission="can_manage_data_configuration"><DistrictsPage /></PermissionRoute></TeamLayout>} />
            <Route path="/data/precincts" element={<TeamLayout><PermissionRoute permission="can_manage_data_configuration"><PrecinctSettingsPage /></PermissionRoute></TeamLayout>} />
            <Route path="/data/campaign-settings" element={<TeamLayout><PermissionRoute permission="can_manage_configuration"><SmsSettingsPage /></PermissionRoute></TeamLayout>} />

            {/* Legacy /team aliases */}
            <Route path="/team" element={<Navigate to="/data" replace />} />
            <Route path="/team/supporters" element={<Navigate to="/data/supporters" replace />} />
            <Route path="/team/reports" element={<Navigate to="/data/reports" replace />} />
            <Route path="/team/entry" element={<Navigate to="/data/entry" replace />} />
            <Route path="/team/import" element={<Navigate to="/data/import" replace />} />
            <Route path="/team/duplicates" element={<Navigate to="/data/duplicates" replace />} />
            <Route path="/team/audit-logs" element={<Navigate to="/data/audit-logs" replace />} />
            <Route path="/team/users" element={<Navigate to="/data/users" replace />} />
            <Route path="/team/districts" element={<Navigate to="/data/districts" replace />} />
            <Route path="/team/precincts" element={<Navigate to="/data/precincts" replace />} />
            <Route path="/team/campaign-settings" element={<Navigate to="/data/campaign-settings" replace />} />
          </Routes>
        </Suspense>
      </BrowserRouter>
    </QueryClientProvider>
  );
}
