import { useState, useMemo, useEffect } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { getDuplicates, resolveDuplicate, scanDuplicates, getVillages } from '../../lib/api';
import { Link, useLocation, useSearchParams } from 'react-router-dom';
import { AlertTriangle, CheckCircle, Search, ArrowRight, X } from 'lucide-react';
import { useSession } from '../../hooks/useSession';
import { formatDateTime } from '../../lib/datetime';
import WorkspacePage from '../../components/WorkspacePage';

interface Supporter {
  id: number;
  first_name: string;
  last_name: string;
  print_name: string;
  contact_number: string;
  email?: string;
  village_name: string;
  village_id: number;
  precinct_number?: string;
  potential_duplicate: boolean;
  duplicate_of_id?: number;
  duplicate_notes?: string;
  duplicate_of?: { id: number; name: string; contact_number: string };
  source: string;
  created_at: string;
  verification_status: string;
  review_status?: string;
  public_review_status?: string;
}

interface Village {
  id: number;
  name: string;
}

interface DuplicateGroup {
  key: string;
  supporter: Supporter;
  match: Supporter | { id: number; name: string; contact_number: string } | null;
}

function sourceLabel(source: string) {
  return source?.replace(/_/g, ' ') || 'Unknown';
}

function verificationBadge(status: string) {
  if (status === 'verified') return <span className="text-[11px] font-medium text-green-700">Voter check: Matched to GEC</span>;
  if (status === 'flagged') return <span className="text-[11px] font-medium text-amber-700">Voter check: Flagged for review</span>;
  return <span className="text-[11px] font-medium text-slate-600">Voter check: Needs voter review</span>;
}

function supporterApprovalStatusLabel(supporter: Pick<Supporter, 'source' | 'review_status' | 'public_review_status'>) {
  if ((supporter.source === 'public_signup' || supporter.source === 'qr_signup') && supporter.public_review_status === 'pending') {
    return 'Pending Public Review';
  }
  if (supporter.review_status === 'pending') {
    return 'Pending Supporter Review';
  }
  if (supporter.review_status === 'rejected') {
    return 'Rejected Submission';
  }
  if ((supporter.source === 'public_signup' || supporter.source === 'qr_signup') && supporter.review_status === 'approved') {
    return 'Approved Public Supporter';
  }
  if (supporter.source === 'staff_entry') return 'Approved Staff Supporter';
  if (supporter.source === 'bulk_import') return 'Approved Imported Supporter';
  return 'DPG Supporter';
}

function supporterApprovalStatusClass(supporter: Pick<Supporter, 'source' | 'review_status' | 'public_review_status'>) {
  if ((supporter.source === 'public_signup' || supporter.source === 'qr_signup') && supporter.public_review_status === 'pending') {
    return 'bg-amber-100 text-amber-700';
  }
  if (supporter.review_status === 'pending') {
    return 'bg-blue-100 text-blue-700';
  }
  if (supporter.review_status === 'rejected') {
    return 'bg-red-100 text-red-700';
  }
  if ((supporter.source === 'public_signup' || supporter.source === 'qr_signup') && supporter.review_status === 'approved') {
    return 'bg-blue-100 text-blue-700';
  }
  if (supporter.source === 'staff_entry') return 'bg-purple-100 text-purple-700';
  if (supporter.source === 'bulk_import') return 'bg-slate-100 text-slate-700';
  return 'bg-gray-100 text-gray-700';
}

