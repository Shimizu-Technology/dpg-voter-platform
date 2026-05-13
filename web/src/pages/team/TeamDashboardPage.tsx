import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { getDashboard, getReportsList } from '../../lib/api';
import { useSession } from '../../hooks/useSession';
import {
  FileSpreadsheet,
  Upload,
  ClipboardPlus,
  CheckCircle,
  ShieldCheck,
  TrendingUp,
  UserCheck,
  Users,
} from 'lucide-react';
import WorkspacePage from '../../components/WorkspacePage';

interface VillageProgressRow {
  villageId: number;
  villageName: string;
  progress: number;
  teamApprovedCount: number;
  publicApprovedCount: number;
  teamPendingCount: number;
  publicPendingCount: number;
}

export default function TeamDashboardPage() {
  const { data: session } = useSession();
  const { data: dashboard, isLoading: dashLoading } = useQuery({
    queryKey: ['dashboard', session?.user?.id ?? 'anonymous'],
    queryFn: getDashboard,
    enabled: !!session?.user?.id,
  });
  const { data: reportsInfo } = useQuery({ queryKey: ['reports-list'], queryFn: getReportsList });

  const counts = session?.counts;
  const summary = dashboard?.summary;
  const quickStats = reportsInfo?.quick_stats;
  const villageProgressRows: VillageProgressRow[] = (dashboard?.villages || []).map((row: Record<string, unknown>) => ({
    villageId: Number(row.id),
    villageName: String(row.name || ''),
    progress: Number(row.total_count || 0),
    teamApprovedCount: Number(row.team_input_count || 0),
    publicApprovedCount: Number(row.public_approved_count || 0),
    teamPendingCount: Number(row.team_pending_count || 0),
    publicPendingCount: Number(row.public_signup_count || 0),
  }));

  if (dashLoading) {
    return (
      <WorkspacePage width="full">
        <div className="animate-pulse space-y-4">
          <div className="h-8 bg-gray-200 rounded w-48" />
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
            {[1, 2, 3, 4].map(i => <div key={i} className="h-28 bg-gray-200 rounded-xl" />)}
          </div>
        </div>
      </WorkspacePage>
    );
  }

  return (
    <WorkspacePage width="full" className="space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold tracking-tight text-gray-900">Data Ops Workspace</h1>
        <p className="text-sm text-gray-500 mt-0.5">Daily voter engagement and outreach operations</p>
      </div>

      {/* Key Metrics */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard
          label="Official Supporters"
          value={summary?.total_supporters ?? counts?.official_supporters ?? 0}
          icon={CheckCircle}
          color="green"
          detail="Approved active supporters"
        />
        <StatCard
          label="Supporter Review Queue"
          value={counts?.pending_vetting || 0}
          icon={ShieldCheck}
          color="amber"
          detail="Pending submissions awaiting data-team approval"
        />
        <StatCard
          label="Pending Public Signups"
          value={counts?.public_signups_pending || 0}
          icon={UserCheck}
          color="blue"
          detail="Waiting for intake review"
        />
        <StatCard
          label="Matched To Voter List"
          value={quickStats?.matched_to_gec ?? counts?.matched_to_gec ?? 0}
          icon={Users}
          color="gray"
          detail="Official supporters matched to the voter list"
        />
      </div>

      {/* Quick Actions */}
      <div>
        <h2 className="text-sm font-semibold text-gray-700 mb-3">Quick Actions</h2>
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
          <QuickAction to="/data/entry" icon={ClipboardPlus} label="Manual Entry" />
          <QuickAction to="/data/import" icon={Upload} label="Excel Import" />
        </div>
      </div>

      {/* Two-column layout */}
      <div className="grid lg:grid-cols-2 gap-6">
        {/* Reports Quick Access */}
        <div className="bg-white rounded-xl border border-gray-200 p-5">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-sm font-semibold text-gray-700">Reports</h2>
            <Link to="/data/reports" className="text-xs text-blue-600 hover:text-blue-700 font-medium">View All</Link>
          </div>
          <div className="space-y-2">
            {quickStats && (
              <>
                <ReportStat label="Official Supporters" value={quickStats.official_supporters ?? quickStats.total_active} />
                <ReportStat label="Matched To Voter List" value={quickStats.matched_to_gec ?? quickStats.total_verified} />
                <ReportStat label="Referral List Size" value={quickStats.referral_list_size ?? 0} />
                <ReportStat label="Mapping Issues" value={quickStats.mapping_issues_list_size ?? 0} />
                <ReportStat label="Purge List Size" value={quickStats.purge_list_size ?? quickStats.purged_voters} />
                <ReportStat label="Unregistered" value={quickStats.unregistered} />
              </>
            )}
            <div className="text-[11px] text-gray-500 pt-1">
              Referrals are official supporters submitted under the wrong village. Mapping Issues are GEC rows that became unassigned or could not be mapped cleanly.
            </div>
            <Link
              to="/data/reports"
              className="mt-3 flex items-center gap-2 px-3 py-2 bg-blue-50 hover:bg-blue-100 rounded-lg text-sm font-medium text-blue-700 transition-colors"
            >
              <FileSpreadsheet className="w-4 h-4" />
              Generate Excel Reports
            </Link>
          </div>
        </div>
      </div>

      {/* Village breakdown */}
      {villageProgressRows.length > 0 && (
        <div className="bg-white rounded-xl border border-gray-200 p-5">
          <h2 className="text-sm font-semibold text-gray-700 mb-4">Village Engagement Progress</h2>
          <p className="text-xs text-gray-500 mb-3">
            Current progress counts approved supporter records by village.
          </p>
          <div className="overflow-x-auto">
            <table className="w-full text-sm min-w-[920px]">
              <thead>
                <tr className="border-b border-gray-100">
                  <th className="text-left py-2 px-3 text-xs font-semibold text-gray-400 uppercase">Village</th>
                  <th className="text-right py-2 px-3 text-xs font-semibold text-gray-400 uppercase">Supporters</th>
                  <th className="text-right py-2 px-3 text-xs font-semibold text-gray-400 uppercase">Team Approved</th>
                  <th className="text-right py-2 px-3 text-xs font-semibold text-gray-400 uppercase">Public Approved</th>
                  <th className="text-right py-2 px-3 text-xs font-semibold text-gray-400 uppercase">Team Pending</th>
                  <th className="text-right py-2 px-3 text-xs font-semibold text-gray-400 uppercase">Public Pending</th>
                </tr>
              </thead>
              <tbody>
                {villageProgressRows.map((v) => (
                    <tr key={v.villageId} className="border-b border-gray-50 hover:bg-gray-50">
                      <td className="py-2 px-3 font-medium text-gray-900">{v.villageName}</td>
                      <td className="py-2 px-3 text-right font-semibold text-green-700">{v.progress}</td>
                      <td className="py-2 px-3 text-right text-gray-600">{v.teamApprovedCount}</td>
                      <td className="py-2 px-3 text-right text-gray-600">{v.publicApprovedCount}</td>
                      <td className="py-2 px-3 text-right text-amber-700">{v.teamPendingCount}</td>
                      <td className="py-2 px-3 text-right text-amber-700">{v.publicPendingCount}</td>
                    </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </WorkspacePage>
  );
}

function StatCard({ label, value, icon: Icon, color, detail, to }: {
  label: string;
  value: number;
  icon: React.ComponentType<{ className?: string }>;
  color: string;
  detail: string;
  to?: string;
}) {
  const colorMap: Record<string, string> = {
    green: 'bg-green-50 text-green-600 border-green-100',
    amber: 'bg-amber-50 text-amber-600 border-amber-100',
    blue: 'bg-blue-50 text-blue-600 border-blue-100',
    gray: 'bg-gray-50 text-gray-600 border-gray-100',
  };

  const content = (
    <div className={`p-4 rounded-xl border ${colorMap[color]} ${to ? 'hover:shadow-md transition-shadow cursor-pointer' : ''}`}>
      <div className="flex items-center justify-between mb-2">
        <Icon className="w-5 h-5 opacity-70" />
        {to && <TrendingUp className="w-3.5 h-3.5 opacity-40" />}
      </div>
      <div className="text-2xl font-bold">{value.toLocaleString()}</div>
      <div className="text-xs font-medium opacity-70 mt-0.5">{label}</div>
      <div className="text-[10px] opacity-50 mt-0.5">{detail}</div>
    </div>
  );

  return to ? <Link to={to}>{content}</Link> : content;
}

function QuickAction({ to, icon: Icon, label }: { to: string; icon: React.ComponentType<{ className?: string }>; label: string }) {
  return (
    <Link
      to={to}
      className="flex flex-col items-center gap-2 p-4 bg-white rounded-xl border border-gray-200 hover:border-blue-200 hover:shadow-sm transition-all text-center"
    >
      <Icon className="w-5 h-5 text-gray-500" />
      <span className="text-xs font-medium text-gray-700">{label}</span>
    </Link>
  );
}

function ReportStat({ label, value }: { label: string; value: number }) {
  return (
    <div className="flex justify-between text-sm py-1">
      <span className="text-gray-500">{label}</span>
      <span className="font-semibold text-gray-900">{(value || 0).toLocaleString()}</span>
    </div>
  );
}
