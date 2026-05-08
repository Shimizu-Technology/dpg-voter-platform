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
} from 'lucide-react';
import DashboardSkeleton from '../../components/DashboardSkeleton';
import { getCurrentCycle, getDashboard } from '../../lib/api';
import { useSession } from '../../hooks/useSession';
import WorkspacePage from '../../components/WorkspacePage';

interface VillageData {
  id: number;
  name: string;
  region: string;
  registered_voters: number;
  quota_target: number;
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
  observed_elsewhere_count?: number;
}

interface DashboardPayload {
  campaign?: {
    id?: number;
    name?: string;
  };
  summary?: Partial<DashboardSummary>;
  villages?: VillageData[];
}

interface QuotaPeriodSummary {
  id: number;
  name: string;
  due_date: string;
  quota_target: number;
  official_count?: number;
  matched_count?: number;
  total_assigned?: number;
  eligible_count?: number;
  days_until_due?: number;
  overdue?: boolean;
  due_soon?: boolean;
  village_breakdown?: Array<Record<string, unknown>>;
}

interface CurrentCycleResponse {
  current_period?: QuotaPeriodSummary | null;
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
  const { data: cycleData } = useQuery<CurrentCycleResponse>({
    queryKey: ['current-cycle'],
    queryFn: getCurrentCycle,
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
  const period = cycleData?.current_period;
  const periodProgress = Number(period?.official_count ?? period?.total_assigned ?? period?.eligible_count ?? 0);
  const periodTarget = Number(period?.quota_target ?? 0);
  const periodPct = periodTarget > 0 ? Math.round((periodProgress / periodTarget) * 100) : 0;
  const scopedVillageIds = sessionData?.user?.scoped_village_ids ?? null;
  const hasScopedVillageView = scopedVillageIds !== null;
  const hasUnassignedBucket = villages.some((v) => v.name === 'Unassigned');
  const officialVillageCount = Number(
    summary.total_villages || villages.filter((v) => v.name !== 'Unassigned').length
  );
  const villageMeta = new Map<number, VillageData>(villages.map((v) => [v.id, v]));
  const villageProgressRows = Array.isArray(period?.village_breakdown) && period.village_breakdown.length > 0
    ? period.village_breakdown
      .filter((row) => villageMeta.has(Number(row.village_id)))
      .map((row) => {
        const villageId = Number(row.village_id);
        const meta = villageMeta.get(villageId);
        return {
          villageId,
          villageName: String(row.village_name || ''),
          target: Number(row.target || 0),
          progress: Number(row.eligible || 0),
          teamApprovedCount: Number(meta?.team_input_count || 0),
          publicApprovedCount: Number(meta?.public_approved_count || 0),
          teamPendingCount: Number(meta?.team_pending_count || 0),
          publicPendingCount: Number(meta?.public_signup_count || 0),
          route: `/admin/villages/${villageId}`,
        };
      })
    : villages.map((row) => ({
        villageId: row.id,
        villageName: row.name,
        target: Number(row.quota_target || 0),
        progress: Number(row.total_count || 0),
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


      {period && (
        <div className={`rounded-xl border p-5 ${period.overdue ? 'bg-red-50 border-red-200' : period.due_soon ? 'bg-amber-50 border-amber-200' : 'bg-white border-gray-200'}`}>
          <div className="flex items-center justify-between mb-3">
            <div>
              <h2 className="text-sm font-semibold text-gray-700">{period.name} Quota Progress</h2>
              <p className="text-xs text-gray-400 mt-0.5">
                Due {new Date(period.due_date).toLocaleDateString()}
                {period.overdue && <span className="text-red-600 font-semibold ml-1">OVERDUE</span>}
                {period.due_soon && !period.overdue && (
                  <span className="text-amber-600 font-semibold ml-1">({period.days_until_due} days left)</span>
                )}
              </p>
            </div>
            <div className="text-right">
              <div className="text-2xl font-bold text-gray-900">{periodProgress.toLocaleString()}</div>
              <div className="text-xs text-gray-400">of {periodTarget.toLocaleString()} target</div>
            </div>
          </div>
          <div className="w-full h-3 bg-gray-100 rounded-full overflow-hidden">
            <div
              className={`h-full rounded-full transition-all ${periodPct >= 100 ? 'bg-green-500' : periodPct >= 75 ? 'bg-blue-500' : periodPct >= 50 ? 'bg-amber-500' : 'bg-red-400'}`}
              style={{ width: `${Math.min(periodPct, 100)}%` }}
            />
          </div>
          <div className="flex justify-between mt-1.5 text-[10px] text-gray-400">
            <span>{periodPct}% complete</span>
            <span>{Math.max(periodTarget - periodProgress, 0).toLocaleString()} remaining</span>
          </div>
          <div className="mt-2 text-[11px] text-gray-500">
            Current progress counts supporters approved during this period. Matched to GEC: {(period.matched_count || 0).toLocaleString()}.
          </div>
        </div>
      )}

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
        <h2 className="text-sm font-semibold text-gray-700 mb-4">Village Quota Progress</h2>
        <p className="text-xs text-gray-500 mb-3">
          Current Progress counts supporters approved during this quota period. The source columns show how much has already been approved versus what is still waiting on review.
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
                <th className="text-right py-2 px-3 text-xs font-semibold text-gray-400 uppercase">Target</th>
                <th className="text-right py-2 px-3 text-xs font-semibold text-gray-400 uppercase">Current Progress</th>
                <th className="text-right py-2 px-3 text-xs font-semibold text-gray-400 uppercase">Team Approved</th>
                <th className="text-right py-2 px-3 text-xs font-semibold text-gray-400 uppercase">Public Approved</th>
                <th className="text-right py-2 px-3 text-xs font-semibold text-gray-400 uppercase">Team Pending</th>
                <th className="text-right py-2 px-3 text-xs font-semibold text-gray-400 uppercase">Public Pending</th>
                <th className="text-right py-2 px-3 text-xs font-semibold text-gray-400 uppercase">Progress</th>
              </tr>
            </thead>
            <tbody>
              {villageProgressRows.map((v) => {
                const pct = v.target > 0 ? Math.round((v.progress / v.target) * 100) : 0;
                return (
                  <tr key={v.villageId} className="border-b border-gray-50 hover:bg-gray-50">
                    <td className="py-2 px-3 font-medium text-gray-900">
                      <Link to={v.route} className="hover:text-blue-600">
                        {v.villageName}
                      </Link>
                    </td>
                    <td className="py-2 px-3 text-right text-gray-600">{v.target}</td>
                    <td className="py-2 px-3 text-right font-semibold text-green-700">{v.progress}</td>
                    <td className="py-2 px-3 text-right text-gray-600">{v.teamApprovedCount}</td>
                    <td className="py-2 px-3 text-right text-gray-600">{v.publicApprovedCount}</td>
                    <td className="py-2 px-3 text-right text-amber-700">{v.teamPendingCount}</td>
                    <td className="py-2 px-3 text-right text-amber-700">{v.publicPendingCount}</td>
                    <td className="py-2 px-3 text-right">
                      <div className="flex items-center justify-end gap-2">
                        <div className="w-16 h-1.5 bg-gray-100 rounded-full overflow-hidden">
                          <div
                            className={`h-full rounded-full ${pct >= 100 ? 'bg-green-500' : pct >= 50 ? 'bg-blue-500' : 'bg-amber-500'}`}
                            style={{ width: `${Math.min(pct, 100)}%` }}
                          />
                        </div>
                        <span className="text-xs font-medium text-gray-500 w-8 text-right">{pct}%</span>
                      </div>
                    </td>
                  </tr>
                );
              })}
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