function SupporterCard({
  supporter,
  isFullRecord,
  recordLabel,
  supporterBasePath,
}: {
  supporter: Supporter | { id: number; name: string; contact_number: string };
  isFullRecord: boolean;
  recordLabel?: string;
  supporterBasePath: string;
}) {
  if (!isFullRecord) {
    const s = supporter as { id: number; name: string; contact_number: string };
    return (
      <div className="flex-1 min-w-0 p-4 bg-[var(--surface-bg)] rounded-xl">
        <div className="flex items-start justify-between gap-3 mb-2">
          <div className="min-w-0">
            {recordLabel && (
              <div className="text-[11px] uppercase tracking-[0.08em] text-[var(--text-muted)] mb-1">
                {recordLabel}
              </div>
            )}
            <Link to={`${supporterBasePath}/${s.id}`} className="font-medium text-primary hover:underline">
              {s.name}
            </Link>
          </div>
        </div>
        <p className="text-sm text-[var(--text-secondary)] mt-1">{s.contact_number}</p>
        <p className="text-xs text-[var(--text-muted)] mt-2">Limited info shown here. Open the full record for more detail.</p>
      </div>
    );
  }

  const s = supporter as Supporter;
  return (
    <div className="flex-1 min-w-0 p-4 bg-[var(--surface-bg)] rounded-xl">
      <div className="flex items-start justify-between gap-3 mb-3">
        <div className="min-w-0">
          {recordLabel && (
            <div className="text-[11px] uppercase tracking-[0.08em] text-[var(--text-muted)] mb-1">
              {recordLabel}
            </div>
          )}
          <Link to={`${supporterBasePath}/${s.id}`} className="font-semibold text-primary hover:underline">
            {s.first_name} {s.last_name}
          </Link>
        </div>
        <span className={`shrink-0 text-[11px] px-2.5 py-1 rounded-full font-medium ${supporterApprovalStatusClass(s)}`}>
          {supporterApprovalStatusLabel(s)}
        </span>
      </div>
      <div className="space-y-1.5 text-sm text-[var(--text-secondary)]">
        <p>{s.contact_number || 'No phone'}</p>
        {s.email && <p>{s.email}</p>}
        <p>{s.village_name}{s.precinct_number ? ` · Precinct ${s.precinct_number}` : ''}</p>
        <div className="flex flex-wrap items-center gap-x-3 gap-y-1 pt-1 text-[11px] text-[var(--text-muted)]">
          <span>{sourceLabel(s.source)}</span>
          <span>Created {formatDateTime(s.created_at)}</span>
        </div>
        <div className="pt-1">
          {verificationBadge(s.verification_status)}
        </div>
      </div>
    </div>
  );
}

