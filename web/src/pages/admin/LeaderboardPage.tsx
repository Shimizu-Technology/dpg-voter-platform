import { useEffect, useMemo, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { getLeaderboard } from '../../lib/api';
import { Link, useSearchParams } from 'react-router-dom';
import { Trophy, Medal, Award, TrendingUp, Users, Target, Search } from 'lucide-react';
import { useSession } from '../../hooks/useSession';
import WorkspacePage from '../../components/WorkspacePage';

interface LeaderboardEntry {
  leader_code: string;
  owner_name: string;
  assigned_user_name?: string | null;
  assigned_user_email?: string | null;
  rank: number;
  signup_count: number;
  qr_signups: number;
  manual_entries: number;
  scan_entries: number;
  import_entries: number;
  total_added: number;
  village_name: string;
}

interface LeaderboardStats {
  total_qr_signups: number;
  total_manual_entries: number;
  total_scan_entries: number;
  total_import_entries: number;
  total_added: number;
  active_leaders: number;
  avg_signups_per_leader: number;
  top_leader_signups: number;
}

type LeaderboardSortField = 'rank' | 'leader_code' | 'qr_signups' | 'total_added' | 'village_name';
const SORT_FIELDS: LeaderboardSortField[] = ['rank', 'leader_code', 'qr_signups', 'total_added', 'village_name'];

function parseSortField(value: string | null): LeaderboardSortField {
  return SORT_FIELDS.includes(value as LeaderboardSortField) ? (value as LeaderboardSortField) : 'qr_signups';
}

function rankIcon(rank: number) {
  if (rank === 1) return <Trophy className="w-6 h-6 text-yellow-500" />;
  if (rank === 2) return <Medal className="w-6 h-6 text-[var(--text-muted)]" />;
  if (rank === 3) return <Award className="w-6 h-6 text-amber-600" />;
  return <span className="w-6 h-6 flex items-center justify-center text-sm font-bold text-[var(--text-muted)]">{rank}</span>;
}

function rankBg(rank: number) {
  if (rank === 1) return 'bg-yellow-500/10 border-yellow-500/30';
  if (rank === 2) return 'bg-[var(--surface-bg)] border-[var(--border-soft)]';
  if (rank === 3) return 'bg-amber-50 border-amber-200';
  return 'bg-[var(--surface-raised)] border-[var(--border-soft)]';
}

export default function LeaderboardPage() {
  const { data: sessionData } = useSession();
  const [searchParams, setSearchParams] = useSearchParams();
  const [search, setSearch] = useState(searchParams.get('search') || '');
  const [villageFilter, setVillageFilter] = useState(searchParams.get('village') || '');
  const [sortBy, setSortBy] = useState<LeaderboardSortField>(parseSortField(searchParams.get('sort_by')));
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>((searchParams.get('sort_dir') as 'asc' | 'desc') || 'desc');
  const { data, isLoading } = useQuery({
    queryKey: ['leaderboard'],
    queryFn: getLeaderboard,
  });
  const leaderboard: LeaderboardEntry[] = useMemo(() => data?.leaderboard || [], [data?.leaderboard]);
  const scopedVillageIds = sessionData?.user?.scoped_village_ids ?? null;
  const stats: LeaderboardStats = data?.stats || {
    total_qr_signups: 0,
    total_manual_entries: 0,
    total_scan_entries: 0,
    total_import_entries: 0,
    total_added: 0,
    active_leaders: 0,
    avg_signups_per_leader: 0,
    top_leader_signups: 0,
  };
  const villageOptions = useMemo(
    () => Array.from(new Set(leaderboard.map((entry) => entry.village_name).filter(Boolean))).sort((a, b) => a.localeCompare(b)),
    [leaderboard]
  );

  const filteredLeaderboard = useMemo(() => {
    const q = search.trim().toLowerCase();
    const filtered = leaderboard.filter((entry) => {
      const searchHit = q.length === 0 ||
        entry.leader_code.toLowerCase().includes(q) ||
        entry.owner_name.toLowerCase().includes(q) ||
        entry.village_name.toLowerCase().includes(q);
      const villageHit = villageFilter ? entry.village_name === villageFilter : true;
      return searchHit && villageHit;
    });

    return [...filtered].sort((a, b) => {
      const dir = sortDir === 'asc' ? 1 : -1;
      if (sortBy === 'rank') return (a.rank - b.rank) * dir;
      if (sortBy === 'leader_code') return a.leader_code.localeCompare(b.leader_code) * dir;
      if (sortBy === 'village_name') return a.village_name.localeCompare(b.village_name) * dir;
      if (sortBy === 'total_added') return (a.total_added - b.total_added) * dir;
      return (a.qr_signups - b.qr_signups) * dir;
    });
  }, [leaderboard, search, villageFilter, sortBy, sortDir]);

  useEffect(() => {
    const params = new URLSearchParams();
    if (search) params.set('search', search);
    if (villageFilter) params.set('village', villageFilter);
    params.set('sort_by', sortBy);
    params.set('sort_dir', sortDir);
    setSearchParams(params, { replace: true });
  }, [search, villageFilter, sortBy, sortDir, setSearchParams]);

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-20">
        <div className="text-[var(--text-muted)] text-sm font-medium">Loading leaderboard...</div>
      </div>
    );
  }

  return (
    <WorkspacePage width="full" className="space-y-6">
      {/* Header */}
      <div>
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-yellow-100 flex items-center justify-center">
            <Trophy className="w-5 h-5 text-yellow-600" />
          </div>
          <div>
            <h1 className="text-2xl font-bold text-gray-900 tracking-tight">Block Leader Leaderboard</h1>
            <p className="text-gray-500 text-sm">Ranked by QR referrals with full intake breakdown</p>
          </div>
        </div>
      </div>

      <div className="rounded-xl border border-blue-200 bg-blue-50 px-3 py-2 text-xs text-blue-800">
        Rankings use <span className="font-semibold">Referred (QR)</span>. Manual, scan, and import totals are shown for operational visibility.
      </div>

      <div>
        {/* Stats */}
        <div className="grid grid-cols-2 lg:grid-cols-5 gap-3 mb-6">
          <div className="app-card p-3 text-center">
            <Users className="w-5 h-5 mx-auto text-[var(--text-muted)] mb-1" />
            <div className="text-2xl font-bold text-[var(--text-primary)]">{stats.total_qr_signups}</div>
            <div className="text-xs text-[var(--text-secondary)]">Referred (QR)</div>
          </div>
          <div className="app-card p-3 text-center">
            <Target className="w-5 h-5 mx-auto text-[var(--text-muted)] mb-1" />
            <div className="text-2xl font-bold text-[var(--text-primary)]">{stats.total_manual_entries}</div>
            <div className="text-xs text-[var(--text-secondary)]">Entered Manually</div>
          </div>
          <div className="app-card p-3 text-center">
            <TrendingUp className="w-5 h-5 mx-auto text-[var(--text-muted)] mb-1" />
            <div className="text-2xl font-bold text-[var(--text-primary)]">{stats.total_scan_entries}</div>
            <div className="text-xs text-[var(--text-secondary)]">Entered via Scan</div>
          </div>
          <div className="app-card p-3 text-center">
            <TrendingUp className="w-5 h-5 mx-auto text-[var(--text-muted)] mb-1" />
            <div className="text-2xl font-bold text-[var(--text-primary)]">{stats.total_import_entries}</div>
            <div className="text-xs text-[var(--text-secondary)]">Imported</div>
          </div>
          <div className="app-card p-3 text-center">
            <TrendingUp className="w-5 h-5 mx-auto text-[var(--text-muted)] mb-1" />
            <div className="text-2xl font-bold text-[var(--text-primary)]">{stats.total_added}</div>
            <div className="text-xs text-[var(--text-secondary)]">Total Added</div>
          </div>
        </div>

        <div className="app-card p-4 mb-4 grid grid-cols-1 md:grid-cols-4 gap-3">
          <div className="relative md:col-span-2">
            <Search className="w-4 h-4 absolute left-3 top-3 text-[var(--text-muted)]" />
            <input
              type="text"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search owner, code, or village..."
              className="w-full pl-9 pr-3 py-2 border border-[var(--border-soft)] rounded-xl min-h-[44px]"
            />
          </div>
          <select
            value={villageFilter}
            onChange={(e) => setVillageFilter(e.target.value)}
            className="border border-[var(--border-soft)] rounded-xl px-3 py-2 bg-[var(--surface-raised)] min-h-[44px]"
          >
            <option value="">{scopedVillageIds === null ? 'All villages' : 'All accessible villages'}</option>
            {villageOptions.map((village) => (
              <option key={village} value={village}>{village}</option>
            ))}
          </select>
          <select
            value={`${sortBy}:${sortDir}`}
            onChange={(e) => {
              const [field, dir] = e.target.value.split(':') as [LeaderboardSortField, 'asc' | 'desc'];
              setSortBy(field);
              setSortDir(dir);
            }}
            className="border border-[var(--border-soft)] rounded-xl px-3 py-2 bg-[var(--surface-raised)] min-h-[44px]"
          >
            <option value="qr_signups:desc">Most QR referrals</option>
            <option value="qr_signups:asc">Least QR referrals</option>
            <option value="total_added:desc">Most total added</option>
            <option value="total_added:asc">Least total added</option>
            <option value="rank:asc">Best rank first</option>
            <option value="rank:desc">Lowest rank first</option>
            <option value="leader_code:asc">Leader code A-Z</option>
            <option value="leader_code:desc">Leader code Z-A</option>
            <option value="village_name:asc">Village A-Z</option>
            <option value="village_name:desc">Village Z-A</option>
          </select>
        </div>

        <p className="text-xs text-[var(--text-secondary)] mb-3">
          Showing {filteredLeaderboard.length} of {leaderboard.length} staff/referral owners
        </p>

        {/* Leaderboard */}
        <div className="space-y-3">
          {filteredLeaderboard.map((leader) => (
            <div
              key={leader.leader_code}
              className={`rounded-2xl shadow-sm border p-4 ${rankBg(leader.rank)} transition-all`}
            >
              <div className="flex items-center gap-3">
                <div className="shrink-0">{rankIcon(leader.rank)}</div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center justify-between">
                    <span className="font-semibold text-[var(--text-primary)] truncate">
                      {leader.owner_name}
                    </span>
                    <span className="text-lg font-bold text-primary ml-2">
                      {leader.total_added}
                    </span>
                  </div>
                  <div className="flex items-center justify-between text-sm text-[var(--text-secondary)]">
                    <span>{leader.village_name} · {leader.leader_code}</span>
                    <span>Total added</span>
                  </div>
                  <div className="mt-2 flex flex-wrap gap-2 text-[11px]">
                    <span className="rounded-full bg-amber-100 text-amber-800 px-2 py-0.5">QR: {leader.qr_signups}</span>
                    <span className="rounded-full bg-blue-100 text-blue-800 px-2 py-0.5">Manual: {leader.manual_entries}</span>
                    <span className="rounded-full bg-indigo-100 text-indigo-800 px-2 py-0.5">Scan: {leader.scan_entries}</span>
                    <span className="rounded-full bg-emerald-100 text-emerald-800 px-2 py-0.5">Import: {leader.import_entries}</span>
                    <span className="rounded-full bg-gray-200 text-gray-900 px-2 py-0.5 font-semibold">Total: {leader.total_added}</span>
                  </div>
                </div>
              </div>
              {/* Progress bar relative to top leader */}
              {stats.top_leader_signups > 0 && (
                <div className="mt-2 w-full bg-[var(--surface-overlay)] rounded-full h-1.5">
                  <div
                    className="h-1.5 rounded-full bg-primary transition-all"
                    style={{ width: `${(leader.qr_signups / stats.top_leader_signups) * 100}%` }}
                  />
                </div>
              )}
            </div>
          ))}

          {filteredLeaderboard.length === 0 && (
            <div className="text-center text-[var(--text-muted)] py-12">
              No leaderboard entries match current filters.
            </div>
          )}
        </div>

        {sessionData?.permissions?.can_access_qr && (
          <div className="mt-6 text-center">
            <Link to="/admin/qr" className="text-primary hover:underline text-sm font-medium">
              Generate QR Codes →
            </Link>
          </div>
        )}
      </div>
    </WorkspacePage>
  );
}
