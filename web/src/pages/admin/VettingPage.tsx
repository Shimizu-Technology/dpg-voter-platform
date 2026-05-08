import { useEffect, useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { getSupporters, getVillages, verifySupporter, bulkVerifySupporters, updateSupporter } from '../../lib/api';
import { Link, useSearchParams } from 'react-router-dom';
import { useSession } from '../../hooks/useSession';
import { CheckCircle, XCircle, AlertTriangle, ShieldCheck, ClipboardList, ChevronDown, ChevronUp, Trash2, ArrowRight } from 'lucide-react';
import WorkspacePage from '../../components/WorkspacePage';

function DataOpsRedirectBanner() {
  return (
    <div className="mb-6 flex items-center gap-3 rounded-xl border border-blue-200 bg-blue-50 px-4 py-3 text-sm text-blue-800">
      <ShieldCheck className="w-4 h-4 shrink-0 text-blue-500" />
      <span>Vetting is now managed in the <strong>Data Ops Workspace</strong> for a cleaner workflow.</span>
      <Link to="/data/vetting" className="ml-auto flex items-center gap-1 font-semibold text-blue-700 hover:text-blue-900 whitespace-nowrap">
        Go to Data Ops <ArrowRight className="w-3.5 h-3.5" />
      </Link>
    </div>
  );
}

interface Supporter {
  id: number;
  first_name: string;
  last_name: string;
  contact_number: string;
  email?: string;
  village_name: string;
  village_id: number;
  source: string;
  created_at: string;
  verification_status: string;
  potential_duplicate: boolean;
  duplicate_notes?: string;
  duplicate_of_id?: number;
  registered_voter: boolean;
  opt_in_email: boolean;
  opt_in_text: boolean;
}

interface Village {
  id: number;
  name: string;
}

function canMarkVerifiedVoter(supporter: Pick<Supporter, 'registered_voter' | 'verification_status'>) {
  if (supporter.verification_status === 'verified') return false;
  return supporter.registered_voter;
}

export default function VettingPage() {
  const [searchParams] = useSearchParams();
  const initialVillageFilter = searchParams.get('village_id') || '';
  const [villageFilter, setVillageFilter] = useState<string>(initialVillageFilter);
  const [statusFilter, setStatusFilter] = useState<string>('unverified');
  const [selectedIds, setSelectedIds] = useState<Set<number>>(new Set());
  const [expandedId, setExpandedId] = useState<number | null>(null);
  const queryClient = useQueryClient();
  const { data: sessionData } = useSession();

  // Scoped users should default to their assigned area.
  const userVillageId = sessionData?.user?.assigned_village_id;
  const scopedVillageIds = sessionData?.user?.scoped_village_ids ?? null;
  const singleScopedVillageId = scopedVillageIds && scopedVillageIds.length === 1 ? String(scopedVillageIds[0]) : '';
  const forcedVillageFilter = singleScopedVillageId || (userVillageId ? String(userVillageId) : '');
  const effectiveVillageFilter = forcedVillageFilter || villageFilter;
  const isChief = sessionData?.user?.role === 'village_chief';
  const isLeader = sessionData?.user?.role === 'block_leader';

  const { data: supportersData, isLoading } = useQuery({
    queryKey: ['vetting-supporters', effectiveVillageFilter, statusFilter],
    queryFn: () => getSupporters({
      status: 'active',
      verification_status: statusFilter || undefined,
      village_id: effectiveVillageFilter || undefined,
      per_page: 200,
    }),
  });

  const { data: villagesData } = useQuery({
    queryKey: ['villages'],
    queryFn: getVillages,
  });

  const verifyMutation = useMutation({
    mutationFn: ({ id, status }: { id: number; status: string }) => verifySupporter(id, status),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['vetting-supporters'] });
      queryClient.invalidateQueries({ queryKey: ['session'] });
    },
  });

  const removeMutation = useMutation({
    mutationFn: (id: number) => updateSupporter(id, { status: 'removed' }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['vetting-supporters'] });
      queryClient.invalidateQueries({ queryKey: ['session'] });
      queryClient.invalidateQueries({ queryKey: ['dashboard'] });
    },
  });

  const bulkMutation = useMutation({
    mutationFn: ({ ids, status }: { ids: number[]; status: string }) => bulkVerifySupporters(ids, status),
    onSuccess: () => {
      setSelectedIds(new Set());
      queryClient.invalidateQueries({ queryKey: ['vetting-supporters'] });
      queryClient.invalidateQueries({ queryKey: ['session'] });
    },
  });

  const supporters: Supporter[] = supportersData?.supporters || [];
  const villagesAll: Village[] = villagesData?.villages || villagesData || [];
  const villages: Village[] = scopedVillageIds === null
    ? villagesAll
    : villagesAll.filter((v) => scopedVillageIds.includes(v.id));
  const selectedSupporters = supporters.filter((supporter) => selectedIds.has(supporter.id));
  const selectedCanVerify = selectedSupporters.length > 0 && selectedSupporters.every((supporter) => canMarkVerifiedVoter(supporter));

  useEffect(() => {
    if (scopedVillageIds === null) return;
    if (!villageFilter) return;
    if (scopedVillageIds.includes(Number(villageFilter))) return;
    queueMicrotask(() => setVillageFilter(''));
  }, [scopedVillageIds, villageFilter]);

  const toggleSelect = (id: number) => {
    setSelectedIds(prev => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const toggleSelectAll = () => {
    if (selectedIds.size === supporters.length) {
      setSelectedIds(new Set());
    } else {
      setSelectedIds(new Set(supporters.map(s => s.id)));
    }
  };

  const formatDate = (iso: string) => {
    const d = new Date(iso);
    return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });
  };

  const statusBadge = (status: string) => {
    switch (status) {
      case 'verified':
        return <span className="inline-flex items-center gap-1 text-xs px-2 py-0.5 rounded-full bg-green-100 text-green-600"><CheckCircle className="w-3 h-3" /> Verified</span>;
      case 'flagged':
        return <span className="inline-flex items-center gap-1 text-xs px-2 py-0.5 rounded-full bg-red-100 text-red-600"><XCircle className="w-3 h-3" /> Needs Review</span>;
      default:
        return <span className="inline-flex items-center gap-1 text-xs px-2 py-0.5 rounded-full bg-amber-100 text-amber-600"><AlertTriangle className="w-3 h-3" /> Pending Review</span>;
    }
  };

  return (
    <WorkspacePage width="full" className="space-y-6">
      <DataOpsRedirectBanner />
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-[var(--text-primary)] flex items-center gap-2">
            <ShieldCheck className="w-7 h-7 text-primary" />
            Voter Check Queue
          </h1>
          <p className="text-sm text-[var(--text-secondary)] mt-1">
            {statusFilter === 'unverified'
              ? `${supporters.length} supporter${supporters.length !== 1 ? 's' : ''} pending voter-check review`
              : `${supporters.length} supporter${supporters.length !== 1 ? 's' : ''} shown`
            }
          </p>
          <p className="text-xs text-[var(--text-muted)] mt-1">
            This queue is for accepted supporters whose GEC voter check still needs attention. Removed supporters are excluded from this queue.
          </p>
        </div>

        {/* Bulk actions */}
        {selectedIds.size > 0 && (
          <div className="flex items-center gap-2">
            <span className="text-sm text-[var(--text-secondary)]">{selectedIds.size} selected</span>
            <button
              onClick={() => bulkMutation.mutate({ ids: Array.from(selectedIds), status: 'verified' })}
              disabled={bulkMutation.isPending || !selectedCanVerify}
              className="inline-flex items-center gap-1 px-3 py-1.5 text-sm bg-green-600 text-white rounded-lg hover:bg-green-700 disabled:opacity-50"
              title={selectedCanVerify ? 'Mark selected supporters as verified voters' : 'Only supporters with a current GEC match can be marked as verified voters'}
            >
              <CheckCircle className="w-4 h-4" />
              Mark Verified Voter
            </button>
            <button
              onClick={() => bulkMutation.mutate({ ids: Array.from(selectedIds), status: 'flagged' })}
              disabled={bulkMutation.isPending}
              className="inline-flex items-center gap-1 px-3 py-1.5 text-sm bg-red-600 text-white rounded-lg hover:bg-red-700 disabled:opacity-50"
            >
              <XCircle className="w-4 h-4" />
              Flag All
            </button>
          </div>
        )}
      </div>

      {/* Filters */}
      <div className="app-card p-4 flex flex-wrap items-center gap-4">
        <div>
          <label className="text-sm font-medium text-[var(--text-primary)] mr-2">Status:</label>
          <select
            value={statusFilter}
            onChange={(e) => { setStatusFilter(e.target.value); setSelectedIds(new Set()); }}
            className="rounded-lg border border-[var(--border-soft)] px-3 py-1.5 text-sm"
          >
            <option value="unverified">Pending Review</option>
            <option value="verified">Verified</option>
            <option value="flagged">Needs Review</option>
            <option value="">All</option>
          </select>
        </div>

        {!isChief && !isLeader && !singleScopedVillageId && (
          <div>
            <label className="text-sm font-medium text-[var(--text-primary)] mr-2">Village:</label>
            <select
              value={villageFilter}
              onChange={(e) => { setVillageFilter(e.target.value); setSelectedIds(new Set()); }}
              className="rounded-lg border border-[var(--border-soft)] px-3 py-1.5 text-sm"
            >
              <option value="">{scopedVillageIds === null ? 'All villages' : 'All accessible villages'}</option>
              {villages.map((v: Village) => (
                <option key={v.id} value={v.id}>{v.name}</option>
              ))}
            </select>
          </div>
        )}

        {(isChief || isLeader || singleScopedVillageId) && effectiveVillageFilter && (
          <div className="text-sm text-[var(--text-secondary)]">
            Showing assigned area only
          </div>
        )}
      </div>

      {/* List */}
      {isLoading ? (
        <div className="text-center py-12 text-[var(--text-muted)]">Loading...</div>
      ) : supporters.length === 0 ? (
        <div className="app-card p-12 text-center">
          <ClipboardList className="w-12 h-12 text-green-400 mx-auto mb-3" />
          <h3 className="text-lg font-medium text-[var(--text-primary)]">
            {statusFilter === 'unverified' ? 'All Clear!' : 'No Results'}
          </h3>
          <p className="text-sm text-[var(--text-secondary)] mt-1">
            {statusFilter === 'unverified'
              ? 'No accepted supporters need voter-check review. Great job!'
              : 'No supporters match the current filters.'}
          </p>
        </div>
      ) : (
        <div className="space-y-2">
          {/* Select All */}
          <div className="flex items-center gap-2 px-2">
            <input
              type="checkbox"
              checked={selectedIds.size === supporters.length && supporters.length > 0}
              onChange={toggleSelectAll}
              className="w-4 h-4 rounded border-[var(--border-soft)] text-primary focus:ring-primary"
            />
            <span className="text-sm text-[var(--text-secondary)]">Select all</span>
          </div>

          {supporters.map((s) => {
            const isExpanded = expandedId === s.id;
            const canVerify = canMarkVerifiedVoter(s);
            return (
              <div key={s.id} className={`app-card p-4 transition-colors ${s.potential_duplicate ? 'border-l-4 border-l-amber-400' : ''}`}>
                <div className="flex items-start gap-3">
                  {/* Checkbox */}
                  <input
                    type="checkbox"
                    checked={selectedIds.has(s.id)}
                    onChange={() => toggleSelect(s.id)}
                    className="mt-1 w-4 h-4 rounded border-[var(--border-soft)] text-primary focus:ring-primary"
                  />

                  {/* Main content */}
                  <div className="flex-1 min-w-0">
                    <div className="flex flex-wrap items-center gap-2">
                      <Link
                        to={`/admin/supporters/${s.id}`}
                        className="font-medium text-primary hover:underline"
                      >
                        {s.first_name} {s.last_name}
                      </Link>
                      {statusBadge(s.verification_status)}
                      {s.potential_duplicate && (
                        <span className="inline-flex items-center gap-1 text-xs px-2 py-0.5 rounded-full bg-orange-100 text-orange-700">
                          <AlertTriangle className="w-3 h-3" /> Possible Duplicate
                        </span>
                      )}
                    </div>
                    <div className="mt-1 text-sm text-[var(--text-secondary)]">
                      {s.contact_number} · {s.village_name} · {s.source?.replace('_', ' ')} · {formatDate(s.created_at)}
                    </div>

                    {/* Duplicate warning */}
                    {s.potential_duplicate && s.duplicate_notes && (
                      <div className="mt-1.5 text-xs text-amber-600 bg-amber-50 rounded px-2 py-1">
                        {s.duplicate_notes}
                        {s.duplicate_of_id && (
                          <span>
                            {' — '}
                            <Link to={`/admin/supporters/${s.duplicate_of_id}`} className="text-primary hover:underline">
                              View match #{s.duplicate_of_id}
                            </Link>
                          </span>
                        )}
                      </div>
                    )}

                    {/* Expanded details */}
                    {isExpanded && (
                      <div className="mt-3 grid grid-cols-2 sm:grid-cols-3 gap-2 text-sm">
                        <div>
                          <span className="text-[var(--text-muted)]">Email:</span>{' '}
                          <span className="text-[var(--text-primary)]">{s.email || '—'}</span>
                        </div>
                        <div>
                          <span className="text-[var(--text-muted)]">Registered Voter:</span>{' '}
                          <span className="text-[var(--text-primary)]">{s.registered_voter ? 'Yes' : 'No'}</span>
                        </div>
                        <div>
                          <span className="text-[var(--text-muted)]">Opt-in Email:</span>{' '}
                          <span className="text-[var(--text-primary)]">{s.opt_in_email ? 'Yes' : 'No'}</span>
                        </div>
                        <div>
                          <span className="text-[var(--text-muted)]">Opt-in Text:</span>{' '}
                          <span className="text-[var(--text-primary)]">{s.opt_in_text ? 'Yes' : 'No'}</span>
                        </div>
                      </div>
                    )}
                  </div>

                  {/* Actions */}
                  <div className="flex items-center gap-1 flex-shrink-0">
                    <button
                      onClick={() => setExpandedId(isExpanded ? null : s.id)}
                      className="p-1.5 rounded-lg hover:bg-[var(--surface-overlay)] text-[var(--text-muted)]"
                      title="Show details"
                    >
                      {isExpanded ? <ChevronUp className="w-4 h-4" /> : <ChevronDown className="w-4 h-4" />}
                    </button>

                    {s.verification_status !== 'verified' && (
                      <button
                        onClick={() => verifyMutation.mutate({ id: s.id, status: 'verified' })}
                        disabled={verifyMutation.isPending || !canVerify}
                        className="inline-flex items-center gap-1 px-2.5 py-1.5 text-sm bg-green-600 text-white rounded-lg hover:bg-green-700 disabled:opacity-50"
                        title={canVerify ? 'Mark verified voter' : 'A current GEC match is required before this supporter can be marked as a verified voter'}
                      >
                        <CheckCircle className="w-3.5 h-3.5" />
                        <span className="hidden sm:inline">Mark Verified Voter</span>
                      </button>
                    )}

                    {s.verification_status !== 'flagged' && (
                      <button
                        onClick={() => verifyMutation.mutate({ id: s.id, status: 'flagged' })}
                        disabled={verifyMutation.isPending}
                        className="inline-flex items-center gap-1 px-2.5 py-1.5 text-sm border border-red-300 text-red-600 rounded-lg hover:bg-red-50 disabled:opacity-50"
                        title="Flag"
                      >
                        <XCircle className="w-3.5 h-3.5" />
                        <span className="hidden sm:inline">Flag</span>
                      </button>
                    )}

                    {s.verification_status !== 'unverified' && (
                      <button
                        onClick={() => verifyMutation.mutate({ id: s.id, status: 'unverified' })}
                        disabled={verifyMutation.isPending}
                        className="inline-flex items-center gap-1 px-2.5 py-1.5 text-sm border border-[var(--border-soft)] text-[var(--text-secondary)] rounded-lg hover:bg-[var(--surface-bg)] disabled:opacity-50"
                        title="Reset to unverified"
                      >
                        Reset
                      </button>
                    )}

                    <button
                      onClick={() => {
                        if (!window.confirm(`Remove ${s.first_name} ${s.last_name}? They will be excluded from all counts but kept in the audit log.`)) return;
                        removeMutation.mutate(s.id);
                      }}
                      disabled={removeMutation.isPending}
                      className="inline-flex items-center gap-1 px-2.5 py-1.5 text-sm bg-red-50 border border-red-200 text-red-600 rounded-lg hover:bg-red-100 disabled:opacity-50"
                      title="Remove from counts (soft delete)"
                    >
                      <Trash2 className="w-3.5 h-3.5" />
                      <span className="hidden sm:inline">Remove</span>
                    </button>
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
// CT-50 vetting queue
