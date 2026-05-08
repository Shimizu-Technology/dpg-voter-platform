import { useMemo, useRef, useState, type SetStateAction } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import {
  approveSupporter,
  bulkRevetSupporters,
  getDistricts,
  getGecVoters,
  getPrecincts,
  getVettingQueue,
  getVillages,
  rejectSupporterReview,
  revetSupporter,
  updateSupporter,
} from '../../lib/api';
import { Link, useLocation, useSearchParams } from 'react-router-dom';
import { captureAnalyticsEvent } from '../../lib/analytics';
import { assignPrecinctIdByLastName } from '../../lib/precinctAssignment';
import {
  CheckCircle,
  ChevronLeft,
  Database,
  MapPin,
  PencilLine,
  RefreshCw,
  Save,
  Search,
  ShieldCheck,
  XCircle,
} from 'lucide-react';
import WorkspacePage from '../../components/WorkspacePage';

type VettingFilter = 'all' | 'verified' | 'flagged' | 'no_match' | 'referral' | 'registration_help' | 'help_requests';
type QueueBucket = 'pending' | 'approved' | 'rejected';

interface QueueSupporter {
  id: number;
  first_name: string;
  middle_name?: string | null;
  last_name: string;
  contact_number?: string | null;
  email?: string | null;
  street_address?: string | null;
  dob?: string | null;
  village_id?: number | null;
  village_name?: string | null;
  submitted_village_id?: number | null;
  submitted_village_name?: string | null;
  submitted_village_referral?: boolean;
  precinct_id?: number | null;
  precinct_number?: string | null;
  review_status: string;
  public_review_status: string;
  verification_status: string;
  verification_reason_label?: string | null;
  verification_reason_detail?: string | null;
  registered_voter?: boolean;
  self_reported_registered_voter?: boolean | null;
  registered_voter_status?: string | null;
  registered_voter_location_note?: string | null;
  wants_to_volunteer?: boolean;
  needs_absentee_ballot_help?: boolean;
  needs_homebound_voting_help?: boolean;
  needs_voter_registration_help?: boolean;
  needs_election_day_ride?: boolean;
  referred_by_name?: string | null;
  referred_from_village_id?: number | null;
  referred_from_village_name?: string | null;
  source?: string;
  potential_duplicate?: boolean;
  household_group_id?: number | null;
  household_member_count?: number;
  created_at?: string;
  gec_matches?: GecMatch[];
}

interface GecMatch {
  gec_voter: GecVoter;
  confidence: string;
  match_type: string;
  match_count?: number;
}

interface GecVoter {
  id: number;
  first_name: string;
  middle_name?: string | null;
  last_name: string;
  dob?: string | null;
  birth_year?: number | null;
  address?: string | null;
  village_name?: string | null;
  village_id?: number | null;
  precinct_id?: number | null;
  precinct_number?: string | null;
  previous_village_name?: string | null;
  voter_registration_number?: string | null;
  status?: string | null;
  gec_list_date?: string | null;
}

interface EditDraft {
  first_name: string;
  middle_name: string;
  last_name: string;
  dob: string;
  street_address: string;
  village_id: string;
  precinct_id: string;
  contact_number: string;
  email: string;
}

interface PrecinctOption {
  id: number;
  number: string;
  alpha_range?: string | null;
  village_name?: string;
}

const EMPTY_SUPPORTERS: QueueSupporter[] = [];
const EMPTY_DRAFT: EditDraft = {
  first_name: '',
  middle_name: '',
  last_name: '',
  dob: '',
  street_address: '',
  village_id: '',
  precinct_id: '',
  contact_number: '',
  email: '',
};

function verificationStatusLabel(supporter: QueueSupporter, hasMatches: boolean) {
  if (typeof supporter.verification_reason_label === 'string' && supporter.verification_reason_label.length > 0) {
    return supporter.verification_reason_label;
  }
  if (supporter.verification_status === 'verified') return 'Verified';
  if (supporter.submitted_village_referral) return 'Village Referral';
  if (supporter.verification_status === 'flagged') return 'Needs Review';
  if (supporter.verification_status === 'unverified' && !hasMatches) return 'No GEC Match';
  return 'Pending Review';
}

function verificationStatusDetail(supporter: QueueSupporter, hasMatches: boolean) {
  if (typeof supporter.verification_reason_detail === 'string' && supporter.verification_reason_detail.length > 0) {
    return supporter.verification_reason_detail;
  }
  if (supporter.verification_status === 'unverified' && !hasMatches) {
    return 'Not found in the current GEC list.';
  }
  return null;
}

function canApproveSupporter(supporter: QueueSupporter) {
  return supporter.review_status === 'pending' &&
    supporter.public_review_status !== 'pending' &&
    supporter.potential_duplicate !== true;
}

function selfReportedStatusLabel(supporter: QueueSupporter) {
  if (supporter.registered_voter_status === 'yes') return 'Self-reported: Yes';
  if (supporter.registered_voter_status === 'no') return 'Self-reported: No';
  if (supporter.registered_voter_status === 'not_sure') return 'Self-reported: Not sure';
  if (supporter.self_reported_registered_voter === true) return 'Self-reported: Yes';
  if (supporter.self_reported_registered_voter === false) return 'Self-reported: No';
  return 'Self-reported: Not sure';
}

function supportRequestBadges(supporter: QueueSupporter) {
  const badges: string[] = [];
  if (supporter.needs_voter_registration_help) badges.push('Registration Help');
  if (supporter.needs_absentee_ballot_help) badges.push('Absentee Help');
  if (supporter.needs_homebound_voting_help) badges.push('Homebound Help');
  if (supporter.needs_election_day_ride) badges.push('Ride To Polls');
  if (supporter.wants_to_volunteer) badges.push('Volunteer');
  return badges;
}

