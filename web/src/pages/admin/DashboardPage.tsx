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
  Target,
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
  total_contacts?: number;
  new_intake_count?: number;
  supporter_count?: number;
  volunteer_count?: number;
  needs_follow_up_count?: number;
  matched_to_gec_count?: number;
  team_input_count?: number;
  public_approved_count?: number;
  team_pending_count?: number;
  public_signup_count?: number;
}

interface DashboardSummary {
  total_contacts: number;
  new_intake: number;
  supporters: number;
  volunteers: number;
  needs_follow_up: number;
  matched_to_gec: number;
  total_supporters: number;
  total_registered_voters: number;
  total_villages: number;
}

interface ActiveQuotaPeriod {
  id: number;
  name: string;
  start_date: string;
  end_date: string;
  due_date: string;
  quota_target: number;
  status: string;
  counts: {
    total_contacts: number;
    pending_intake: number;
    active_contacts: number;
    supporters: number;
    qr_signups: number;
    public_signups: number;
  };
}

interface DashboardPayload {
  campaign?: {
    id?: number;
    name?: string;
  };
  active_quota_period?: ActiveQuotaPeriod | null;
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
  const activeQuotaPeriod = dashboard.active_quota_period;
  const villageProgressRows = villages.map((row) => ({
    villageId: row.id,
    villageName: row.name,
    contacts: Number(row.total_contacts ?? row.total_count ?? 0),
    intake: Number(row.new_intake_count ?? row.team_pending_count ?? 0),
    matched: Number(row.matched_to_gec_count ?? 0),
    followUp: Number(row.needs_follow_up_count ?? 0),
    supporters: Number(row.supporter_count ?? 0),
    route: `/admin/villages/${row.id}`,
  }));

  const quickActions = [
    permissions?.can_create_staff_supporters ? { to: '/admin/supporters/new', icon: ClipboardPlus, label: 'New Entry' } : null,
    permissions?.can_import_supporters ? { to: '/admin/import', icon: Upload, label: 'Import Contacts' } : null,
    permissions?.can_access_reports ? { to: '/admin/reports', icon: FileSpreadsheet, label: 'Reports' } : null,
    permissions?.can_view_supporters ? { to: '/admin/supporters', icon: ClipboardCheck, label: 'Contacts' } : null,
    permissions?.can_view_supporters ? { to: '/admin/intake', icon: UserCheck, label: 'Intake' } : null,
  ].filter(Boolean) as Array<{ to: string; icon: ComponentType<{ className?: string }>; label: string }>;

