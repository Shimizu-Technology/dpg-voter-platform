import { useQuery } from '@tanstack/react-query';
import { useParams, Link } from 'react-router-dom';
import { getVillage } from '../../lib/api';
import { ChevronLeft, MapPin, Info } from 'lucide-react';
import { useSession } from '../../hooks/useSession';
import WorkspacePage from '../../components/WorkspacePage';

interface PrecinctDetail {
  id: number;
  number: string;
  alpha_range: string;
  supporter_count: number;
  polling_site: string;
  registered_voters: number;
}

interface BlockDetail {
  id: number;
  name: string;
  supporter_count: number;
}

interface VillageDetail {
  name: string;
  region: string;
  registered_voters: number;
  official_supporters_count?: number;
  matched_to_gec_count?: number;
  current_period_progress?: number;
  current_period_target?: number;
  current_period_matched_count?: number;
  current_period_name?: string | null;
  current_period_due_date?: string | null;
  current_period_progress_pct?: number;
  team_approved_count?: number;
  public_approved_count?: number;
  team_pending_count?: number;
  public_pending_count?: number;
  latest_gec_list_date?: string | null;
  verified_count?: number;
  total_count?: number;
  unverified_count?: number;
  supporter_count: number;
  quota_target: number;
  unassigned_precinct_count: number;
  precincts: PrecinctDetail[];
  blocks: BlockDetail[];
}

function supporterLabel(count: number) {
  return `${count} supporter${count === 1 ? '' : 's'}`;
}

