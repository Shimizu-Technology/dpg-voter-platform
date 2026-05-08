import { useMemo, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Save, Search, Target, TrendingUp } from 'lucide-react';
import { getCurrentCycle, getQuotaPeriod, getQuotas, updateVillageQuota, getSettings, updateSettings } from '../../lib/api';
import WorkspacePage from '../../components/WorkspacePage';

interface QuotaItem {
  village_id: number;
  village_name: string;
  region: string | null;
  registered_voters: number;
  quota_id: number | null;
  target_count: number;
  period: string | null;
  target_date: string | null;
  updated_at: string | null;
}

interface QuotasResponse {
  campaign?: {
    id: number;
    name: string;
    election_year: number;
  };
  latest_gec_list_date?: string | null;
  current_period?: {
    id: number;
    name: string;
    due_date: string;
    quota_target: number;
  } | null;
  quotas: QuotaItem[];
}

interface SettingsResponse {
  show_pace: boolean;
}

interface QuotaPeriodSummary {
  id: number;
  name: string;
  start_date: string;
  end_date: string;
  due_date: string;
  quota_target: number;
  status: string;
  official_count?: number;
  matched_count?: number;
  eligible_count?: number;
  days_until_due?: number;
  overdue?: boolean;
  due_soon?: boolean;
  editable?: boolean;
  locked?: boolean;
}

interface QuotaHistoryRow {
  village_id: number;
  village_name: string;
  target: number;
  eligible: number;
  matched: number;
  total_assigned?: number;
}

interface QuotaPeriodDetail extends QuotaPeriodSummary {
  campaign_cycle_id: number;
  campaign_cycle_name: string;
  total_assigned: number;
  submission_summary?: {
    submitted_at?: string;
  } | null;
  village_breakdown: QuotaHistoryRow[];
}

interface CurrentCycleResponse {
  current_period?: QuotaPeriodSummary | null;
  periods: QuotaPeriodSummary[];
}

interface QuotaPeriodDetailResponse {
  quota_period: QuotaPeriodDetail;
}

