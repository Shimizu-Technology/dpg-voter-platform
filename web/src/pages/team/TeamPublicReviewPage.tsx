import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { getPublicReview, getVillages, acceptToQuota, rejectPublicReview } from '../../lib/api';
import { Link, useLocation, useSearchParams } from 'react-router-dom';
import { captureAnalyticsEvent } from '../../lib/analytics';
import { formatDateTime } from '../../lib/datetime';
import { gecMatchLabel, gecMatchState } from '../../lib/gecMatch';
import {
  UserCheck,
  UserPlus,
  Search,
  CheckCircle,
  XCircle,
  ChevronLeft,
  ChevronRight,
  Loader2,
} from 'lucide-react';
import WorkspacePage from '../../components/WorkspacePage';

type ReviewBucket = 'pending' | 'approved' | 'rejected';

function summaryCardClass(active: boolean, tone: 'blue' | 'green' | 'red') {
  const activeMap = {
    blue: 'bg-blue-100 border-blue-300 ring-2 ring-blue-100',
    green: 'bg-green-100 border-green-300 ring-2 ring-green-100',
    red: 'bg-red-100 border-red-300 ring-2 ring-red-100',
  } as const;

  const idleMap = {
    blue: 'bg-blue-50 border-blue-100 hover:border-blue-200',
    green: 'bg-green-50 border-green-100 hover:border-green-200',
    red: 'bg-red-50 border-red-100 hover:border-red-200',
  } as const;

  return `${active ? activeMap[tone] : idleMap[tone]} rounded-lg px-4 py-3 border text-left transition-colors`;
}

function selfReportedStatusLabel(supporter: Record<string, unknown>) {
  const status = supporter.registered_voter_status as string | undefined;
  if (status === 'yes') return 'Yes';
  if (status === 'no') return 'No';
  if (status === 'not_sure') return 'Not sure';
  return supporter.self_reported_registered_voter ? 'Yes' : 'No';
}

function supporterRequestBadges(supporter: Record<string, unknown>) {
  const badges: string[] = [];
  if (supporter.needs_voter_registration_help) badges.push('Registration');
  if (supporter.needs_absentee_ballot_help) badges.push('Absentee');
  if (supporter.needs_homebound_voting_help) badges.push('Homebound');
  if (supporter.needs_election_day_ride) badges.push('Ride');
  if (supporter.wants_to_volunteer) badges.push('Volunteer');
  return badges;
}

function gecFoundDisplay(supporter: Record<string, unknown>) {
  const state = gecMatchState({
    current_gec_match: supporter.current_gec_match as boolean | undefined,
    registered_voter: supporter.registered_voter as boolean | undefined,
  });

  if (state === 'matched') return <CheckCircle className="w-4 h-4 text-green-500" />;
  if (state === 'possible') return <span className="text-xs font-medium text-amber-700">{gecMatchLabel(supporter as { current_gec_match?: boolean; registered_voter?: boolean })}</span>;
  return <span className="text-xs text-red-500">No match</span>;
}

