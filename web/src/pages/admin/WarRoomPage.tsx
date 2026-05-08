import { useEffect, useMemo, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { createWarRoomContactAttempt, getWarRoom } from '../../lib/api';
import { Link, useSearchParams } from 'react-router-dom';
import {
  Radio, Users, TrendingUp, MapPin, Phone, PhoneCall, UserCheck,
  AlertTriangle, Clock, Activity, Eye, CheckCircle, X, Search
} from 'lucide-react';
import { useCampaignUpdates } from '../../hooks/useCampaignUpdates';
import { useRealtimeToast } from '../../hooks/useRealtimeToast';
import { useSession } from '../../hooks/useSession';
import WorkspacePage from '../../components/WorkspacePage';

interface WarRoomVillage {
  id: number;
  name: string;
  status: string;
  has_issues: boolean;
  reporting_precincts: number;
  total_precincts: number;
  turnout_pct: number;
  voters_reported: number;
  supporter_count: number;
  motorcade_count: number;
  not_yet_voted_count: number;
  observed_elsewhere_count?: number;
  outreach_attempted_count: number;
  outreach_reached_count: number;
}

interface CallPriority {
  id: number;
  name: string;
  turnout_pct: number;
  supporter_count: number;
  motorcade_count: number;
}

interface ActivityItem {
  id: number;
  report_type: string;
  precinct_number: string;
  reported_at: string;
  village_name: string;
  voter_count: number;
  notes?: string;
}

interface WarRoomStats {
  island_turnout_pct: number;
  total_voted: number;
  total_registered: number;
  reporting_precincts: number;
  total_precincts: number;
  reporting_pct: number;
  total_supporters: number;
  last_hour_reports: number;
  total_not_yet_voted: number;
  total_observed_elsewhere: number;
  total_outreach_attempted: number;
  total_outreach_reached: number;
  total_unmatched_supporters: number;
  election_day_voters: number;
}

interface NotYetVotedQueueItem {
  id: number;
  name: string;
  turnout_pct: number;
  not_yet_voted_count: number;
  outreach_attempted_count: number;
  outreach_reached_count: number;
}

interface SupporterQueueItem {
  id: number;
  print_name: string;
  contact_number?: string | null;
  village_name?: string | null;
  precinct_number?: string | null;
  gec_village_name?: string | null;
  turnout_status?: string | null;
  turnout_note?: string | null;
  turnout_updated_at?: string | null;
  turnout_updated_by_user_name?: string | null;
  latest_contact_attempt?: {
    outcome: string;
    channel: string;
    recorded_at: string;
  } | null;
}

interface ElectionDayInfo {
  list_date?: string | null;
  active_import_id?: number | null;
  active_import_filename?: string | null;
  active_import_set_at?: string | null;
  active_import_explicit?: boolean;
}

interface WarRoomData {
  election_day?: ElectionDayInfo;
  villages: WarRoomVillage[];
  stats: WarRoomStats;
  call_priorities: CallPriority[];
  not_yet_voted_queue: NotYetVotedQueueItem[];
  not_yet_voted_supporters?: SupporterQueueItem[];
  observed_elsewhere_supporters?: SupporterQueueItem[];
  unmatched_supporters?: SupporterQueueItem[];
  activity: ActivityItem[];
}

type WarRoomVillageSortField = 'turnout_pct' | 'name' | 'supporter_count';

function turnoutColor(pct: number) {
  if (pct >= 50) return 'text-green-600';
  if (pct >= 30) return 'text-yellow-600';
  return 'text-red-600';
}

function turnoutBg(pct: number) {
  if (pct >= 50) return 'bg-green-500';
  if (pct >= 30) return 'bg-yellow-500';
  return 'bg-red-500';
}

function statusBadge(status: string, hasIssues: boolean) {
  if (hasIssues) return 'bg-red-100 text-red-700 border-red-300';
  if (status === 'strong') return 'bg-green-100 text-green-700 border-green-300';
  if (status === 'moderate') return 'bg-yellow-100 text-yellow-700 border-yellow-300';
  if (status === 'low') return 'bg-red-100 text-red-700 border-red-300';
  return 'bg-gray-100 text-gray-500 border-gray-300';
}

function statusLabel(status: string, hasIssues: boolean) {
  if (hasIssues) return 'ISSUE';
  if (status === 'strong') return 'STRONG';
  if (status === 'moderate') return 'MODERATE';
  if (status === 'low') return 'LOW';
  return 'NO DATA';
}

function reportTypeIcon(type: string) {
  switch (type) {
    case 'turnout_update': return 'TURNOUT';
    case 'line_length': return 'LINES';
    case 'issue': return 'ISSUE';
    case 'closing': return 'CLOSING';
    case 'not_on_list': return 'NOT ON LIST';
    default: return 'REPORT';
  }
}

function timeAgo(iso: string) {
  const diff = Date.now() - new Date(iso).getTime();
  const mins = Math.floor(diff / 60000);
  if (mins < 1) return 'just now';
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.floor(mins / 60);
  return `${hrs}h ${mins % 60}m ago`;
}

function supporterLabel(count: number) {
  return `${count} supporter${count === 1 ? "" : "s"}`;
}

function voterLabel(count: number) {
  return `${count.toLocaleString()} voter${count === 1 ? "" : "s"}`;
}

export default function WarRoomPage() {
  const queryClient = useQueryClient();
  const { toasts, handleEvent, dismiss } = useRealtimeToast();
  useCampaignUpdates(handleEvent);
  const { data: sessionData } = useSession();
  const [searchParams, setSearchParams] = useSearchParams();
  const [villageSearch, setVillageSearch] = useState(searchParams.get('village_search') || '');
  const [statusFilter, setStatusFilter] = useState(searchParams.get('status') || '');
  const [sortBy, setSortBy] = useState<WarRoomVillageSortField>((searchParams.get('sort_by') as WarRoomVillageSortField) || 'turnout_pct');
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>((searchParams.get('sort_dir') as 'asc' | 'desc') || 'desc');
  const [contactNotice, setContactNotice] = useState('');

  const { data, isLoading, isError } = useQuery<WarRoomData>({
    queryKey: ['war_room'],
    queryFn: getWarRoom,
    refetchInterval: 30_000, // Fallback poll every 30s (WebSocket handles instant updates)
  });

  const contactAttemptMutation = useMutation({
    mutationFn: ({ supporterId, outcome }: { supporterId: number; outcome: 'attempted' | 'reached' }) =>
      createWarRoomContactAttempt(supporterId, { outcome, channel: 'call' }),
    onSuccess: (response: { message?: string }) => {
      setContactNotice(response?.message || 'Contact attempt logged');
      queryClient.invalidateQueries({ queryKey: ['war_room'] });
      setTimeout(() => setContactNotice(''), 3000);
    },
  });

  const villages = useMemo(() => data?.villages || [], [data?.villages]);
  const filteredVillages = useMemo(() => {
    const q = villageSearch.trim().toLowerCase();
    const filtered = villages.filter((village) => {
      const searchHit = q.length === 0 || village.name.toLowerCase().includes(q);
      const statusHit = statusFilter === ''
        ? true
        : statusFilter === 'issues'
          ? village.has_issues
          : village.status === statusFilter;
      return searchHit && statusHit;
    });

    return [...filtered].sort((a, b) => {
      const dir = sortDir === 'asc' ? 1 : -1;
      if (sortBy === 'name') return a.name.localeCompare(b.name) * dir;
      if (sortBy === 'supporter_count') return (a.supporter_count - b.supporter_count) * dir;
      return (a.turnout_pct - b.turnout_pct) * dir;
    });
  }, [villages, villageSearch, statusFilter, sortBy, sortDir]);

  useEffect(() => {
    const params = new URLSearchParams();
    if (villageSearch) params.set('village_search', villageSearch);
    if (statusFilter) params.set('status', statusFilter);
    params.set('sort_by', sortBy);
    params.set('sort_dir', sortDir);
    setSearchParams(params, { replace: true });
  }, [villageSearch, statusFilter, sortBy, sortDir, setSearchParams]);

  if (isLoading) {
    return (
      <div className="min-h-[200px] flex items-center justify-center">
        <div className="text-gray-500 text-lg flex items-center gap-3">
          <Radio className="w-5 h-5 animate-pulse" /> Loading War Room...
        </div>
      </div>
    );
  }

  if (isError || !data) {
    return (
      <div className="min-h-[200px] flex items-center justify-center">
        <div className="text-center p-8">
          <AlertTriangle className="w-12 h-12 text-red-500 mx-auto mb-4 opacity-70" />
          <h2 className="text-xl font-bold text-gray-900 mb-2">Can't connect to server</h2>
          <p className="text-gray-500 mb-4">Check your connection and try again.</p>
          <button onClick={() => window.location.reload()} className="bg-primary text-white px-4 py-2 rounded-lg hover:bg-primary-dark">
            Retry
          </button>
        </div>
      </div>
    );
  }

  const { stats, call_priorities, activity, not_yet_voted_queue } = data;
  const notYetVotedSupporters = data.not_yet_voted_supporters || [];
  const observedElsewhereSupporters = data.observed_elsewhere_supporters || [];
  const unmatchedSupporters = data.unmatched_supporters || [];

  return (
    <WorkspacePage width="full" className="space-y-6">
      {/* Real-time toast notifications */}
      {toasts.length > 0 && (
        <div className="fixed top-16 left-2 right-2 sm:left-auto sm:right-4 z-50 space-y-2 max-w-sm sm:max-w-md">
          {toasts.map(toast => (
            <div
              key={toast.id}
              className={`rounded-lg p-3 pr-8 shadow-lg border text-sm animate-slide-in relative ${
                toast.type === 'success' ? 'bg-green-50 border-green-200 text-green-800' :
                toast.type === 'warning' ? 'bg-yellow-50 border-yellow-200 text-yellow-800' :
                'bg-blue-50 border-blue-200 text-blue-800'
              }`}
            >
              {toast.message}
              <button
                onClick={() => dismiss(toast.id)}
                className="absolute top-2 right-2 text-gray-400 hover:text-gray-600"
              >
                <X className="w-3.5 h-3.5" />
              </button>
            </div>
          ))}
        </div>
      )}

      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <Radio className="w-5 h-5 text-red-500 animate-pulse" />
          <div>
            <h1 className="text-lg font-bold text-gray-900 tracking-tight">WAR ROOM</h1>
            <p className="text-xs text-gray-400">
              Election Day Command Center
              {data.election_day?.list_date ? ` · GEC list ${data.election_day.list_date}` : ''}
            </p>
          </div>
        </div>
        <div className="flex items-center gap-4 text-sm">
          {sessionData?.permissions?.can_access_poll_watcher && (
            <Link to="/admin/poll-watcher" className="text-primary hover:text-primary-dark min-h-[44px] px-2 flex items-center gap-1 font-medium">
              <Eye className="w-4 h-4" /> Poll Watcher
            </Link>
          )}
          <span className="text-gray-400">
            {new Date().toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' })}
          </span>
        </div>
      </div>

      <div>
        {/* Top Stats */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-6">
          <div className="app-card p-4">
            <div className="flex items-center gap-2 text-gray-500 text-xs mb-1">
              <Activity className="w-3.5 h-3.5" /> ISLAND TURNOUT
            </div>
            <div className={`text-3xl font-bold ${turnoutColor(stats.island_turnout_pct)}`}>
              {stats.island_turnout_pct}%
            </div>
            <div className="text-xs text-gray-400">
              {stats.total_voted.toLocaleString()} / {stats.total_registered.toLocaleString()}
            </div>
          </div>
          <div className="app-card p-4">
            <div className="flex items-center gap-2 text-gray-500 text-xs mb-1">
              <MapPin className="w-3.5 h-3.5" /> REPORTING
            </div>
            <div className="text-3xl font-bold text-primary">
              {stats.reporting_precincts}/{stats.total_precincts}
            </div>
            <div className="text-xs text-gray-400">{stats.reporting_pct}% of precincts</div>
          </div>
          <div className="app-card p-4">
            <div className="flex items-center gap-2 text-gray-500 text-xs mb-1">
              <Users className="w-3.5 h-3.5" /> SUPPORTERS
            </div>
            <div className="text-3xl font-bold text-purple-600">
              {stats.total_supporters.toLocaleString()}
            </div>
            <div className="text-xs text-gray-400">{stats.election_day_voters.toLocaleString()} election-day voters</div>
          </div>
          <div className="app-card p-4">
            <div className="flex items-center gap-2 text-gray-500 text-xs mb-1">
              <Clock className="w-3.5 h-3.5" /> LAST HOUR
            </div>
            <div className="text-3xl font-bold text-cyan-600">
              {stats.last_hour_reports}
            </div>
            <div className="text-xs text-gray-400">reports received</div>
          </div>
        </div>
        <div className="grid grid-cols-1 md:grid-cols-4 gap-3 mb-6">
          <div className="app-card p-4">
            <div className="flex items-center gap-2 text-gray-500 text-xs mb-1">
              <Users className="w-3.5 h-3.5" /> NOT YET VOTED
            </div>
            <div className="text-2xl font-bold text-amber-600">
              {stats.total_not_yet_voted.toLocaleString()}
            </div>
            <div className="text-xs text-gray-400">matched supporter queue</div>
          </div>
          <div className="app-card p-4">
            <div className="flex items-center gap-2 text-gray-500 text-xs mb-1">
              <AlertTriangle className="w-3.5 h-3.5" /> OBSERVED ELSEWHERE
            </div>
            <div className="text-2xl font-bold text-amber-700">
              {stats.total_observed_elsewhere.toLocaleString()}
            </div>
            <div className="text-xs text-gray-400">turnout exceptions to reconcile</div>
          </div>
          <div className="app-card p-4">
            <div className="flex items-center gap-2 text-gray-500 text-xs mb-1">
              <Phone className="w-3.5 h-3.5" /> ATTEMPTED
            </div>
            <div className="text-2xl font-bold text-primary">
              {stats.total_outreach_attempted.toLocaleString()}
            </div>
            <div className="text-xs text-gray-400">supporters contacted</div>
          </div>
          <div className="app-card p-4">
            <div className="flex items-center gap-2 text-gray-500 text-xs mb-1">
              <CheckCircle className="w-3.5 h-3.5" /> REACHED
            </div>
            <div className="text-2xl font-bold text-green-600">
              {stats.total_outreach_reached.toLocaleString()}
            </div>
            <div className="text-xs text-gray-400">supporters reached</div>
          </div>
        </div>
        {stats.total_unmatched_supporters > 0 && (
          <div className="bg-amber-50 border border-amber-200 rounded-xl px-3 py-2 mb-6 text-sm text-amber-800">
            {stats.total_unmatched_supporters.toLocaleString()} approved supporters are not linked to the active election-day GEC list yet. Review the unmatched queue before live use.
          </div>
        )}

        <div className="grid md:grid-cols-3 gap-4">
          {/* Village Map - 2 cols */}
          <div className="md:col-span-2">
            <h2 className="text-sm font-semibold text-gray-400 uppercase tracking-wider mb-3 flex items-center gap-2">
              <TrendingUp className="w-4 h-4" /> Village Turnout
            </h2>
            <p className="text-xs text-gray-500 mb-3">
              "NO DATA" means no precinct turnout report has been submitted yet (strike-list supporter updates alone do not mark precinct reporting).
            </p>
            <p className="text-xs text-blue-700 bg-blue-50 border border-blue-200 rounded-lg px-2.5 py-2 mb-3">
              War Room turnout is driven by precinct reports. Supporter strike-list marks are for outreach tracking and follow-up.
            </p>
            <div className="bg-white border border-gray-200 rounded-xl p-3 mb-3 grid grid-cols-1 sm:grid-cols-4 gap-3">
              <div className="relative sm:col-span-2">
                <Search className="w-4 h-4 absolute left-3 top-3 text-gray-500" />
                <input
                  type="text"
                  value={villageSearch}
                  onChange={(e) => setVillageSearch(e.target.value)}
                  placeholder="Search village..."
                  className="w-full pl-9 pr-3 py-2 rounded-xl bg-white border border-gray-300 text-gray-900 text-sm min-h-[44px]"
                />
              </div>
              <select
                value={statusFilter}
                onChange={(e) => setStatusFilter(e.target.value)}
                className="px-3 py-2 rounded-xl bg-white border border-gray-300 text-gray-900 text-sm min-h-[44px]"
              >
                <option value="">All statuses</option>
                <option value="strong">Strong</option>
                <option value="moderate">Moderate</option>
                <option value="low">Low</option>
                <option value="issues">With issues</option>
              </select>
              <select
                value={`${sortBy}:${sortDir}`}
                onChange={(e) => {
                  const [field, dir] = e.target.value.split(':') as [WarRoomVillageSortField, 'asc' | 'desc'];
                  setSortBy(field);
                  setSortDir(dir);
                }}
                className="px-3 py-2 rounded-xl bg-white border border-gray-300 text-gray-900 text-sm min-h-[44px]"
              >
                <option value="turnout_pct:desc">Highest turnout</option>
                <option value="turnout_pct:asc">Lowest turnout</option>
                <option value="name:asc">Village A-Z</option>
                <option value="name:desc">Village Z-A</option>
                <option value="supporter_count:desc">Most supporters</option>
                <option value="supporter_count:asc">Least supporters</option>
              </select>
            </div>
            <p className="text-xs text-gray-500 mb-3">
              Showing {filteredVillages.length} of {villages.length} villages
            </p>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
              {filteredVillages.map((v) => (
                <div
                  key={v.id}
                  className={`bg-white rounded-xl border p-3 ${
                    v.has_issues ? 'border-red-500/50' : 'border-gray-200'
                  }`}
                >
                  <div className="flex items-center justify-between mb-1">
                    <span className="font-medium text-sm truncate">{v.name}</span>
                    <span className={`text-xs px-1.5 py-0.5 rounded border font-medium ${statusBadge(v.status, v.has_issues)}`}>
                      {statusLabel(v.status, v.has_issues)}
                    </span>
                  </div>
                  <div className="flex items-center justify-between text-xs text-gray-400 mb-1.5">
                    <span>{v.reporting_precincts}/{v.total_precincts} precincts</span>
                    <span className={`font-bold text-sm ${turnoutColor(v.turnout_pct)}`}>
                      {v.turnout_pct}%
                    </span>
                  </div>
                  <div className="w-full bg-gray-200 rounded-full h-1.5">
                    <div
                      className={`h-1.5 rounded-full transition-all ${turnoutBg(v.turnout_pct)}`}
                      style={{ width: `${Math.min(v.turnout_pct, 100)}%` }}
                    />
                  </div>
                  <div className="flex justify-between text-xs text-gray-500 mt-1">
                    <span>{v.voters_reported.toLocaleString()} voted</span>
                    <span>{supporterLabel(v.supporter_count)} · {v.observed_elsewhere_count || 0} elsewhere</span>
                  </div>
                </div>
              ))}
            </div>
            {filteredVillages.length === 0 && (
              <div className="bg-white border border-gray-200 rounded-xl p-4 text-sm text-gray-500 text-center mt-2">
                No villages match current filters.
              </div>
            )}
          </div>

          {/* Right Sidebar */}
          <div className="space-y-4">
            {/* Not-yet-voted Queue */}
            <div>
              <div className="mb-3 flex items-center justify-between">
                <h2 className="text-sm font-semibold text-gray-400 uppercase tracking-wider flex items-center gap-2">
                  <Users className="w-4 h-4 text-amber-500" /> Not Yet Voted Queue
                </h2>
                {sessionData?.permissions?.can_access_poll_watcher && (
                  <Link
                    to="/admin/poll-watcher"
                    className="text-xs font-medium text-primary hover:text-primary-dark underline underline-offset-2"
                  >
                    View list
                  </Link>
                )}
              </div>
              {not_yet_voted_queue.length > 0 ? (
                <div className="space-y-2">
                  {not_yet_voted_queue.map((v) => (
                    <Link
                      key={v.id}
                      to={`/admin/poll-watcher?village_id=${v.id}`}
                      className="block bg-amber-50 border border-amber-200 rounded-xl p-3 hover:bg-amber-100 transition-colors"
                    >
                      <div className="flex items-center justify-between">
                        <span className="font-medium text-sm">{v.name}</span>
                        <span className="text-amber-600 font-bold text-sm">{v.not_yet_voted_count} pending</span>
                      </div>
                      <div className="text-xs text-gray-400">
                        Turnout {v.turnout_pct}% · Attempted {v.outreach_attempted_count} · Reached {v.outreach_reached_count}
                      </div>
                    </Link>
                  ))}
                </div>
              ) : (
                <div className="bg-white border border-gray-200 rounded-xl p-4 text-center text-sm text-gray-400">
                  No pending not-yet-voted queue.
                </div>
              )}
            </div>

            <div>
              <h2 className="text-sm font-semibold text-gray-400 uppercase tracking-wider mb-3 flex items-center gap-2">
                <Users className="w-4 h-4 text-amber-500" /> Supporters To Call
              </h2>
              {contactNotice && (
                <p className="text-xs text-green-600 bg-green-50 border border-green-200 rounded-lg px-2.5 py-2 mb-3">
                  {contactNotice}
                </p>
              )}
              {notYetVotedSupporters.length > 0 ? (
                <div className="space-y-2 max-h-80 overflow-y-auto">
                  {notYetVotedSupporters.slice(0, 12).map((supporter) => (
                    <div key={supporter.id} className="bg-white border border-gray-200 rounded-xl p-3">
                      <div className="flex items-start justify-between gap-2">
                        <div>
                          <p className="font-medium text-sm">{supporter.print_name}</p>
                          <p className="text-xs text-gray-400">
                            {supporter.village_name || 'Unknown village'} · Precinct {supporter.precinct_number || 'unassigned'}
                          </p>
                          {supporter.contact_number && (
                            <p className="text-xs text-primary mt-1">{supporter.contact_number}</p>
                          )}
                        </div>
                        <span className="text-xs text-amber-700 bg-amber-50 border border-amber-200 rounded-full px-2 py-1">
                          pending
                        </span>
                      </div>
                      {supporter.latest_contact_attempt && (
                        <p className="text-xs text-gray-500 mt-2">
                          Last contact: {supporter.latest_contact_attempt.outcome} via {supporter.latest_contact_attempt.channel}
                        </p>
                      )}
                      <div className="mt-3 grid grid-cols-2 gap-2">
                        <button
                          type="button"
                          onClick={() => contactAttemptMutation.mutate({ supporterId: supporter.id, outcome: 'attempted' })}
                          className="min-h-[40px] rounded-xl border border-gray-300 text-xs font-semibold text-gray-700 flex items-center justify-center gap-1 disabled:opacity-40"
                          disabled={contactAttemptMutation.isPending}
                        >
                          <PhoneCall className="w-3.5 h-3.5" /> Call Attempted
                        </button>
                        <button
                          type="button"
                          onClick={() => contactAttemptMutation.mutate({ supporterId: supporter.id, outcome: 'reached' })}
                          className="min-h-[40px] rounded-xl border border-gray-300 text-xs font-semibold text-gray-700 flex items-center justify-center gap-1 disabled:opacity-40"
                          disabled={contactAttemptMutation.isPending}
                        >
                          <UserCheck className="w-3.5 h-3.5" /> Reached
                        </button>
                      </div>
                    </div>
                  ))}
                </div>
              ) : (
                <div className="bg-white border border-gray-200 rounded-xl p-4 text-center text-sm text-gray-400">
                  No matched supporters currently need calls.
                </div>
              )}
            </div>

            <div>
              <h2 className="text-sm font-semibold text-gray-400 uppercase tracking-wider mb-3 flex items-center gap-2">
                <AlertTriangle className="w-4 h-4 text-amber-600" /> Observed Elsewhere / Reconcile
              </h2>
              {observedElsewhereSupporters.length > 0 ? (
                <div className="space-y-2 max-h-72 overflow-y-auto">
                  {observedElsewhereSupporters.map((supporter) => (
                    <div key={supporter.id} className="bg-amber-50 border border-amber-200 rounded-xl p-3">
                      <div className="flex items-start justify-between gap-2">
                        <div>
                          <p className="font-medium text-sm">{supporter.print_name}</p>
                          <p className="text-xs text-gray-500">
                            Registered in {supporter.gec_village_name || supporter.village_name || 'Unknown village'} · Precinct {supporter.precinct_number || 'unknown'}
                          </p>
                          {supporter.contact_number && <p className="text-xs text-primary mt-1">{supporter.contact_number}</p>}
                        </div>
                        <span className="text-xs text-amber-800 bg-white border border-amber-200 rounded-full px-2 py-1">
                          observed elsewhere
                        </span>
                      </div>
                      {supporter.turnout_note && (
                        <p className="text-xs text-amber-900 mt-2">{supporter.turnout_note}</p>
                      )}
                      {(supporter.turnout_updated_at || supporter.turnout_updated_by_user_name) && (
                        <p className="text-[11px] text-gray-500 mt-1">
                          {supporter.turnout_updated_by_user_name ? `Marked by ${supporter.turnout_updated_by_user_name}` : 'Updated'}
                          {supporter.turnout_updated_at ? ` · ${new Date(supporter.turnout_updated_at).toLocaleString()}` : ''}
                        </p>
                      )}
                    </div>
                  ))}
                </div>
              ) : (
                <div className="bg-white border border-gray-200 rounded-xl p-4 text-center text-sm text-gray-400">
                  No out-of-precinct turnout exceptions in this scope.
                </div>
              )}
            </div>

            <div>
              <h2 className="text-sm font-semibold text-gray-400 uppercase tracking-wider mb-3 flex items-center gap-2">
                <AlertTriangle className="w-4 h-4 text-yellow-500" /> Unmatched Supporters
              </h2>
              {unmatchedSupporters.length > 0 ? (
                <div className="space-y-2 max-h-64 overflow-y-auto">
                  {unmatchedSupporters.slice(0, 8).map((supporter) => (
                    <div key={supporter.id} className="bg-yellow-50 border border-yellow-200 rounded-xl p-3">
                      <p className="font-medium text-sm">{supporter.print_name}</p>
                      <p className="text-xs text-gray-500">
                        {supporter.village_name || 'Unknown village'} · Precinct {supporter.precinct_number || 'unassigned'}
                      </p>
                      {supporter.contact_number && <p className="text-xs text-primary mt-1">{supporter.contact_number}</p>}
                    </div>
                  ))}
                </div>
              ) : (
                <div className="bg-white border border-gray-200 rounded-xl p-4 text-center text-sm text-gray-400">
                  No unmatched approved supporters in this scope.
                </div>
              )}
            </div>

            {/* Call Bank Priorities */}
            <div>
              <h2 className="text-sm font-semibold text-gray-400 uppercase tracking-wider mb-3 flex items-center gap-2">
                <Phone className="w-4 h-4 text-red-500" /> Call Priorities
              </h2>
              {call_priorities.length > 0 ? (
                <div className="space-y-2">
                  {call_priorities.map((v) => (
                    <div key={v.id} className="bg-red-50 border border-red-200 rounded-xl p-3">
                      <div className="flex items-center justify-between">
                        <span className="font-medium text-sm">{v.name}</span>
                        <span className="text-red-600 font-bold text-sm">{v.turnout_pct}%</span>
                      </div>
                      <div className="text-xs text-gray-400">
                        {supporterLabel(v.supporter_count)} to call · {v.motorcade_count} motorcade ready
                      </div>
                    </div>
                  ))}
                </div>
              ) : (
                <div className="bg-white border border-gray-200 rounded-xl p-4 text-center text-sm text-gray-400">
                  {stats.reporting_precincts === 0 ? (
                    <>No reports yet — waiting for poll watchers</>
                  ) : (
                    <><CheckCircle className="w-5 h-5 mx-auto mb-1 text-green-500" /> All visible villages showing good turnout</>
                  )}
                </div>
              )}
            </div>

            {/* Activity Feed */}
            <div>
              <h2 className="text-sm font-semibold text-gray-400 uppercase tracking-wider mb-3 flex items-center gap-2">
                <Radio className="w-4 h-4 text-green-500" /> Live Activity
              </h2>
              {activity.length > 0 ? (
                <div className="space-y-2 max-h-96 overflow-y-auto">
                  {activity.map((a) => (
                    <div key={a.id} className="bg-white border border-gray-200 rounded-xl p-3">
                      <div className="flex items-center justify-between">
                        <span className="text-sm">
                          {reportTypeIcon(a.report_type)} Precinct {a.precinct_number}
                        </span>
                        <span className="text-xs text-gray-400">{timeAgo(a.reported_at)}</span>
                      </div>
                      <div className="text-xs text-gray-400">
                        {a.report_type === 'not_on_list'
                          ? `${a.village_name} · Name heard but not found on election-day list`
                          : `${a.village_name} · ${voterLabel(a.voter_count)}`}
                      </div>
                      {a.notes && (
                        <div className="text-xs text-yellow-600 mt-1 flex items-center gap-1">
                          <AlertTriangle className="w-3 h-3" /> {a.notes}
                        </div>
                      )}
                    </div>
                  ))}
                </div>
              ) : (
                <div className="bg-white border border-gray-200 rounded-xl p-4 text-center text-sm text-gray-400">
                  Waiting for first reports...
                </div>
              )}
            </div>
          </div>
        </div>
      </div>
    </WorkspacePage>
  );
}
