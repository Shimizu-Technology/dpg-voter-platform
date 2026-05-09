import type { ComponentType } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import {
  CheckCircle,
  ShieldCheck,
  UserCheck,
  Users,
  ClipboardPlus,
  ClipboardCheck,
  Upload,
  FileSpreadsheet,
  TrendingUp,
} from 'lucide-react';
import DashboardSkeleton from '../../components/DashboardSkeleton';
import { getDashboard } from '../../lib/api';
import { useSession } from '../../hooks/useSession';
import WorkspacePage from '../../components/WorkspacePage';

interface VillageData {
  id: number;
  name: string;
  region: string;
  registered_voters: number;
  total_count: number;
  team_input_count?: number;
  public_approved_count?: number;
  team_pending_count?: number;
  public_signup_count?: number;
}

interface DashboardSummary {
  total_supporters: number;
  total_registered_voters: number;
  total_villages: number;
}

interface DashboardPayload {
  campaign?: {
    id?: number;
    name?: string;
  };
  summary?: Partial<DashboardSummary>;
  villages?: VillageData[];
}


export default function DashboardPage() {
  const { data: sessionData } = useSession();
  const { data: dashboard, isLoading, isError } = useQuery<DashboardPayload>({
    queryKey: ['dashboard', sessionData?.user?.id ?? 'anonymous'],
    queryFn: getDashboard,
    enabled: !!sessionData?.user?.id,
    retry: (failureCount, error) => {
      const status = (error as { response?: { status?: number } })?.response?.status;
      if (status === 401 || status === 403) return false;
      return failureCount < 1;
    },
  });

  if (isLoading) {
    return <DashboardSkeleton />;
  }

  if (isError || !dashboard) {
    return (
      <div className="flex items-center justify-center py-32 px-4">
        <div className="text-center max-w-sm">
          <div className="w-16 h-16 mx-auto mb-5 rounded-2xl bg-(--surface-overlay) flex items-center justify-center">
            <Users className="w-8 h-8 text-(--text-muted)" />
          </div>
          <h2 className="text-xl font-bold text-(--text-primary) mb-2">Can&apos;t connect to server</h2>
          <p className="text-(--text-secondary) mb-6 text-sm leading-relaxed">Check your connection and try again.</p>
          <button onClick={() => window.location.reload()} className="app-btn-primary">
            Retry
          </button>
        </div>
      </div>
    );
  }

  const counts = sessionData?.counts;
  const permissions = sessionData?.permissions;
  const summary = dashboard.summary || {};
  const villages = Array.isArray(dashboard.villages) ? dashboard.villages : [];
  const scopedVillageIds = sessionData?.user?.scoped_village_ids ?? null;
  const hasScopedVillageView = scopedVillageIds !== null;
  const hasUnassignedBucket = villages.some((v) => v.name === 'Unassigned');
  const officialVillageCount = Number(
    summary.total_villages || villages.filter((v) => v.name !== 'Unassigned').length
  );
  const villageProgressRows = villages.map((row) => ({
    villageId: row.id,
    villageName: row.name,
    supporters: Number(row.total_count || 0),
    teamApprovedCount: Number(row.team_input_count || 0),
    publicApprovedCount: Number(row.public_approved_count || 0),
    teamPendingCount: Number(row.team_pending_count || 0),
    publicPendingCount: Number(row.public_signup_count || 0),
    route: `/admin/villages/${row.id}`,
  }));

  const quickActions = [
    permissions?.can_create_staff_supporters ? { to: '/admin/supporters/new', icon: ClipboardPlus, label: 'New Entry' } : null,
    permissions?.can_import_supporters ? { to: '/admin/import', icon: Upload, label: 'Excel Import' } : null,
    permissions?.can_access_reports ? { to: '/admin/reports', icon: FileSpreadsheet, label: 'Reports' } : null,
    permissions?.can_view_supporters ? { to: '/admin/supporters', icon: ClipboardCheck, label: 'Supporters' } : null,
  ].filter(Boolean) as Array<{ to: string; icon: ComponentType<{ className?: string }>; label: string }>;

  return (
    <WorkspacePage width="full" className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-(--text-primary) tracking-tight">DPG Voter Engagement</h1>
        <p className="text-sm text-(--text-secondary) mt-1">
          Track public signups, supporter records, voter-help follow-up, and outreach activity for the Democratic Party of Guam.
        </p>
      </div>

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard
          label="Official Supporters"
          value={Number(summary.total_supporters ?? counts?.official_supporters ?? 0)}
          icon={CheckCircle}
          color="green"
          detail="Approved active supporters"
          to={permissions?.can_view_supporters ? '/admin/supporters' : undefined}
        />
        <StatCard
          label="Supporter Review Queue"
          value={counts?.pending_vetting ?? 0}
          icon={ShieldCheck}
          color="amber"
          detail="Submitted entries still waiting for data-team approval"
        />
        <StatCard
          label="Pending Public Signups"
          value={counts?.public_signups_pending ?? 0}
          icon={UserCheck}
          color="blue"
          detail="Separate public submissions waiting on intake review"
        />
        <StatCard
          label="Matched To Voter List"
          value={counts?.matched_to_gec ?? 0}
          icon={Users}
          color="gray"
          detail="Official supporters matched to the voter list"
        />
      </div>


      {quickActions.length > 0 && (
        <div>
          <h2 className="text-sm font-semibold text-gray-700 mb-3">Quick Actions</h2>
          <div className="grid grid-cols-2 sm:grid-cols-3 xl:grid-cols-6 gap-3">
            {quickActions.map((action) => (
              <QuickAction key={action.to} to={action.to} icon={action.icon} label={action.label} />
            ))}
          </div>
          <p className="mt-3 text-xs text-gray-500">
            Staff submissions created here go to the data team&apos;s review workflow before they count as official supporters.
          </p>
        </div>
      )}

      <div className="bg-white rounded-xl border border-gray-200 p-5">
        <h2 className="text-sm font-semibold text-gray-700 mb-4">Village Engagement Summary</h2>
        <p className="text-xs text-gray-500 mb-3">
          Supporter counts show approved records and pending submissions by village.
        </p>
        {hasScopedVillageView && (
          <p className="text-xs text-gray-500 mb-3">
            Top metrics stay island-wide for leadership awareness. This table is limited to your assigned area.
          </p>
        )}
        {!hasScopedVillageView && (
          <p className="text-xs text-gray-500 mb-3">
            Showing {officialVillageCount} official villages across the island{hasUnassignedBucket ? ' plus the Unassigned bucket' : ''}.
          </p>
        )}
        <div className="overflow-x-auto">
          <table className="w-full text-sm min-w-[940px]">
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
                    <td className="py-2 px-3 font-medium text-gray-900">
                      <Link to={v.route} className="hover:text-blue-600">
                        {v.villageName}
                      </Link>
                    </td>
                    <td className="py-2 px-3 text-right font-semibold text-green-700">{v.supporters}</td>
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
    </WorkspacePage>
  );
}

function StatCard({ label, value, icon: Icon, color, detail, to }: {
  label: string;
  value: number;
  icon: ComponentType<{ className?: string }>;
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

function QuickAction({ to, icon: Icon, label }: { to: string; icon: ComponentType<{ className?: string }>; label: string }) {
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