export default function DuplicatesPage() {
  const [villageFilter, setVillageFilter] = useState<string>('');
  const queryClient = useQueryClient();
  const { data: sessionData } = useSession();
  const location = useLocation();
  const [searchParams] = useSearchParams();
  const supporterBasePath = location.pathname.startsWith('/data') ? '/data/supporters' : '/admin/supporters';
  const focusSupporterId = Number(searchParams.get('focus_supporter_id') || '');

  const { data: dupData, isLoading } = useQuery({
    queryKey: ['duplicates', villageFilter],
    queryFn: () => getDuplicates(villageFilter ? Number(villageFilter) : undefined),
  });

  const { data: villagesData } = useQuery({
    queryKey: ['villages'],
    queryFn: getVillages,
  });

  const scanMutation = useMutation({
    mutationFn: scanDuplicates,
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: ['duplicates'] });
      alert(`Scan complete: ${data.flagged_count} new duplicates found`);
    },
  });

  const resolveMutation = useMutation({
    mutationFn: ({ id, resolution, mergeIntoId }: { id: number; resolution: string; mergeIntoId?: number }) =>
      resolveDuplicate(id, resolution, mergeIntoId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['duplicates'] });
    },
  });

  const supporters: Supporter[] = useMemo(() => dupData?.supporters || [], [dupData?.supporters]);
  const totalCount: number = dupData?.total_count || 0;
  const villagesAll: Village[] = villagesData?.villages || villagesData || [];
  const scopedVillageIds = sessionData?.user?.scoped_village_ids ?? null;
  const villages: Village[] = scopedVillageIds === null
    ? villagesAll
    : villagesAll.filter((v) => scopedVillageIds.includes(v.id));

  useEffect(() => {
    if (scopedVillageIds === null) return;
    if (!villageFilter) return;
    if (scopedVillageIds.includes(Number(villageFilter))) return;
    queueMicrotask(() => setVillageFilter(''));
  }, [scopedVillageIds, villageFilter]);

  // Group duplicates into pairs
  const groups: DuplicateGroup[] = useMemo(() => {
    const seen = new Set<string>();
    const result: DuplicateGroup[] = [];

    // Build a lookup map for full supporter records
    const supporterMap = new Map<number, Supporter>();
    for (const s of supporters) {
      supporterMap.set(s.id, s);
    }

    for (const s of supporters) {
      const matchId = s.duplicate_of_id;
      // Create a stable key so we don't show the same pair twice
      const pairKey = matchId
        ? [Math.min(s.id, matchId), Math.max(s.id, matchId)].join('-')
        : `solo-${s.id}`;

      if (seen.has(pairKey)) continue;
      seen.add(pairKey);

      // Try to find the full match record; fall back to the embedded reference
      const fullMatch = matchId ? supporterMap.get(matchId) : null;
      const match = fullMatch || s.duplicate_of || null;

      result.push({ key: pairKey, supporter: s, match });
    }

    return result;
  }, [supporters]);

  useEffect(() => {
    if (!focusSupporterId || groups.length === 0) return;

    const target = document.querySelector<HTMLElement>(`[data-duplicate-group="${focusSupporterId}"]`);
    if (!target) return;

    target.scrollIntoView({ behavior: 'smooth', block: 'center' });
  }, [focusSupporterId, groups]);

  return (
    <WorkspacePage width="full" className="space-y-6">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-[var(--text-primary)]">Duplicate Review</h1>
          <p className="text-sm text-[var(--text-secondary)] mt-1">
            {groups.length} potential duplicate group{groups.length !== 1 ? 's' : ''} ({totalCount} records flagged)
          </p>
        </div>
        <button
          onClick={() => scanMutation.mutate()}
          disabled={scanMutation.isPending}
          className="inline-flex items-center gap-2 px-4 py-2 bg-primary text-white rounded-xl min-h-[44px] hover:bg-[#15305a] disabled:opacity-50"
        >
          <Search className="w-4 h-4" />
          {scanMutation.isPending ? 'Scanning...' : 'Scan for Duplicates'}
        </button>
      </div>

      {/* Filter */}
      <div className="app-card p-4">
        <label className="text-sm font-medium text-[var(--text-primary)] mr-2">Filter by Village:</label>
        <select
          value={villageFilter}
          onChange={(e) => setVillageFilter(e.target.value)}
          className="rounded-xl border border-[var(--border-soft)] px-3 py-2 text-sm min-h-[44px]"
        >
          <option value="">{scopedVillageIds === null ? 'All villages' : 'All accessible villages'}</option>
          {villages.map((v: Village) => (
            <option key={v.id} value={v.id}>{v.name}</option>
          ))}
        </select>
      </div>

      {/* Groups */}
      {isLoading ? (
        <div className="text-center py-12 text-[var(--text-muted)]">Loading...</div>
      ) : groups.length === 0 ? (
        <div className="app-card p-12 text-center">
          <CheckCircle className="w-12 h-12 text-green-400 mx-auto mb-3" />
          <h3 className="text-lg font-medium text-[var(--text-primary)]">No Duplicates Found</h3>
          <p className="text-sm text-[var(--text-secondary)] mt-1">All supporters look unique. Run a scan to check again.</p>
        </div>
      ) : (
        <div className="space-y-4">
          {groups.map((group) => {
            const s = group.supporter;
            const match = group.match;
            const matchIsFullRecord = match ? 'first_name' in match : false;
            const fullMatch = matchIsFullRecord ? match as Supporter : null;
            const isFocusedGroup =
              focusSupporterId > 0 &&
              (s.id === focusSupporterId || ('id' in (match || {}) && (match as { id?: number }).id === focusSupporterId));
            const leftLabel = fullMatch
              ? new Date(s.created_at) >= new Date(fullMatch.created_at) ? 'Newer record' : 'Existing record'
              : 'Selected record';
            const rightLabel = fullMatch
              ? new Date(s.created_at) >= new Date(fullMatch.created_at) ? 'Existing record' : 'Newer record'
              : 'Matched record';

            return (
              <div
                key={group.key}
                data-duplicate-group={isFocusedGroup ? focusSupporterId : undefined}
                className={`app-card overflow-hidden ${isFocusedGroup ? 'ring-2 ring-amber-300' : ''}`}
              >
                {/* Match reason header */}
                <div className="px-4 py-2 bg-amber-50 border-b border-amber-200 flex items-center gap-2">
                  <AlertTriangle className="w-4 h-4 text-amber-500" />
                  <span className="text-sm font-medium text-amber-800">Potential Duplicate</span>
                  {s.duplicate_notes && (
                    <span className="text-xs text-amber-600 ml-2">{s.duplicate_notes}</span>
                  )}
                </div>

                {/* Side-by-side comparison */}
                <div className="p-4">
                  <div className="grid grid-cols-1 md:grid-cols-[1fr_auto_1fr] gap-3 items-start">
                    <SupporterCard supporter={s} isFullRecord={true} recordLabel={leftLabel} supporterBasePath={supporterBasePath} />

                    <div className="hidden md:flex items-center justify-center px-2">
                      <ArrowRight className="w-5 h-5 text-[var(--text-muted)] rotate-0" />
                    </div>
                    <div className="md:hidden flex items-center justify-center">
                      <span className="text-xs text-[var(--text-muted)]">matches with</span>
                    </div>

                    {match ? (
                      <SupporterCard supporter={match} isFullRecord={matchIsFullRecord} recordLabel={rightLabel} supporterBasePath={supporterBasePath} />
                    ) : (
                      <div className="flex-1 min-w-0 p-4 bg-[var(--surface-bg)] rounded-xl text-center text-sm text-[var(--text-muted)]">
                        Match record not found
                      </div>
                    )}
                  </div>

                  {/* Actions */}
                  <div className="flex flex-wrap items-center gap-2 mt-4 pt-3 border-t border-[var(--border-soft)]">
                    <button
                      onClick={() => resolveMutation.mutate({ id: s.id, resolution: 'dismiss' })}
                      disabled={resolveMutation.isPending}
                      className="inline-flex items-center gap-1 px-3 py-2 text-sm border border-[var(--border-soft)] rounded-xl min-h-[44px] hover:bg-[var(--surface-bg)] text-[var(--text-primary)]"
                    >
                      <X className="w-3.5 h-3.5" />
                      Not a Duplicate
                    </button>
                    {s.duplicate_of_id && match && (
                      <>
                        <button
                          onClick={() => {
                            if (!confirm(`Keep "${s.first_name} ${s.last_name}" and merge the other record into it?`)) return;
                            resolveMutation.mutate({ id: matchIsFullRecord ? match!.id : s.duplicate_of_id!, resolution: 'merge', mergeIntoId: s.id });
                          }}
                          disabled={resolveMutation.isPending}
                          className="inline-flex items-center gap-1 px-3 py-2 text-sm bg-primary text-white rounded-xl min-h-[44px] hover:bg-[#15305a]"
                        >
                          Keep Left
                        </button>
                        <button
                          onClick={() => {
                            if (!confirm(`Keep the matched record and merge "${s.first_name} ${s.last_name}" into it?`)) return;
                            resolveMutation.mutate({ id: s.id, resolution: 'merge', mergeIntoId: s.duplicate_of_id! });
                          }}
                          disabled={resolveMutation.isPending}
                          className="inline-flex items-center gap-1 px-3 py-2 text-sm bg-cta text-white rounded-xl min-h-[44px] hover:bg-[#a3182f]"
                        >
                          Keep Right
                        </button>
                      </>
                    )}
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      )}
    </WorkspacePage>
  );
}
