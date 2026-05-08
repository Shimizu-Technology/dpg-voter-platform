import { useEffect, useMemo, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { getSupporters, exportSupporters, getVillages, updateSupporter } from '../../lib/api';
import { Link, useLocation, useSearchParams } from 'react-router-dom';
import { Search, ClipboardPlus, Download, ArrowUpDown, ChevronLeft } from 'lucide-react';
import { motion, useReducedMotion } from 'framer-motion';
import { formatDateTime } from '../../lib/datetime';
import { gecMatchClass, gecMatchLabel } from '../../lib/gecMatch';
import { useSession } from '../../hooks/useSession';
import { useDebouncedValue } from '../../hooks/useDebouncedValue';
import WorkspacePage from '../../components/WorkspacePage';

interface VillageOption {
  id: number;
  name: string;
  precincts: {
    id: number;
    number: string;
    alpha_range: string;
  }[];
}

interface SupporterItem {
  id: number;
  first_name: string;
  middle_name: string | null;
  last_name: string;
  print_name: string;
  contact_number: string;
  village_id: number;
  village_name: string;
  precinct_id: number | null;
  precinct_number: string | null;
  registered_voter_status?: string | null;
  registered_voter_location_note?: string | null;
  registered_voter: boolean;
  current_gec_match?: boolean;
  wants_to_volunteer?: boolean;
  needs_absentee_ballot_help?: boolean;
  needs_homebound_voting_help?: boolean;
  needs_voter_registration_help?: boolean;
  needs_election_day_ride?: boolean;
  referred_by_name?: string | null;
  yard_sign: boolean;
  opt_in_email: boolean;
  opt_in_text: boolean;
  verification_status: string;
  referred_from_village_id: number | null;
  referred_from_village_name?: string | null;
  verification_reason?: string | null;
  verification_reason_label?: string | null;
  verification_reason_detail?: string | null;
  potential_duplicate: boolean;
  source: string;
  attribution_method?: string | null;
  intake_status?: string;
  review_status?: string;
  public_review_status?: string;
  household_group_id?: number | null;
  household_member_count?: number;
  registration_outreach_status?: string | null;
  support_follow_up_status?: string | null;
  status: string;
  created_at: string;
}

interface SupportersResponse {
  supporters: SupporterItem[];
  pagination: {
    total: number;
    page: number;
    pages: number;
  };
}

type SortField = 'created_at' | 'print_name' | 'village_name' | 'source' | 'registered_voter';
const SORT_FIELDS: SortField[] = ['created_at', 'print_name', 'village_name', 'source', 'registered_voter'];
const PER_PAGE_OPTIONS = [25, 50, 100, 200] as const;
type PerPage = (typeof PER_PAGE_OPTIONS)[number];

function parseSortField(value: string | null): SortField {
  return SORT_FIELDS.includes(value as SortField) ? (value as SortField) : 'created_at';
}

function parsePerPage(value: string | null): PerPage {
  const parsed = Number(value);
  return PER_PAGE_OPTIONS.includes(parsed as PerPage) ? (parsed as PerPage) : 50;
}

function supporterLabel(count: number) {
  return `${count} supporter${count === 1 ? '' : 's'}`;
}

function backLinkLabel(returnTo: string) {
  if (returnTo.includes('/villages/')) return 'Back to Village';
  if (returnTo.includes('/admin')) return 'Back';
  return 'Back';
}

function lifecycleChipClass(status: string) {
  switch (status) {
    case 'active':
      return 'bg-emerald-100 text-emerald-700';
    case 'removed':
      return 'bg-slate-200 text-slate-700';
    case 'duplicate':
      return 'bg-amber-100 text-amber-700';
    case 'inactive':
      return 'bg-zinc-200 text-zinc-700';
    default:
      return 'bg-gray-200 text-gray-700';
  }
}

function verificationStatusLabel(supporter: Pick<SupporterItem, 'verification_status' | 'registered_voter' | 'referred_from_village_id' | 'verification_reason_label'>) {
  if (supporter.verification_reason_label) return supporter.verification_reason_label;
  if (supporter.verification_status === 'verified') return 'Matched to GEC';
  if (supporter.referred_from_village_id) return 'Village Referral';
  if (supporter.verification_status === 'flagged') return 'Flagged for review';
  if (supporter.verification_status === 'unverified' && !supporter.registered_voter) return 'No GEC Match';
  return 'Needs voter review';
}

function verificationStatusDetail(supporter: Pick<SupporterItem, 'verification_reason_detail'>) {
  return supporter.verification_reason_detail || null;
}

function sourceLabel(supporter: Pick<SupporterItem, 'source' | 'attribution_method'>) {
  if (supporter.source === 'qr_signup' || supporter.source === 'public_signup') {
    return 'Public Signup';
  }
  if (supporter.attribution_method === 'staff_scan') return 'Blue Form Scan';
  if (supporter.source === 'bulk_import') return 'Excel Import';
  return 'Staff Entry';
}

function sourceChipClass(supporter: Pick<SupporterItem, 'source' | 'attribution_method'>) {
  if (supporter.source === 'qr_signup' || supporter.source === 'public_signup') {
    return 'bg-sky-100 text-sky-700';
  }
  if (supporter.attribution_method === 'staff_scan') {
    return 'bg-cyan-100 text-cyan-700';
  }
  if (supporter.source === 'bulk_import') {
    return 'bg-slate-100 text-slate-700';
  }
  return 'bg-purple-100 text-purple-700';
}

function supporterStatusLabel(supporter: Pick<SupporterItem, 'source' | 'review_status' | 'public_review_status'>) {
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
  return 'Campaign Supporter';
}

function supporterStatusChipClass(supporter: Pick<SupporterItem, 'source' | 'review_status' | 'public_review_status'>) {
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

function supporterSortName(supporter: Pick<SupporterItem, 'first_name' | 'middle_name' | 'last_name'>) {
  return [
    supporter.last_name,
    [ supporter.first_name, supporter.middle_name ].filter(Boolean).join(' ')
  ].filter(Boolean).join(', ');
}

function selfReportedStatusLabel(supporter: Pick<SupporterItem, 'registered_voter_status'>) {
  if (supporter.registered_voter_status === 'yes') return 'Self: Yes';
  if (supporter.registered_voter_status === 'no') return 'Self: No';
  return 'Self: Not sure';
}

function supportRequestBadges(supporter: Pick<SupporterItem, 'needs_voter_registration_help' | 'needs_absentee_ballot_help' | 'needs_homebound_voting_help' | 'needs_election_day_ride' | 'wants_to_volunteer' | 'household_member_count'>) {
  const badges: string[] = [];
  if (supporter.needs_voter_registration_help) badges.push('Registration');
  if (supporter.needs_absentee_ballot_help) badges.push('Absentee');
  if (supporter.needs_homebound_voting_help) badges.push('Homebound');
  if (supporter.needs_election_day_ride) badges.push('Ride');
  if (supporter.wants_to_volunteer) badges.push('Volunteer');
  if ((supporter.household_member_count || 0) > 0) badges.push(`Household +${supporter.household_member_count}`);
  return badges;
}

function registrationFollowUpResultLabel(supporter: Pick<SupporterItem, 'registration_outreach_status'>) {
  if (supporter.registration_outreach_status === 'registered') return 'Registered via follow-up';
  if (supporter.registration_outreach_status === 'contacted') return 'Contacted';
  if (supporter.registration_outreach_status === 'declined') return 'Declined';
  return null;
}

function registrationFollowUpResultClass(supporter: Pick<SupporterItem, 'registration_outreach_status'>) {
  if (supporter.registration_outreach_status === 'registered') return 'bg-green-100 text-green-700';
  if (supporter.registration_outreach_status === 'contacted') return 'bg-blue-100 text-blue-700';
  if (supporter.registration_outreach_status === 'declined') return 'bg-red-100 text-red-700';
  return 'bg-gray-100 text-gray-700';
}

function supportFollowUpResultLabel(supporter: Pick<SupporterItem, 'support_follow_up_status'>) {
  if (supporter.support_follow_up_status === 'completed') return 'Support completed';
  if (supporter.support_follow_up_status === 'in_progress') return 'Support in progress';
  if (supporter.support_follow_up_status === 'declined') return 'Support declined';
  return null;
}

function supportFollowUpResultClass(supporter: Pick<SupporterItem, 'support_follow_up_status'>) {
  if (supporter.support_follow_up_status === 'completed') return 'bg-green-100 text-green-700';
  if (supporter.support_follow_up_status === 'in_progress') return 'bg-blue-100 text-blue-700';
  if (supporter.support_follow_up_status === 'declined') return 'bg-red-100 text-red-700';
  return 'bg-gray-100 text-gray-700';
}

export default function SupportersPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const queryClient = useQueryClient();
  const { data: sessionData } = useSession();
  const location = useLocation();
  const [returnTo] = useState(searchParams.get('return_to') || '');
  const [search, setSearch] = useState(searchParams.get('search') || '');
  const [villageFilter, setVillageFilter] = useState(searchParams.get('village_id') || '');
  const [precinctFilter, setPrecinctFilter] = useState(searchParams.get('precinct_id') || '');
  const [sourceFilter, setSourceFilter] = useState(searchParams.get('source') || '');
  const [optInFilter, setOptInFilter] = useState(searchParams.get('opt_in') || '');
  const [verificationFilter, setVerificationFilter] = useState(searchParams.get('verification_status') || '');
  const [registeredStatusFilter, setRegisteredStatusFilter] = useState(searchParams.get('registered_voter_status') || '');
  const [supportNeedFilter, setSupportNeedFilter] = useState(searchParams.get('support_need') || '');
  const [lifecycleFilter, setLifecycleFilter] = useState(searchParams.get('status') || 'active');
  const [unassignedPrecinct, setUnassignedPrecinct] = useState(searchParams.get('unassigned_precinct') === 'true');
  const [sortBy, setSortBy] = useState<SortField>(parseSortField(searchParams.get('sort_by')));
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>((searchParams.get('sort_dir') as 'asc' | 'desc') || 'desc');
  const [perPage, setPerPage] = useState<PerPage>(parsePerPage(searchParams.get('per_page')));
  const [page, setPage] = useState(1);
  const [visibleRows, setVisibleRows] = useState(80);
  const [pendingPrecinctBySupporter, setPendingPrecinctBySupporter] = useState<Record<number, string>>({});
  const prefersReducedMotion = useReducedMotion();
  const debouncedSearch = useDebouncedValue(search, 250);

  const { data: villageData } = useQuery({ queryKey: ['villages'], queryFn: getVillages });
  const villages: VillageOption[] = useMemo(() => villageData?.villages || [], [villageData]);
  const scopedVillageIds = sessionData?.user?.scoped_village_ids ?? null;
  const accessibleVillages: VillageOption[] = useMemo(() => {
    if (scopedVillageIds === null) return villages;
    const allowed = new Set(scopedVillageIds);
    return villages.filter((v) => allowed.has(v.id));
  }, [scopedVillageIds, villages]);
  const singleScopedVillageId = scopedVillageIds && scopedVillageIds.length === 1 ? String(scopedVillageIds[0]) : '';
  const effectiveVillageFilter = villageFilter || singleScopedVillageId;
  const villagesById = useMemo(
    () => new Map(accessibleVillages.map((v) => [v.id, v])),
    [accessibleVillages]
  );
  const selectedVillagePrecincts = useMemo(
    () => (effectiveVillageFilter ? villagesById.get(Number(effectiveVillageFilter))?.precincts || [] : []),
    [effectiveVillageFilter, villagesById]
  );

  useEffect(() => {
    if (scopedVillageIds === null) return;
    if (!villageFilter) return;
    if (scopedVillageIds.includes(Number(villageFilter))) return;
    queueMicrotask(() => {
      setVillageFilter('');
      setPrecinctFilter('');
      setPage(1);
    });
  }, [scopedVillageIds, villageFilter]);

  useEffect(() => {
    const params = new URLSearchParams();
    if (debouncedSearch) params.set('search', debouncedSearch);
    if (effectiveVillageFilter) params.set('village_id', effectiveVillageFilter);
    if (precinctFilter) params.set('precinct_id', precinctFilter);
    if (sourceFilter) params.set('source', sourceFilter);
    if (optInFilter) params.set('opt_in', optInFilter);
    if (verificationFilter) params.set('verification_status', verificationFilter);
    if (registeredStatusFilter) params.set('registered_voter_status', registeredStatusFilter);
    if (supportNeedFilter) params.set('support_need', supportNeedFilter);
    if (lifecycleFilter) params.set('status', lifecycleFilter);
    if (unassignedPrecinct) params.set('unassigned_precinct', 'true');
    params.set('sort_by', sortBy);
    params.set('sort_dir', sortDir);
    params.set('per_page', String(perPage));
    if (returnTo) params.set('return_to', returnTo);
    setSearchParams(params, { replace: true });
  }, [debouncedSearch, effectiveVillageFilter, precinctFilter, sourceFilter, optInFilter, verificationFilter, registeredStatusFilter, supportNeedFilter, lifecycleFilter, unassignedPrecinct, sortBy, sortDir, perPage, returnTo, setSearchParams]);

  const { data, isFetching } = useQuery<SupportersResponse>({
    queryKey: ['supporters', debouncedSearch, effectiveVillageFilter, precinctFilter, sourceFilter, optInFilter, verificationFilter, registeredStatusFilter, supportNeedFilter, lifecycleFilter, unassignedPrecinct, sortBy, sortDir, page, perPage],
    queryFn: () => getSupporters({
      search: debouncedSearch,
      village_id: effectiveVillageFilter || undefined,
      precinct_id: precinctFilter || undefined,
      source: sourceFilter || undefined,
      opt_in_email: optInFilter === 'email' || optInFilter === 'both' ? 'true' : undefined,
      opt_in_text: optInFilter === 'text' || optInFilter === 'both' ? 'true' : undefined,
      verification_status: verificationFilter || undefined,
      registered_voter_status: registeredStatusFilter || undefined,
      support_need: supportNeedFilter || undefined,
      status: lifecycleFilter || undefined,
      unassigned_precinct: unassignedPrecinct ? 'true' : undefined,
      sort_by: sortBy,
      sort_dir: sortDir,
      page,
      per_page: perPage,
    }),
    placeholderData: (previous) => previous,
  });
  const highVolumeMode = (data?.pagination.total || 0) >= 5000;
  const shouldAnimateRows = !prefersReducedMotion && !highVolumeMode;
  const progressiveRenderingEnabled = highVolumeMode && perPage >= 100;
  const supportersRows = data?.supporters || [];
  const effectiveVisibleRows = progressiveRenderingEnabled
    ? Math.min(visibleRows, supportersRows.length)
    : supportersRows.length;
  const visibleSupporters = supportersRows.slice(0, effectiveVisibleRows);

  useEffect(() => {
    const timer = window.setTimeout(() => setVisibleRows(80), 0);
    return () => window.clearTimeout(timer);
  }, [progressiveRenderingEnabled, page, debouncedSearch, effectiveVillageFilter, precinctFilter, sourceFilter, optInFilter, verificationFilter, registeredStatusFilter, supportNeedFilter, lifecycleFilter, unassignedPrecinct, sortBy, sortDir, perPage]);

  useEffect(() => {
    if (!progressiveRenderingEnabled) return;
    if (effectiveVisibleRows >= supportersRows.length) return;

    const timer = window.setTimeout(() => {
      setVisibleRows((prev) => Math.min(prev + 60, supportersRows.length));
    }, 16);
    return () => window.clearTimeout(timer);
  }, [progressiveRenderingEnabled, effectiveVisibleRows, supportersRows.length]);

  useEffect(() => {
    if (!data) return;
    const totalPages = data.pagination.pages;
    if (page < totalPages) {
      void queryClient.prefetchQuery({
        queryKey: ['supporters', debouncedSearch, effectiveVillageFilter, precinctFilter, sourceFilter, optInFilter, verificationFilter, registeredStatusFilter, supportNeedFilter, lifecycleFilter, unassignedPrecinct, sortBy, sortDir, page + 1, perPage],
        queryFn: () => getSupporters({
          search: debouncedSearch,
          village_id: effectiveVillageFilter || undefined,
          precinct_id: precinctFilter || undefined,
          source: sourceFilter || undefined,
          opt_in_email: optInFilter === 'email' || optInFilter === 'both' ? 'true' : undefined,
          opt_in_text: optInFilter === 'text' || optInFilter === 'both' ? 'true' : undefined,
          verification_status: verificationFilter || undefined,
          registered_voter_status: registeredStatusFilter || undefined,
          support_need: supportNeedFilter || undefined,
          status: lifecycleFilter || undefined,
          unassigned_precinct: unassignedPrecinct ? 'true' : undefined,
          sort_by: sortBy,
          sort_dir: sortDir,
          page: page + 1,
          per_page: perPage,
        }),
      });
    }
  }, [data, page, perPage, debouncedSearch, effectiveVillageFilter, precinctFilter, sourceFilter, optInFilter, verificationFilter, registeredStatusFilter, supportNeedFilter, lifecycleFilter, unassignedPrecinct, sortBy, sortDir, queryClient]);

  const assignPrecinctMutation = useMutation({
    mutationFn: ({ supporterId, precinctId }: { supporterId: number; precinctId: number }) =>
      updateSupporter(supporterId, { precinct_id: precinctId }),
    onSuccess: (_data, variables) => {
      setPendingPrecinctBySupporter((prev) => {
        const next = { ...prev };
        delete next[variables.supporterId];
        return next;
      });
      queryClient.invalidateQueries({ queryKey: ['supporters'] });
      queryClient.invalidateQueries({ queryKey: ['dashboard'] });
      queryClient.invalidateQueries({ queryKey: ['village'] });
    },
  });

  const renderPrecinctAssignControl = (supporter: SupporterItem) => {
    if (supporter.precinct_number) {
      return <span className="text-[var(--text-primary)]">Precinct {supporter.precinct_number}</span>;
    }
    if (!sessionData?.permissions?.can_edit_supporters) {
      return <span className="text-[var(--text-muted)]">Unassigned</span>;
    }

    const village = villagesById.get(supporter.village_id);
    const precincts = village?.precincts || [];
    if (precincts.length === 0) {
      return <span className="text-[var(--text-muted)]">No precinct data</span>;
    }

    const pendingValue = pendingPrecinctBySupporter[supporter.id] || '';
    const isSaving = assignPrecinctMutation.isPending;

    return (
      <div className="flex flex-col sm:flex-row items-stretch sm:items-center gap-2">
        <select
          value={pendingValue}
          onChange={(e) => setPendingPrecinctBySupporter((prev) => ({ ...prev, [supporter.id]: e.target.value }))}
          className="border border-[var(--border-soft)] rounded-xl px-3 py-2 min-h-[44px] text-sm bg-[var(--surface-raised)]"
          disabled={isSaving}
        >
          <option value="">Assign precinct</option>
          {precincts.map((p) => (
            <option key={p.id} value={p.id}>Precinct {p.number}</option>
          ))}
        </select>
        <button
          type="button"
          disabled={!pendingValue || isSaving}
          onClick={() => assignPrecinctMutation.mutate({ supporterId: supporter.id, precinctId: Number(pendingValue) })}
          className="px-3 py-2 rounded-xl min-h-[44px] bg-primary text-white text-sm disabled:opacity-50"
        >
          Save
        </button>
      </div>
    );
  };

  const supporterDetailLink = (supporterId: number) =>
    `${location.pathname.startsWith('/data') ? '/data/supporters' : '/admin/supporters'}/${supporterId}?return_to=${encodeURIComponent(`${location.pathname.split('?')[0]}?${searchParams.toString()}`)}`;

  const handleSort = (field: SortField) => {
    setPage(1);
    if (sortBy === field) {
      setSortDir((prev) => (prev === 'asc' ? 'desc' : 'asc'));
      return;
    }
    setSortBy(field);
    setSortDir(field === 'created_at' ? 'desc' : 'asc');
  };

  const sortLabel = (field: SortField) => {
    if (sortBy !== field) return '';
    return sortDir === 'asc' ? '▲' : '▼';
  };

  return (
    <WorkspacePage width="full" className="space-y-6">
      {/* Header */}
      <div>
        {returnTo && (
          <Link
            to={returnTo}
            className="inline-flex items-center gap-1.5 text-sm text-gray-500 hover:text-gray-900 mb-3"
          >
            <ChevronLeft className="w-4 h-4" />
            {backLinkLabel(returnTo)}
          </Link>
        )}
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
          <h1 className="text-2xl font-bold text-gray-900 tracking-tight">All Supporters</h1>
          <div className="flex flex-wrap gap-2">
            <button
              onClick={() => exportSupporters({
                village_id: effectiveVillageFilter || undefined,
                precinct_id: precinctFilter || undefined,
                source: sourceFilter || undefined,
                opt_in: optInFilter || undefined,
                verification_status: verificationFilter || undefined,
                registered_voter_status: registeredStatusFilter || undefined,
                support_need: supportNeedFilter || undefined,
                status: lifecycleFilter || undefined,
                unassigned_precinct: unassignedPrecinct ? 'true' : undefined,
                search: debouncedSearch || undefined,
                sort_by: sortBy || undefined,
                sort_dir: sortDir || undefined,
              })}
              className="app-btn-secondary"
              >
                <Download className="w-4 h-4" /> Excel
              </button>
              {sessionData?.permissions?.can_create_staff_supporters && (
                <Link to="/admin/supporters/new" className="app-btn-danger">
                  <ClipboardPlus className="w-4 h-4" /> New Entry
                </Link>
              )}
              <Link to="/admin/supporters?status=removed" className="app-btn-secondary">
                Removed
              </Link>
          </div>
        </div>
      </div>

      <div>
        {/* Filters */}
        <div className="grid grid-cols-1 md:grid-cols-12 gap-3 mb-6">
          <div className="relative md:col-span-5 min-w-0">
            <Search className="w-5 h-5 absolute left-3 top-3 text-[var(--text-muted)]" />
            <input
              type="text"
              value={search}
              onChange={e => { setSearch(e.target.value); setPage(1); }}
              placeholder="Search by name or phone..."
              className="w-full pl-10 pr-4 py-3 border border-[var(--border-soft)] rounded-xl text-lg focus:ring-2 focus:ring-primary focus:border-transparent"
            />
          </div>
          {singleScopedVillageId ? (
            <div className="md:col-span-3 rounded-xl border border-[var(--border-soft)] bg-[var(--surface-bg)] px-3 py-3 text-sm text-[var(--text-secondary)]">
              Assigned village: <span className="font-medium text-[var(--text-primary)]">{accessibleVillages[0]?.name || `Village #${singleScopedVillageId}`}</span>
            </div>
          ) : (
            <select
              value={villageFilter}
              onChange={e => {
                setVillageFilter(e.target.value);
                setPrecinctFilter('');
                setUnassignedPrecinct(false);
                setPage(1);
              }}
              className="md:col-span-3 px-3 py-3 border border-[var(--border-soft)] rounded-xl bg-[var(--surface-raised)] text-[var(--text-primary)] focus:ring-2 focus:ring-primary focus:border-transparent min-w-0"
            >
              <option value="">
                {scopedVillageIds === null ? 'All villages' : 'All accessible villages'}
              </option>
              {accessibleVillages.map((v) => (
                <option key={v.id} value={v.id}>{v.name}</option>
              ))}
            </select>
          )}
          <select
            value={sourceFilter}
            onChange={(e) => {
              setSourceFilter(e.target.value);
              setPage(1);
            }}
            className="md:col-span-2 px-3 py-3 border border-[var(--border-soft)] rounded-xl bg-[var(--surface-raised)] text-[var(--text-primary)] focus:ring-2 focus:ring-primary focus:border-transparent min-w-0"
          >
            <option value="">All origins</option>
            <option value="public_signup">Public signup</option>
            <option value="qr_signup">QR signup</option>
            <option value="staff_entry">Staff entry</option>
            <option value="bulk_import">Excel import</option>
          </select>
          <select
            value={optInFilter}
            onChange={(e) => {
              setOptInFilter(e.target.value);
              setPage(1);
            }}
            className="md:col-span-2 px-3 py-3 border border-[var(--border-soft)] rounded-xl bg-[var(--surface-raised)] text-[var(--text-primary)] focus:ring-2 focus:ring-primary focus:border-transparent min-w-0"
          >
            <option value="">All opt-in</option>
            <option value="text">Opted in: Text</option>
            <option value="email">Opted in: Email</option>
            <option value="both">Opted in: Both</option>
          </select>
          <select
            value={verificationFilter}
            onChange={(e) => {
              setVerificationFilter(e.target.value);
              setPage(1);
            }}
            className="md:col-span-2 px-3 py-3 border border-[var(--border-soft)] rounded-xl bg-[var(--surface-raised)] text-[var(--text-primary)] focus:ring-2 focus:ring-primary focus:border-transparent min-w-0"
          >
            <option value="">All voter checks</option>
            <option value="unverified">Needs voter review</option>
            <option value="verified">Matched to GEC</option>
            <option value="flagged">Flagged for review</option>
          </select>
          <select
            value={registeredStatusFilter}
            onChange={(e) => {
              setRegisteredStatusFilter(e.target.value);
              setPage(1);
            }}
            className="md:col-span-2 px-3 py-3 border border-[var(--border-soft)] rounded-xl bg-[var(--surface-raised)] text-[var(--text-primary)] focus:ring-2 focus:ring-primary focus:border-transparent min-w-0"
          >
            <option value="">All self-reported voter status</option>
            <option value="yes">Self-reported yes</option>
            <option value="no">Self-reported no</option>
            <option value="not_sure">Self-reported not sure</option>
          </select>
          <select
            value={supportNeedFilter}
            onChange={(e) => {
              setSupportNeedFilter(e.target.value);
              setPage(1);
            }}
            className="md:col-span-2 px-3 py-3 border border-[var(--border-soft)] rounded-xl bg-[var(--surface-raised)] text-[var(--text-primary)] focus:ring-2 focus:ring-primary focus:border-transparent min-w-0"
          >
            <option value="">All support requests</option>
            <option value="registration">Registration help</option>
            <option value="absentee">Absentee help</option>
            <option value="homebound">Homebound help</option>
            <option value="ride">Ride to polls</option>
            <option value="volunteer">Volunteer</option>
            <option value="any">Any help request</option>
          </select>
          <select
            value={lifecycleFilter}
            onChange={(e) => {
              setLifecycleFilter(e.target.value);
              setPage(1);
            }}
            className="md:col-span-2 px-3 py-3 border border-[var(--border-soft)] rounded-xl bg-[var(--surface-raised)] text-[var(--text-primary)] focus:ring-2 focus:ring-primary focus:border-transparent min-w-0"
          >
            <option value="">All lifecycle</option>
            <option value="active">Active</option>
            <option value="removed">Removed</option>
            <option value="duplicate">Duplicate</option>
            <option value="inactive">Inactive</option>
          </select>
          {effectiveVillageFilter && (
            <select
              value={precinctFilter}
              onChange={(e) => {
                setPrecinctFilter(e.target.value);
                if (e.target.value) setUnassignedPrecinct(false);
                setPage(1);
              }}
              className="md:col-span-2 px-3 py-3 border border-[var(--border-soft)] rounded-xl bg-[var(--surface-raised)] text-[var(--text-primary)] focus:ring-2 focus:ring-primary focus:border-transparent min-w-0"
            >
              <option value="">All precincts</option>
              {selectedVillagePrecincts.map((p) => (
                <option key={p.id} value={p.id}>Precinct {p.number}</option>
              ))}
            </select>
          )}
          <select
            value={`${sortBy}:${sortDir}`}
            onChange={(e) => {
              const [field, dir] = e.target.value.split(':') as [SortField, 'asc' | 'desc'];
              setSortBy(field);
              setSortDir(dir);
              setPage(1);
            }}
            className="md:col-span-2 px-3 py-3 border border-[var(--border-soft)] rounded-xl bg-[var(--surface-raised)] text-[var(--text-primary)] focus:ring-2 focus:ring-primary focus:border-transparent min-w-0"
          >
            <option value="created_at:desc">Newest first</option>
            <option value="created_at:asc">Oldest first</option>
            <option value="print_name:asc">Name A-Z</option>
            <option value="print_name:desc">Name Z-A</option>
            <option value="village_name:asc">Village A-Z</option>
            <option value="village_name:desc">Village Z-A</option>
          </select>
          <label className="md:col-span-2 flex items-center gap-2 text-sm text-[var(--text-primary)] whitespace-nowrap min-h-[44px]">
            <input
              type="checkbox"
              checked={unassignedPrecinct}
              onChange={(e) => {
                const checked = e.target.checked;
                setUnassignedPrecinct(checked);
                if (checked) setPrecinctFilter('');
                setPage(1);
              }}
              className="rounded border-[var(--border-soft)] text-primary focus:ring-primary"
            />
            Unassigned precinct
          </label>
        </div>

        {/* Count */}
        {data && (
          <div className="mb-4 flex items-center justify-between gap-2">
            <p className="text-sm text-[var(--text-secondary)]">
              {supporterLabel(data.pagination.total)} total (page {data.pagination.page} of {data.pagination.pages})
            </p>
            <div className="flex items-center gap-3">
              <select
                value={perPage}
                onChange={(e) => {
                  setPerPage(Number(e.target.value) as PerPage);
                  setPage(1);
                }}
                className="border border-[var(--border-soft)] rounded-xl px-2 py-1.5 bg-[var(--surface-raised)] text-xs text-[var(--text-primary)]"
                aria-label="Rows per page"
              >
                {PER_PAGE_OPTIONS.map((size) => (
                  <option key={size} value={size}>{size}/page</option>
                ))}
              </select>
              <p
                aria-live="polite"
                className={`text-xs text-[var(--text-muted)] transition-opacity duration-200 ${isFetching ? 'opacity-100' : 'opacity-0'}`}
              >
                {search !== debouncedSearch ? 'Searching...' : 'Updating...'}
              </p>
            </div>
          </div>
        )}

        {/* Mobile Card View */}
        <div className={`md:hidden space-y-3 transition-opacity duration-200 ${isFetching ? 'opacity-70' : 'opacity-100'}`}>
          {visibleSupporters.map((s) => (
            <div key={s.id} className="app-card p-4">
              <div className="flex items-center justify-between mb-1">
                <div className="flex items-center gap-1.5">
                  <Link to={supporterDetailLink(s.id)} className="font-semibold text-[var(--text-primary)] hover:underline">
                    {supporterSortName(s)}
                  </Link>
                  {s.potential_duplicate && (
                    <span className="flex-shrink-0 w-2 h-2 rounded-full bg-amber-400" title="Potential duplicate" />
                  )}
                </div>
                <span className={`app-chip ${
                  sourceChipClass(s)
                }`}>
                  {sourceLabel(s)}
                </span>
                <span className={`app-chip ${supporterStatusChipClass(s)}`}>
                  {supporterStatusLabel(s)}
                </span>
                <span className={`app-chip ${
                  s.verification_status === 'verified' ? 'bg-green-100 text-green-700' :
                  s.verification_status === 'flagged' ? 'bg-red-100 text-red-700' :
                  'bg-yellow-100 text-yellow-700'
                }`}>
                  {verificationStatusLabel(s)}
                </span>
                <span className={`app-chip ${lifecycleChipClass(s.status)}`}>
                  {s.status}
                </span>
              </div>
              <div className="text-sm text-[var(--text-secondary)] space-y-0.5">
                <div className="flex justify-between">
                  <span>{s.village_name}</span>
                  <span>{s.contact_number}</span>
                </div>
                <div>{renderPrecinctAssignControl(s)}</div>
                <div className="text-xs text-[var(--text-muted)]">{selfReportedStatusLabel(s)}</div>
                {verificationStatusDetail(s) && (
                  <div className={`text-xs leading-5 ${
                    s.referred_from_village_id ? 'text-purple-700' : 'text-[var(--text-muted)]'
                  }`}>
                    {verificationStatusDetail(s)}
                  </div>
                )}
                <div className="flex items-center gap-2 pt-1">
                  {s.yard_sign && (
                    <span className="app-chip bg-amber-100 text-amber-700">Yard Sign</span>
                  )}
                  
                  {registrationFollowUpResultLabel(s) && (
                    <span className={`app-chip ${registrationFollowUpResultClass(s)}`}>{registrationFollowUpResultLabel(s)}</span>
                  )}
                  {supportFollowUpResultLabel(s) && (
                    <span className={`app-chip ${supportFollowUpResultClass(s)}`}>{supportFollowUpResultLabel(s)}</span>
                  )}
                  {supportRequestBadges(s).map((badge) => (
                    <span key={`${s.id}-${badge}`} className="app-chip bg-yellow-100 text-yellow-800">{badge}</span>
                  ))}
                  {!registrationFollowUpResultLabel(s) && !supportFollowUpResultLabel(s) && supportRequestBadges(s).length === 0 && (
                    <span className="text-xs text-[var(--text-muted)]">No extra flags</span>
                  )}
                </div>
                <div className="flex justify-between">
                  <span className={gecMatchClass(s)}>{gecMatchLabel(s)}</span>
                  <span>{formatDateTime(s.created_at)}</span>
                </div>
              </div>
            </div>
          ))}
          {supportersRows.length === 0 && (
            <div className="text-center text-[var(--text-muted)] py-8">No supporters found</div>
          )}
          {progressiveRenderingEnabled && effectiveVisibleRows < supportersRows.length && (
            <div className="text-center text-xs text-[var(--text-muted)] py-2">
              Rendering {effectiveVisibleRows} / {supportersRows.length} rows...
            </div>
          )}
        </div>

        {/* Desktop Table */}
        <div className={`hidden md:block app-card overflow-x-auto transition-opacity duration-200 ${isFetching ? 'opacity-80' : 'opacity-100'}`}>
          <table className="w-full min-w-[1320px] text-sm">
            <thead>
              <tr className="border-b bg-[var(--surface-bg)]">
                <th className="text-left px-4 py-3 font-medium text-[var(--text-secondary)]">
                  <button type="button" onClick={() => handleSort('print_name')} className="inline-flex items-center gap-1 hover:text-[var(--text-primary)]">
                    Name <ArrowUpDown className="w-3.5 h-3.5" /> {sortLabel('print_name')}
                  </button>
                </th>
                <th className="text-left px-4 py-3 font-medium text-[var(--text-secondary)]">Phone</th>
                <th className="text-left px-4 py-3 font-medium text-[var(--text-secondary)]">
                  <button type="button" onClick={() => handleSort('village_name')} className="inline-flex items-center gap-1 hover:text-[var(--text-primary)]">
                    Village <ArrowUpDown className="w-3.5 h-3.5" /> {sortLabel('village_name')}
                  </button>
                </th>
                <th className="text-left px-4 py-3 font-medium text-[var(--text-secondary)]">Precinct</th>
                <th className="text-left px-4 py-3 font-medium text-[var(--text-secondary)]">Flags</th>
                <th className="text-left px-4 py-3 font-medium text-[var(--text-secondary)]">
                  <button type="button" onClick={() => handleSort('registered_voter')} className="inline-flex items-center gap-1 hover:text-[var(--text-primary)]">
                    GEC Match <ArrowUpDown className="w-3.5 h-3.5" /> {sortLabel('registered_voter')}
                  </button>
                </th>
                <th className="text-left px-4 py-3 font-medium text-[var(--text-secondary)]">
                  <button type="button" onClick={() => handleSort('source')} className="inline-flex items-center gap-1 hover:text-[var(--text-primary)]">
                    Origin <ArrowUpDown className="w-3.5 h-3.5" /> {sortLabel('source')}
                  </button>
                </th>
                <th className="text-left px-4 py-3 font-medium text-[var(--text-secondary)]">Supporter Status</th>
                <th className="w-[320px] min-w-[320px] text-left px-4 py-3 font-medium text-[var(--text-secondary)]">Voter Check</th>
                <th className="text-left px-4 py-3 font-medium text-[var(--text-secondary)]">Lifecycle</th>
                <th className="text-left px-4 py-3 font-medium text-[var(--text-secondary)]">
                  <button type="button" onClick={() => handleSort('created_at')} className="inline-flex items-center gap-1 hover:text-[var(--text-primary)]">
                    Date <ArrowUpDown className="w-3.5 h-3.5" /> {sortLabel('created_at')}
                  </button>
                </th>
              </tr>
            </thead>
            <motion.tbody layout={shouldAnimateRows}>
              {visibleSupporters.map((s) => (
                <motion.tr
                  key={s.id}
                  layout={shouldAnimateRows}
                  transition={shouldAnimateRows ? { type: 'spring', stiffness: 380, damping: 34 } : { duration: 0 }}
                  className="border-b hover:bg-[var(--surface-bg)]"
                >
                  <td className="px-4 py-3 font-medium text-[var(--text-primary)] max-w-[240px]">
                    <div className="flex items-center gap-1.5">
                      <Link to={supporterDetailLink(s.id)} className="hover:underline block truncate" title={supporterSortName(s)}>
                        {supporterSortName(s)}
                      </Link>
                      {s.potential_duplicate && (
                        <span className="flex-shrink-0 w-2 h-2 rounded-full bg-amber-400" title="Potential duplicate" />
                      )}
                    </div>
                  </td>
                  <td className="px-4 py-3 text-[var(--text-secondary)] whitespace-nowrap">{s.contact_number}</td>
                  <td className="px-4 py-3 text-[var(--text-secondary)] whitespace-nowrap">{s.village_name}</td>
                  <td className="px-4 py-3 text-[var(--text-secondary)] whitespace-nowrap">{renderPrecinctAssignControl(s)}</td>
                  <td className="px-4 py-3 text-[var(--text-secondary)] whitespace-nowrap">
                    <div className="flex items-center gap-1.5 whitespace-nowrap">
                      {s.yard_sign && (
                        <span className="app-chip bg-amber-100 text-amber-700">Yard</span>
                      )}
                      
                      {registrationFollowUpResultLabel(s) && (
                        <span className={`app-chip ${registrationFollowUpResultClass(s)}`}>{registrationFollowUpResultLabel(s)}</span>
                      )}
                      {supportFollowUpResultLabel(s) && (
                        <span className={`app-chip ${supportFollowUpResultClass(s)}`}>{supportFollowUpResultLabel(s)}</span>
                      )}
                      {supportRequestBadges(s).map((badge) => (
                        <span key={`${s.id}-${badge}`} className="app-chip bg-yellow-100 text-yellow-800">{badge}</span>
                      ))}
                      {!registrationFollowUpResultLabel(s) && !supportFollowUpResultLabel(s) && supportRequestBadges(s).length === 0 && (
                        <span className="text-xs text-[var(--text-muted)]">—</span>
                      )}
                    </div>
                    <div className="mt-1 text-xs text-[var(--text-muted)]">{selfReportedStatusLabel(s)}</div>
                  </td>
                  <td className="px-4 py-3 whitespace-nowrap">
                    <div className="space-y-1">
                      <span className={gecMatchClass(s)}>{gecMatchLabel(s)}</span>
                      {s.registration_outreach_status === 'registered' && (
                        <div className="text-xs text-green-700">Follow-up says registered</div>
                      )}
                      {s.support_follow_up_status === 'completed' && (
                        <div className="text-xs text-blue-700">Support help completed</div>
                      )}
                    </div>
                  </td>
                  <td className="px-4 py-3 whitespace-nowrap">
                    <span className={`app-chip ${
                      sourceChipClass(s)
                    }`}>
                      {sourceLabel(s)}
                    </span>
                  </td>
                  <td className="px-4 py-3 whitespace-nowrap align-middle">
                    <span className={`app-chip ${supporterStatusChipClass(s)}`}>
                      {supporterStatusLabel(s)}
                    </span>
                  </td>
                  <td className="w-[320px] min-w-[320px] px-4 py-3 align-top">
                    <div className="space-y-2">
                      <span className={`app-chip ${
                        s.verification_status === 'verified' ? 'bg-green-100 text-green-700' :
                        s.verification_status === 'flagged' ? 'bg-red-100 text-red-700' :
                        'bg-yellow-100 text-yellow-700'
                      }`}>
                        {verificationStatusLabel(s)}
                      </span>
                      {verificationStatusDetail(s) && (
                        <div
                          title={verificationStatusDetail(s) || undefined}
                          className={`text-xs whitespace-normal break-words leading-5 max-w-[300px] ${
                          s.referred_from_village_id ? 'text-purple-700' : 'text-[var(--text-muted)]'
                        }`}>
                          {verificationStatusDetail(s)}
                        </div>
                      )}
                    </div>
                  </td>
                  <td className="px-4 py-3 whitespace-nowrap">
                    <span className={`app-chip ${lifecycleChipClass(s.status)}`}>
                      {s.status}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-[var(--text-secondary)] whitespace-nowrap">{formatDateTime(s.created_at)}</td>
                </motion.tr>
              ))}
              {supportersRows.length === 0 && (
                <tr>
                  <td colSpan={11} className="px-4 py-8 text-center text-[var(--text-muted)]">
                    No supporters found
                  </td>
                </tr>
              )}
            </motion.tbody>
          </table>
          {progressiveRenderingEnabled && effectiveVisibleRows < supportersRows.length && (
            <div className="px-4 py-2 text-xs text-[var(--text-muted)]">
              Rendering {effectiveVisibleRows} / {supportersRows.length} rows...
            </div>
          )}
        </div>

        {/* Pagination */}
        {data && data.pagination.pages > 1 && (
          <div className="flex justify-center gap-2 mt-6">
            <button
              disabled={page <= 1}
              onClick={() => setPage(p => p - 1)}
              className="px-4 py-2 min-h-[44px] border rounded-xl disabled:opacity-30 hover:bg-[var(--surface-overlay)]"
            >
              Previous
            </button>
            <span className="px-4 py-2 text-[var(--text-secondary)]">Page {page} of {data.pagination.pages}</span>
            <button
              disabled={page >= data.pagination.pages}
              onClick={() => setPage(p => p + 1)}
              className="px-4 py-2 min-h-[44px] border rounded-xl disabled:opacity-30 hover:bg-[var(--surface-overlay)]"
            >
              Next
            </button>
          </div>
        )}
      </div>
    </WorkspacePage>
  );
}