export default function QuotaSettingsPage() {
  const queryClient = useQueryClient();
  const { data, isLoading, isError } = useQuery<QuotasResponse>({
    queryKey: ['quotas'],
    queryFn: getQuotas,
  });
  const { data: settings } = useQuery<SettingsResponse>({
    queryKey: ['settings'],
    queryFn: getSettings,
  });
  const { data: currentCycleData } = useQuery<CurrentCycleResponse>({
    queryKey: ['current-cycle'],
    queryFn: getCurrentCycle,
  });
  const paceMutation = useMutation({
    mutationFn: (showPace: boolean) => updateSettings({ show_pace: showPace }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['settings'] });
      queryClient.invalidateQueries({ queryKey: ['dashboard'] });
      queryClient.invalidateQueries({ queryKey: ['current-cycle'] });
      queryClient.invalidateQueries({ queryKey: ['reports-list'] });
    },
  });
  const [search, setSearch] = useState('');
  const [pendingByVillage, setPendingByVillage] = useState<Record<number, string>>({});
  const [changeNote, setChangeNote] = useState('');
  const [notice, setNotice] = useState<string | null>(null);
  const [selectedPeriodId, setSelectedPeriodId] = useState<number | null>(null);

  const mutation = useMutation({
    mutationFn: ({ villageId, targetCount }: { villageId: number; targetCount: number }) =>
      updateVillageQuota(villageId, targetCount, changeNote.trim() || undefined),
    onSuccess: (_payload, vars) => {
      setPendingByVillage((prev) => {
        const next = { ...prev };
        delete next[vars.villageId];
        return next;
      });
      queryClient.invalidateQueries({ queryKey: ['quotas'] });
      queryClient.invalidateQueries({ queryKey: ['quota-period'] });
      queryClient.invalidateQueries({ queryKey: ['dashboard'] });
      queryClient.invalidateQueries({ queryKey: ['village'] });
      queryClient.invalidateQueries({ queryKey: ['current-cycle'] });
      queryClient.invalidateQueries({ queryKey: ['reports-list'] });
      setNotice('Quota updated');
      window.setTimeout(() => setNotice(null), 2500);
    },
  });

  const quotas = useMemo(() => data?.quotas || [], [data?.quotas]);
  const historyPeriods = useMemo(
    () => [...(currentCycleData?.periods || [])].sort((a, b) => new Date(b.start_date).getTime() - new Date(a.start_date).getTime()),
    [currentCycleData?.periods]
  );
  const activeSelectedPeriodId = selectedPeriodId ?? currentCycleData?.current_period?.id ?? historyPeriods[0]?.id ?? null;

  const { data: selectedPeriodData } = useQuery<QuotaPeriodDetailResponse>({
    queryKey: ['quota-period', activeSelectedPeriodId],
    queryFn: () => getQuotaPeriod(activeSelectedPeriodId as number),
    enabled: activeSelectedPeriodId !== null,
  });

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    if (!q) return quotas;
    return quotas.filter((item) =>
      item.village_name.toLowerCase().includes(q) ||
      (item.region || '').toLowerCase().includes(q)
    );
  }, [quotas, search]);

  const totalTarget = quotas.reduce((sum, row) => sum + row.target_count, 0);
  const totalVoters = quotas.reduce((sum, row) => sum + row.registered_voters, 0);
  const currentPeriod = data?.current_period;
  const selectedPeriod = selectedPeriodData?.quota_period || null;
  const selectedBreakdown = useMemo(
    () => [...(selectedPeriod?.village_breakdown || [])].sort((a, b) => a.village_name.localeCompare(b.village_name)),
    [selectedPeriod?.village_breakdown]
  );
  const historyProgress = Number(selectedPeriod?.eligible_count ?? selectedPeriod?.official_count ?? selectedPeriod?.total_assigned ?? 0);
  const historyTarget = Number(selectedPeriod?.quota_target ?? 0);
  const historyPct = historyTarget > 0 ? Math.round((historyProgress / historyTarget) * 100) : 0;
  const historyRemaining = Math.max(historyTarget - historyProgress, 0);
  const latestGecListLabel = data?.latest_gec_list_date ? new Date(data.latest_gec_list_date).toLocaleDateString() : 'latest GEC list';
  const currentEditorLabel = currentPeriod ? `Edit ${currentPeriod.name} Targets` : 'Edit Current Month Targets';
  const viewingHistoricalPeriod = Boolean(selectedPeriod && currentPeriod && selectedPeriod.id !== currentPeriod.id);
  const selectedPeriodStatusLabel = selectedPeriod
    ? selectedPeriod.submission_summary?.submitted_at
      ? 'Submitted period'
      : selectedPeriod.locked
        ? 'Locked historical period'
        : 'Open current period'
    : '';

  const effectiveValue = (row: QuotaItem) => {
    const pending = pendingByVillage[row.village_id];
    return pending ?? String(row.target_count);
  };

  const hasChanged = (row: QuotaItem) => {
    const parsed = Number(effectiveValue(row));
    return Number.isFinite(parsed) && parsed !== row.target_count;
  };

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-20">
        <div className="text-[var(--text-muted)] text-sm font-medium">Loading quotas...</div>
      </div>
    );
  }

  if (isError) {
    return (
      <div className="flex items-center justify-center py-20">
        <div className="app-card p-6 text-center max-w-md">
          <h1 className="text-xl font-bold text-[var(--text-primary)] mb-2">Could not load quotas</h1>
          <p className="text-sm text-[var(--text-secondary)] mb-4">Please refresh and try again.</p>
          <button
            type="button"
            onClick={() => window.location.reload()}
            className="bg-primary text-white px-4 py-2 rounded-xl min-h-[44px]"
          >
            Retry
          </button>
        </div>
      </div>
    );
  }

  return (
    <WorkspacePage width="full" className="space-y-6">
      <div>
        <h1 className="text-xl font-bold text-gray-900 flex items-center gap-2">
          <Target className="w-5 h-5 text-primary" /> Monthly Quota Settings
        </h1>
        <p className="text-gray-500 text-sm">
          Set village goals for the current month. The dashboard's monthly quota target is automatically calculated from these village totals.
        </p>
      </div>

      {currentPeriod && (
        <div className="app-card p-4">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
            <div className="border border-[var(--border-soft)] rounded-xl px-3 py-3 bg-[var(--surface-bg)]">
              <div className="text-xs font-semibold uppercase tracking-wide text-[var(--text-muted)]">Current Period</div>
              <div className="mt-1 text-base font-semibold text-[var(--text-primary)]">{currentPeriod.name}</div>
              <div className="text-xs text-[var(--text-secondary)]">
                Due {new Date(currentPeriod.due_date).toLocaleDateString()}
              </div>
            </div>
            <div className="border border-[var(--border-soft)] rounded-xl px-3 py-3 bg-[var(--surface-bg)]">
              <div className="text-xs font-semibold uppercase tracking-wide text-[var(--text-muted)]">Monthly Goal</div>
              <div className="mt-1 text-base font-semibold text-[var(--text-primary)]">
                {currentPeriod.quota_target.toLocaleString()}
              </div>
              <div className="text-xs text-[var(--text-secondary)]">Derived from the village goals below</div>
            </div>
            <div className="border border-[var(--border-soft)] rounded-xl px-3 py-3 bg-[var(--surface-bg)]">
              <div className="text-xs font-semibold uppercase tracking-wide text-[var(--text-muted)]">How Weekly Pace Works</div>
              <div className="mt-1 text-sm font-medium text-[var(--text-primary)]">Calculated automatically</div>
              <div className="text-xs text-[var(--text-secondary)]">Staff do not need to set a separate weekly goal</div>
            </div>
          </div>
        </div>
      )}

      {historyPeriods.length > 0 && (
        <div className="app-card p-4 space-y-4">
          <div className="flex flex-col gap-3 lg:flex-row lg:items-end lg:justify-between">
            <div>
              <h2 className="text-base font-semibold text-[var(--text-primary)]">Quota History</h2>
              <p className="text-sm text-[var(--text-secondary)]">
                Review the current month or switch to an earlier quota period to see how that month finished.
              </p>
            </div>
            <div className="w-full lg:w-80">
              <label htmlFor="quota-history-period" className="block text-xs font-semibold uppercase tracking-wide text-[var(--text-muted)] mb-1">
                Quota Period
              </label>
              <select
                id="quota-history-period"
                value={activeSelectedPeriodId ?? ''}
                onChange={(e) => setSelectedPeriodId(Number(e.target.value))}
                className="w-full px-3 py-2 border border-[var(--border-soft)] rounded-xl min-h-[44px] bg-white"
              >
                {historyPeriods.map((period) => (
                  <option key={period.id} value={period.id}>
                    {period.name} ({new Date(period.start_date).toLocaleDateString()} - {new Date(period.end_date).toLocaleDateString()})
                  </option>
                ))}
              </select>
            </div>
          </div>

          {selectedPeriod && (
            <>
              <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-3">
                <HistoryCard
                  label="Selected Period"
                  value={selectedPeriod.name}
                  detail={`Due ${new Date(selectedPeriod.due_date).toLocaleDateString()} · ${selectedPeriodStatusLabel}`}
                />
                <HistoryCard
                  label="Current Progress"
                  value={`${historyProgress.toLocaleString()} / ${historyTarget.toLocaleString()}`}
                  detail={`${historyRemaining.toLocaleString()} remaining`}
                />
                <HistoryCard
                  label="Matched To GEC"
                  value={(selectedPeriod.matched_count ?? 0).toLocaleString()}
                  detail="Official supporters in this period matched to the voter list"
                />
                <HistoryCard
                  label="Snapshot"
                  value={selectedPeriod.locked ? 'Locked' : 'Live'}
                  detail={
                    selectedPeriod.submission_summary?.submitted_at
                      ? `Submitted ${new Date(selectedPeriod.submission_summary.submitted_at).toLocaleString()}`
                      : selectedPeriod.locked
                        ? 'Past periods are read-only and no longer change when current targets are updated'
                      : 'Counts will keep updating until this period is submitted'
                  }
                />
              </div>

              <div className="space-y-2">
                <div className="flex items-center justify-between text-sm">
                  <span className="font-medium text-[var(--text-primary)]">{historyPct}% of goal reached</span>
                  <span className="text-[var(--text-secondary)]">
                    {historyProgress.toLocaleString()} of {historyTarget.toLocaleString()}
                  </span>
                </div>
                <div className="w-full h-3 bg-gray-100 rounded-full overflow-hidden">
                  <div
                    className={`h-full rounded-full transition-all ${
                      historyPct >= 100 ? 'bg-green-500' : historyPct >= 75 ? 'bg-blue-500' : historyPct >= 50 ? 'bg-amber-500' : 'bg-red-400'
                    }`}
                    style={{ width: `${Math.min(historyPct, 100)}%` }}
                  />
                </div>
                <p className="text-xs text-[var(--text-secondary)]">
                  Current Progress counts supporters approved during this period. Locked or submitted periods stay read-only so past months do not shift when current goals change.
                </p>
              </div>

              <div className="overflow-x-auto border border-[var(--border-soft)] rounded-2xl">
                <table className="w-full text-sm min-w-[720px]">
                  <thead>
                    <tr className="border-b bg-[var(--surface-bg)]">
                      <th className="text-left px-4 py-3 font-medium text-[var(--text-secondary)]">Village</th>
                      <th className="text-right px-4 py-3 font-medium text-[var(--text-secondary)]">Target</th>
                      <th className="text-right px-4 py-3 font-medium text-[var(--text-secondary)]">Current Progress</th>
                      <th className="text-right px-4 py-3 font-medium text-[var(--text-secondary)]">Matched To GEC</th>
                      <th className="text-right px-4 py-3 font-medium text-[var(--text-secondary)]">Progress</th>
                    </tr>
                  </thead>
                  <tbody>
                    {selectedBreakdown.map((row) => {
                      const target = Number(row.target ?? 0);
                      const eligible = Number(row.eligible ?? 0);
                      const matched = Number(row.matched ?? 0);
                      const pct = target > 0 ? Math.round((eligible / target) * 100) : 0;
                      return (
                        <tr key={row.village_id} className="border-b last:border-b-0">
                          <td className="px-4 py-3 font-medium text-[var(--text-primary)]">{row.village_name}</td>
                          <td className="px-4 py-3 text-right tabular-nums text-[var(--text-secondary)]">{target.toLocaleString()}</td>
                          <td className="px-4 py-3 text-right tabular-nums font-semibold text-green-700">{eligible.toLocaleString()}</td>
                          <td className="px-4 py-3 text-right tabular-nums text-[var(--text-secondary)]">{matched.toLocaleString()}</td>
                          <td className="px-4 py-3 text-right">
                            <div className="flex items-center justify-end gap-2">
                              <div className="w-20 h-1.5 bg-gray-100 rounded-full overflow-hidden">
                                <div
                                  className={`h-full rounded-full ${pct >= 100 ? 'bg-green-500' : pct >= 50 ? 'bg-blue-500' : 'bg-amber-500'}`}
                                  style={{ width: `${Math.min(pct, 100)}%` }}
                                />
                              </div>
                              <span className="text-xs font-medium text-[var(--text-secondary)] w-9 text-right">{pct}%</span>
                            </div>
                          </td>
                        </tr>
                      );
                    })}
                    {selectedBreakdown.length === 0 && (
                      <tr>
                        <td colSpan={5} className="px-4 py-8 text-center text-[var(--text-muted)]">
                          {selectedPeriod.locked
                            ? 'This historical period does not have locked village target rows yet.'
                            : 'No village quota data is available for this period yet.'}
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>
            </>
          )}
        </div>
      )}

      {/* Pace Tracking Toggle */}
      <div className="app-card p-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="w-9 h-9 rounded-xl bg-blue-50 flex items-center justify-center">
              <TrendingUp className="w-[18px] h-[18px] text-blue-500" />
            </div>
            <div>
              <p className="text-sm font-semibold text-[var(--text-primary)]">Pace Tracking</p>
              <p className="text-xs text-[var(--text-secondary)]">
                Show expected progress and weekly targets on the dashboard
              </p>
            </div>
          </div>
          <button
            type="button"
            role="switch"
            aria-checked={settings?.show_pace ?? false}
            disabled={paceMutation.isPending}
            onClick={() => paceMutation.mutate(!(settings?.show_pace ?? false))}
            className={`relative inline-flex h-7 w-12 items-center rounded-full transition-colors focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 ${
              settings?.show_pace ? 'bg-primary' : 'bg-gray-300'
            } ${paceMutation.isPending ? 'opacity-50' : ''}`}
          >
            <span
              className={`inline-block h-5 w-5 transform rounded-full bg-white shadow-sm transition-transform ${
                settings?.show_pace ? 'translate-x-6' : 'translate-x-1'
              }`}
            />
          </button>
        </div>
      </div>

      <div className="space-y-4">
        <div className={`app-card p-4 ${viewingHistoricalPeriod ? 'border border-amber-200 bg-amber-50/60' : ''}`}>
          <div className="flex flex-col gap-2 md:flex-row md:items-start md:justify-between">
            <div>
              <h2 className="text-base font-semibold text-[var(--text-primary)]">{currentEditorLabel}</h2>
              <p className="text-sm text-[var(--text-secondary)]">
                This section always edits the current month. The quota-period dropdown above only changes the history view.
              </p>
            </div>
            {currentPeriod && (
              <div className="text-xs font-medium text-[var(--text-secondary)]">
                Currently editing: <span className="text-[var(--text-primary)]">{currentPeriod.name}</span>
              </div>
            )}
          </div>
          {viewingHistoricalPeriod && selectedPeriod && currentPeriod && (
            <div className="mt-3 rounded-xl border border-amber-200 bg-white px-3 py-2 text-xs text-amber-800">
              You are viewing <span className="font-semibold">{selectedPeriod.name}</span> history above, but any changes below will apply to <span className="font-semibold">{currentPeriod.name}</span>.
            </div>
          )}
        </div>

        <div className="app-card p-4">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-3 mb-3">
            <div className="relative">
              <Search className="w-4 h-4 absolute left-3 top-3 text-[var(--text-muted)]" />
              <input
                type="text"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="Search village or region..."
                className="w-full pl-9 pr-3 py-2 border border-[var(--border-soft)] rounded-xl min-h-[44px]"
              />
            </div>
            <input
              type="text"
              value={changeNote}
              onChange={(e) => setChangeNote(e.target.value)}
              placeholder="Change note (optional)"
              className="w-full px-3 py-2 border border-[var(--border-soft)] rounded-xl min-h-[44px]"
            />
            <div className="border border-[var(--border-soft)] rounded-xl px-3 py-2 bg-[var(--surface-bg)] min-h-[44px] flex items-center justify-between text-sm">
              <span className="text-[var(--text-secondary)]">Current monthly goal</span>
              <span className="font-semibold text-[var(--text-primary)]">{totalTarget.toLocaleString()}</span>
            </div>
          </div>
          <div className="text-xs text-[var(--text-secondary)]">
            Total registered voters: <span className="font-semibold">{totalVoters.toLocaleString()}</span> (from {latestGecListLabel})
          </div>
          {notice && <p className="text-sm text-green-700 mt-2">{notice}</p>}
        </div>

        <div className="app-card overflow-x-auto">
          <table className="w-full text-sm min-w-[640px]">
            <thead>
              <tr className="border-b bg-[var(--surface-bg)]">
                <th className="text-left px-4 py-3 font-medium text-[var(--text-secondary)]">Village</th>
                <th className="text-left px-4 py-3 font-medium text-[var(--text-secondary)]">Region</th>
                <th className="text-right px-4 py-3 font-medium text-[var(--text-secondary)]">Registered Voters</th>
                <th className="text-left px-4 py-3 font-medium text-[var(--text-secondary)]">Quota Target</th>
                <th className="text-left px-4 py-3 font-medium text-[var(--text-secondary)]">Updated</th>
                <th className="text-left px-4 py-3 font-medium text-[var(--text-secondary)]">Action</th>
              </tr>
            </thead>
            <tbody>
              {filtered.map((row) => {
                const candidate = Number(effectiveValue(row));
                const invalid = !Number.isFinite(candidate) || candidate <= 0;
                return (
                  <tr key={row.village_id} className="border-b">
                    <td className="px-4 py-3 font-medium text-[var(--text-primary)]">{row.village_name}</td>
                    <td className="px-4 py-3 text-[var(--text-secondary)]">{row.region || '—'}</td>
                    <td className="px-4 py-3 text-right tabular-nums text-[var(--text-secondary)]">{row.registered_voters.toLocaleString()}</td>
                    <td className="px-4 py-3">
                      <input
                        type="number"
                        min={1}
                        value={effectiveValue(row)}
                        onChange={(e) => setPendingByVillage((prev) => ({ ...prev, [row.village_id]: e.target.value }))}
                        className="border border-[var(--border-soft)] rounded-xl px-3 py-2 min-h-[44px] w-32"
                      />
                    </td>
                    <td className="px-4 py-3 text-[var(--text-secondary)]">{row.updated_at ? new Date(row.updated_at).toLocaleString() : '—'}</td>
                    <td className="px-4 py-3">
                      <button
                        type="button"
                        disabled={mutation.isPending || invalid || !hasChanged(row)}
                        onClick={() => {
                          if (!window.confirm(`Update quota target for ${row.village_name} to ${candidate.toLocaleString()}?`)) return;
                          mutation.mutate({ villageId: row.village_id, targetCount: candidate });
                        }}
                        className="bg-primary text-white px-3 py-2 rounded-xl min-h-[44px] text-xs font-medium flex items-center gap-1 disabled:opacity-50"
                      >
                        <Save className="w-3.5 h-3.5" /> Save
                      </button>
                    </td>
                  </tr>
                );
              })}
              {filtered.length === 0 && (
                <tr>
                  <td colSpan={6} className="px-4 py-8 text-center text-[var(--text-muted)]">
                    No villages match current search.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>

        <p className="text-xs text-[var(--text-secondary)]">
          Voter counts are from GEC precinct data based on {latestGecListLabel}. To update voter numbers, go to Precinct Settings. Village goals set here drive the current month's overall quota target shown on the dashboard and reports.
        </p>
      </div>
    </WorkspacePage>
  );
}

function HistoryCard({ label, value, detail }: { label: string; value: string; detail: string }) {
  return (
    <div className="border border-[var(--border-soft)] rounded-xl px-3 py-3 bg-[var(--surface-bg)]">
      <div className="text-xs font-semibold uppercase tracking-wide text-[var(--text-muted)]">{label}</div>
      <div className="mt-1 text-base font-semibold text-[var(--text-primary)]">{value}</div>
      <div className="text-xs text-[var(--text-secondary)]">{detail}</div>
    </div>
  );
}
