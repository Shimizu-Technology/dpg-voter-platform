import { useMemo, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { AlertCircle, CheckCircle2, ChevronLeft, ChevronRight, ClipboardCheck, Clock3, MapPinned, Search, StickyNote, Users } from 'lucide-react';
import { getOutreachSupporters, getVillages, updateOutreachStatus } from '../../lib/api';
import { formatDateTime } from '../../lib/datetime';
import { gecMatchClass, gecMatchLabel } from '../../lib/gecMatch';
import WorkspacePage from '../../components/WorkspacePage';
import { useSession } from '../../hooks/useSession';
import { useDebouncedValue } from '../../hooks/useDebouncedValue';

interface VillageOption {
  id: number;
  name: string;
}

interface OutreachSupporter {
  id: number;
  first_name: string;
  middle_name?: string | null;
  last_name: string;
  village_id?: number;
  village_name: string;
  precinct_number?: string | null;
  contact_number: string;
  email: string | null;
  registered_voter?: boolean;
  current_gec_match?: boolean;
  registered_voter_status?: string | null;
  registered_voter_location_note?: string | null;
  wants_to_volunteer?: boolean;
  needs_absentee_ballot_help?: boolean;
  needs_homebound_voting_help?: boolean;
  needs_voter_registration_help?: boolean;
  needs_election_day_ride?: boolean;
  referred_by_name?: string | null;
  household_member_count?: number;
  follow_up_priority?: string;
  follow_up_reasons?: string[];
  needs_registration_follow_up?: boolean;
  needs_support_follow_up?: boolean;
  registration_follow_up_open?: boolean;
  support_follow_up_open?: boolean;
  follow_up_open?: boolean;
  registration_outreach_status: string | null;
  registration_outreach_date: string | null;
  registration_outreach_notes: string | null;
  support_follow_up_status: string | null;
  support_follow_up_date: string | null;
  support_follow_up_notes: string | null;
  created_at?: string | null;
}

interface OutreachCounts {
  total: number;
  open: number;
  registration_priority: number;
  support_requests: number;
  registered_follow_up: number;
  completed: number;
}

const QUEUE_VIEWS = [
  { value: 'open', label: 'All Open Follow-Up', countKey: 'open', icon: Clock3 },
  { value: 'registration_priority', label: 'Registration Priority', countKey: 'registration_priority', icon: AlertCircle },
  { value: 'support_requests', label: 'Campaign Help Requests', countKey: 'support_requests', icon: Users },
  { value: 'registered_follow_up', label: 'Registered Via Follow-Up', countKey: 'registered_follow_up', icon: CheckCircle2 },
  { value: 'completed', label: 'Resolved Outcomes', countKey: 'completed', icon: ClipboardCheck },
] as const;

const REGISTRATION_STATUS_OPTIONS = [
  { value: '', label: 'All registration follow-up' },
  { value: 'not_contacted', label: 'Not Contacted' },
  { value: 'contacted', label: 'Contacted' },
  { value: 'registered', label: 'Registered via follow-up' },
  { value: 'declined', label: 'Declined' },
];

const SUPPORT_STATUS_OPTIONS = [
  { value: '', label: 'All support help progress' },
  { value: 'not_started', label: 'Not Started' },
  { value: 'in_progress', label: 'In Progress' },
  { value: 'completed', label: 'Completed' },
  { value: 'declined', label: 'Declined' },
];

const REGISTRATION_STATUS_BADGES: Record<string, { bg: string; text: string; label: string }> = {
  contacted: { bg: 'bg-blue-100', text: 'text-blue-800', label: 'Contacted' },
  registered: { bg: 'bg-green-100', text: 'text-green-800', label: 'Registered via follow-up' },
  declined: { bg: 'bg-red-100', text: 'text-red-800', label: 'Declined' },
};

const SUPPORT_STATUS_BADGES: Record<string, { bg: string; text: string; label: string }> = {
  in_progress: { bg: 'bg-blue-100', text: 'text-blue-800', label: 'In Progress' },
  completed: { bg: 'bg-green-100', text: 'text-green-800', label: 'Completed' },
  declined: { bg: 'bg-red-100', text: 'text-red-800', label: 'Declined' },
};

function StatusBadge({
  status,
  emptyLabel,
  badges,
}: {
  status: string | null;
  emptyLabel: string;
  badges: Record<string, { bg: string; text: string; label: string }>;
}) {
  if (!status) {
    return <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-600">{emptyLabel}</span>;
  }
  const badge = badges[status] || { bg: 'bg-gray-100', text: 'text-gray-600', label: status };
  return <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${badge.bg} ${badge.text}`}>{badge.label}</span>;
}

function priorityBadgeClass(priority?: string | null) {
  if (priority === 'Registration Priority') return 'bg-red-100 text-red-700';
  if (priority === 'Support Help') return 'bg-amber-100 text-amber-800';
  if (priority === 'Resolved') return 'bg-emerald-100 text-emerald-700';
  return 'bg-slate-100 text-slate-700';
}

function reasonChipClass(reason: string) {
  if (reason.includes('Registered via follow-up')) return 'bg-green-100 text-green-700';
  if (reason.includes('Support help completed')) return 'bg-green-100 text-green-700';
  if (reason.includes('Declined')) return 'bg-red-100 text-red-700';
  if (reason.includes('registration') || reason.includes('No GEC match') || reason.includes('not registered')) return 'bg-amber-100 text-amber-800';
  return 'bg-blue-100 text-blue-700';
}

export default function OutreachPage() {
  const queryClient = useQueryClient();
  const { data: sessionData } = useSession();
  const [page, setPage] = useState(1);
  const [search, setSearch] = useState('');
  const [queueView, setQueueView] = useState('open');
  const [registrationStatusFilter, setRegistrationStatusFilter] = useState('');
  const [supportStatusFilter, setSupportStatusFilter] = useState('');
  const [registeredStatusFilter, setRegisteredStatusFilter] = useState('');
  const [supportNeedFilter, setSupportNeedFilter] = useState('');
  const [villageFilter, setVillageFilter] = useState('');
  const [drafts, setDrafts] = useState<Record<number, {
    registrationStatus: string;
    registrationNotes: string;
    supportStatus: string;
    supportNotes: string;
  }>>({});
  const debouncedSearch = useDebouncedValue(search, 250);

  const { data: villageData } = useQuery({ queryKey: ['villages'], queryFn: getVillages });
  const villages: VillageOption[] = useMemo(() => villageData?.villages || [], [villageData]);
  const scopedVillageIds = sessionData?.user?.scoped_village_ids ?? null;
  const accessibleVillages = useMemo(() => {
    if (scopedVillageIds === null) return villages;
    const allowed = new Set(scopedVillageIds);
    return villages.filter((village) => allowed.has(village.id));
  }, [scopedVillageIds, villages]);
  const singleScopedVillageId = scopedVillageIds && scopedVillageIds.length === 1 ? String(scopedVillageIds[0]) : '';
  const effectiveVillageFilter = villageFilter || singleScopedVillageId;

  const params: Record<string, string | number> = { page, per_page: 50 };
  if (debouncedSearch) params.search = debouncedSearch;
  if (queueView) params.queue_view = queueView;
  if (registrationStatusFilter) params.registration_outreach_status = registrationStatusFilter;
  if (supportStatusFilter) params.support_follow_up_status = supportStatusFilter;
  if (effectiveVillageFilter) params.village_id = effectiveVillageFilter;
  if (registeredStatusFilter) params.registered_voter_status = registeredStatusFilter;
  if (supportNeedFilter) params.support_need = supportNeedFilter;

  const { data, isLoading, isFetching } = useQuery({
    queryKey: ['outreach', page, debouncedSearch, queueView, registrationStatusFilter, supportStatusFilter, effectiveVillageFilter, registeredStatusFilter, supportNeedFilter],
    queryFn: () => getOutreachSupporters(params),
    placeholderData: (previous) => previous,
  });

  const updateMutation = useMutation({
    mutationFn: ({
      id,
      registrationStatus,
      registrationNotes,
      supportStatus,
      supportNotes,
    }: {
      id: number;
      registrationStatus?: string;
      registrationNotes?: string;
      supportStatus?: string;
      supportNotes?: string;
    }) => {
      const payload: Record<string, unknown> = {};
      if (registrationStatus !== undefined) payload.registration_outreach_status = registrationStatus === '' ? null : registrationStatus;
      if (registrationNotes !== undefined) payload.registration_outreach_notes = registrationNotes;
      if (supportStatus !== undefined) payload.support_follow_up_status = supportStatus === '' ? null : supportStatus;
      if (supportNotes !== undefined) payload.support_follow_up_notes = supportNotes;
      return updateOutreachStatus(id, payload);
    },
    onSuccess: (data, variables) => {
      const updatedSupporter = data?.supporter as OutreachSupporter | undefined;
      if (updatedSupporter) {
        setDrafts((prev) => ({
          ...prev,
          [variables.id]: {
            registrationStatus: updatedSupporter.registration_outreach_status || '',
            registrationNotes: updatedSupporter.registration_outreach_notes || '',
            supportStatus: updatedSupporter.support_follow_up_status || '',
            supportNotes: updatedSupporter.support_follow_up_notes || '',
          },
        }));
      }
      queryClient.invalidateQueries({ queryKey: ['outreach'] });
    },
  });

  const supporters: OutreachSupporter[] = data?.supporters || [];
  const counts: OutreachCounts = data?.counts || {
    total: 0,
    open: 0,
    registration_priority: 0,
    support_requests: 0,
    registered_follow_up: 0,
    completed: 0,
  };
  const pagination = data?.pagination || { page: 1, pages: 1, total: 0 };
  const showInitialLoading = isLoading && !data;
  const showUpdatingState = isFetching && !showInitialLoading;

  const selfReportedLabel = (status?: string | null) => {
    if (status === 'yes') return 'Self: Yes';
    if (status === 'no') return 'Self: No';
    return 'Self: Not sure';
  };

  const getDraft = (supporter: OutreachSupporter) =>
    drafts[supporter.id] || {
      registrationStatus: supporter.registration_outreach_status || '',
      registrationNotes: supporter.registration_outreach_notes || '',
      supportStatus: supporter.support_follow_up_status || '',
      supportNotes: supporter.support_follow_up_notes || '',
    };

  const updateDraft = (
    supporterId: number,
    patch: Partial<{
      registrationStatus: string;
      registrationNotes: string;
      supportStatus: string;
      supportNotes: string;
    }>
  ) => {
    setDrafts((prev) => {
      const existing = prev[supporterId] || {
        registrationStatus: '',
        registrationNotes: '',
        supportStatus: '',
        supportNotes: '',
      };
      return {
        ...prev,
        [supporterId]: { ...existing, ...patch },
      };
    });
  };

  const saveDraft = (supporter: OutreachSupporter) => {
    const draft = getDraft(supporter);
    const registrationStatusChanged = draft.registrationStatus !== (supporter.registration_outreach_status || '');
    const registrationNotesChanged = draft.registrationNotes !== (supporter.registration_outreach_notes || '');
    const supportStatusChanged = draft.supportStatus !== (supporter.support_follow_up_status || '');
    const supportNotesChanged = draft.supportNotes !== (supporter.support_follow_up_notes || '');
    if (!registrationStatusChanged && !registrationNotesChanged && !supportStatusChanged && !supportNotesChanged) return;

    updateMutation.mutate({
      id: supporter.id,
      registrationStatus: registrationStatusChanged ? draft.registrationStatus : undefined,
      registrationNotes: registrationNotesChanged ? draft.registrationNotes : undefined,
      supportStatus: supportStatusChanged ? draft.supportStatus : undefined,
      supportNotes: supportNotesChanged ? draft.supportNotes : undefined,
    });
  };

  return (
    <WorkspacePage width="full" className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900 tracking-tight flex items-center gap-2">
          <ClipboardCheck className="w-5 h-5 text-primary" /> Follow-Up Queue
        </h1>
        <p className="text-gray-500 text-sm mt-1">One queue for approved supporters who still need registration follow-up, campaign-help follow-up, or both.</p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-5 gap-3">
        {QUEUE_VIEWS.map((view) => {
          const Icon = view.icon;
          const active = queueView === view.value;
          const count = counts[view.countKey];

          return (
            <button
              key={view.value}
              type="button"
              onClick={() => {
                setQueueView(view.value);
                setPage(1);
              }}
              className={`app-card p-4 text-left transition ${active ? 'ring-2 ring-primary border-primary bg-blue-50/40' : 'hover:border-gray-300'}`}
            >
              <div className="flex items-center justify-between gap-3">
                <div>
                  <div className="text-sm font-semibold text-gray-900">{view.label}</div>
                  <div className="mt-1 text-2xl font-bold text-gray-900">{count}</div>
                </div>
                <span className={`rounded-full p-2 ${active ? 'bg-primary text-white' : 'bg-gray-100 text-gray-500'}`}>
                  <Icon className="h-4 w-4" />
                </span>
              </div>
            </button>
          );
        })}
      </div>

      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
        <div className="app-card p-3 text-center">
          <div className="text-2xl font-bold text-gray-900">{counts.total}</div>
          <div className="text-xs text-gray-500">Total Follow-Up</div>
        </div>
        <div className="app-card p-3 text-center">
          <div className="text-2xl font-bold text-red-600">{counts.registration_priority}</div>
          <div className="text-xs text-gray-500">Open Registration</div>
        </div>
        <div className="app-card p-3 text-center">
          <div className="text-2xl font-bold text-amber-600">{counts.support_requests}</div>
          <div className="text-xs text-gray-500">Open Support Help</div>
        </div>
        <div className="app-card p-3 text-center">
          <div className="text-2xl font-bold text-green-600">{counts.completed}</div>
          <div className="text-xs text-gray-500">Fully Resolved</div>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-6 gap-3">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
          <input
            type="text"
            placeholder="Search by name..."
            value={search}
            onChange={(e) => { setSearch(e.target.value); setPage(1); }}
            className="w-full pl-9 pr-3 py-2 border border-gray-300 rounded-xl text-sm"
          />
        </div>
        {singleScopedVillageId ? (
          <div className="rounded-xl border border-gray-200 bg-gray-50 px-3 py-2 text-sm text-gray-600">
            Assigned village: <span className="font-medium text-gray-900">{accessibleVillages[0]?.name || `Village #${singleScopedVillageId}`}</span>
          </div>
        ) : (
          <select
            value={villageFilter}
            onChange={(e) => { setVillageFilter(e.target.value); setPage(1); }}
            className="border border-gray-300 rounded-xl px-3 py-2 text-sm bg-white"
          >
            <option value="">All villages</option>
            {accessibleVillages.map((village) => (
              <option key={village.id} value={village.id}>{village.name}</option>
            ))}
          </select>
        )}
        <select
          value={registrationStatusFilter}
          onChange={(e) => { setRegistrationStatusFilter(e.target.value); setPage(1); }}
          className="border border-gray-300 rounded-xl px-3 py-2 text-sm bg-white"
        >
          {REGISTRATION_STATUS_OPTIONS.map((opt) => (
            <option key={opt.value} value={opt.value}>{opt.label}</option>
          ))}
        </select>
        <select
          value={supportStatusFilter}
          onChange={(e) => { setSupportStatusFilter(e.target.value); setPage(1); }}
          className="border border-gray-300 rounded-xl px-3 py-2 text-sm bg-white"
        >
          {SUPPORT_STATUS_OPTIONS.map((opt) => (
            <option key={opt.value} value={opt.value}>{opt.label}</option>
          ))}
        </select>
        <select
          value={registeredStatusFilter}
          onChange={(e) => { setRegisteredStatusFilter(e.target.value); setPage(1); }}
          className="border border-gray-300 rounded-xl px-3 py-2 text-sm bg-white"
        >
          <option value="">All self-reported voter status</option>
          <option value="yes">Self-reported yes</option>
          <option value="no">Self-reported no</option>
          <option value="not_sure">Self-reported not sure</option>
        </select>
        <select
          value={supportNeedFilter}
          onChange={(e) => { setSupportNeedFilter(e.target.value); setPage(1); }}
          className="border border-gray-300 rounded-xl px-3 py-2 text-sm bg-white"
        >
          <option value="">All support requests</option>
          <option value="registration">Registration help</option>
          <option value="absentee">Absentee help</option>
          <option value="homebound">Homebound help</option>
          <option value="ride">Ride to polls</option>
          <option value="volunteer">Volunteer</option>
          <option value="any">Any help request</option>
        </select>
      </div>

      <div className="app-card p-4">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <div className="flex flex-wrap items-center gap-2 text-xs text-gray-500">
            <span className="font-medium text-gray-700">Current queue:</span>
            <span>{QUEUE_VIEWS.find((view) => view.value === queueView)?.label || 'All Open Follow-Up'}</span>
            {effectiveVillageFilter && (
              <span className="inline-flex items-center gap-1 rounded-full bg-gray-100 px-2.5 py-1 text-gray-600">
                <MapPinned className="h-3.5 w-3.5" />
                {accessibleVillages.find((village) => String(village.id) === effectiveVillageFilter)?.name || `Village #${effectiveVillageFilter}`}
              </span>
            )}
          </div>
          <div className={`text-xs text-gray-400 transition-opacity duration-200 ${showUpdatingState ? 'opacity-100' : 'opacity-0'}`}>
            {search !== debouncedSearch ? 'Searching...' : 'Updating...'}
          </div>
        </div>
      </div>

      <div className={`space-y-4 transition-opacity duration-200 ${showUpdatingState ? 'opacity-70' : 'opacity-100'}`}>
        {showInitialLoading ? (
          <div className="app-card p-8 text-center text-gray-400">Loading...</div>
        ) : supporters.length === 0 ? (
          <div className="app-card p-8 text-center text-gray-400">No supporters found</div>
        ) : (
          supporters.map((supporter) => {
            const draft = getDraft(supporter);
            const registrationStatusChanged = draft.registrationStatus !== (supporter.registration_outreach_status || '');
            const registrationNotesChanged = draft.registrationNotes !== (supporter.registration_outreach_notes || '');
            const supportStatusChanged = draft.supportStatus !== (supporter.support_follow_up_status || '');
            const supportNotesChanged = draft.supportNotes !== (supporter.support_follow_up_notes || '');
            const hasPendingChanges = registrationStatusChanged || registrationNotesChanged || supportStatusChanged || supportNotesChanged;
            const isSaving = updateMutation.isPending && updateMutation.variables?.id === supporter.id;
            const latestFollowUpDate = [supporter.registration_outreach_date, supporter.support_follow_up_date]
              .filter((value): value is string => Boolean(value))
              .sort()
              .at(-1);
            const queueStatusText = supporter.follow_up_open
              ? supporter.registration_follow_up_open && supporter.support_follow_up_open
                ? 'Registration + support help still open'
                : supporter.registration_follow_up_open
                  ? 'Registration follow-up still open'
                  : 'Support help still open'
              : 'All needed follow-up resolved';

            return (
              <div key={supporter.id} className="app-card p-5">
                <div className="flex flex-col gap-5 lg:flex-row lg:items-start lg:justify-between">
                  <div className="min-w-0 flex-1 space-y-4">
                    <div className="flex flex-wrap items-start gap-2">
                      <div className="min-w-0 flex-1">
                        <Link to={`/admin/supporters/${supporter.id}`} className="text-primary hover:underline text-lg font-semibold">
                          {supporter.first_name} {supporter.last_name}
                        </Link>
                        <div className="mt-1 flex flex-wrap items-center gap-3 text-sm text-gray-500">
                          <span>{supporter.village_name || 'Unknown village'}</span>
                          {supporter.precinct_number && <span>Precinct {supporter.precinct_number}</span>}
                          {supporter.contact_number && <span>{supporter.contact_number}</span>}
                          {supporter.email && <span>{supporter.email}</span>}
                        </div>
                      </div>
                      <span className={`rounded-full px-2.5 py-1 text-xs font-semibold ${priorityBadgeClass(supporter.follow_up_priority)}`}>
                        {supporter.follow_up_priority || 'Low'} priority
                      </span>
                      {supporter.needs_registration_follow_up && (
                        <StatusBadge
                          status={supporter.registration_outreach_status}
                          emptyLabel="Registration: Not Contacted"
                          badges={REGISTRATION_STATUS_BADGES}
                        />
                      )}
                      {supporter.needs_support_follow_up && (
                        <StatusBadge
                          status={supporter.support_follow_up_status}
                          emptyLabel="Support: Not Started"
                          badges={SUPPORT_STATUS_BADGES}
                        />
                      )}
                    </div>

                    <div className="flex flex-wrap gap-2">
                      {(supporter.follow_up_reasons || []).map((reason) => (
                        <span key={`${supporter.id}-${reason}`} className={`rounded-full px-2.5 py-1 text-xs font-medium ${reasonChipClass(reason)}`}>
                          {reason}
                        </span>
                      ))}
                      {(supporter.follow_up_reasons || []).length === 0 && (
                        <span className="rounded-full bg-slate-100 px-2.5 py-1 text-xs font-medium text-slate-700">General follow-up</span>
                      )}
                    </div>

                    <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
                      <div className="rounded-xl border border-gray-100 bg-gray-50 px-3 py-2">
                        <div className="text-[11px] font-semibold uppercase tracking-wide text-gray-400">Voter context</div>
                        <div className="mt-1 text-sm text-gray-700">{selfReportedLabel(supporter.registered_voter_status)}</div>
                        <div className={`mt-1 text-sm ${gecMatchClass(supporter)}`}>
                          GEC Match: {gecMatchLabel(supporter)}
                        </div>
                      </div>
                      <div className="rounded-xl border border-gray-100 bg-gray-50 px-3 py-2">
                        <div className="text-[11px] font-semibold uppercase tracking-wide text-gray-400">Queue status</div>
                        <div className="mt-1 text-sm text-gray-700">{queueStatusText}</div>
                        <div className="mt-1 text-xs text-gray-500">
                          {latestFollowUpDate ? `Last updated ${formatDateTime(latestFollowUpDate)}` : 'No follow-up update yet'}
                        </div>
                      </div>
                      <div className="rounded-xl border border-gray-100 bg-gray-50 px-3 py-2">
                        <div className="text-[11px] font-semibold uppercase tracking-wide text-gray-400">Household / referral</div>
                        <div className="mt-1 text-sm text-gray-700">
                          {(supporter.household_member_count || 0) > 0 ? `${supporter.household_member_count} linked supporter${supporter.household_member_count === 1 ? '' : 's'}` : 'Single supporter'}
                        </div>
                        <div className="mt-1 text-xs text-gray-500">
                          {supporter.referred_by_name ? `Referred by ${supporter.referred_by_name}` : 'No referral note'}
                        </div>
                      </div>
                    </div>

                    {(supporter.registered_voter_location_note || supporter.registration_outreach_notes || supporter.support_follow_up_notes) && (
                      <div className="space-y-2">
                        {supporter.registered_voter_location_note && (
                          <div className="rounded-xl border border-blue-100 bg-blue-50 px-3 py-2 text-sm text-blue-800">
                            Votes elsewhere: {supporter.registered_voter_location_note}
                          </div>
                        )}
                        {supporter.registration_outreach_notes && (
                          <div className="rounded-xl border border-amber-100 bg-amber-50 px-3 py-2 text-sm text-amber-900">
                            <div className="flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-amber-700">
                              <StickyNote className="h-3.5 w-3.5" />
                              Registration follow-up note
                            </div>
                            <div className="mt-1 whitespace-pre-wrap">{supporter.registration_outreach_notes}</div>
                          </div>
                        )}
                        {supporter.support_follow_up_notes && (
                          <div className="rounded-xl border border-blue-100 bg-blue-50 px-3 py-2 text-sm text-blue-900">
                            <div className="flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-blue-700">
                              <StickyNote className="h-3.5 w-3.5" />
                              Support follow-up note
                            </div>
                            <div className="mt-1 whitespace-pre-wrap">{supporter.support_follow_up_notes}</div>
                          </div>
                        )}
                      </div>
                    )}
                  </div>

                  <div className="w-full lg:w-[340px] shrink-0 rounded-2xl border border-gray-200 bg-white p-4">
                    <div className="text-sm font-semibold text-gray-900">Update Follow-Up</div>
                    <div className="mt-3 space-y-3">
                      {supporter.needs_registration_follow_up && (
                        <div className="space-y-3 rounded-xl border border-amber-100 bg-amber-50/60 p-3">
                          <div>
                            <div className="text-xs font-semibold uppercase tracking-wide text-amber-700">Registration follow-up</div>
                            <div className="mt-1 text-xs text-amber-900">Track registration outreach separately from any campaign-help requests.</div>
                          </div>
                          <div>
                            <label className="mb-1 block text-xs font-medium uppercase tracking-wide text-gray-500">Result</label>
                            <select
                              value={draft.registrationStatus}
                              onChange={(e) => updateDraft(supporter.id, { registrationStatus: e.target.value })}
                              className="w-full rounded-xl border border-gray-300 bg-white px-3 py-2 text-sm"
                            >
                              <option value="">Not contacted</option>
                              <option value="contacted">Contacted</option>
                              <option value="registered">Registered via follow-up</option>
                              <option value="declined">Declined</option>
                            </select>
                          </div>
                          <div>
                            <label className="mb-1 block text-xs font-medium uppercase tracking-wide text-gray-500">Notes</label>
                            <textarea
                              value={draft.registrationNotes}
                              onChange={(e) => updateDraft(supporter.id, { registrationNotes: e.target.value })}
                              rows={3}
                              placeholder="Add registration outreach notes..."
                              className="w-full rounded-xl border border-gray-300 px-3 py-2 text-sm"
                            />
                          </div>
                        </div>
                      )}
                      {supporter.needs_support_follow_up && (
                        <div className="space-y-3 rounded-xl border border-blue-100 bg-blue-50/60 p-3">
                          <div>
                            <div className="text-xs font-semibold uppercase tracking-wide text-blue-700">Campaign-help follow-up</div>
                            <div className="mt-1 text-xs text-blue-900">Use this track for volunteer, absentee, homebound, and ride-to-polls requests.</div>
                          </div>
                          <div>
                            <label className="mb-1 block text-xs font-medium uppercase tracking-wide text-gray-500">Progress</label>
                            <select
                              value={draft.supportStatus}
                              onChange={(e) => updateDraft(supporter.id, { supportStatus: e.target.value })}
                              className="w-full rounded-xl border border-gray-300 bg-white px-3 py-2 text-sm"
                            >
                              <option value="">Not started</option>
                              <option value="in_progress">In progress</option>
                              <option value="completed">Completed</option>
                              <option value="declined">Declined</option>
                            </select>
                          </div>
                          <div>
                            <label className="mb-1 block text-xs font-medium uppercase tracking-wide text-gray-500">Notes</label>
                            <textarea
                              value={draft.supportNotes}
                              onChange={(e) => updateDraft(supporter.id, { supportNotes: e.target.value })}
                              rows={3}
                              placeholder="Add campaign-help follow-up notes..."
                              className="w-full rounded-xl border border-gray-300 px-3 py-2 text-sm"
                            />
                          </div>
                        </div>
                      )}
                      <button
                        type="button"
                        onClick={() => saveDraft(supporter)}
                        disabled={!hasPendingChanges || isSaving}
                        className="w-full rounded-xl bg-primary px-3 py-2 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-50"
                      >
                        {isSaving ? 'Saving...' : 'Save Follow-Up Updates'}
                      </button>
                    </div>
                  </div>
                </div>
              </div>
            );
          })
        )}
      </div>

      {pagination.pages > 1 && (
        <div className="flex items-center justify-between text-sm text-gray-500">
          <span>Page {pagination.page} of {pagination.pages} ({pagination.total} total)</span>
          <div className="flex gap-2">
            <button
              onClick={() => setPage((currentPage) => Math.max(1, currentPage - 1))}
              disabled={page <= 1}
              className="p-2 border border-gray-300 rounded-lg disabled:opacity-30 hover:bg-gray-50"
            >
              <ChevronLeft className="w-4 h-4" />
            </button>
            <button
              onClick={() => setPage((currentPage) => Math.min(pagination.pages, currentPage + 1))}
              disabled={page >= pagination.pages}
              className="p-2 border border-gray-300 rounded-lg disabled:opacity-30 hover:bg-gray-50"
            >
              <ChevronRight className="w-4 h-4" />
            </button>
          </div>
        </div>
      )}
    </WorkspacePage>
  );
}