export default function VillageDetailPage() {
  const { id } = useParams();
  const { data: sessionData } = useSession();
  const returnTo = `/admin/villages/${id}`;
  const { data, isLoading } = useQuery({
    queryKey: ['village', id],
    queryFn: () => getVillage(Number(id)),
  });

  if (isLoading) return <div className="min-h-screen flex items-center justify-center text-[var(--text-muted)]">Loading...</div>;

  const v: VillageDetail | undefined = data?.village;
  if (!v) return <div className="p-8 text-center text-[var(--text-muted)]">Village not found</div>;

  const canAccessDataTeam = sessionData?.permissions?.can_access_data_team ?? false;
  const officialSupporters = v.official_supporters_count ?? v.supporter_count ?? 0;
  const matchedToGec = v.matched_to_gec_count ?? v.verified_count ?? 0;
  const currentPeriodProgress = v.current_period_progress ?? 0;
  const currentPeriodTarget = v.current_period_target ?? v.quota_target ?? 0;
  const currentPeriodPct = typeof v.current_period_progress_pct === 'number'
    ? v.current_period_progress_pct
    : currentPeriodTarget > 0
      ? Number(((currentPeriodProgress / currentPeriodTarget) * 100).toFixed(1))
      : 0;
  const currentPeriodName = v.current_period_name || 'Current Period';
  const currentPeriodDueLabel = v.current_period_due_date
    ? new Date(v.current_period_due_date).toLocaleDateString()
    : null;
  const latestGecListLabel = v.latest_gec_list_date
    ? new Date(v.latest_gec_list_date).toLocaleDateString()
    : 'latest GEC list';

  return (
    <WorkspacePage width="full" className="space-y-6">
      <div>
        <Link
          to="/admin"
          className="inline-flex items-center gap-1.5 text-sm text-gray-500 hover:text-gray-900 mb-3"
        >
          <ChevronLeft className="w-4 h-4" />
          Back to Campaign Operations
        </Link>
        <h1 className="text-2xl font-bold text-gray-900 tracking-tight flex items-center gap-2">
          <MapPin className="w-6 h-6 text-primary" /> {v.name}
        </h1>
        <p className="text-gray-500 text-sm">
          {v.region} · {v.registered_voters.toLocaleString()} registered voters (from {latestGecListLabel})
        </p>
      </div>

      <div className="app-card p-6 space-y-4">
        <div className="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
          <div>
            <h2 className="text-lg font-semibold text-gray-900">{currentPeriodName} Quota Progress</h2>
            <p className="text-sm text-gray-500">
              Current Progress counts supporters approved during this quota period.
              {currentPeriodDueLabel ? ` Due ${currentPeriodDueLabel}.` : ''}
            </p>
          </div>
          <div className="text-right">
            <div className="text-2xl font-bold text-gray-900">
              {currentPeriodProgress.toLocaleString()} / {currentPeriodTarget.toLocaleString()}
            </div>
            <div className="text-xs text-gray-500">
              {Math.max(currentPeriodTarget - currentPeriodProgress, 0).toLocaleString()} remaining
            </div>
          </div>
        </div>
        <div className="w-full bg-[var(--surface-overlay)] rounded-full h-4">
          <div
            className={`h-4 rounded-full ${currentPeriodPct >= 75 ? 'bg-green-500' : currentPeriodPct >= 50 ? 'bg-yellow-500' : 'bg-red-500'}`}
            style={{ width: `${Math.min(currentPeriodPct, 100)}%` }}
          />
        </div>
        <div className="flex items-start gap-2 text-xs text-[var(--text-secondary)]">
          <Info className="w-3.5 h-3.5 mt-0.5 shrink-0" />
          <p>
            <strong>Official Supporters</strong> is the all-time approved active supporter count for this village.
            <strong> Matched To GEC</strong> shows how many of those official supporters have a current voter-list match.
          </p>
        </div>
      </div>

      <div className="grid grid-cols-2 xl:grid-cols-3 gap-4">
        <MetricCard label="Official Supporters" value={officialSupporters} tone="green" />
        <MetricCard label="Matched To GEC" value={matchedToGec} tone="slate" />
        <MetricCard label="Team Approved" value={v.team_approved_count || 0} tone="purple" />
        <MetricCard label="Public Approved" value={v.public_approved_count || 0} tone="blue" />
        <MetricCard
          label="Team Pending"
          value={v.team_pending_count || 0}
          tone="amber"
          link={canAccessDataTeam && (v.team_pending_count || 0) > 0 ? `/data/vetting?village_id=${id}&source_group=team&return_to=${encodeURIComponent(returnTo)}` : undefined}
        />
        <MetricCard
          label="Public Pending"
          value={v.public_pending_count || 0}
          tone="amber"
          link={canAccessDataTeam && (v.public_pending_count || 0) > 0 ? `/data/public-review?village_id=${id}&return_to=${encodeURIComponent(returnTo)}` : undefined}
        />
      </div>

      <div>
        <h2 className="app-section-title text-xl mb-4">Precincts</h2>
        <p className="text-sm text-[var(--text-secondary)] mb-4">
          Precinct cards below show approved official supporters for this village. Use them to drill into supporter lists for field and outreach work.
        </p>
        {v.unassigned_precinct_count > 0 && (
          <div className="bg-yellow-500/10 border border-yellow-500/30 text-yellow-800 rounded-xl p-3 mb-4 text-sm">
            {v.unassigned_precinct_count} official supporter{v.unassigned_precinct_count > 1 ? "s are" : " is"} in this village without a precinct assignment.
            {" "}
            <Link
              to={`/admin/supporters?village_id=${id}&unassigned_precinct=true&status=active&return_to=${encodeURIComponent(returnTo)}`}
              className="underline font-medium hover:text-yellow-900"
            >
              View and assign
            </Link>
            .
          </div>
        )}
        <div className="grid md:grid-cols-2 gap-4 mb-8">
          {v.precincts.map((p) => (
            <Link
              key={p.id}
              to={`/admin/supporters?village_id=${id}&precinct_id=${p.id}&status=active&return_to=${encodeURIComponent(returnTo)}`}
              className="app-card p-4 block hover:shadow-md transition-shadow"
            >
              <div className="flex justify-between items-center">
                <div>
                  <span className="font-semibold text-[var(--text-primary)]">Precinct {p.number}</span>
                  <span className="text-sm text-[var(--text-secondary)] ml-2">({p.alpha_range})</span>
                </div>
                <span className="text-sm text-[var(--text-secondary)]">{supporterLabel(p.supporter_count)}</span>
              </div>
              <p className="text-xs text-[var(--text-muted)] mt-1">{p.polling_site} · {p.registered_voters} registered voters (GEC)</p>
            </Link>
          ))}
        </div>

        {v.blocks.length > 0 && (
          <>
            <h2 className="app-section-title text-xl mb-4">Blocks</h2>
            <div className="grid md:grid-cols-3 gap-4">
              {v.blocks.map((b) => (
                <div key={b.id} className="app-card p-4">
                  <span className="font-medium text-[var(--text-primary)]">{b.name}</span>
                  <span className="text-sm text-[var(--text-secondary)] ml-2">{supporterLabel(b.supporter_count)}</span>
                </div>
              ))}
            </div>
          </>
        )}
      </div>
    </WorkspacePage>
  );
}

function MetricCard({ label, value, tone, link }: { label: string; value: number; tone: 'green' | 'slate' | 'purple' | 'blue' | 'amber'; link?: string }) {
  const toneClasses: Record<string, string> = {
    green: 'bg-green-50 border-green-100 text-green-700',
    slate: 'bg-slate-50 border-slate-100 text-slate-700',
    purple: 'bg-purple-50 border-purple-100 text-purple-700',
    blue: 'bg-blue-50 border-blue-100 text-blue-700',
    amber: 'bg-amber-50 border-amber-100 text-amber-700',
  };

  const content = (
    <div className={`rounded-xl border p-4 ${toneClasses[tone]} ${link ? 'hover:shadow-sm transition-shadow cursor-pointer' : ''}`}>
      <div className="text-2xl font-bold">{value.toLocaleString()}</div>
      <div className="text-xs font-medium mt-1 opacity-80">{label}</div>
      {link && <div className="text-[10px] mt-1 opacity-65">Open queue</div>}
    </div>
  );

  return link ? <Link to={link}>{content}</Link> : content;
}