  return (
    <WorkspacePage width="full" className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-(--text-primary) tracking-tight">DPG Voter Engagement</h1>
        <p className="text-sm text-(--text-secondary) mt-1">
          Track public signups, supporter records, voter-help follow-up, and outreach activity for the Democratic Party of Guam.
        </p>
      </div>

      {activeQuotaPeriod && (
        <Link to="/admin/periods" className="block rounded-xl border border-emerald-100 bg-emerald-50/70 p-5 transition hover:border-emerald-200 hover:bg-emerald-50">
          <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
            <div>
              <div className="inline-flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.1em] text-emerald-700">
                <Target className="h-4 w-4" />
                Active period
              </div>
              <h2 className="mt-2 text-lg font-semibold text-slate-950">{activeQuotaPeriod.name}</h2>
              <p className="mt-1 text-sm text-slate-600">
                {new Date(`${activeQuotaPeriod.start_date}T00:00:00`).toLocaleDateString()} to {new Date(`${activeQuotaPeriod.end_date}T00:00:00`).toLocaleDateString()}
              </p>
            </div>
            <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
              <MiniPeriodStat label="Intake" value={activeQuotaPeriod.counts.pending_intake} />
              <MiniPeriodStat label="Active contacts" value={activeQuotaPeriod.counts.active_contacts} />
              <MiniPeriodStat label="Supporters" value={activeQuotaPeriod.counts.supporters} />
            </div>
          </div>
          <DashboardGoalProgress period={activeQuotaPeriod} />
        </Link>
      )}

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard
          label="Official Supporters"
          value={Number(summary.supporters ?? counts?.supporters ?? counts?.official_supporters ?? 0)}
          icon={CheckCircle}
          color="green"
          detail="Contacts marked as supporters"
          to={permissions?.can_view_supporters ? '/admin/supporters' : undefined}
        />
        <StatCard
          label="New Intake"
          value={Number(summary.new_intake ?? counts?.new_intake ?? counts?.pending_vetting ?? 0)}
          icon={ShieldCheck}
          color="amber"
          detail="New contacts to classify"
          to={permissions?.can_view_supporters ? '/admin/intake' : undefined}
        />
        <StatCard
          label="Total Contacts"
          value={Number(summary.total_contacts ?? counts?.total_contacts ?? summary.total_supporters ?? 0)}
          icon={UserCheck}
          color="blue"
          detail="Visible DPG contact list"
          to={permissions?.can_view_supporters ? '/admin/supporters' : undefined}
        />
        <StatCard
          label="Matched To Voter List"
          value={Number(summary.matched_to_gec ?? counts?.matched_to_gec ?? 0)}
          icon={Users}
          color="gray"
          detail="Contacts matched to GEC"
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
        </div>
      )}

      <div className="bg-white rounded-xl border border-gray-200 p-5">
        <h2 className="text-sm font-semibold text-gray-700 mb-4">Village Engagement Summary</h2>
        <p className="text-xs text-gray-500 mb-3">
          Contact counts show all active DPG contacts, new intake, GEC matches, and follow-up needs by village.
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
                <th className="text-right py-2 px-3 text-xs font-semibold text-gray-400 uppercase">Contacts</th>
                <th className="text-right py-2 px-3 text-xs font-semibold text-gray-400 uppercase">Intake</th>
                <th className="text-right py-2 px-3 text-xs font-semibold text-gray-400 uppercase">GEC Matches</th>
                <th className="text-right py-2 px-3 text-xs font-semibold text-gray-400 uppercase">Follow-Up</th>
                <th className="text-right py-2 px-3 text-xs font-semibold text-gray-400 uppercase">Supporters</th>
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
                    <td className="py-2 px-3 text-right font-semibold text-blue-700">{v.contacts}</td>
                    <td className="py-2 px-3 text-right text-amber-700">{v.intake}</td>
                    <td className="py-2 px-3 text-right text-green-700">{v.matched}</td>
                    <td className="py-2 px-3 text-right text-red-700">{v.followUp}</td>
                    <td className="py-2 px-3 text-right text-gray-600">{v.supporters}</td>
                  </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </WorkspacePage>
  );
}

function DashboardGoalProgress({ period }: { period: ActiveQuotaPeriod }) {
  const goal = Number(period.quota_target || 0);
  const current = Number(period.counts.supporters || 0);
  const percent = goal > 0 ? Math.min(100, Math.round((current / goal) * 100)) : 0;

  return (
    <div className="mt-4">
      <div className="mb-2 flex flex-wrap items-center justify-between gap-2 text-sm">
        <span className="font-semibold text-emerald-900">Overall supporter goal</span>
        <span className="text-emerald-800/80">
          {current.toLocaleString()} / {goal > 0 ? goal.toLocaleString() : 'No goal set'}{goal > 0 ? ` · ${percent}%` : ''}
        </span>
      </div>
      <div className="h-2.5 overflow-hidden rounded-full bg-white/80">
        <div className="h-full rounded-full bg-emerald-500 transition-all" style={{ width: `${goal > 0 ? percent : 0}%` }} />
      </div>
    </div>
  );
}

function MiniPeriodStat({ label, value }: { label: string; value: number }) {
  return (
    <div className="rounded-lg bg-white/75 px-3 py-2">
      <div className="text-[11px] font-semibold uppercase tracking-[0.08em] text-emerald-700">{label}</div>
      <div className="mt-1 text-lg font-semibold text-slate-950">{Number(value || 0).toLocaleString()}</div>
    </div>
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