export default function TeamPublicReviewPage() {
  const queryClient = useQueryClient();
  const location = useLocation();
  const [searchParams] = useSearchParams();
  const [reviewBucket, setReviewBucket] = useState<ReviewBucket>('pending');
  const [villageId, setVillageId] = useState(searchParams.get('village_id') || '');
  const [search, setSearch] = useState(searchParams.get('search') || '');
  const [page, setPage] = useState(Number(searchParams.get('page') || 1));
  const returnTo = searchParams.get('return_to') || '';

  const { data: villages } = useQuery({ queryKey: ['villages'], queryFn: getVillages });
  const { data, isLoading, isFetching } = useQuery({
    queryKey: ['public-review', reviewBucket, villageId, search, page],
    queryFn: () => getPublicReview({
      review_bucket: reviewBucket,
      village_id: villageId || undefined,
      search: search || undefined,
      page,
      per_page: 50,
    }),
    placeholderData: (previous) => previous,
  });

  const acceptMutation = useMutation({
    mutationFn: (id: number) => acceptToQuota(id),
    onSuccess: (result) => {
      captureAnalyticsEvent('public_signup_sent_to_supporter_review', {
        review_bucket: reviewBucket,
        village_filter: villageId ? Number(villageId) : undefined,
        has_search_filter: Boolean(search),
        source: (result as { supporter?: { source?: string } })?.supporter?.source,
      });
      queryClient.invalidateQueries({ queryKey: ['public-review'] });
      queryClient.invalidateQueries({ queryKey: ['vetting-queue'] });
      queryClient.invalidateQueries({ queryKey: ['dashboard'] });
      queryClient.invalidateQueries({ queryKey: ['reports-list'] });
      queryClient.invalidateQueries({ queryKey: ['current-cycle'] });
      queryClient.invalidateQueries({ queryKey: ['session'] });
    },
  });
  const rejectMutation = useMutation({
    mutationFn: (id: number) => rejectPublicReview(id),
    onSuccess: (result) => {
      captureAnalyticsEvent('public_signup_rejected', {
        review_bucket: reviewBucket,
        village_filter: villageId ? Number(villageId) : undefined,
        has_search_filter: Boolean(search),
        source: (result as { supporter?: { source?: string } })?.supporter?.source,
      });
      queryClient.invalidateQueries({ queryKey: ['public-review'] });
      queryClient.invalidateQueries({ queryKey: ['dashboard'] });
      queryClient.invalidateQueries({ queryKey: ['reports-list'] });
      queryClient.invalidateQueries({ queryKey: ['current-cycle'] });
      queryClient.invalidateQueries({ queryKey: ['session'] });
    },
  });

  const supporters = data?.supporters || [];
  const summary = data?.summary || {};
  const pagination = data?.pagination || {};
  const isPendingBucket = reviewBucket === 'pending';
  const showInitialLoading = isLoading && !data;
  const showUpdatingState = isFetching && !showInitialLoading;
  const emptyStateTitle =
    reviewBucket === 'approved'
      ? 'No signups have been sent to supporter review'
      : reviewBucket === 'rejected'
        ? 'No rejected public signups'
        : 'No public signups to review';
  const emptyStateDetail =
    reviewBucket === 'approved'
      ? 'Approved public submissions will appear here after intake review.'
      : reviewBucket === 'rejected'
        ? 'Rejected public submissions will appear here for audit and follow-up.'
        : 'All public signups have been reviewed.';

  const currentQueuePath = () => {
    const params = new URLSearchParams();
    if (reviewBucket !== 'pending') params.set('review_bucket', reviewBucket);
    if (villageId) params.set('village_id', villageId);
    if (search) params.set('search', search);
    if (page > 1) params.set('page', String(page));
    if (returnTo) params.set('return_to', returnTo);
    const query = params.toString();
    return `${location.pathname}${query ? `?${query}` : ''}`;
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
        <h1 className="text-xl font-bold text-gray-900">Public Signup Review</h1>
        <p className="text-sm text-gray-500 mt-0.5">Review public signups before they enter the main supporter review queue</p>
        <p className="text-xs text-gray-400 mt-1">
          Browse pending, approved, and rejected public submissions here. Approving a signup does not add someone to the official supporter list yet. It sends them to the main supporter review queue.
        </p>
      </div>

      {/* Summary */}
      <div className="flex gap-4">
        <button
          type="button"
          onClick={() => { setReviewBucket('pending'); setPage(1); }}
          className={summaryCardClass(reviewBucket === 'pending', 'blue')}
        >
          <div className="text-xl font-bold text-blue-900">{summary.pending_review || 0}</div>
          <div className="text-[10px] text-blue-600 font-medium uppercase">Pending Signups</div>
        </button>
        <button
          type="button"
          onClick={() => { setReviewBucket('approved'); setPage(1); }}
          className={summaryCardClass(reviewBucket === 'approved', 'green')}
        >
          <div className="text-xl font-bold text-green-900">{summary.approved_for_supporter_review || 0}</div>
          <div className="text-[10px] text-green-600 font-medium uppercase">Sent to Supporter Review</div>
        </button>
        <button
          type="button"
          onClick={() => { setReviewBucket('rejected'); setPage(1); }}
          className={summaryCardClass(reviewBucket === 'rejected', 'red')}
        >
          <div className="text-xl font-bold text-red-900">{summary.rejected || 0}</div>
          <div className="text-[10px] text-red-600 font-medium uppercase">Rejected</div>
        </button>
      </div>

      {/* Filters */}
      <div className="flex flex-wrap gap-3">
        <div className="relative flex-1 min-w-[200px] max-w-xs">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
          <input
            type="text"
            placeholder="Search by name..."
            value={search}
            onChange={e => { setSearch(e.target.value); setPage(1); }}
            className="w-full pl-9 pr-3 py-2 text-sm border border-gray-200 rounded-lg focus:ring-2 focus:ring-blue-500"
          />
        </div>
        <select
          value={villageId}
          onChange={e => { setVillageId(e.target.value); setPage(1); }}
          className="px-3 py-2 text-sm border border-gray-200 rounded-lg focus:ring-2 focus:ring-blue-500"
        >
          <option value="">All Villages</option>
          {(villages?.villages || []).map((v: Record<string, unknown>) => (
            <option key={v.id as number} value={v.id as number}>{v.name as string}</option>
          ))}
        </select>
        <div className={`flex items-center gap-2 text-sm text-gray-400 transition-opacity ${showUpdatingState ? 'opacity-100' : 'opacity-0'}`}>
          <Loader2 className="w-4 h-4 animate-spin" />
          Updating...
        </div>
      </div>

      {/* List */}
      {showInitialLoading ? (
        <div className="space-y-3">
          {[1, 2, 3].map(i => <div key={i} className="h-16 bg-gray-200 animate-pulse rounded-xl" />)}
        </div>
      ) : supporters.length === 0 ? (
        <div className={`text-center py-16 transition-opacity duration-200 ${showUpdatingState ? 'opacity-70' : 'opacity-100'}`}>
          <UserCheck className="w-12 h-12 text-green-300 mx-auto mb-3" />
          <h3 className="text-lg font-semibold text-gray-700">{emptyStateTitle}</h3>
          <p className="text-sm text-gray-400 mt-1">{emptyStateDetail}</p>
        </div>
      ) : (
        <div className={`bg-white rounded-xl border border-gray-200 overflow-x-auto transition-opacity duration-200 ${showUpdatingState ? 'opacity-70' : 'opacity-100'}`}>
          <table className="min-w-[1040px] w-full text-sm">
            <thead>
              <tr className="border-b border-gray-100 bg-gray-50">
                <th className="text-left py-3 px-4 text-xs font-semibold text-gray-400 uppercase">Name</th>
                <th className="text-left py-3 px-4 text-xs font-semibold text-gray-400 uppercase">Village</th>
                <th className="text-left py-3 px-4 text-xs font-semibold text-gray-400 uppercase">Phone</th>
                <th className="text-left py-3 px-4 text-xs font-semibold text-gray-400 uppercase">Origin</th>
                <th className="text-left py-3 px-4 text-xs font-semibold text-gray-400 uppercase">Date</th>
                <th className="text-left py-3 px-4 text-xs font-semibold text-gray-400 uppercase">Self-Reported</th>
                <th className="text-left py-3 px-4 text-xs font-semibold text-gray-400 uppercase">GEC Match</th>
                <th className="text-left py-3 px-4 text-xs font-semibold text-gray-400 uppercase">Requests</th>
                <th className="text-right py-3 px-4 text-xs font-semibold text-gray-400 uppercase">{isPendingBucket ? 'Review' : 'Status'}</th>
              </tr>
            </thead>
            <tbody>
              {supporters.map((s: Record<string, unknown>) => (
                <tr key={s.id as number} className="border-b border-gray-50 hover:bg-gray-50">
                  <td className="py-3 px-4">
                    <Link to={`/data/supporters/${s.id}?return_to=${encodeURIComponent(currentQueuePath())}`} className="font-medium text-gray-900 hover:text-blue-600">
                      {[s.first_name as string, s.middle_name as string | undefined, s.last_name as string].filter(Boolean).join(' ')}
                    </Link>
                    <div className="mt-1 space-y-1">
                      {(s.registered_voter_location_note as string | undefined) && (
                        <div className="text-xs text-slate-500">
                          Votes elsewhere: {s.registered_voter_location_note as string}
                        </div>
                      )}
                      {Number(s.household_member_count || 0) > 0 && (
                        <div className="text-xs text-indigo-600">
                          Household signup ({s.household_member_count as number} linked supporter{Number(s.household_member_count || 0) === 1 ? '' : 's'})
                        </div>
                      )}
                    </div>
                  </td>
                  <td className="py-3 px-4 text-gray-600">{s.village_name as string}</td>
                  <td className="py-3 px-4 text-gray-600">{s.contact_number as string || '-'}</td>
                  <td className="py-3 px-4">
                    <span className="text-xs bg-gray-100 text-gray-600 px-2 py-0.5 rounded-full">
                      {(s.source as string)?.replace(/_/g, ' ')}
                    </span>
                  </td>
                  <td className="py-3 px-4 text-gray-400 text-xs">{formatDateTime(s.created_at as string)}</td>
                  <td className="py-3 px-4">
                    <span className="text-xs font-medium text-slate-600">
                      {selfReportedStatusLabel(s)}
                    </span>
                  </td>
                  <td className="py-3 px-4">
                    {gecFoundDisplay(s)}
                  </td>
                  <td className="py-3 px-4">
                    <div className="flex flex-wrap gap-1">
                      {supporterRequestBadges(s).map((badge) => (
                        <span key={`${s.id as number}-${badge}`} className="rounded-full bg-amber-50 px-2 py-0.5 text-[10px] font-medium text-amber-700">
                          {badge}
                        </span>
                      ))}
                      {supporterRequestBadges(s).length === 0 && (
                        <span className="text-xs text-gray-400">None</span>
                      )}
                    </div>
                  </td>
                  <td className="py-3 px-4 text-right">
                    {isPendingBucket ? (
                      <div className="flex justify-end gap-2">
                        <button
                          onClick={() => acceptMutation.mutate(s.id as number)}
                          disabled={acceptMutation.isPending || rejectMutation.isPending}
                          className="px-3 py-1.5 text-xs font-medium bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50 transition-colors"
                        >
                          <span className="flex items-center gap-1">
                            <UserPlus className="w-3 h-3" />
                            Send to Supporter Review
                          </span>
                        </button>
                        <button
                          onClick={() => rejectMutation.mutate(s.id as number)}
                          disabled={acceptMutation.isPending || rejectMutation.isPending}
                          className="px-3 py-1.5 text-xs font-medium bg-white text-red-600 border border-red-200 rounded-lg hover:bg-red-50 disabled:opacity-50 transition-colors"
                        >
                          <span className="flex items-center gap-1">
                            <XCircle className="w-3 h-3" />
                            Reject
                          </span>
                        </button>
                      </div>
                    ) : (
                      <span className={`inline-flex items-center rounded-full px-2.5 py-1 text-xs font-medium ${
                        reviewBucket === 'approved'
                          ? 'bg-green-100 text-green-700'
                          : 'bg-red-100 text-red-700'
                      }`}>
                        {reviewBucket === 'approved' ? 'Sent to Supporter Review' : 'Rejected'}
                      </span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* Pagination */}
      {pagination.pages > 1 && (
        <div className="flex items-center justify-center gap-2">
          <button disabled={page <= 1} onClick={() => setPage(p => p - 1)}
            className="px-3 py-1.5 text-sm border border-gray-200 rounded-lg disabled:opacity-40 hover:bg-gray-50">
            <ChevronLeft className="w-4 h-4" />
          </button>
          <span className="text-sm text-gray-500">Page {page} of {pagination.pages}</span>
          <button disabled={page >= pagination.pages} onClick={() => setPage(p => p + 1)}
            className="px-3 py-1.5 text-sm border border-gray-200 rounded-lg disabled:opacity-40 hover:bg-gray-50">
            <ChevronRight className="w-4 h-4" />
          </button>
        </div>
      )}
    </WorkspacePage>
  );
}
