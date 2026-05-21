import { useMemo, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Archive, CalendarDays, CheckCircle2, Loader2, Plus, RefreshCw, Target } from 'lucide-react';
import WorkspacePage from '../../components/WorkspacePage';
import { activateQuotaPeriod, archiveQuotaPeriod, createQuotaPeriod, getQuotaPeriods, updateQuotaPeriod } from '../../lib/api';

type QuotaPeriodCounts = {
  total_contacts: number;
  pending_intake: number;
  active_contacts: number;
  supporters: number;
  qr_signups: number;
  public_signups: number;
  staff_entries?: number;
};

type QuotaPeriod = {
  id: number;
  name: string;
  start_date: string;
  end_date: string;
  due_date: string;
  quota_target: number;
  status: 'open' | 'closed' | 'archived';
  active: boolean;
  campaign_cycle_name?: string | null;
  counts: QuotaPeriodCounts;
};

type QuotaPeriodsResponse = {
  quota_periods: QuotaPeriod[];
  active_quota_period?: QuotaPeriod | null;
};

type PeriodDraft = {
  id?: number;
  name: string;
  start_date: string;
  end_date: string;
  due_date: string;
  quota_target: string;
  status: 'open' | 'closed';
};

const emptyDraft = (): PeriodDraft => {
  const today = new Date();
  const start = new Date(today.getFullYear(), today.getMonth(), 1).toISOString().slice(0, 10);
  const end = new Date(today.getFullYear(), today.getMonth() + 1, 0).toISOString().slice(0, 10);
  return { name: '', start_date: start, end_date: end, due_date: end, quota_target: '0', status: 'closed' };
};

function formatDate(value: string) {
  if (!value) return 'Not set';
  return new Date(`${value}T00:00:00`).toLocaleDateString();
}

function statusLabel(period: QuotaPeriod) {
  if (period.active) return 'Active period';
  if (period.status === 'closed') return 'Closed';
  return 'Archived';
}

function statusClass(period: QuotaPeriod) {
  if (period.active) return 'bg-emerald-50 text-emerald-700';
  if (period.status === 'closed') return 'bg-slate-100 text-slate-700';
  return 'bg-amber-50 text-amber-700';
}

function getErrorMessage(error: unknown) {
  if (error instanceof Error) return error.message;
  if (typeof error === 'object' && error && 'response' in error) {
    const response = (error as { response?: { data?: { message?: string; error?: string } } }).response;
    return response?.data?.message || response?.data?.error || 'The request failed.';
  }
  return 'The request failed.';
}