function buildDraft(supporter: QueueSupporter | null): EditDraft {
  if (!supporter) {
    return EMPTY_DRAFT;
  }

  return {
    first_name: supporter.first_name || '',
    middle_name: supporter.middle_name || '',
    last_name: supporter.last_name || '',
    dob: supporter.dob ? String(supporter.dob).slice(0, 10) : '',
    street_address: supporter.street_address || '',
    village_id: supporter.village_id ? String(supporter.village_id) : '',
    precinct_id: supporter.precinct_id ? String(supporter.precinct_id) : '',
    contact_number: supporter.contact_number || '',
    email: supporter.email || '',
  };
}

function sameDraft(a: EditDraft, b: EditDraft) {
  return a.first_name === b.first_name &&
    a.middle_name === b.middle_name &&
    a.last_name === b.last_name &&
    a.dob === b.dob &&
    a.street_address === b.street_address &&
    a.village_id === b.village_id &&
    a.precinct_id === b.precinct_id &&
    a.contact_number === b.contact_number &&
    a.email === b.email;
}

function defaultGecSearchFor(supporter: QueueSupporter | null) {
  if (!supporter) return '';
  return [supporter.first_name, supporter.middle_name, supporter.last_name].filter(Boolean).join(' ');
}

export default function TeamVettingPage() {
  const queryClient = useQueryClient();
  const location = useLocation();
  const lastRequestedVillageRef = useRef<string | null>(null);
  const [searchParams] = useSearchParams();
  const [filter, setFilter] = useState<VettingFilter>('all');
  const [reviewBucket, setReviewBucket] = useState<QueueBucket>((searchParams.get('review_bucket') as QueueBucket) || 'pending');
  const [districtId, setDistrictId] = useState(searchParams.get('district_id') || '');
  const [villageId, setVillageId] = useState(searchParams.get('village_id') || '');
  const [precinctId, setPrecinctId] = useState(searchParams.get('precinct_id') || '');
  const [source, setSource] = useState(searchParams.get('source_group') === 'team' ? 'team' : (searchParams.get('source') || ''));
  const [search, setSearch] = useState(searchParams.get('search') || '');
  const [page, setPage] = useState(Number(searchParams.get('page') || 1));
  const [selectedIds, setSelectedIds] = useState<Set<number>>(new Set());
  const [selectedSupporterId, setSelectedSupporterId] = useState<number | null>(null);
  const [draftState, setDraftState] = useState<{ supporterId: number | null; value: EditDraft }>({
    supporterId: null,
    value: EMPTY_DRAFT,
  });
  const [gecSearchState, setGecSearchState] = useState<{ supporterId: number | null; value: string }>({
    supporterId: null,
    value: '',
  });
  const returnTo = searchParams.get('return_to') || '';

  const { data: villages } = useQuery({ queryKey: ['villages'], queryFn: getVillages });
  const { data: districts } = useQuery({ queryKey: ['districts'], queryFn: getDistricts });
  const { data: precincts } = useQuery({
    queryKey: ['precincts', villageId],
    queryFn: () => getPrecincts(villageId ? { village_id: villageId } : undefined),
  });
  const { data, isLoading } = useQuery({
    queryKey: ['vetting-queue', reviewBucket, filter, districtId, villageId, precinctId, source, search, page],
    queryFn: () => getVettingQueue({
      review_bucket: reviewBucket,
      filter: filter === 'all' ? undefined : filter,
      district_id: districtId || undefined,
      village_id: villageId || undefined,
      precinct_id: precinctId || undefined,
      source_group: source === 'team' ? 'team' : undefined,
      source: source && source !== 'team' ? source : undefined,
      search: search || undefined,
      page,
      per_page: 50,
    }),
  });

  const supporters = useMemo<QueueSupporter[]>(() => data?.supporters ?? EMPTY_SUPPORTERS, [data?.supporters]);
  const summary = data?.summary || {};
  const pagination = data?.pagination || {};
  const effectiveSelectedSupporterId = useMemo(() => {
    if (supporters.length === 0) return null;
    if (selectedSupporterId && supporters.some((supporter) => supporter.id === selectedSupporterId)) {
      return selectedSupporterId;
    }
    return supporters[0].id;
  }, [selectedSupporterId, supporters]);
  const selectedSupporter = supporters.find((supporter) => supporter.id === effectiveSelectedSupporterId) || null;
  const defaultDraft = useMemo(() => buildDraft(selectedSupporter), [selectedSupporter]);
  const draft = draftState.supporterId === effectiveSelectedSupporterId ? draftState.value : defaultDraft;
  const defaultGecSearch = useMemo(() => defaultGecSearchFor(selectedSupporter), [selectedSupporter]);
  const gecSearch = gecSearchState.supporterId === effectiveSelectedSupporterId ? gecSearchState.value : defaultGecSearch;

  const updateDraft = (value: SetStateAction<EditDraft>) => {
    const supporterId = effectiveSelectedSupporterId;
    setDraftState((prev) => {
      const baseDraft = prev.supporterId === supporterId ? prev.value : defaultDraft;
      const nextDraft = typeof value === 'function' ? value(baseDraft) : value;

      if (prev.supporterId === supporterId && sameDraft(prev.value, nextDraft)) {
        return prev;
      }

      return { supporterId, value: nextDraft };
    });
  };

  const updateGecSearch = (value: SetStateAction<string>) => {
    const supporterId = effectiveSelectedSupporterId;
    setGecSearchState((prev) => {
      const baseSearch = prev.supporterId === supporterId ? prev.value : defaultGecSearch;
      const nextSearch = typeof value === 'function' ? value(baseSearch) : value;

      if (prev.supporterId === supporterId && prev.value === nextSearch) {
        return prev;
      }

      return { supporterId, value: nextSearch };
    });
  };

  const { data: editPrecincts } = useQuery({
    queryKey: ['vetting-edit-precincts', draft.village_id],
    queryFn: () => getPrecincts(draft.village_id ? { village_id: draft.village_id } : undefined),
    enabled: Boolean(draft.village_id),
  });

  const { data: gecLookupData, isLoading: gecLookupLoading } = useQuery({
    queryKey: ['vetting-gec-lookup', gecSearch, draft.village_id],
    queryFn: () => getGecVoters({
      q: gecSearch || undefined,
      village_id: draft.village_id || undefined,
      per_page: 25,
    }),
    enabled: Boolean(effectiveSelectedSupporterId),
  });

  const invalidateQueueData = () => {
    queryClient.invalidateQueries({ queryKey: ['vetting-queue'] });
    queryClient.invalidateQueries({ queryKey: ['supporters'] });
    queryClient.invalidateQueries({ queryKey: ['dashboard'] });
    queryClient.invalidateQueries({ queryKey: ['reports-list'] });
    queryClient.invalidateQueries({ queryKey: ['current-cycle'] });
    queryClient.invalidateQueries({ queryKey: ['session'] });
  };

  const approveMutation = useMutation({
    mutationFn: (id: number) => approveSupporter(id),
    onSuccess: (result) => {
      captureAnalyticsEvent('supporter_review_approved', {
        filter,
        district_id: districtId ? Number(districtId) : undefined,
        village_id: villageId ? Number(villageId) : undefined,
        precinct_id: precinctId ? Number(precinctId) : undefined,
        source_filter: source || undefined,
        has_search_filter: Boolean(search),
        verification_status: (result as { supporter?: { verification_status?: string } })?.supporter?.verification_status,
      });
      invalidateQueueData();
    },
    onError: (error: unknown) => {
      const message =
        (error as { response?: { data?: { message?: string } } })?.response?.data?.message ||
        'Failed to approve supporter.';
      alert(message);
    },
  });

  const bulkMutation = useMutation({
    mutationFn: async ({ ids }: { ids: number[] }) => Promise.all(ids.map((id) => approveSupporter(id))),
    onSuccess: (_result, { ids }) => {
      captureAnalyticsEvent('supporter_review_bulk_approved', {
        supporter_count: ids.length,
        filter,
        district_id: districtId ? Number(districtId) : undefined,
        village_id: villageId ? Number(villageId) : undefined,
        precinct_id: precinctId ? Number(precinctId) : undefined,
        source_filter: source || undefined,
        has_search_filter: Boolean(search),
      });
      setSelectedIds(new Set());
      invalidateQueueData();
    },
    onError: (error: unknown) => {
      const message =
        (error as { response?: { data?: { message?: string } } })?.response?.data?.message ||
        'Failed to approve selected supporters.';
      alert(message);
    },
  });
  const rejectMutation = useMutation({
    mutationFn: (id: number) => rejectSupporterReview(id),
    onSuccess: (result) => {
      captureAnalyticsEvent('supporter_review_rejected', {
        filter,
        district_id: districtId ? Number(districtId) : undefined,
        village_id: villageId ? Number(villageId) : undefined,
        precinct_id: precinctId ? Number(precinctId) : undefined,
        source_filter: source || undefined,
        has_search_filter: Boolean(search),
        verification_status: (result as { supporter?: { verification_status?: string } })?.supporter?.verification_status,
      });
      invalidateQueueData();
    },
  });

  const saveDraftMutation = useMutation({
    mutationFn: async ({ reVet }: { reVet: boolean }) => {
      if (!selectedSupporter) throw new Error('No supporter selected');
      await updateSupporter(selectedSupporter.id, {
        first_name: draft.first_name.trim(),
        middle_name: draft.middle_name.trim() || null,
        last_name: draft.last_name.trim(),
        dob: draft.dob || null,
        street_address: draft.street_address.trim() || null,
        village_id: draft.village_id ? Number(draft.village_id) : null,
        precinct_id: draft.precinct_id ? Number(draft.precinct_id) : null,
        contact_number: draft.contact_number.trim() || null,
        email: draft.email.trim() || null,
      });
      if (reVet) {
        await revetSupporter(selectedSupporter.id);
      }
    },
    onSuccess: () => {
      invalidateQueueData();
    },
    onError: (error: unknown) => {
      const message =
        (error as { response?: { data?: { message?: string } } })?.response?.data?.message ||
        'Failed to save supporter changes.';
      alert(message);
    },
  });

  const singleRevetMutation = useMutation({
    mutationFn: (id: number) => revetSupporter(id),
    onSuccess: () => invalidateQueueData(),
    onError: () => alert('Failed to re-vet supporter.'),
  });

  const bulkRevetMutation = useMutation({
    mutationFn: (payload: { supporter_ids?: number[]; apply_current_filters?: boolean }) => bulkRevetSupporters({
      ...payload,
      review_bucket: reviewBucket,
      filter: filter === 'all' ? undefined : filter,
      district_id: districtId || undefined,
      village_id: villageId || undefined,
      precinct_id: precinctId || undefined,
      source_group: source === 'team' ? 'team' : undefined,
      source: source && source !== 'team' ? source : undefined,
      search: search || undefined,
    }),
    onSuccess: () => {
      setSelectedIds(new Set());
      invalidateQueueData();
    },
    onError: () => alert('Failed to bulk re-vet supporters.'),
  });

  const selectedSupporters = supporters.filter((supporter) => selectedIds.has(supporter.id));
  const selectedCanApprove = selectedSupporters.length > 0 && selectedSupporters.every((supporter) => canApproveSupporter(supporter));
  const selectedHasDuplicateWarnings = selectedSupporters.some((supporter) => supporter.potential_duplicate === true);
  const gecResults: GecVoter[] = gecLookupData?.gec_voters || [];
  const villageOptions = villages?.villages || [];
  const editPrecinctOptions: PrecinctOption[] = editPrecincts?.precincts || [];

  const handleDraftVillageChange = async (nextVillageId: string) => {
    lastRequestedVillageRef.current = nextVillageId || null;
    updateDraft((prev) => ({ ...prev, village_id: nextVillageId, precinct_id: '' }));

    if (!nextVillageId) {
      return;
    }

    try {
      const precinctData = await queryClient.fetchQuery({
        queryKey: ['vetting-edit-precincts', nextVillageId],
        queryFn: () => getPrecincts({ village_id: nextVillageId }),
      });
      const nextPrecinctOptions: PrecinctOption[] = precinctData?.precincts || [];
      if (lastRequestedVillageRef.current !== nextVillageId) {
        return;
      }

      updateDraft((prev) => {
        if (prev.village_id !== nextVillageId) {
          return prev;
        }

        const nextPrecinctId = assignPrecinctIdByLastName(prev.last_name, nextPrecinctOptions);
        return {
          ...prev,
          precinct_id: nextPrecinctId ? String(nextPrecinctId) : '',
        };
      });
    } catch {
      if (lastRequestedVillageRef.current !== nextVillageId) {
        return;
      }

      updateDraft((prev) => {
        if (prev.village_id !== nextVillageId) {
          return prev;
        }

        return { ...prev, precinct_id: '' };
      });
    }
  };

  const toggleSelect = (id: number) => {
    const next = new Set(selectedIds);
    if (next.has(id)) { next.delete(id); } else { next.add(id); }
    setSelectedIds(next);
  };

  const toggleAll = () => {
    if (selectedIds.size === supporters.length) {
      setSelectedIds(new Set());
    } else {
      setSelectedIds(new Set(supporters.map((s: Record<string, unknown>) => s.id as number)));
    }
  };

  const confidenceColor = (confidence: string) => {
    switch (confidence) {
      case 'exact': return 'text-green-700 bg-green-50';
      case 'high': return 'text-blue-700 bg-blue-50';
      case 'medium': return 'text-amber-700 bg-amber-50';
      case 'low': return 'text-red-700 bg-red-50';
      default: return 'text-gray-700 bg-gray-50';
    }
  };

  const matchTypeLabel = (type: string) => {
    switch (type) {
      // Legacy (full DOB) match types
      case 'exact_match':
      case 'exact_dob_village':   return 'Exact (DOB + Village)';
      case 'different_village':   return 'Different Village';
      case 'fuzzy_name_year':     return 'Fuzzy Name (Birth Year)';
      case 'name_village_only':   return 'Name + Village';
      // New (birth-year-only) match types
      case 'name_year_village':   return 'Name + Year + Village';
      case 'name_year_only':      return 'Name + Year';
      default: return type.replace(/_/g, ' ');
    }
  };

  const confidenceLabel = (confidence: string, matchCount?: number) => {
    const count = matchCount && matchCount > 1 ? ` (${matchCount} candidates)` : '';
    switch (confidence) {
      case 'exact':  return `Exact${count}`;
      case 'high':   return `High${count}`;
      case 'medium': return `Medium${count}`;
      case 'low':    return `Low${count}`;
      default:       return confidence;
    }
  };

  const currentQueuePath = () => {
    const params = new URLSearchParams();
    if (reviewBucket !== 'pending') params.set('review_bucket', reviewBucket);
    if (filter !== 'all') params.set('filter', filter);
    if (districtId) params.set('district_id', districtId);
    if (villageId) params.set('village_id', villageId);
    if (precinctId) params.set('precinct_id', precinctId);
    if (source === 'team') params.set('source_group', 'team');
    else if (source) params.set('source', source);
    if (search) params.set('search', search);
    if (page > 1) params.set('page', String(page));
    if (returnTo) params.set('return_to', returnTo);
    const query = params.toString();
    return `${location.pathname}${query ? `?${query}` : ''}`;
  };

  const bucketLabel = useMemo(() => {
    if (reviewBucket === 'approved') return 'approved';
    if (reviewBucket === 'rejected') return 'rejected';
    return 'pending';
  }, [reviewBucket]);

  const applyGecIdentity = (voter: GecVoter) => {
    updateDraft((prev) => ({
      ...prev,
      first_name: voter.first_name || '',
      middle_name: voter.middle_name || '',
      last_name: voter.last_name || '',
      dob: voter.dob ? String(voter.dob).slice(0, 10) : prev.dob,
    }));
  };

  const applyGecLocation = (voter: GecVoter) => {
    const nextVillageId = voter.village_id ? String(voter.village_id) : '';
    const nextPrecinctId = voter.precinct_id ? String(voter.precinct_id) : '';

    updateDraft((prev) => ({
      ...prev,
      village_id: nextVillageId || prev.village_id,
      precinct_id: nextPrecinctId || (nextVillageId && nextVillageId !== prev.village_id ? '' : prev.precinct_id),
    }));
  };

  const applyGecAddress = (voter: GecVoter) => {
    if (!voter.address) return;
    updateDraft((prev) => ({
      ...prev,
      street_address: voter.address || prev.street_address,
    }));
  };

  return (
    <WorkspacePage width="full" className="space-y-6">
      <div>
        {returnTo && (
          <Link
            to={returnTo}
            className="inline-flex items-center gap-1.5 text-sm text-gray-500 hover:text-gray-900 mb-3"
          >
            <ChevronLeft className="w-4 h-4" />
            Back to Village
          </Link>
        )}
        <h1 className="text-xl font-bold text-gray-900">Supporter Review Queue</h1>
        <p className="text-sm text-gray-500 mt-0.5">Correction workspace for supporter submissions, with live GEC lookup and queue re-vetting.</p>
        <p className="text-xs text-gray-400 mt-1">
          Submission village is now tracked separately from the current assigned village so referral reporting stays accurate after edits.
        </p>
      </div>

      <div className="flex flex-wrap gap-2">
        <FilterBadge active={reviewBucket === 'pending'} onClick={() => { setReviewBucket('pending'); setPage(1); setSelectedIds(new Set()); }}
          label="Pending" count={summary.pending} />
        <FilterBadge active={reviewBucket === 'approved'} onClick={() => { setReviewBucket('approved'); setPage(1); setSelectedIds(new Set()); }}
          label="Approved" count={summary.approved} />
        <FilterBadge active={reviewBucket === 'rejected'} onClick={() => { setReviewBucket('rejected'); setPage(1); setSelectedIds(new Set()); }}
          label="Rejected" count={summary.rejected} />
      </div>

      <div className="flex flex-wrap gap-2">
        <FilterBadge active={filter === 'all'} onClick={() => { setFilter('all'); setPage(1); }}
          label={reviewBucket === 'pending' ? 'All Pending' : `All ${reviewBucket}`} count={summary.total_needing_review} />
        <FilterBadge active={filter === 'verified'} onClick={() => { setFilter('verified'); setPage(1); }}
          label="Exact GEC Match" count={summary.verified} />
        <FilterBadge active={filter === 'flagged'} onClick={() => { setFilter('flagged'); setPage(1); }}
          label="Needs Review" count={summary.flagged} />
        <FilterBadge active={filter === 'no_match'} onClick={() => { setFilter('no_match'); setPage(1); }}
          label="No GEC Match" count={summary.no_match} />
        <FilterBadge active={filter === 'referral'} onClick={() => { setFilter('referral'); setPage(1); }}
          label="Village Referrals" count={summary.referrals} />
        <FilterBadge active={filter === 'registration_help'} onClick={() => { setFilter('registration_help'); setPage(1); }}
          label="Registration Help" count={summary.registration_help} />
        <FilterBadge active={filter === 'help_requests'} onClick={() => { setFilter('help_requests'); setPage(1); }}
          label="Any Help Request" count={summary.help_requests} />
      </div>

      <div className="flex flex-wrap gap-3">
        <div className="relative flex-1 min-w-[200px] max-w-xs">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
          <input
            type="text"
            placeholder="Search by name..."
            value={search}
            onChange={e => { setSearch(e.target.value); setPage(1); }}
            className="w-full pl-9 pr-3 py-2 text-sm border border-gray-200 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
          />
        </div>
        <select
          value={districtId}
          onChange={e => {
            setDistrictId(e.target.value);
            setVillageId('');
            setPrecinctId('');
            setPage(1);
          }}
          className="px-3 py-2 text-sm border border-gray-200 rounded-lg focus:ring-2 focus:ring-blue-500"
        >
          <option value="">All Districts</option>
          {(districts?.districts || []).map((d: Record<string, unknown>) => (
            <option key={d.id as number} value={d.id as number}>{d.name as string}</option>
          ))}
        </select>
        <select
          value={villageId}
          onChange={e => {
            setVillageId(e.target.value);
            setPrecinctId('');
            setPage(1);
          }}
          className="px-3 py-2 text-sm border border-gray-200 rounded-lg focus:ring-2 focus:ring-blue-500"
        >
          <option value="">All Villages</option>
          {(villages?.villages || [])
            .filter((v: Record<string, unknown>) => !districtId || String(v.district_id || '') === districtId)
            .map((v: Record<string, unknown>) => (
            <option key={v.id as number} value={v.id as number}>{v.name as string}</option>
          ))}
        </select>
        <select
          value={precinctId}
          onChange={e => { setPrecinctId(e.target.value); setPage(1); }}
          className="px-3 py-2 text-sm border border-gray-200 rounded-lg focus:ring-2 focus:ring-blue-500"
        >
          <option value="">All Precincts</option>
          {(precincts?.precincts || []).map((p: Record<string, unknown>) => (
            <option key={p.id as number} value={p.id as number}>
              {(p.village_name as string) ? `${p.village_name as string} · ${p.number as string}` : (p.number as string)}
            </option>
          ))}
        </select>
        <select
          value={source}
          onChange={e => { setSource(e.target.value); setPage(1); }}
          className="px-3 py-2 text-sm border border-gray-200 rounded-lg focus:ring-2 focus:ring-blue-500"
        >
          <option value="">All Origins</option>
          <option value="team">Team submissions</option>
          <option value="public_signup">Public Signup</option>
          <option value="qr_signup">QR Signup</option>
          <option value="staff_entry">Staff Entry</option>
          <option value="bulk_import">Excel Import</option>
        </select>
      </div>

      {reviewBucket === 'pending' && supporters.length > 0 && (
        <div className="flex justify-end">
          <button
            type="button"
            onClick={() => bulkRevetMutation.mutate({ apply_current_filters: true })}
            disabled={bulkRevetMutation.isPending}
            className="inline-flex items-center gap-2 rounded-xl border border-blue-200 bg-blue-50 px-4 py-2 text-sm font-medium text-blue-700 hover:bg-blue-100 disabled:opacity-50"
          >
            <RefreshCw className="h-4 w-4" />
            Re-vet Current Filtered Queue
          </button>
        </div>
      )}

      {selectedIds.size > 0 && (
        <div className="flex items-center gap-3 p-3 bg-blue-50 border border-blue-100 rounded-lg">
          <span className="text-sm font-medium text-blue-700">{selectedIds.size} selected</span>
          {reviewBucket === 'pending' && (
            <button
              onClick={() => bulkMutation.mutate({ ids: Array.from(selectedIds) })}
              disabled={bulkMutation.isPending || !selectedCanApprove}
              className="px-3 py-1.5 text-xs font-medium bg-green-600 text-white rounded-lg hover:bg-green-700 disabled:opacity-50"
              title={
                selectedCanApprove
                  ? 'Approve selected supporters into the official list'
                  : selectedHasDuplicateWarnings
                    ? 'Resolve duplicate warnings before approving these supporters'
                    : 'Only pending submissions can be approved'
              }
            >
              Approve Selected
            </button>
          )}
          <button
            onClick={() => bulkRevetMutation.mutate({ supporter_ids: Array.from(selectedIds) })}
            disabled={bulkRevetMutation.isPending}
            className="px-3 py-1.5 text-xs font-medium bg-white text-blue-700 border border-blue-200 rounded-lg hover:bg-blue-100 disabled:opacity-50"
          >
            Re-vet Selected
          </button>
          {selectedHasDuplicateWarnings && (
            <Link
              to="/data/duplicates"
              className="px-3 py-1.5 text-xs font-medium text-amber-700 bg-amber-100 rounded-lg hover:bg-amber-200"
            >
              Resolve duplicates first
            </Link>
          )}
          <button
            onClick={() => setSelectedIds(new Set())}
            className="px-3 py-1.5 text-xs font-medium text-gray-600 hover:text-gray-900"
          >
            Clear
          </button>
        </div>
      )}

      {isLoading ? (
        <div className="space-y-3">
          {[1, 2, 3, 4, 5].map(i => <div key={i} className="h-20 bg-gray-200 animate-pulse rounded-xl" />)}
        </div>
      ) : supporters.length === 0 ? (
        <div className="text-center py-16">
          <ShieldCheck className="w-12 h-12 text-green-300 mx-auto mb-3" />
          <h3 className="text-lg font-semibold text-gray-700">All caught up!</h3>
          <p className="text-sm text-gray-400 mt-1">No {bucketLabel} supporter submissions match the current filters.</p>
        </div>
      ) : (
        <div className="grid gap-6 xl:grid-cols-[minmax(0,1.3fr)_minmax(360px,0.9fr)]">
          <div className="space-y-2">
            <div className="flex items-center gap-2 px-3 py-1">
              <input type="checkbox" checked={selectedIds.size === supporters.length && supporters.length > 0}
                onChange={toggleAll} className="rounded border-gray-300" />
              <span className="text-xs text-gray-400">Select all on page</span>
            </div>

            {supporters.map((supporter) => {
              const id = supporter.id;
              const matches = supporter.gec_matches || [];
              const statusLabel = verificationStatusLabel(supporter, matches.length > 0);
              const statusDetail = verificationStatusDetail(supporter, matches.length > 0);
              const canApprove = canApproveSupporter(supporter);
              const hasDuplicateWarning = supporter.potential_duplicate === true;
              const duplicatesPath = `/data/duplicates?focus_supporter_id=${id}`;
              const isSelected = effectiveSelectedSupporterId === id;
              const statusColor = supporter.submitted_village_referral ? 'text-purple-600 bg-purple-50' :
                supporter.verification_status === 'flagged' ? 'text-amber-700 bg-amber-50' :
                supporter.verification_status === 'unverified' ? 'text-red-700 bg-red-50' : 'text-green-700 bg-green-50';

              return (
                <div
                  key={id}
                  className={`rounded-xl border overflow-hidden bg-white ${isSelected ? 'border-blue-400 ring-2 ring-blue-100' : 'border-gray-200'}`}
                >
                  <div className="flex gap-3 p-4">
                    <input type="checkbox" checked={selectedIds.has(id)} onChange={() => toggleSelect(id)}
                      className="mt-1 rounded border-gray-300 shrink-0" />

                    <button type="button" className="flex-1 min-w-0 text-left" onClick={() => setSelectedSupporterId(id)}>
                      <div className="flex flex-wrap items-center gap-2">
                        <span className="font-medium text-gray-900 text-sm">
                          {[supporter.last_name, [supporter.first_name, supporter.middle_name].filter(Boolean).join(' ')].filter(Boolean).join(', ')}
                        </span>
                        <span className={`text-[10px] font-semibold uppercase px-1.5 py-0.5 rounded ${statusColor}`}>
                          {statusLabel}
                        </span>
                        {supporter.submitted_village_referral && (
                          <span className="text-[10px] font-semibold text-indigo-700 bg-indigo-50 px-1.5 py-0.5 rounded flex items-center gap-1">
                            <MapPin className="w-3 h-3" />
                            Submitted by {supporter.submitted_village_name}
                          </span>
                        )}
                        {hasDuplicateWarning && (
                          <span className="text-[10px] font-semibold text-amber-700 bg-amber-100 px-1.5 py-0.5 rounded">
                            Duplicate review required
                          </span>
                        )}
                      </div>

                      <div className="mt-1 text-xs text-gray-400">
                        {supporter.village_name || 'No village'} &middot; {supporter.contact_number || 'No phone'}
                        {supporter.dob ? <> &middot; DOB: {new Date(supporter.dob).toLocaleDateString()}</> : null}
                      </div>

                      <div className="mt-1 text-xs text-slate-500">
                        {selfReportedStatusLabel(supporter)}
                        {supporter.registered_voter_location_note ? ` · Votes elsewhere: ${supporter.registered_voter_location_note}` : ''}
                      </div>

                      {(Boolean(supporter.referred_by_name) || Number(supporter.household_member_count || 0) > 0) && (
                        <div className="mt-1 text-xs text-indigo-700">
                          {supporter.referred_by_name ? `Referred by: ${supporter.referred_by_name}` : 'Household signup'}
                          {Number(supporter.household_member_count || 0) > 0 ? ` · Linked supporters: ${supporter.household_member_count}` : ''}
                        </div>
                      )}

                      {statusDetail && (
                        <div className={`mt-1 text-xs leading-5 ${supporter.submitted_village_referral ? 'text-purple-700' : 'text-gray-500'}`}>
                          {statusDetail}
                        </div>
                      )}

                      {supporter.submitted_village_referral && (
                        <div className="mt-1 text-xs text-indigo-700">
                          Original submission village: {supporter.submitted_village_name || 'Unknown'} · Current assignment: {supporter.village_name || 'Unknown'}
                        </div>
                      )}

                      {matches.length > 0 && (
                        <div className="flex flex-wrap gap-1.5 mt-1.5">
                          {matches.slice(0, 3).map((match, index) => (
                            <span key={`${id}-${index}`} className={`text-[10px] font-medium px-2 py-0.5 rounded-full ${confidenceColor(match.confidence)}`}>
                              {confidenceLabel(match.confidence, match.match_count)} &middot; {matchTypeLabel(match.match_type)}
                              {match.match_type === 'different_village' && ` — ${match.gec_voter.village_name}`}
                            </span>
                          ))}
                        </div>
                      )}
                      {matches.length === 0 && (
                        <div className="flex items-center gap-1 mt-1.5">
                          <XCircle className="w-3 h-3 text-red-400" />
                          <span className="text-[10px] text-red-500 font-medium">No GEC match found in the current voter list</span>
                        </div>
                      )}

                      <div className="mt-2 flex flex-wrap gap-1.5">
                        {supportRequestBadges(supporter).map((badge) => (
                          <span key={`${id}-${badge}`} className="rounded-full bg-amber-50 px-2 py-0.5 text-[10px] font-medium text-amber-700">
                            {badge}
                          </span>
                        ))}
                        {supportRequestBadges(supporter).length === 0 && (
                          <span className="text-[10px] text-gray-400">No special follow-up requests</span>
                        )}
                      </div>
                    </button>

                    <div className="flex shrink-0 items-start gap-1">
                      <Link
                        to={`/data/supporters/${id}?return_to=${encodeURIComponent(currentQueuePath())}`}
                        className="px-2.5 py-2 text-xs font-medium text-gray-600 hover:bg-gray-50 rounded-lg transition-colors"
                        title="Open supporter detail"
                      >
                        <PencilLine className="w-4 h-4" />
                      </Link>
                      <button
                        onClick={() => singleRevetMutation.mutate(id)}
                        disabled={singleRevetMutation.isPending}
                        className="px-2.5 py-2 text-xs font-medium text-blue-700 hover:bg-blue-50 rounded-lg transition-colors"
                        title="Re-vet supporter against current GEC list"
                      >
                        <RefreshCw className="w-4 h-4" />
                      </button>
                      {reviewBucket === 'pending' && (hasDuplicateWarning ? (
                        <Link
                          to={duplicatesPath}
                          className="px-2.5 py-2 text-xs font-medium text-amber-700 hover:bg-amber-50 rounded-lg transition-colors"
                          title="Resolve duplicate before approving"
                        >
                          Resolve
                        </Link>
                      ) : (
                        <button
                          onClick={() => approveMutation.mutate(id)}
                          disabled={approveMutation.isPending || rejectMutation.isPending || !canApprove}
                          className="p-2 text-green-600 hover:bg-green-50 rounded-lg transition-colors"
                          title={canApprove ? 'Approve into official supporter list' : 'This submission is not ready for approval'}
                        >
                          <CheckCircle className="w-5 h-5" />
                        </button>
                      ))}
                      {reviewBucket === 'pending' && (
                        <button
                          onClick={() => rejectMutation.mutate(id)}
                          disabled={approveMutation.isPending || rejectMutation.isPending}
                          className="p-2 text-red-500 hover:bg-red-50 rounded-lg transition-colors"
                          title="Reject submission"
                        >
                          <XCircle className="w-5 h-5" />
                        </button>
                      )}
                    </div>
                  </div>
                </div>
              );
            })}
          </div>

          <div className="space-y-4">
            <section className="rounded-2xl border border-gray-200 bg-white p-4">
              <div className="flex items-start justify-between gap-3">
                <div>
                  <h2 className="text-sm font-semibold text-gray-900">Quick Edit + Re-vet</h2>
                  <p className="mt-1 text-xs text-gray-500">Edit the selected supporter, then save changes or save and immediately re-vet.</p>
                </div>
                {selectedSupporter && (
                  <Link
                    to={`/data/supporters/${selectedSupporter.id}?return_to=${encodeURIComponent(currentQueuePath())}`}
                    className="text-xs text-blue-600 hover:text-blue-700"
                  >
                    Full detail
                  </Link>
                )}
              </div>

              {!selectedSupporter ? (
                <div className="py-10 text-center text-sm text-gray-500">Select a supporter from the queue to start editing.</div>
              ) : (
                <div className="mt-4 space-y-3">
                  <div className="grid gap-3 sm:grid-cols-2">
                    <input value={draft.first_name} onChange={(e) => updateDraft((prev) => ({ ...prev, first_name: e.target.value }))} placeholder="First name" className="rounded-xl border border-gray-200 px-3 py-2 text-sm" />
                    <input value={draft.middle_name} onChange={(e) => updateDraft((prev) => ({ ...prev, middle_name: e.target.value }))} placeholder="Middle name" className="rounded-xl border border-gray-200 px-3 py-2 text-sm" />
                    <input value={draft.last_name} onChange={(e) => updateDraft((prev) => ({ ...prev, last_name: e.target.value }))} placeholder="Last name" className="rounded-xl border border-gray-200 px-3 py-2 text-sm" />
                    <input value={draft.dob} onChange={(e) => updateDraft((prev) => ({ ...prev, dob: e.target.value }))} placeholder="DOB" type="date" className="rounded-xl border border-gray-200 px-3 py-2 text-sm" />
                    <input value={draft.contact_number} onChange={(e) => updateDraft((prev) => ({ ...prev, contact_number: e.target.value }))} placeholder="Phone" className="rounded-xl border border-gray-200 px-3 py-2 text-sm" />
                    <input value={draft.email} onChange={(e) => updateDraft((prev) => ({ ...prev, email: e.target.value }))} placeholder="Email" className="rounded-xl border border-gray-200 px-3 py-2 text-sm" />
                  </div>
                  <input value={draft.street_address} onChange={(e) => updateDraft((prev) => ({ ...prev, street_address: e.target.value }))} placeholder="Street address" className="w-full rounded-xl border border-gray-200 px-3 py-2 text-sm" />
                  <div className="grid gap-3 sm:grid-cols-2">
                    <select value={draft.village_id} onChange={(e) => { void handleDraftVillageChange(e.target.value); }} className="rounded-xl border border-gray-200 px-3 py-2 text-sm">
                      <option value="">Select village</option>
                      {villageOptions.map((village: { id: number; name: string }) => (
                        <option key={village.id} value={village.id}>{village.name}</option>
                      ))}
                    </select>
                    <select value={draft.precinct_id} onChange={(e) => updateDraft((prev) => ({ ...prev, precinct_id: e.target.value }))} className="rounded-xl border border-gray-200 px-3 py-2 text-sm">
                      <option value="">Select precinct</option>
                      {editPrecinctOptions.map((precinct) => (
                        <option key={precinct.id} value={precinct.id}>
                          {precinct.village_name ? `${precinct.village_name} · ${precinct.number}` : precinct.number}
                        </option>
                      ))}
                    </select>
                  </div>

                  <div className="rounded-xl border border-indigo-100 bg-indigo-50 px-3 py-2 text-xs text-indigo-700">
                    Original submission village: {selectedSupporter.submitted_village_name || selectedSupporter.village_name || 'Unknown'}
                  </div>

                  <div className="flex flex-col gap-2 sm:flex-row">
                    <button
                      type="button"
                      onClick={() => saveDraftMutation.mutate({ reVet: false })}
                      disabled={saveDraftMutation.isPending}
                      className="inline-flex items-center justify-center gap-2 rounded-xl border border-gray-200 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 disabled:opacity-50"
                    >
                      <Save className="w-4 h-4" />
                      Save Changes
                    </button>
                    <button
                      type="button"
                      onClick={() => saveDraftMutation.mutate({ reVet: true })}
                      disabled={saveDraftMutation.isPending}
                      className="inline-flex items-center justify-center gap-2 rounded-xl bg-blue-600 px-4 py-2 text-sm font-medium text-white hover:bg-blue-700 disabled:opacity-50"
                    >
                      <RefreshCw className="w-4 h-4" />
                      Save + Re-vet
                    </button>
                  </div>
                </div>
              )}
            </section>

            <section className="rounded-2xl border border-gray-200 bg-white p-4">
              <div className="flex items-start justify-between gap-3">
                <div>
                  <h2 className="text-sm font-semibold text-gray-900">GEC Lookup</h2>
                  <p className="mt-1 text-xs text-gray-500">Use separate presets for identity, location, and address so staff can copy only what they actually want from the matched GEC voter.</p>
                </div>
                <Database className="h-4 w-4 text-gray-400" />
              </div>

              <div className="relative mt-4">
                <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
                <input
                  type="text"
                  value={gecSearch}
                    onChange={(e) => updateGecSearch(e.target.value)}
                  placeholder="Search GEC voter list"
                  className="w-full rounded-xl border border-gray-200 py-2 pl-9 pr-3 text-sm"
                />
              </div>

              <div className="mt-4 space-y-2">
                {gecLookupLoading ? (
                  <div className="rounded-xl border border-gray-100 bg-gray-50 px-3 py-4 text-sm text-gray-500">Searching GEC list...</div>
                ) : gecResults.length === 0 ? (
                  <div className="rounded-xl border border-gray-100 bg-gray-50 px-3 py-4 text-sm text-gray-500">No current GEC matches found for this search.</div>
                ) : (
                  gecResults.map((voter) => (
                    <div key={voter.id} className="rounded-xl border border-gray-200 p-3">
                      <div className="flex items-start justify-between gap-3">
                        <div className="min-w-0">
                          <p className="text-sm font-medium text-gray-900">
                            {[voter.first_name, voter.middle_name, voter.last_name].filter(Boolean).join(' ')}
                          </p>
                          <p className="mt-1 text-xs text-gray-500">
                            {voter.village_name || 'Unknown village'}
                            {voter.precinct_number ? ` · Precinct ${voter.precinct_number}` : ''}
                            {voter.dob ? ` · DOB: ${new Date(voter.dob).toLocaleDateString()}` : ''}
                            {!voter.dob && voter.birth_year ? ` · Born: ${voter.birth_year}` : ''}
                            {voter.voter_registration_number ? ` · Reg: ${voter.voter_registration_number}` : ''}
                          </p>
                          {voter.address && (
                            <p className="mt-1 text-xs text-gray-600">{voter.address}</p>
                          )}
                          <p className="mt-1 text-[11px] text-gray-400">
                            {voter.status ? `Status: ${voter.status}` : 'Status: active'}
                            {voter.previous_village_name ? ` · Previous village: ${voter.previous_village_name}` : ''}
                            {voter.gec_list_date ? ` · List date: ${new Date(voter.gec_list_date).toLocaleDateString()}` : ''}
                          </p>
                        </div>
                        <div className="flex shrink-0 flex-col items-end gap-2">
                          <button
                            type="button"
                            onClick={() => applyGecIdentity(voter)}
                            className="rounded-lg border border-blue-200 bg-blue-50 px-2.5 py-1 text-xs font-medium text-blue-700 hover:bg-blue-100"
                          >
                            Apply Identity
                          </button>
                          <button
                            type="button"
                            onClick={() => applyGecLocation(voter)}
                            className="rounded-lg border border-indigo-200 bg-indigo-50 px-2.5 py-1 text-xs font-medium text-indigo-700 hover:bg-indigo-100"
                          >
                            Apply Location
                          </button>
                          {voter.address && (
                            <button
                              type="button"
                              onClick={() => applyGecAddress(voter)}
                              className="rounded-lg border border-gray-200 bg-white px-2.5 py-1 text-xs font-medium text-gray-700 hover:bg-gray-50"
                            >
                              Use GEC Address
                            </button>
                          )}
                        </div>
                      </div>
                      <p className="mt-2 text-[11px] text-gray-400">
                        `Apply Identity` copies name and a full DOB when the GEC record has one. If the GEC match only has a birth year, we keep the supporter DOB unchanged instead of guessing a date.
                      </p>
                      <p className="mt-1 text-[11px] text-gray-400">
                        `Apply Location` copies village and precinct when available. `Use GEC Address` only replaces the supporter address.
                      </p>
                    </div>
                  ))
                )}
              </div>
            </section>
          </div>
        </div>
      )}

      {pagination.pages > 1 && (
        <div className="flex items-center justify-center gap-2">
          <button disabled={page <= 1} onClick={() => setPage(p => p - 1)}
            className="px-3 py-1.5 text-sm border border-gray-200 rounded-lg disabled:opacity-40 hover:bg-gray-50">Prev</button>
          <span className="text-sm text-gray-500">Page {page} of {pagination.pages}</span>
          <button disabled={page >= pagination.pages} onClick={() => setPage(p => p + 1)}
            className="px-3 py-1.5 text-sm border border-gray-200 rounded-lg disabled:opacity-40 hover:bg-gray-50">Next</button>
        </div>
      )}
    </WorkspacePage>
  );
}

function FilterBadge({ active, onClick, label, count }: {
  active: boolean;
  onClick: () => void;
  label: string;
  count?: number;
}) {
  const base = active
    ? 'bg-gray-900 text-white border-gray-900'
    : 'bg-white text-gray-600 border-gray-200 hover:border-gray-300';
  return (
    <button onClick={onClick} className={`px-3 py-1.5 text-xs font-medium rounded-full border transition-colors ${base}`}>
      {label}
      {count !== undefined && <span className="ml-1.5 opacity-70">{count}</span>}
    </button>
  );
}
