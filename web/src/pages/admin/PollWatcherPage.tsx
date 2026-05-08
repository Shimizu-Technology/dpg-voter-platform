import { useEffect, useMemo, useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { getPollWatcher, getPollWatcherStrikeList, submitPollReport, updateStrikeListTurnout } from '../../lib/api';
import { useSearchParams } from 'react-router-dom';
import { Eye, Send, CheckCircle, Clock, AlertTriangle, MapPin, BarChart3, Timer, Lock, Search, ChevronDown, ChevronUp } from 'lucide-react';
import { useDebouncedValue } from '../../hooks/useDebouncedValue';
import WorkspacePage from '../../components/WorkspacePage';

interface PrecinctItem {
  id: number;
  number: string;
  polling_site?: string;
  registered_voters?: number;
  alpha_range?: string;
  reporting: boolean;
  turnout_pct: number | null;
  last_voter_count?: number;
  last_notes?: string;
}

interface VillageItem {
  id: number;
  name: string;
  reporting_count: number;
  total_precincts: number;
  precincts: PrecinctItem[];
}

interface PollWatcherStats {
  reporting_precincts: number;
  total_precincts: number;
  total_voters_reported: number;
  overall_turnout_pct: number;
}

interface PollWatcherData {
  villages: VillageItem[];
  stats: PollWatcherStats;
}

interface StrikeListVoter {
  id: number;
  first_name: string;
  middle_name?: string | null;
  last_name: string;
  print_name: string;
  voter_registration_number?: string | null;
  address?: string | null;
  precinct_number?: string | null;
  village_name?: string | null;
  turnout_status: 'unknown' | 'not_yet_voted' | 'voted' | 'observed_elsewhere';
  turnout_source?: string | null;
  turnout_note?: string | null;
  turnout_updated_at?: string | null;
  out_of_precinct?: boolean;
  supporter_overlay?: {
    supporter_count: number;
  };
}

interface StrikeListData {
  compliance_note?: string;
  voters: StrikeListVoter[];
  external_matches?: StrikeListVoter[];
  pagination?: {
    page: number;
    per_page: number;
    total: number;
    pages: number;
  };
}

type PollWatcherSortField = 'precinct_number' | 'turnout_pct' | 'last_voter_count';

const REPORT_TYPES = [
  { value: 'turnout_update', label: 'Turnout Update', icon: BarChart3 },
  { value: 'line_length', label: 'Long Lines', icon: Timer },
  { value: 'issue', label: 'Report Issue', icon: AlertTriangle },
  { value: 'not_on_list', label: 'Name Not On List', icon: Search },
  { value: 'closing', label: 'Polls Closing', icon: Lock },
];

const TURNOUT_PRIMARY_OPTIONS = [
  { value: 'not_yet_voted', label: 'Not Yet Voted' },
  { value: 'voted', label: 'Voted' },
] as const;

const TURNOUT_OBSERVED_ELSEWHERE_OPTION = { value: 'observed_elsewhere', label: 'Observed Elsewhere' } as const;
const TURNOUT_CLEAR_OPTION = { value: 'unknown', label: 'Clear turnout status' } as const;

function turnoutColor(pct: number | null) {
  if (pct === null) return 'text-[var(--text-muted)]';
  if (pct >= 60) return 'text-green-600';
  if (pct >= 40) return 'text-yellow-600';
  return 'text-red-600';
}

function turnoutBg(pct: number | null) {
  if (pct === null) return 'bg-[var(--surface-overlay)]';
  if (pct >= 60) return 'bg-green-500';
  if (pct >= 40) return 'bg-yellow-500';
  return 'bg-red-500';
}

function turnoutStatusBadgeClasses(status: StrikeListVoter['turnout_status']) {
  if (status === 'voted') return 'bg-green-100 text-green-600 border-green-200';
  if (status === 'observed_elsewhere') return 'bg-amber-100 text-amber-800 border-amber-300';
  if (status === 'not_yet_voted') return 'bg-yellow-100 text-yellow-700 border-yellow-500/30';
  return 'bg-[var(--surface-overlay)] text-[var(--text-secondary)] border-[var(--border-soft)]';
}

function turnoutStatusLabel(status: StrikeListVoter['turnout_status']) {
  if (status === 'not_yet_voted') return 'not yet voted';
  if (status === 'voted') return 'voted';
  if (status === 'observed_elsewhere') return 'observed elsewhere';
  return 'not set';
}

function turnoutSourceLabel(source?: string | null) {
  if (!source) return null;
  if (source === 'poll_watcher') return 'Marked by poll watcher';
  if (source === 'data_team') return 'Marked by data team';
  if (source === 'admin_override') return 'Marked by admin';
  return source.replace(/_/g, ' ');
}

export default function PollWatcherPage() {
  const queryClient = useQueryClient();
  const [searchParams, setSearchParams] = useSearchParams();
  const [selectedPrecinct, setSelectedPrecinct] = useState<PrecinctItem | null>(null);
  const [voterCount, setVoterCount] = useState('');
  const [reportType, setReportType] = useState('turnout_update');
  const [notes, setNotes] = useState('');
  const [successMsg, setSuccessMsg] = useState('');
  const [filterVillage, setFilterVillage] = useState(searchParams.get('village_id') || '');
  const [search, setSearch] = useState(searchParams.get('search') || '');
  const [reportingFilter, setReportingFilter] = useState(searchParams.get('reporting') || '');
  const [sortBy, setSortBy] = useState<PollWatcherSortField>((searchParams.get('sort_by') as PollWatcherSortField) || 'precinct_number');
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>((searchParams.get('sort_dir') as 'asc' | 'desc') || 'asc');
  const [strikeSearch, setStrikeSearch] = useState('');
  const [strikeStatusFilter, setStrikeStatusFilter] = useState<'not_yet_voted' | 'voted' | 'unknown' | 'observed_elsewhere' | ''>('not_yet_voted');
  const [strikeNotice, setStrikeNotice] = useState('');
  const [turnoutNoteByVoter, setTurnoutNoteByVoter] = useState<Record<number, string>>({});
  const [noteOpenByVoter, setNoteOpenByVoter] = useState<Record<number, boolean>>({});
  const [turnoutDraftByVoter, setTurnoutDraftByVoter] = useState<Record<number, StrikeListVoter['turnout_status']>>({});
  const [activeVoterId, setActiveVoterId] = useState<number | null>(null);
  const [strikePage, setStrikePage] = useState(1);
  const [strikePerPage, setStrikePerPage] = useState(25);
  const [reportFormOpen, setReportFormOpen] = useState(false);
  const debouncedStrikeSearch = useDebouncedValue(strikeSearch, 250);
  const isNameNotOnListReport = reportType === 'not_on_list';

  const { data, isLoading, isError } = useQuery<PollWatcherData>({
    queryKey: ['poll_watcher'],
    queryFn: getPollWatcher,
    refetchInterval: 15_000, // Refresh every 15s on election day
  });

  const reportMutation = useMutation({
    mutationFn: submitPollReport,
    onSuccess: (data) => {
      setSuccessMsg(data.message);
      setVoterCount('');
      setNotes('');
      setSelectedPrecinct(null);
      queryClient.invalidateQueries({ queryKey: ['poll_watcher'] });
      setTimeout(() => setSuccessMsg(''), 3000);
    },
  });

  const { data: strikeListData, isLoading: strikeListLoading } = useQuery<StrikeListData>({
    queryKey: ['poll_watcher_strike_list', selectedPrecinct?.id, strikeStatusFilter, debouncedStrikeSearch, strikePage, strikePerPage],
    queryFn: () => getPollWatcherStrikeList({
      precinct_id: selectedPrecinct?.id,
      turnout_status: strikeStatusFilter || undefined,
      search: debouncedStrikeSearch || undefined,
      page: strikePage,
      per_page: strikePerPage,
    }),
    enabled: Boolean(selectedPrecinct?.id),
  });

  const turnoutMutation = useMutation({
    mutationFn: ({ voterId, turnoutStatus }: { voterId: number; turnoutStatus: 'not_yet_voted' | 'voted' | 'unknown' | 'observed_elsewhere' }) => {
      if (!selectedPrecinct) throw new Error('No precinct selected');
      return updateStrikeListTurnout(voterId, {
        precinct_id: selectedPrecinct.id,
        turnout_status: turnoutStatus,
        note: turnoutNoteByVoter[voterId] || undefined,
      });
    },
    onSuccess: (response: { message?: string }, variables) => {
      setStrikeNotice(response?.message || 'Turnout updated');
      setTurnoutDraftByVoter((prev) => {
        const next = { ...prev };
        delete next[variables.voterId];
        return next;
      });
      queryClient.invalidateQueries({ queryKey: ['poll_watcher'] });
      queryClient.invalidateQueries({ queryKey: ['poll_watcher_strike_list'] });
      setTimeout(() => setStrikeNotice(''), 3000);
    },
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedPrecinct) return;
    if (!isNameNotOnListReport && !voterCount) return;
    if (isNameNotOnListReport && !notes.trim()) return;
    reportMutation.mutate({
      precinct_id: selectedPrecinct.id,
      voter_count: isNameNotOnListReport ? 0 : parseInt(voterCount),
      report_type: reportType,
      notes: notes || undefined,
    });
  };

  const handleSelectPrecinct = (precinct: PrecinctItem) => {
    setSelectedPrecinct(precinct);
    setStrikeSearch('');
    setStrikeStatusFilter('not_yet_voted');
    setTurnoutNoteByVoter({});
    setNoteOpenByVoter({});
    setTurnoutDraftByVoter({});
    setActiveVoterId(null);
    setStrikePage(1);
    setReportFormOpen(false);
    setReportType('turnout_update');
    setVoterCount('');
    setNotes('');
  };

  useEffect(() => {
    const params = new URLSearchParams();
    if (filterVillage) params.set('village_id', filterVillage);
    if (search) params.set('search', search);
    if (reportingFilter) params.set('reporting', reportingFilter);
    params.set('sort_by', sortBy);
    params.set('sort_dir', sortDir);
    setSearchParams(params, { replace: true });
  }, [filterVillage, search, reportingFilter, sortBy, sortDir, setSearchParams]);

  const strikeVoters = useMemo(() => strikeListData?.voters || [], [strikeListData]);
  const externalMatches = useMemo(() => strikeListData?.external_matches || [], [strikeListData]);
  const visibleStrikeVoters = useMemo(
    () => [...strikeVoters, ...externalMatches],
    [strikeVoters, externalMatches]
  );

  // Sync active supporter when strike list changes — setState is intentional here
  // to keep user's selection in sync with filtered data
  const strikeIds = useMemo(() => visibleStrikeVoters.map((v) => v.id), [visibleStrikeVoters]);
  /* eslint-disable react-hooks/set-state-in-effect -- intentional: sync selection with filtered data */
  useEffect(() => {
    if (strikeIds.length === 0) {
      setActiveVoterId(null);
    } else {
      setActiveVoterId((prev) =>
        prev && strikeIds.includes(prev) ? prev : strikeIds[0]
      );
    }
  }, [strikeIds]);
  /* eslint-enable react-hooks/set-state-in-effect */

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-20">
        <div className="text-[var(--text-muted)] text-sm font-medium">Loading precincts...</div>
      </div>
    );
  }

  if (isError || !data) {
    return (
      <div className="flex items-center justify-center py-20">
        <div className="text-center p-8">
          <AlertTriangle className="w-12 h-12 text-neutral-300 mx-auto mb-4" />
          <h2 className="text-xl font-bold text-neutral-800 mb-2">Can&apos;t connect to server</h2>
          <p className="text-neutral-500 mb-4 text-sm">Check your connection and try again.</p>
          <button onClick={() => window.location.reload()} className="bg-[var(--campaign-blue)] hover:opacity-90 text-white px-5 py-2.5 rounded-xl font-medium transition-all">
            Retry
          </button>
        </div>
      </div>
    );
  }

  const { villages, stats } = data;
  const filteredVillages = (filterVillage
    ? villages.filter((v) => v.id === parseInt(filterVillage))
    : villages
  ).map((village) => {
    const q = search.trim().toLowerCase();
    const filteredPrecincts = village.precincts.filter((precinct) => {
      const searchHit = q.length === 0 ||
        precinct.number.toLowerCase().includes(q) ||
        (precinct.polling_site || '').toLowerCase().includes(q) ||
        (precinct.alpha_range || '').toLowerCase().includes(q);
      const reportingHit = reportingFilter === ''
        ? true
        : reportingFilter === 'reporting'
          ? precinct.reporting
          : !precinct.reporting;
      return searchHit && reportingHit;
    });

    const sortedPrecincts = [...filteredPrecincts].sort((a, b) => {
      const dir = sortDir === 'asc' ? 1 : -1;
      if (sortBy === 'turnout_pct') return ((a.turnout_pct || 0) - (b.turnout_pct || 0)) * dir;
      if (sortBy === 'last_voter_count') return ((a.last_voter_count || 0) - (b.last_voter_count || 0)) * dir;
      return a.number.localeCompare(b.number, undefined, { numeric: true, sensitivity: 'base' }) * dir;
    });

    return {
      ...village,
      precincts: sortedPrecincts,
    };
  }).filter((village) => village.precincts.length > 0);

  const visiblePrecinctCount = filteredVillages.reduce((sum, village) => sum + village.precincts.length, 0);
  const activeVoter = activeVoterId
    ? visibleStrikeVoters.find((voter) => voter.id === activeVoterId) || null
    : null;

  const renderVoterActions = (voter: StrikeListVoter) => {
    const selectedTurnoutStatus = turnoutDraftByVoter[voter.id] || voter.turnout_status;
    const hasPendingTurnoutChange = selectedTurnoutStatus !== voter.turnout_status;
    const noteOpen = noteOpenByVoter[voter.id] || Boolean(turnoutNoteByVoter[voter.id]);
    const supporterCount = voter.supporter_overlay?.supporter_count || 0;
    const sourceLabel = turnoutSourceLabel(voter.turnout_source);
    const isExternalMatch = Boolean(voter.out_of_precinct);

    return (
      <>
        {isExternalMatch ? (
          <div className="mt-3 rounded-xl border border-amber-200 bg-amber-50 px-3 py-3 text-xs text-amber-900">
            <p className="font-semibold">Registered outside Precinct {selectedPrecinct?.number}</p>
            <p className="mt-1">
              This voter belongs to {voter.village_name || 'another village'} / Precinct {voter.precinct_number || 'unknown'} in the election-day list.
              Use <span className="font-semibold">Observed Elsewhere</span> to flag that they were seen voting here without overwriting their registered-precinct turnout as a normal in-precinct mark.
            </p>
          </div>
        ) : null}

        <div className="mt-2 grid grid-cols-2 gap-2">
          {(isExternalMatch ? [TURNOUT_OBSERVED_ELSEWHERE_OPTION] : TURNOUT_PRIMARY_OPTIONS).map((option) => (
            <button
              key={`${voter.id}-${option.value}`}
              type="button"
              onClick={() => setTurnoutDraftByVoter((prev) => ({ ...prev, [voter.id]: option.value }))}
              className={`min-h-[44px] rounded-xl border text-xs font-semibold ${
                selectedTurnoutStatus === option.value
                  ? option.value === 'observed_elsewhere'
                    ? 'border-amber-300 bg-amber-50 text-amber-800'
                    : 'border-primary bg-blue-50 text-primary'
                  : 'border-[var(--border-soft)] text-[var(--text-secondary)]'
              }`}
              disabled={turnoutMutation.isPending}
            >
              {option.label}
            </button>
          ))}
          {isExternalMatch && (
            <button
              type="button"
              onClick={() => setTurnoutDraftByVoter((prev) => ({ ...prev, [voter.id]: TURNOUT_CLEAR_OPTION.value }))}
              className={`min-h-[44px] rounded-xl border text-xs font-semibold ${
                selectedTurnoutStatus === TURNOUT_CLEAR_OPTION.value
                  ? 'border-[var(--border-soft)] bg-[var(--surface-overlay)] text-[var(--text-primary)]'
                  : 'border-[var(--border-soft)] text-[var(--text-secondary)]'
              }`}
              disabled={turnoutMutation.isPending}
            >
              {TURNOUT_CLEAR_OPTION.label}
            </button>
          )}
        </div>

        {!isExternalMatch && (
          <div className="mt-2">
            <button
              type="button"
              onClick={() => setTurnoutDraftByVoter((prev) => ({ ...prev, [voter.id]: TURNOUT_CLEAR_OPTION.value }))}
              className={`min-h-[40px] rounded-xl border px-3 text-xs font-semibold ${
                selectedTurnoutStatus === TURNOUT_CLEAR_OPTION.value
                  ? 'border-amber-300 bg-amber-50 text-amber-800'
                  : 'border-[var(--border-soft)] text-[var(--text-secondary)]'
                }`}
              disabled={turnoutMutation.isPending}
            >
              {TURNOUT_CLEAR_OPTION.label}
            </button>
          </div>
        )}

        <div className="mt-2 flex flex-wrap items-center gap-2">
          <button
            type="button"
            onClick={() => turnoutMutation.mutate({ voterId: voter.id, turnoutStatus: selectedTurnoutStatus })}
            disabled={!hasPendingTurnoutChange || turnoutMutation.isPending}
            className="min-h-[40px] rounded-xl bg-primary text-white text-xs font-semibold px-3 disabled:opacity-40"
          >
            Save Turnout
          </button>
          <button
            type="button"
            onClick={() => setTurnoutDraftByVoter((prev) => {
              const next = { ...prev };
              delete next[voter.id];
              return next;
            })}
            disabled={!hasPendingTurnoutChange || turnoutMutation.isPending}
            className="min-h-[40px] rounded-xl border border-[var(--border-soft)] text-xs font-semibold px-3 text-[var(--text-secondary)] disabled:opacity-40"
          >
            Revert
          </button>
          {hasPendingTurnoutChange && (
            <span className="text-[11px] text-amber-700">Unsaved turnout change</span>
          )}
        </div>

        <p className="mt-2 text-[11px] text-[var(--text-secondary)]">
          {isExternalMatch
            ? supporterCount > 0
              ? `${supporterCount} matched campaign supporter${supporterCount === 1 ? '' : 's'} will move out of the active call queue and into War Room reconciliation when marked observed elsewhere.`
              : 'Use this when a voter is seen here even though their registered election-day precinct is somewhere else.'
            : supporterCount > 0
              ? `${supporterCount} matched campaign supporter${supporterCount === 1 ? '' : 's'} will be routed to War Room follow-up from this turnout status.`
              : 'No matched campaign supporter for this voter yet, so only turnout can be updated here.'}
        </p>
        {(voter.turnout_note || voter.turnout_updated_at || sourceLabel) && (
          <div className="mt-2 rounded-xl border border-[var(--border-soft)] bg-[var(--surface-bg)] px-3 py-2 text-[11px] text-[var(--text-secondary)] space-y-1">
            {sourceLabel && <p>{sourceLabel}</p>}
            {voter.turnout_updated_at && <p>Last updated {new Date(voter.turnout_updated_at).toLocaleString()}</p>}
            {voter.turnout_note && <p className="text-[var(--text-primary)]">{voter.turnout_note}</p>}
          </div>
        )}

        <div className="mt-2">
          <button
            type="button"
            onClick={() => setNoteOpenByVoter((prev) => ({ ...prev, [voter.id]: !noteOpen }))}
            className="text-xs text-[var(--text-secondary)] underline underline-offset-2"
          >
            {noteOpen ? 'Hide note' : 'Add note'}
          </button>
          {noteOpen && (
            <input
              type="text"
              value={turnoutNoteByVoter[voter.id] || ''}
              onChange={(e) => setTurnoutNoteByVoter((prev) => ({ ...prev, [voter.id]: e.target.value }))}
              placeholder={isExternalMatch ? 'Optional note for out-of-precinct or provisional observation' : 'Optional note for turnout update'}
              className="mt-2 w-full px-3 py-2 border border-[var(--border-soft)] rounded-xl text-xs min-h-[44px]"
            />
          )}
        </div>
      </>
    );
  };

  return (
    <WorkspacePage width="full" className="space-y-6">
      {/* Header */}
      <div>
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-green-100 flex items-center justify-center">
            <Eye className="w-5 h-5 text-green-600" />
          </div>
          <div>
            <h1 className="text-xl font-bold text-gray-900 tracking-tight">Poll Watcher</h1>
            <p className="text-gray-500 text-xs">Election Day Real-Time Reporting</p>
          </div>
        </div>
      </div>

      <div className="space-y-4">
        {/* Success Message */}
        {successMsg && (
          <div className="bg-green-50 border border-green-200 text-green-700 rounded-2xl p-3 mb-4 flex items-center gap-2">
            <CheckCircle className="w-5 h-5 shrink-0" />
            <span className="font-medium">{successMsg}</span>
          </div>
        )}

        {/* Stats Bar */}
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 mb-4">
          <div className="app-card p-3 text-center">
            <div className="text-2xl font-bold text-[var(--text-primary)]">{stats.reporting_precincts}/{stats.total_precincts}</div>
            <div className="text-xs text-[var(--text-secondary)]">Reporting</div>
          </div>
          <div className="app-card p-3 text-center">
            <div className="text-2xl font-bold text-[var(--text-primary)]">{stats.total_voters_reported.toLocaleString()}</div>
            <div className="text-xs text-[var(--text-secondary)]">Voters Counted</div>
          </div>
          <div className="app-card p-3 text-center">
            <div className={`text-2xl font-bold ${turnoutColor(stats.overall_turnout_pct)}`}>
              {stats.overall_turnout_pct || 0}%
            </div>
            <div className="text-xs text-[var(--text-secondary)]">Turnout</div>
          </div>
        </div>

        {/* Report + Strike List */}
        {selectedPrecinct ? (
          <div className="space-y-4 mb-4">
            <div className="app-card p-4">
              <div className="flex items-center justify-between mb-3">
                <div>
                  <h3 className="font-bold text-[var(--text-primary)]">Precinct {selectedPrecinct.number}</h3>
                  <p className="text-sm text-[var(--text-secondary)]">{selectedPrecinct.polling_site || 'No polling site listed'}</p>
                  <p className="text-xs text-[var(--text-muted)]">{selectedPrecinct.registered_voters?.toLocaleString()} registered voters</p>
                </div>
                <div className="flex items-center gap-2">
                  <button
                    type="button"
                    onClick={() => setReportFormOpen((prev) => !prev)}
                    className="text-xs px-3 py-1.5 rounded-lg border border-[var(--border-soft)] text-[var(--text-secondary)] hover:bg-[var(--surface-bg)]"
                  >
                    {reportFormOpen ? 'Hide Report Form' : 'Open Report Form'}
                  </button>
                  <button type="button" onClick={() => setSelectedPrecinct(null)} className="text-[var(--text-muted)] hover:text-[var(--text-secondary)] text-sm">
                    Cancel
                  </button>
                </div>
              </div>
            </div>

            {/* Strike list first: most frequent poll-watcher workflow */}
            <div className="app-card p-4">
              <div className="flex items-center justify-between mb-3 gap-2">
                <h3 className="font-bold text-[var(--text-primary)]">Precinct Voter List</h3>
                <span className="text-xs text-[var(--text-secondary)]">
                  {(strikeListData?.pagination?.total || strikeListData?.voters.length || 0) + externalMatches.length} voters shown
                </span>
              </div>
              <p className="text-xs text-blue-700 bg-blue-50 border border-blue-200 rounded-lg px-2.5 py-2 mb-3">
                {strikeListData?.compliance_note || 'Campaign operations tracking only; not official election records.'} This list shows the full precinct voter universe, with campaign supporter details layered in when a voter is matched to a supporter.
              </p>
              {strikeNotice && (
                <p className="text-xs text-green-600 bg-green-50 border border-green-200 rounded-lg px-2.5 py-2 mb-3">
                  {strikeNotice}
                </p>
              )}

              <div className="grid grid-cols-1 md:grid-cols-3 gap-2 mb-3">
                <input
                  type="text"
                  value={strikeSearch}
                  onChange={(e) => {
                    setStrikeSearch(e.target.value);
                    setStrikePage(1);
                  }}
                  placeholder="Search voter name, address, or registration number..."
                  className="md:col-span-2 w-full px-3 py-2 border border-[var(--border-soft)] rounded-xl text-sm min-h-[44px]"
                />
                <select
                  value={strikeStatusFilter}
                  onChange={(e) => {
                    setStrikeStatusFilter(e.target.value as 'not_yet_voted' | 'voted' | 'unknown' | 'observed_elsewhere' | '');
                    setStrikePage(1);
                  }}
                  className="w-full px-3 py-2 border border-[var(--border-soft)] rounded-xl text-sm bg-[var(--surface-raised)] min-h-[44px]"
                >
                  <option value="">All turnout states</option>
                  <option value="not_yet_voted">Not yet voted</option>
                  <option value="voted">Voted</option>
                  <option value="observed_elsewhere">Observed elsewhere</option>
                  <option value="unknown">Unknown</option>
                </select>
              </div>
              <p className="text-[11px] text-[var(--text-secondary)] mb-3">
                Need to correct a prior mark? Switch turnout filter to "Voted" or "All turnout states", then update and save again.
              </p>

              {debouncedStrikeSearch && externalMatches.length > 0 && (
                <div className="mb-3 rounded-xl border border-amber-200 bg-amber-50 px-3 py-2 text-xs text-amber-900">
                  {externalMatches.length} out-of-precinct search match{externalMatches.length === 1 ? '' : 'es'} found. These can be marked <span className="font-semibold">Observed Elsewhere</span> without converting them into normal in-precinct turnout.
                </div>
              )}

              {strikeListLoading ? (
                <div className="text-sm text-[var(--text-secondary)] py-4">Loading strike list...</div>
              ) : (
                <>
                  {/* Mobile: one-at-a-time expandable cards */}
                  <div className="space-y-2 lg:hidden">
                    {[
                      { title: 'Assigned Precinct Voters', items: strikeVoters, emphasized: false },
                      { title: 'Out-of-Precinct Search Matches', items: externalMatches, emphasized: true },
                    ].map((section) => section.items.length > 0 ? (
                      <div key={section.title} className="space-y-2">
                        <p className={`text-[11px] font-semibold uppercase tracking-wider ${section.emphasized ? 'text-amber-700' : 'text-[var(--text-secondary)]'}`}>
                          {section.title}
                        </p>
                        {section.items.map((voter) => {
                          const expanded = activeVoterId === voter.id;
                          return (
                            <div
                              key={voter.id}
                              className={`border rounded-xl p-3 ${voter.out_of_precinct ? 'border-amber-200 bg-amber-50/70' : 'border-[var(--border-soft)] bg-[var(--surface-raised)]'}`}
                            >
                              <button
                                type="button"
                                onClick={() => setActiveVoterId((prev) => prev === voter.id ? null : voter.id)}
                                className="w-full text-left"
                                aria-expanded={expanded}
                              >
                                <div className="flex items-center justify-between gap-2">
                                  <div>
                                    <p className="font-medium text-[var(--text-primary)]">{voter.print_name}</p>
                                    <p className="text-xs text-[var(--text-secondary)]">{voter.address || voter.voter_registration_number || 'No address listed'}</p>
                                    {voter.out_of_precinct ? (
                                      <p className="text-[11px] text-amber-800 mt-1">
                                        Registered in {voter.village_name || 'another village'} / Precinct {voter.precinct_number || 'unknown'}
                                      </p>
                                    ) : voter.supporter_overlay?.supporter_count ? (
                                      <p className="text-[11px] text-primary mt-1">
                                        {voter.supporter_overlay.supporter_count} matched campaign supporter{voter.supporter_overlay.supporter_count === 1 ? '' : 's'}
                                      </p>
                                    ) : null}
                                  </div>
                                  <div className="flex items-center gap-2">
                                    <span className={`text-xs border rounded-full px-2 py-1 ${turnoutStatusBadgeClasses(voter.turnout_status)}`}>
                                      {turnoutStatusLabel(voter.turnout_status)}
                                    </span>
                                    {expanded ? (
                                      <ChevronUp className="w-4 h-4 text-[var(--text-muted)]" />
                                    ) : (
                                      <ChevronDown className="w-4 h-4 text-[var(--text-muted)]" />
                                    )}
                                  </div>
                                </div>
                                <p className="mt-1 text-[11px] text-[var(--text-muted)]">
                                  {expanded ? 'Tap to collapse' : 'Tap to expand'}
                                </p>
                              </button>
                              {expanded && renderVoterActions(voter)}
                            </div>
                          );
                        })}
                      </div>
                    ) : null)}
                  </div>

                  {/* Desktop: split list + detail panel */}
                  <div className="hidden lg:grid lg:grid-cols-3 gap-3">
                    <div className="lg:col-span-1 space-y-2 max-h-[560px] overflow-y-auto pr-1">
                      {[
                        { title: 'Assigned Precinct Voters', items: strikeVoters, emphasized: false },
                        { title: 'Out-of-Precinct Search Matches', items: externalMatches, emphasized: true },
                      ].map((section) => section.items.length > 0 ? (
                        <div key={section.title} className="space-y-2">
                          <p className={`text-[11px] font-semibold uppercase tracking-wider px-1 ${section.emphasized ? 'text-amber-700' : 'text-[var(--text-secondary)]'}`}>
                            {section.title}
                          </p>
                          {section.items.map((voter) => (
                            <button
                              key={voter.id}
                              type="button"
                              onClick={() => setActiveVoterId(voter.id)}
                              className={`w-full text-left border rounded-xl p-3 transition-colors ${
                                activeVoterId === voter.id
                                  ? voter.out_of_precinct
                                    ? 'border-amber-300 bg-amber-50'
                                    : 'border-primary bg-blue-50'
                                  : voter.out_of_precinct
                                    ? 'border-amber-200 bg-amber-50/70 hover:bg-amber-50'
                                    : 'border-[var(--border-soft)] bg-[var(--surface-raised)] hover:bg-[var(--surface-bg)]'
                              }`}
                            >
                              <div className="flex items-center justify-between gap-2">
                                <p className="font-medium text-[var(--text-primary)] truncate">{voter.print_name}</p>
                                <span className={`text-xs border rounded-full px-2 py-1 ${turnoutStatusBadgeClasses(voter.turnout_status)}`}>
                                  {turnoutStatusLabel(voter.turnout_status)}
                                </span>
                              </div>
                              <p className="text-xs text-[var(--text-secondary)] mt-1">{voter.address || voter.voter_registration_number || 'No address listed'}</p>
                              {voter.out_of_precinct ? (
                                <p className="text-[11px] text-amber-800 mt-1 truncate">
                                  Registered in {voter.village_name || 'another village'} / Precinct {voter.precinct_number || 'unknown'}
                                </p>
                              ) : voter.supporter_overlay?.supporter_count ? (
                                <p className="text-[11px] text-primary mt-1 truncate">
                                  {voter.supporter_overlay.supporter_count} matched campaign supporter{voter.supporter_overlay.supporter_count === 1 ? '' : 's'}
                                </p>
                              ) : null}
                            </button>
                          ))}
                        </div>
                      ) : null)}
                    </div>
                    <div className="lg:col-span-2 border border-[var(--border-soft)] rounded-xl p-3 bg-[var(--surface-raised)] min-h-[320px]">
                      {activeVoter ? (
                        <>
                          <div className="flex items-center justify-between gap-2">
                            <div>
                              <p className="font-medium text-[var(--text-primary)]">{activeVoter.print_name}</p>
                              <p className="text-xs text-[var(--text-secondary)]">{activeVoter.address || activeVoter.voter_registration_number || 'No address listed'}</p>
                              {activeVoter.out_of_precinct ? (
                                <p className="text-xs text-amber-800 mt-1">
                                  Registered in {activeVoter.village_name || 'another village'} / Precinct {activeVoter.precinct_number || 'unknown'}
                                </p>
                              ) : activeVoter.supporter_overlay?.supporter_count ? (
                                <p className="text-xs text-primary mt-1">
                                  {activeVoter.supporter_overlay.supporter_count} matched campaign supporter{activeVoter.supporter_overlay.supporter_count === 1 ? '' : 's'}
                                </p>
                              ) : null}
                            </div>
                            <span className={`text-xs border rounded-full px-2 py-1 ${turnoutStatusBadgeClasses(activeVoter.turnout_status)}`}>
                              {turnoutStatusLabel(activeVoter.turnout_status)}
                            </span>
                          </div>
                          {renderVoterActions(activeVoter)}
                        </>
                      ) : (
                        <div className="h-full flex items-center justify-center text-sm text-[var(--text-muted)]">
                          Select a voter to update turnout and matched-supporter details.
                        </div>
                      )}
                    </div>
                  </div>

                  {!strikeListLoading && strikeVoters.length === 0 && externalMatches.length === 0 && (
                    <div className="space-y-3 py-4">
                      <div className="text-sm text-[var(--text-muted)]">No voters match current strike-list filters.</div>
                      {debouncedStrikeSearch && (
                        <div className="rounded-xl border border-amber-200 bg-amber-50 px-3 py-3 text-xs text-amber-900">
                          <p className="font-semibold">Name heard but not on the election-day list?</p>
                          <p className="mt-1">
                            Keep the official strike list tied to real election-day voters. If this person is a campaign supporter or someone heard at the site but no voter row exists here, record a <span className="font-semibold">Name Not On List</span> incident instead of forcing them into turnout.
                          </p>
                          <button
                            type="button"
                            onClick={() => {
                              setReportFormOpen(true);
                              setReportType('not_on_list');
                              setNotes((current) => current || `Name heard but not found on election-day list: ${debouncedStrikeSearch}`);
                              setVoterCount('0');
                            }}
                            className="mt-3 min-h-[40px] rounded-xl border border-amber-300 bg-white px-3 text-xs font-semibold text-amber-900"
                          >
                            Record Name Not On List
                          </button>
                        </div>
                      )}
                    </div>
                  )}
                </>
              )}

              {strikeListData?.pagination && strikeListData.pagination.pages > 1 && (
                <div className="mt-3 flex flex-wrap items-center justify-between gap-2">
                  <div className="text-xs text-[var(--text-secondary)]">
                    Page {strikeListData.pagination.page} of {strikeListData.pagination.pages}
                  </div>
                  <div className="flex items-center gap-2">
                    <select
                      value={strikePerPage}
                      onChange={(e) => {
                        setStrikePerPage(Number(e.target.value));
                        setStrikePage(1);
                      }}
                      className="px-2 py-1.5 border border-[var(--border-soft)] rounded-lg text-xs bg-[var(--surface-raised)]"
                    >
                      <option value={10}>10/page</option>
                      <option value={25}>25/page</option>
                      <option value={50}>50/page</option>
                      <option value={100}>100/page</option>
                    </select>
                    <button
                      type="button"
                      disabled={strikePage <= 1}
                      onClick={() => setStrikePage((p) => p - 1)}
                      className="px-3 py-1.5 rounded-lg border border-[var(--border-soft)] text-xs disabled:opacity-40"
                    >
                      Prev
                    </button>
                    <button
                      type="button"
                      disabled={strikePage >= strikeListData.pagination.pages}
                      onClick={() => setStrikePage((p) => p + 1)}
                      className="px-3 py-1.5 rounded-lg border border-[var(--border-soft)] text-xs disabled:opacity-40"
                    >
                      Next
                    </button>
                  </div>
                </div>
              )}
            </div>

            {reportFormOpen && (
              <form onSubmit={handleSubmit} className="app-card p-4">
                <p className={`text-[11px] border rounded-lg px-2.5 py-2 mb-3 ${
                  isNameNotOnListReport
                    ? 'text-amber-900 bg-amber-50 border-amber-200'
                    : 'text-blue-700 bg-blue-50 border-blue-200'
                }`}>
                  {isNameNotOnListReport
                    ? 'Use this incident when a name is heard at the site but no election-day voter row exists in the strike list. Include the name heard, who reported it, and any provisional / wrong-precinct context.'
                    : 'Submitting this report updates precinct reporting and War Room turnout metrics.'}
                </p>
                <div className="grid grid-cols-2 gap-2 mb-3">
                  {REPORT_TYPES.map(({ value, label, icon: Icon }) => (
                    <button
                      key={value}
                      type="button"
                      onClick={() => setReportType(value)}
                      className={`p-2 min-h-[44px] rounded-xl border text-sm font-medium text-left flex items-center gap-2 ${
                        reportType === value
                          ? 'border-primary bg-blue-50 text-primary'
                          : 'border-[var(--border-soft)] text-[var(--text-secondary)] hover:bg-[var(--surface-bg)]'
                      }`}
                    >
                      <Icon className="w-4 h-4" /> {label}
                    </button>
                  ))}
                </div>

                {isNameNotOnListReport ? (
                  <div className="mb-3 rounded-xl border border-[var(--border-soft)] bg-[var(--surface-bg)] px-4 py-3 text-sm text-[var(--text-secondary)]">
                    This incident does not change the precinct turnout count. It records an exception for War Room and Data Ops follow-up.
                  </div>
                ) : (
                  <div className="mb-3">
                    <label className="block text-sm font-medium text-[var(--text-primary)] mb-1">
                      Voters who have voted so far
                    </label>
                    <input
                      type="number"
                      value={voterCount}
                      onChange={e => setVoterCount(e.target.value)}
                      placeholder="Enter count"
                      className="w-full px-4 py-3 border border-[var(--border-soft)] rounded-xl text-lg focus:ring-2 focus:ring-primary"
                      min="0"
                      autoFocus
                      required
                    />
                  </div>
                )}

                <div className="mb-3">
                  <label className="block text-sm font-medium text-[var(--text-primary)] mb-1">
                    {isNameNotOnListReport ? 'Details (required)' : 'Notes (optional)'}
                  </label>
                  <textarea
                    value={notes}
                    onChange={e => setNotes(e.target.value)}
                    placeholder={isNameNotOnListReport
                      ? 'Example: Stassie Shimizu said she voted here; not found in election-day list; possible supporter-only record.'
                      : 'Any issues, observations...'}
                    className="w-full px-3 py-2 border border-[var(--border-soft)] rounded-xl text-sm focus:ring-2 focus:ring-primary"
                    rows={2}
                    required={isNameNotOnListReport}
                  />
                </div>

                <button
                  type="submit"
                  disabled={reportMutation.isPending || (!isNameNotOnListReport && !voterCount) || (isNameNotOnListReport && !notes.trim())}
                  className="w-full bg-primary hover:bg-primary-dark text-white font-bold py-3 rounded-xl flex items-center justify-center gap-2 disabled:opacity-50"
                >
                  <Send className="w-4 h-4" />
                  {reportMutation.isPending ? 'Submitting...' : isNameNotOnListReport ? 'Submit Incident' : 'Submit Report'}
                </button>
              </form>
            )}
          </div>
        ) : (
          <div className="bg-blue-50 border border-blue-200 rounded-2xl p-3 mb-4 text-sm text-blue-700 flex items-center gap-2">
            <MapPin className="w-4 h-4 shrink-0" />
            Tap a precinct below to submit a report
          </div>
        )}

        <div className="app-card p-3 mb-4 grid grid-cols-1 md:grid-cols-5 gap-3">
          <div className="relative md:col-span-2">
            <Search className="w-4 h-4 absolute left-3 top-3 text-[var(--text-muted)]" />
            <input
              type="text"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search precinct #, site, alpha..."
              className="w-full pl-9 pr-3 py-2 border border-[var(--border-soft)] rounded-xl text-sm min-h-[44px]"
            />
          </div>
          <select
            value={filterVillage}
            onChange={e => setFilterVillage(e.target.value)}
            className="px-3 py-2 border border-[var(--border-soft)] rounded-xl text-sm bg-[var(--surface-raised)] min-h-[44px]"
          >
            <option value="">All accessible villages ({stats.total_precincts} precincts)</option>
            {villages.map((v) => (
              <option key={v.id} value={v.id}>
                {v.name} ({v.reporting_count}/{v.total_precincts} reporting)
              </option>
            ))}
          </select>
          <select
            value={reportingFilter}
            onChange={(e) => setReportingFilter(e.target.value)}
            className="px-3 py-2 border border-[var(--border-soft)] rounded-xl text-sm bg-[var(--surface-raised)] min-h-[44px]"
          >
            <option value="">All statuses</option>
            <option value="reporting">Reporting only</option>
            <option value="not_reporting">Not reporting</option>
          </select>
          <select
            value={`${sortBy}:${sortDir}`}
            onChange={(e) => {
              const [field, dir] = e.target.value.split(':') as [PollWatcherSortField, 'asc' | 'desc'];
              setSortBy(field);
              setSortDir(dir);
            }}
            className="px-3 py-2 border border-[var(--border-soft)] rounded-xl text-sm bg-[var(--surface-raised)] min-h-[44px]"
          >
            <option value="precinct_number:asc">Precinct number A-Z</option>
            <option value="precinct_number:desc">Precinct number Z-A</option>
            <option value="turnout_pct:desc">Highest turnout</option>
            <option value="turnout_pct:asc">Lowest turnout</option>
            <option value="last_voter_count:desc">Most voters counted</option>
            <option value="last_voter_count:asc">Least voters counted</option>
          </select>
        </div>
        <p className="text-xs text-[var(--text-secondary)] mb-3">
          Showing {visiblePrecinctCount} of {stats.total_precincts} precincts
        </p>

        {/* Precinct List */}
        {filteredVillages.map((village) => (
          <div key={village.id} className="mb-4">
            <div className="flex items-center justify-between mb-2">
              <h3 className="font-semibold text-[var(--text-primary)]">{village.name}</h3>
              <span className="text-xs text-[var(--text-muted)]">
                {village.reporting_count}/{village.total_precincts} reporting
              </span>
            </div>
            <div className="space-y-2">
              {village.precincts.map((p) => (
                <button
                  key={p.id}
                  onClick={() => handleSelectPrecinct(p)}
                  className={`w-full text-left rounded-xl border p-3 min-h-[44px] transition-all ${
                    selectedPrecinct?.id === p.id
                      ? 'border-primary bg-blue-50 ring-2 ring-primary/20'
                      : p.reporting
                        ? 'border-green-200 bg-green-50 hover:shadow-sm'
                        : 'border-[var(--border-soft)] bg-[var(--surface-raised)] hover:shadow-sm'
                  }`}
                >
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-2">
                      {p.reporting ? (
                        <CheckCircle className="w-4 h-4 text-green-500" />
                      ) : (
                        <Clock className="w-4 h-4 text-[var(--text-muted)]" />
                      )}
                      <span className="font-medium text-[var(--text-primary)]">Precinct {p.number}</span>
                      {p.alpha_range && (
                        <span className="text-xs text-[var(--text-muted)]">({p.alpha_range})</span>
                      )}
                    </div>
                    {p.reporting ? (
                      <div className="text-right">
                        <span className={`font-bold ${turnoutColor(p.turnout_pct)}`}>
                          {p.turnout_pct}%
                        </span>
                        <span className="text-xs text-[var(--text-muted)] ml-1">
                          ({p.last_voter_count?.toLocaleString()})
                        </span>
                      </div>
                    ) : (
                      <span className="text-xs text-[var(--text-muted)]">No report</span>
                    )}
                  </div>
                  {p.reporting && (
                    <div className="mt-1.5">
                      <div className="w-full bg-[var(--surface-overlay)] rounded-full h-1.5">
                        <div
                          className={`h-1.5 rounded-full ${turnoutBg(p.turnout_pct)}`}
                          style={{ width: `${Math.min(p.turnout_pct || 0, 100)}%` }}
                        />
                      </div>
                      {p.last_notes && (
                        <p className="text-xs text-[var(--text-secondary)] mt-1 flex items-center gap-1">
                          <AlertTriangle className="w-3 h-3" /> {p.last_notes}
                        </p>
                      )}
                    </div>
                  )}
                </button>
              ))}
            </div>
          </div>
        ))}
        {filteredVillages.length === 0 && (
          <div className="text-center text-[var(--text-muted)] py-8">
            No precincts match current filters.
          </div>
        )}
      </div>
    </WorkspacePage>
  );
}