export default function QuotaPeriodsPage() {
  const queryClient = useQueryClient();
  const [draft, setDraft] = useState<PeriodDraft>(emptyDraft);
  const [notice, setNotice] = useState<{ type: 'success' | 'error'; message: string } | null>(null);
  const { data, isLoading } = useQuery<QuotaPeriodsResponse>({ queryKey: ['quota-periods'], queryFn: getQuotaPeriods });
  const periods = useMemo(() => data?.quota_periods ?? [], [data]);
  const activePeriod = data?.active_quota_period;

  const refreshPeriods = () => {
    void queryClient.invalidateQueries({ queryKey: ['quota-periods'] });
    void queryClient.invalidateQueries({ queryKey: ['referral-codes'] });
    void queryClient.invalidateQueries({ queryKey: ['dashboard'] });
  };

  const saveMutation = useMutation({
    mutationFn: () => {
      const payload = {
        name: draft.name.trim(),
        start_date: draft.start_date,
        end_date: draft.end_date,
        due_date: draft.due_date,
        quota_target: Number(draft.quota_target || 0),
        status: draft.status,
      };
      return draft.id ? updateQuotaPeriod(draft.id, payload) : createQuotaPeriod(payload);
    },
    onSuccess: () => {
      setDraft(emptyDraft());
      setNotice({ type: 'success', message: 'Period saved.' });
      refreshPeriods();
    },
    onError: (error) => setNotice({ type: 'error', message: getErrorMessage(error) }),
  });

  const activateMutation = useMutation({
    mutationFn: (id: number) => activateQuotaPeriod(id),
    onSuccess: () => {
      setNotice({ type: 'success', message: 'Active period updated.' });
      refreshPeriods();
    },
    onError: (error) => setNotice({ type: 'error', message: getErrorMessage(error) }),
  });

  const archiveMutation = useMutation({
    mutationFn: (id: number) => archiveQuotaPeriod(id),
    onSuccess: () => {
      setNotice({ type: 'success', message: 'Period archived.' });
      refreshPeriods();
    },
    onError: (error) => setNotice({ type: 'error', message: getErrorMessage(error) }),
  });

  const canSave = draft.name.trim().length > 1 && draft.start_date && draft.end_date && draft.due_date && !saveMutation.isPending;

  return (
    <WorkspacePage width="full" className="space-y-6">
      <div className="flex flex-col gap-3 lg:flex-row lg:items-end lg:justify-between">
        <div>
          <div className="mb-2 inline-flex items-center gap-2 rounded-full bg-blue-50 px-3 py-1 text-xs font-semibold uppercase tracking-[0.12em] text-blue-700">
            <Target className="h-3.5 w-3.5" />
            DPG periods and goals
          </div>
          <h1 className="text-2xl font-bold tracking-tight text-slate-950">Periods & Goals</h1>
          <p className="mt-1 max-w-3xl text-sm text-slate-600">
            Set the active DPG outreach or quota period so new public signups, QR signups, and staff entries are credited to the right organizing window.
          </p>
        </div>
      </div>

      {notice && (
        <div className={`rounded-xl px-4 py-3 text-sm ${notice.type === 'error' ? 'bg-red-50 text-red-700' : 'bg-emerald-50 text-emerald-700'}`}>
          {notice.message}
        </div>
      )}

      {activePeriod && (
        <section className="app-card p-5">
          <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
            <div>
              <p className="text-xs font-semibold uppercase tracking-[0.1em] text-emerald-700">Current active period</p>
              <h2 className="mt-1 text-xl font-semibold text-slate-950">{activePeriod.name}</h2>
              <p className="mt-1 text-sm text-slate-600">
                {formatDate(activePeriod.start_date)} to {formatDate(activePeriod.end_date)} · due {formatDate(activePeriod.due_date)}
              </p>
            </div>
            <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
              <Stat label="Contacts" value={activePeriod.counts.total_contacts} />
              <Stat label="Pending intake" value={activePeriod.counts.pending_intake} />
              <Stat label="QR signups" value={activePeriod.counts.qr_signups} />
              <Stat label="Supporters" value={activePeriod.counts.supporters} />
            </div>
          </div>
        </section>
      )}

      <section className="grid gap-5 xl:grid-cols-[420px_minmax(0,1fr)]">
        <form
          className="app-card p-5"
          onSubmit={(event) => {
            event.preventDefault();
            if (canSave) saveMutation.mutate();
          }}
        >
          <div className="flex items-center gap-2">
            <Plus className="h-5 w-5 text-primary" />
            <h2 className="text-base font-semibold text-slate-950">{draft.id ? 'Edit period' : 'Create period'}</h2>
          </div>
          <div className="mt-4 space-y-4">
            <label className="block text-sm">
              <span className="font-medium text-slate-700">Name</span>
              <input value={draft.name} onChange={(event) => setDraft((value) => ({ ...value, name: event.target.value }))} className="mt-1 w-full rounded-xl border border-slate-200 px-3 py-2" placeholder="Quota Period 1" />
            </label>
            <div className="grid gap-3 sm:grid-cols-2">
              <label className="block text-sm">
                <span className="font-medium text-slate-700">Start date</span>
                <input type="date" value={draft.start_date} onChange={(event) => setDraft((value) => ({ ...value, start_date: event.target.value }))} className="mt-1 w-full rounded-xl border border-slate-200 px-3 py-2" />
              </label>
              <label className="block text-sm">
                <span className="font-medium text-slate-700">End date</span>
                <input type="date" value={draft.end_date} onChange={(event) => setDraft((value) => ({ ...value, end_date: event.target.value, due_date: value.due_date || event.target.value }))} className="mt-1 w-full rounded-xl border border-slate-200 px-3 py-2" />
              </label>
            </div>
            <div className="grid gap-3 sm:grid-cols-2">
              <label className="block text-sm">
                <span className="font-medium text-slate-700">Due date</span>
                <input type="date" value={draft.due_date} onChange={(event) => setDraft((value) => ({ ...value, due_date: event.target.value }))} className="mt-1 w-full rounded-xl border border-slate-200 px-3 py-2" />
              </label>
              <label className="block text-sm">
                <span className="font-medium text-slate-700">Goal target</span>
                <input type="number" min="0" value={draft.quota_target} onChange={(event) => setDraft((value) => ({ ...value, quota_target: event.target.value }))} className="mt-1 w-full rounded-xl border border-slate-200 px-3 py-2" />
              </label>
            </div>
            <label className="block text-sm">
              <span className="font-medium text-slate-700">Initial status</span>
              <select value={draft.status} onChange={(event) => setDraft((value) => ({ ...value, status: event.target.value as 'open' | 'closed' }))} className="mt-1 w-full rounded-xl border border-slate-200 px-3 py-2">
                <option value="closed">Closed until activated</option>
                <option value="open">Active now</option>
              </select>
            </label>
            <div className="flex flex-col gap-2 sm:flex-row">
              <button type="submit" className="app-btn-primary justify-center" disabled={!canSave}>
                {saveMutation.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <CheckCircle2 className="h-4 w-4" />}
                Save period
              </button>
              {draft.id && (
                <button type="button" className="app-btn-secondary justify-center" onClick={() => setDraft(emptyDraft())}>
                  Cancel edit
                </button>
              )}
            </div>
          </div>
        </form>

        <section className="app-card overflow-hidden">
          <div className="border-b border-slate-100 px-5 py-4">
            <h2 className="text-base font-semibold text-slate-950">Period history</h2>
            <p className="mt-1 text-sm text-slate-600">Only one period can be active at a time. Activating a period automatically closes the previous one.</p>
          </div>
          {isLoading ? (
            <div className="flex items-center gap-2 p-5 text-sm text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading periods...</div>
          ) : periods.length === 0 ? (
            <div className="p-5 text-sm text-slate-500">No periods have been created yet.</div>
          ) : (
            <div className="divide-y divide-slate-100">
              {periods.map((period) => (
                <div key={period.id} className="p-5">
                  <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
                    <div className="min-w-0">
                      <div className="flex flex-wrap items-center gap-2">
                        <h3 className="text-base font-semibold text-slate-950">{period.name}</h3>
                        <span className={`rounded-full px-2.5 py-1 text-xs font-semibold ${statusClass(period)}`}>{statusLabel(period)}</span>
                      </div>
                      <p className="mt-1 text-sm text-slate-600">
                        <CalendarDays className="mr-1 inline h-4 w-4" />
                        {formatDate(period.start_date)} to {formatDate(period.end_date)} · due {formatDate(period.due_date)}
                      </p>
                      <div className="mt-3 grid grid-cols-2 gap-2 sm:grid-cols-4">
                        <Stat label="Contacts" value={period.counts.total_contacts} compact />
                        <Stat label="Intake" value={period.counts.pending_intake} compact />
                        <Stat label="QR" value={period.counts.qr_signups} compact />
                        <Stat label="Supporters" value={period.counts.supporters} compact />
                      </div>
                    </div>
                    <div className="flex flex-col gap-2 sm:flex-row lg:flex-col">
                      <button type="button" className="app-btn-secondary justify-center" onClick={() => setDraft({ id: period.id, name: period.name, start_date: period.start_date, end_date: period.end_date, due_date: period.due_date, quota_target: String(period.quota_target), status: period.status === 'open' ? 'open' : 'closed' })}>
                        Edit
                      </button>
                      {!period.active && (
                        <button type="button" className="app-btn-secondary justify-center" disabled={activateMutation.isPending} onClick={() => activateMutation.mutate(period.id)}>
                          <RefreshCw className="h-4 w-4" />
                          Activate
                        </button>
                      )}
                      {period.active ? (
                        <p className="max-w-40 text-xs leading-relaxed text-slate-500">Activate another period before archiving this one.</p>
                      ) : (
                        <button type="button" className="app-btn-secondary justify-center text-amber-700 hover:bg-amber-50" disabled={archiveMutation.isPending} onClick={() => archiveMutation.mutate(period.id)}>
                          <Archive className="h-4 w-4" />
                          Archive
                        </button>
                      )}
                    </div>
                  </div>
                </div>
              ))}
            </div>
          )}
        </section>
      </section>
    </WorkspacePage>
  );
}

function Stat({ label, value, compact = false }: { label: string; value: number; compact?: boolean }) {
  return (
    <div className={`rounded-xl bg-slate-50 ${compact ? 'px-3 py-2' : 'px-4 py-3'}`}>
      <div className="text-xs font-semibold uppercase tracking-[0.08em] text-slate-500">{label}</div>
      <div className="mt-1 text-lg font-semibold text-slate-950">{Number(value || 0).toLocaleString()}</div>
    </div>
  );
}
