import { useEffect, useMemo, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Link, useLocation, useParams, useSearchParams } from 'react-router-dom';
import { AlertTriangle, ChevronLeft, Pencil, Save, UserRound, X } from 'lucide-react';
import { getSupporter, getVillages, updateSupporter, verifySupporter, updateOutreachStatus } from '../../lib/api';
import { formatDateTime } from '../../lib/datetime';
import { gecMatchClass, gecMatchLabel } from '../../lib/gecMatch';
import { assignPrecinctIdByLastName } from '../../lib/precinctAssignment';
import WorkspacePage from '../../components/WorkspacePage';

interface VillageOption {
  id: number;
  name: string;
  precincts: { id: number; number: string; alpha_range: string }[];
}

interface SupporterDetail {
  id: number;
  first_name: string;
  middle_name: string | null;
  last_name: string;
  print_name: string;
  contact_number: string;
  email: string | null;
  dob: string | null;
  street_address: string | null;
  village_id: number;
  village_name: string;
  submitted_village_id?: number | null;
  submitted_village_name?: string | null;
  submitted_village_referral?: boolean;
  precinct_id: number | null;
  precinct_number: string | null;
  self_reported_registered_voter: boolean | null;
  registered_voter_status: string;
  registered_voter_location_note: string | null;
  registered_voter: boolean;
  current_gec_match?: boolean;
  wants_to_volunteer: boolean;
  needs_absentee_ballot_help: boolean;
  needs_homebound_voting_help: boolean;
  needs_voter_registration_help: boolean;
  needs_election_day_ride: boolean;
  referred_by_name: string | null;
  opt_in_email: boolean;
  opt_in_text: boolean;
  verification_status: string;
  contact_classification: string;
  referred_from_village_id?: number | null;
  referred_from_village_name?: string | null;
  verification_reason?: string | null;
  verification_reason_label?: string | null;
  verification_reason_detail?: string | null;
  verification_reason_metadata?: Record<string, unknown> | null;
  verification_reason_derived?: boolean;
  verified_at: string | null;
  verified_by_user_id: number | null;
  potential_duplicate: boolean;
  duplicate_of_id: number | null;
  duplicate_notes: string | null;
  intake_status: string;
  review_status: string;
  public_review_status: string;
  reviewed_at?: string | null;
  reviewed_by_user_id?: number | null;
  public_reviewed_at?: string | null;
  public_reviewed_by_user_id?: number | null;
  registration_outreach_status: string | null;
  registration_outreach_notes: string | null;
  registration_outreach_date: string | null;
  support_follow_up_status: string | null;
  support_follow_up_notes: string | null;
  support_follow_up_date: string | null;
  source: string;
  attribution_method?: string | null;
  status: string;
  leader_code?: string | null;
  referral_code_id?: number | null;
  referral_display_name?: string | null;
  created_at: string;
  household_group_id?: number | null;
  household_primary?: boolean;
  household_member_count?: number;
  household_members?: Array<{
    id: number;
    first_name: string;
    middle_name?: string | null;
    last_name: string;
    print_name: string;
    village_name?: string | null;
    registered_voter_status?: string | null;
    review_status: string;
    public_review_status: string;
  }>;
}

interface AuditLogItem {
  id: number;
  action: string;
  action_label?: string;
  actor_name?: string;
  actor_role?: string;
  changed_data: Record<string, unknown>;
  created_at: string;
}

interface SupporterPermissions {
  can_edit: boolean;
}

const AUDIT_FIELD_LABELS: Record<string, string> = {
  id: 'Record ID',
  first_name: 'First Name',
  middle_name: 'Middle Name',
  last_name: 'Last Name',
  print_name: 'Name',
  contact_number: 'Phone',
  email: 'Email',
  dob: 'Date of birth',
  street_address: 'Street address',
  village_id: 'Village ID',
  precinct_id: 'Precinct ID',
  source: 'Source',
  contact_classification: 'Classification',
  intake_status: 'Supporter status',
  review_status: 'Review status',
  public_review_status: 'Public review status',
  leader_code: 'Referral code',
  status: 'Status',
  verification_status: 'Verification status',
  attribution_method: 'Entry method',
  referral_code_id: 'Referrer',
  self_reported_registered_voter: 'Self-reported registered voter',
  registered_voter_status: 'Self-reported voter status',
  registered_voter_location_note: 'Votes elsewhere note',
  registered_voter: 'GEC found registered voter',
  wants_to_volunteer: 'Volunteer request',
  needs_absentee_ballot_help: 'Absentee ballot help',
  needs_homebound_voting_help: 'Homebound help',
  needs_voter_registration_help: 'Registration help',
  needs_election_day_ride: 'Ride to polls',
  referred_by_name: 'Referred by',
  registration_outreach_status: 'Registration follow-up result',
  registration_outreach_notes: 'Registration follow-up notes',
  support_follow_up_status: 'Support follow-up progress',
  support_follow_up_notes: 'Support follow-up notes',
  opt_in_email: 'Opt-in email',
  opt_in_text: 'Opt-in text',
  created_at: 'Created at',
  resolution: 'Duplicate resolution',
  merge_into_id: 'Merged into supporter',
  merged_supporter_id: 'Merged duplicate supporter',
};

const AUDIT_VALUE_LABELS: Record<string, Record<string, string>> = {
  source: {
    qr_signup: 'QR signup',
    staff_entry: 'Staff entry',
    bulk_import: 'Bulk import',
    referral: 'Referral',
    public_signup: 'Public signup',
  },
  status: {
    active: 'Active',
    inactive: 'Inactive',
    duplicate: 'Duplicate',
    unverified: 'Needs review',
    removed: 'Removed',
  },
  verification_status: {
    unverified: 'Needs voter review',
    verified: 'Matched to GEC',
    flagged: 'Flagged for review',
  },
  attribution_method: {
    qr_self_signup: 'Referred (QR)',
    staff_manual: 'Entered manually',
    staff_scan: 'Entered via scan',
    bulk_import: 'Imported',
    public_signup: 'Public signup',
  },
  intake_status: {
    accepted: 'Accepted',
    pending_public_review: 'Pending public review',
  },
  registered_voter_status: {
    yes: 'Yes',
    no: 'No',
    not_sure: 'Not sure',
  },
  review_status: {
    pending: 'Pending review',
    approved: 'Approved',
    rejected: 'Rejected',
  },
  contact_classification: {
    new_intake: 'New intake',
    active_contact: 'Active contact',
    supporter: 'Supporter',
    member: 'Member',
    volunteer: 'Volunteer',
    undecided: 'Undecided',
    not_supporting: 'Not supporting',
    duplicate: 'Duplicate',
    invalid: 'Invalid',
    archived: 'Archived',
  },
  public_review_status: {
    not_applicable: 'Not applicable',
    pending: 'Pending public review',
    approved: 'Approved in public review',
    rejected: 'Rejected in public review',
  },
  resolution: {
    dismiss: 'Not a duplicate',
    merge: 'Merged duplicate',
  },
};

const TECHNICAL_AUDIT_FIELDS = new Set([ 'id', 'normalized_phone', 'merge_into_id' ]);
const PRIMARY_AUDIT_FIELD_ORDER = [
  'merged_supporter_id',
  'verification_status',
  'status',
  'attribution_method',
  'source',
  'village_id',
  'precinct_id',
  'first_name',
  'middle_name',
  'last_name',
  'print_name',
  'contact_number',
  'email',
  'street_address',
  'self_reported_registered_voter',
  'registered_voter_status',
  'registered_voter_location_note',
  'registered_voter',
  'wants_to_volunteer',
  'needs_absentee_ballot_help',
  'needs_homebound_voting_help',
  'needs_voter_registration_help',
  'needs_election_day_ride',
  'referred_by_name',
  'opt_in_text',
  'opt_in_email',
  'dob',
];

function humanizeRole(role?: string) {
  return role ? role.replaceAll('_', ' ') : 'public/system';
}

function humanizeAuditValue(value: unknown, field?: string) {
  if (value === null || value === undefined || value === '') return 'empty';
  if (typeof value === 'boolean') return value ? 'Yes' : 'No';
  if (typeof value === 'string') {
    if (field && AUDIT_VALUE_LABELS[field]?.[value]) {
      return AUDIT_VALUE_LABELS[field][value];
    }
    if (value.includes('T') && !Number.isNaN(new Date(value).getTime())) return formatDateTime(value);
    if (/^\d{4}-\d{2}-\d{2}$/.test(value)) {
      const parsed = new Date(`${value}T00:00:00`);
      if (!Number.isNaN(parsed.getTime())) {
        return new Intl.DateTimeFormat('en-US', {
          month: 'short',
          day: 'numeric',
          year: 'numeric',
        }).format(parsed);
      }
    }
    if (value.includes('_')) return value.replaceAll('_', ' ');
  }

  return String(value);
}

function auditDiffParts(diff: unknown): { from: unknown; to: unknown } {
  if (diff && typeof diff === 'object' && !Array.isArray(diff) && ('from' in diff || 'to' in diff)) {
    const record = diff as { from?: unknown; to?: unknown };
    return { from: record.from, to: record.to };
  }

  return { from: null, to: diff };
}

function isEmptyAuditValue(value: unknown) {
  return value === null || value === undefined || value === '';
}

function isMeaningfulAuditDiff(diff: unknown) {
  const normalized = auditDiffParts(diff);
  if (isEmptyAuditValue(normalized.from) && isEmptyAuditValue(normalized.to)) return false;
  return normalized.from !== normalized.to;
}

function auditFieldLabel(field: string) {
  return AUDIT_FIELD_LABELS[field] || field.replaceAll('_', ' ');
}

function verificationStatusLabel(supporter: Pick<SupporterDetail, 'verification_status' | 'registered_voter' | 'referred_from_village_id' | 'submitted_village_referral' | 'verification_reason_label'>) {
  if (supporter.verification_reason_label) return supporter.verification_reason_label;
  if (supporter.verification_status === 'verified') return 'Matched to GEC';
  if (supporter.submitted_village_referral) return 'Village Referral';
  // Keep this branch for cross-village GEC matches that were not submitted as
  // referral records; both states share the same reviewer-facing label.
  if (supporter.referred_from_village_id) return 'Village Referral';
  if (supporter.verification_status === 'flagged') return 'Flagged for review';
  if (supporter.verification_status === 'unverified' && !supporter.registered_voter) return 'No GEC Match';
  return 'Needs voter review';
}

function verificationStatusDetail(supporter: Pick<SupporterDetail, 'verification_status' | 'registered_voter' | 'referred_from_village_id' | 'submitted_village_referral' | 'submitted_village_name' | 'village_name' | 'referred_from_village_name' | 'verification_reason_detail'>) {
  if (supporter.verification_reason_detail) {
    return supporter.verification_reason_detail;
  }
  if (supporter.verification_status === 'verified') {
    return 'This supporter has a current GEC match and can be treated as matched to the voter list.';
  }
  if (supporter.submitted_village_referral) {
    const base = `This supporter was originally submitted under ${supporter.submitted_village_name || 'Unknown'}, but is currently assigned to ${supporter.village_name || 'Unknown'}.`;
    if (supporter.referred_from_village_id && supporter.referred_from_village_name) {
      return `${base} Their current GEC match is in ${supporter.referred_from_village_name}.`;
    }
    return base;
  }
  if (supporter.referred_from_village_id) {
    if (supporter.village_name && supporter.referred_from_village_name) {
      return `This supporter is currently assigned to ${supporter.village_name}, but the current GEC match is in ${supporter.referred_from_village_name}.`;
    }
    if (supporter.referred_from_village_name) {
      return `This supporter matched a current GEC voter in ${supporter.referred_from_village_name}, so staff should review the village assignment.`;
    }
    return 'This supporter appears to be registered in a different village and should be reviewed by staff.';
  }
  if (supporter.verification_status === 'flagged') {
    return 'This supporter needs voter-check follow-up before staff should treat the match as confirmed.';
  }
  if (supporter.verification_status === 'unverified' && !supporter.registered_voter) {
    return 'This supporter was not found in the current voter list.';
  }
  return 'This supporter still needs voter-check review.';
}

function isNoGecMatch(supporter: Pick<SupporterDetail, 'verification_status' | 'registered_voter' | 'referred_from_village_id'>) {
  return supporter.verification_status === 'unverified' && !supporter.registered_voter && !supporter.referred_from_village_id;
}

function assignmentHistoryDetail(supporter: Pick<SupporterDetail, 'submitted_village_name' | 'village_name'>) {
  const submittedVillage = supporter.submitted_village_name || 'Unknown';
  const currentVillage = supporter.village_name || 'Unknown';
  const statusLabel = 'Referral active';

  return [
    { label: 'Original submission village', value: submittedVillage },
    { label: 'Current assignment', value: currentVillage },
    { label: 'Assignment status', value: statusLabel },
  ];
}

function hasAssignmentHistory(supporter: Pick<SupporterDetail, 'submitted_village_referral'>) {
  return supporter.submitted_village_referral === true;
}

function isPublicOrigin(supporter: Pick<SupporterDetail, 'source'>) {
  return supporter.source === 'public_signup' || supporter.source === 'qr_signup';
}

function isPendingPublicSignup(supporter: Pick<SupporterDetail, 'source' | 'public_review_status'>) {
  return isPublicOrigin(supporter) && supporter.public_review_status === 'pending';
}

function isApprovedPublicSignup(supporter: Pick<SupporterDetail, 'source' | 'review_status' | 'public_review_status'>) {
  return isPublicOrigin(supporter) && supporter.public_review_status === 'approved' && supporter.review_status === 'approved';
}

function supporterStatusLabel(supporter: Pick<SupporterDetail, 'source' | 'review_status' | 'public_review_status'>) {
  if (isPendingPublicSignup(supporter)) return 'Pending public review';
  if (supporter.review_status === 'pending') return 'Pending review';
  if (supporter.review_status === 'rejected') return 'Rejected submission';
  if (isApprovedPublicSignup(supporter)) return 'Accepted public contact';
  if (supporter.source === 'staff_entry') return 'Staff-entered contact';
  if (supporter.source === 'bulk_import') return 'Imported contact';
  return 'Accepted contact';
}

function supporterStatusDetail(supporter: Pick<SupporterDetail, 'source' | 'review_status' | 'public_review_status'>) {
  if (isPendingPublicSignup(supporter)) {
    return 'This contact came from the public signup form and is waiting for intake review.';
  }
  if (supporter.review_status === 'pending') {
    return 'This submission is waiting for review before it joins the active contact workspace.';
  }
  if (supporter.review_status === 'rejected') {
    return 'This submission was rejected and is kept only for audit and possible follow-up.';
  }
  if (isApprovedPublicSignup(supporter)) {
    return 'This contact came from the public signup form and is available for DPG follow-up.';
  }
  if (supporter.source === 'staff_entry') {
    return 'This contact was entered by staff and is available for DPG follow-up.';
  }
  if (supporter.source === 'bulk_import') {
    return 'This contact was added through an import and is available for DPG follow-up.';
  }
  return 'This contact is part of the DPG contact workspace.';
}

const CONTACT_CLASSIFICATION_OPTIONS = [
  { value: 'new_intake', label: 'New intake' },
  { value: 'active_contact', label: 'Active contact' },
  { value: 'supporter', label: 'Supporter' },
  { value: 'member', label: 'Member' },
  { value: 'volunteer', label: 'Volunteer' },
  { value: 'undecided', label: 'Undecided' },
  { value: 'not_supporting', label: 'Not supporting' },
] as const;

function contactClassificationLabel(status?: string | null) {
  return CONTACT_CLASSIFICATION_OPTIONS.find((entry) => entry.value === status)?.label || 'Contact';
}

function contactClassificationClass(status?: string | null) {
  switch (status) {
    case 'new_intake':
      return 'bg-amber-100 text-amber-700';
    case 'active_contact':
      return 'bg-blue-100 text-blue-700';
    case 'supporter':
      return 'bg-green-100 text-green-700';
    case 'member':
      return 'bg-emerald-100 text-emerald-700';
    case 'volunteer':
      return 'bg-indigo-100 text-indigo-700';
    case 'undecided':
      return 'bg-slate-100 text-slate-700';
    case 'not_supporting':
      return 'bg-red-100 text-red-700';
    default:
      return 'bg-gray-100 text-gray-700';
  }
}

function activitySourceLabel(supporter: Pick<SupporterDetail, 'source' | 'attribution_method'>) {
  if (supporter.source === 'public_signup' || supporter.source === 'qr_signup') return 'Public signup';
  if (supporter.attribution_method === 'staff_scan') return 'Staff scan';
  if (supporter.source === 'staff_entry') return 'Staff entry';
  if (supporter.source === 'bulk_import') return 'Excel import';
  return supporter.source === 'referral' ? 'Referral' : 'Supporter record';
}

function activityActionLabel(supporter: Pick<SupporterDetail, 'source' | 'attribution_method'>) {
  if (supporter.source === 'public_signup' || supporter.source === 'qr_signup') return 'Signed up';
  if (supporter.attribution_method === 'staff_scan' || supporter.source === 'staff_entry') return 'Entered';
  if (supporter.source === 'bulk_import') return 'Imported';
  return 'Created';
}

function fullName(supporter: Pick<SupporterDetail, 'first_name' | 'middle_name' | 'last_name'>) {
  return [ supporter.first_name, supporter.middle_name, supporter.last_name ].filter(Boolean).join(' ');
}

function selfReportedRegisteredStatusLabel(status?: string | null, fallback?: boolean | null) {
  if (status === 'yes') return 'Yes';
  if (status === 'no') return 'No';
  if (status === 'not_sure') return 'Not sure';
  if (fallback === true) return 'Yes';
  if (fallback === false) return 'No';
  return 'Not sure';
}

function supportRequestBadges(supporter: Pick<SupporterDetail, 'needs_voter_registration_help' | 'needs_absentee_ballot_help' | 'needs_homebound_voting_help' | 'needs_election_day_ride' | 'wants_to_volunteer'>) {
  const badges: string[] = [];
  if (supporter.needs_voter_registration_help) badges.push('Registration Help');
  if (supporter.needs_absentee_ballot_help) badges.push('Absentee Help');
  if (supporter.needs_homebound_voting_help) badges.push('Homebound Help');
  if (supporter.needs_election_day_ride) badges.push('Ride To Polls');
  if (supporter.wants_to_volunteer) badges.push('Volunteer');
  return badges;
}

function hasSupportServiceFollowUp(supporter: Pick<SupporterDetail, 'needs_absentee_ballot_help' | 'needs_homebound_voting_help' | 'needs_election_day_ride' | 'wants_to_volunteer'>) {
  return supporter.needs_absentee_ballot_help || supporter.needs_homebound_voting_help || supporter.needs_election_day_ride || supporter.wants_to_volunteer;
}

function registrationFollowUpStatusLabel(status?: string | null) {
  if (status === 'registered') return 'Registered via follow-up';
  if (status === 'contacted') return 'Contacted';
  if (status === 'declined') return 'Declined';
  return 'Not contacted';
}

function registrationFollowUpStatusClass(status?: string | null) {
  if (status === 'registered') return 'bg-green-100 text-green-700';
  if (status === 'contacted') return 'bg-blue-100 text-blue-700';
  if (status === 'declined') return 'bg-red-100 text-red-700';
  return 'bg-gray-100 text-gray-600';
}

function supportFollowUpStatusLabel(status?: string | null) {
  if (status === 'in_progress') return 'In progress';
  if (status === 'completed') return 'Completed';
  if (status === 'declined') return 'Declined';
  return 'Not started';
}

function supportFollowUpStatusClass(status?: string | null) {
  if (status === 'completed') return 'bg-green-100 text-green-700';
  if (status === 'in_progress') return 'bg-blue-100 text-blue-700';
  if (status === 'declined') return 'bg-red-100 text-red-700';
  return 'bg-gray-100 text-gray-600';
}

function supportDetailBackLabel(returnTo: string) {
  if (returnTo.includes('/villages/')) return 'Back to Village';
  if (returnTo.includes('/supporters')) return 'Back to Supporters';
  return 'Back';
}

function detailFlagChips(flags: Array<{ label: string; active: boolean; tone?: 'blue' | 'amber' | 'indigo' | 'green' }>) {
  const toneClass = {
    blue: 'bg-blue-100 text-blue-700',
    amber: 'bg-amber-100 text-amber-800',
    indigo: 'bg-indigo-100 text-indigo-700',
    green: 'bg-green-100 text-green-700',
  } as const;

  return flags
    .filter((flag) => flag.active)
    .map((flag) => ({
      label: flag.label,
      className: toneClass[flag.tone || 'blue'],
    }));
}

export default function SupporterDetailPage() {
  const { id } = useParams();
  const location = useLocation();
  const [searchParams] = useSearchParams();
  const supporterId = Number(id);
  const queryClient = useQueryClient();

  const { data, isLoading, refetch } = useQuery({
    queryKey: ['supporter', supporterId],
    queryFn: () => getSupporter(supporterId),
    enabled: Number.isFinite(supporterId),
  });
  const { data: villagesData } = useQuery({
    queryKey: ['villages'],
    queryFn: getVillages,
  });

  const supporter: SupporterDetail | undefined = data?.supporter;
  const permissions: SupporterPermissions | undefined = data?.permissions;
  const auditLogs: AuditLogItem[] = data?.audit_logs || [];
  const returnTo = searchParams.get('return_to') || '';
  const villages: VillageOption[] = useMemo(() => villagesData?.villages || [], [villagesData]);
  const villageNameById = useMemo(
    () => new Map(villages.map((village) => [ village.id, village.name ])),
    [villages]
  );
  const precinctNameById = useMemo(
    () => new Map(villages.flatMap((village) => village.precincts.map((precinct) => [ precinct.id, `${village.name} · ${precinct.number}` ]))),
    [villages]
  );

  const [isEditing, setIsEditing] = useState(false);
  const [draft, setDraft] = useState<Partial<SupporterDetail> | null>(null);
  const canEdit = permissions?.can_edit ?? false;
  const canMarkVerifiedVoter = supporter ? !isNoGecMatch(supporter) : false;
  const supporterDetailPath = (targetId: number) => {
    const basePath = '/admin/supporters';
    const nextReturnTo = `${location.pathname}${location.search}`;
    return `${basePath}/${targetId}?return_to=${encodeURIComponent(nextReturnTo)}`;
  };

  const baseForm = useMemo(() => {
    if (!supporter) return null;
    return {
      first_name: supporter.first_name,
      middle_name: supporter.middle_name || '',
      last_name: supporter.last_name,
      contact_number: supporter.contact_number,
      email: supporter.email || '',
      dob: supporter.dob || '',
      street_address: supporter.street_address || '',
      village_id: supporter.village_id,
      precinct_id: supporter.precinct_id,
      self_reported_registered_voter: supporter.self_reported_registered_voter,
      registered_voter_status: supporter.registered_voter_status,
      registered_voter_location_note: supporter.registered_voter_location_note || '',
      registered_voter: supporter.registered_voter,
      contact_classification: supporter.contact_classification,
      wants_to_volunteer: supporter.wants_to_volunteer,
      needs_absentee_ballot_help: supporter.needs_absentee_ballot_help,
      needs_homebound_voting_help: supporter.needs_homebound_voting_help,
      needs_voter_registration_help: supporter.needs_voter_registration_help,
      needs_election_day_ride: supporter.needs_election_day_ride,
      referred_by_name: supporter.referred_by_name || '',
      opt_in_email: supporter.opt_in_email,
      opt_in_text: supporter.opt_in_text,
    };
  }, [supporter]);

  const currentForm = isEditing ? (draft || baseForm) : baseForm;
  const isDirty = useMemo(() => {
    if (!isEditing || !baseForm) return false;
    return JSON.stringify(draft || baseForm) !== JSON.stringify(baseForm);
  }, [isEditing, baseForm, draft]);

  const selectedVillage = useMemo(
    () => villages.find((v) => v.id === Number(currentForm?.village_id)),
    [villages, currentForm?.village_id]
  );

  const saveMutation = useMutation({
    mutationFn: (payload: Record<string, unknown>) => updateSupporter(supporterId, payload),
    onSuccess: () => {
      setDraft(null);
      setIsEditing(false);
      queryClient.invalidateQueries({ queryKey: ['supporter', supporterId] });
      queryClient.invalidateQueries({ queryKey: ['supporters'] });
      queryClient.invalidateQueries({ queryKey: ['village'] });
      queryClient.invalidateQueries({ queryKey: ['dashboard'] });
    },
  });


  useEffect(() => {
    if (!isEditing || !isDirty) return;
    const onBeforeUnload = (event: BeforeUnloadEvent) => {
      event.preventDefault();
      event.returnValue = '';
    };
    window.addEventListener('beforeunload', onBeforeUnload);
    return () => window.removeEventListener('beforeunload', onBeforeUnload);
  }, [isEditing, isDirty]);

  const confirmDiscardIfNeeded = () => {
    if (!isEditing || !isDirty) return true;
    return window.confirm('You have unsaved changes. Discard them?');
  };

  const startEdit = () => {
    if (!canEdit) return;
    if (!baseForm) return;
    setDraft(baseForm);
    setIsEditing(true);
  };

  const cancelEdit = () => {
    if (!confirmDiscardIfNeeded()) return;
    setDraft(null);
    setIsEditing(false);
  };

  const updateDraft = (patch: Partial<SupporterDetail>) => {
    if (!isEditing || !currentForm) return;
    setDraft((prev) => ({ ...(prev || currentForm), ...patch }));
  };

  if (isLoading || !supporter || !currentForm) {
    return <div className="min-h-screen flex items-center justify-center text-[var(--text-muted)]">Loading supporter...</div>;
  }

  return (
    <WorkspacePage width="full" className="space-y-6">
      <div>
        {returnTo && (
          <Link
            to={returnTo}
            className="inline-flex items-center gap-1.5 text-sm text-gray-500 hover:text-gray-900 mb-3"
          >
            <ChevronLeft className="w-4 h-4" />
            {supportDetailBackLabel(returnTo)}
          </Link>
        )}
        <h1 className="text-2xl font-bold text-gray-900 tracking-tight flex items-center gap-2">
          <UserRound className="w-5 h-5 text-primary" /> {fullName(supporter)}
        </h1>
        <p className="text-gray-500 text-sm">
          {activityActionLabel(supporter)} {formatDateTime(supporter.created_at)} · {activitySourceLabel(supporter)}
        </p>
        <div className="flex items-center gap-2 mt-1">
          <span className={`inline-block px-2 py-0.5 rounded-full text-xs font-medium ${contactClassificationClass(supporter.contact_classification)}`}>
            {contactClassificationLabel(supporter.contact_classification)}
          </span>
          <span className={`inline-block px-2 py-0.5 rounded-full text-xs font-medium ${
            supporter.verification_status === 'verified' ? 'bg-green-100 text-green-800' :
            supporter.verification_status === 'flagged' ? 'bg-red-100 text-red-800' :
            'bg-yellow-100 text-yellow-800'
          }`}>
            {verificationStatusLabel(supporter)}
          </span>
          {supporter.status === 'removed' && (
            <span className="inline-block px-2 py-0.5 rounded-full text-xs font-medium bg-gray-200 text-gray-600">
              Removed
            </span>
          )}
        </div>
      </div>

      <div className="space-y-6">
        {supporter.potential_duplicate && (
          <div className="bg-amber-50 border border-amber-200 rounded-xl p-4 flex items-start gap-3">
            <AlertTriangle className="w-5 h-5 text-amber-500 flex-shrink-0 mt-0.5" />
            <div>
              <p className="font-medium text-amber-800">Potential Duplicate</p>
              <p className="text-sm text-amber-600 mt-0.5">
                {supporter.duplicate_notes || 'This supporter may be a duplicate of an existing record.'}
              </p>
              {supporter.duplicate_of_id && (
                <Link
                  to={supporterDetailPath(supporter.duplicate_of_id)}
                  className="text-sm text-primary hover:underline mt-1 inline-block"
                >
                  View possible match →
                </Link>
              )}
            </div>
          </div>
        )}

        <section className="app-card p-4">
          <div className="flex items-center justify-between gap-3 mb-3">
            <h2 className="font-semibold text-[var(--text-primary)]">Contact Details</h2>
            {!isEditing ? (
              canEdit && (
                <button
                  type="button"
                  onClick={startEdit}
                  className="bg-[var(--surface-raised)] border border-[var(--border-soft)] text-[var(--text-primary)] px-3 py-2 min-h-[44px] rounded-xl text-sm font-medium flex items-center gap-2 hover:bg-[var(--surface-bg)]"
                >
                  <Pencil className="w-4 h-4" /> Edit
                </button>
              )
            ) : (
              <div className="flex items-center gap-2">
                <button
                  type="button"
                  onClick={cancelEdit}
                  className="bg-[var(--surface-raised)] border border-[var(--border-soft)] text-[var(--text-primary)] px-3 py-2 min-h-[44px] rounded-xl text-sm font-medium flex items-center gap-2 hover:bg-[var(--surface-bg)]"
                >
                  <X className="w-4 h-4" /> Cancel
                </button>
                <button
                  type="button"
                  onClick={() => saveMutation.mutate(currentForm as Record<string, unknown>)}
                  disabled={saveMutation.isPending}
                  className="bg-primary text-white px-4 py-2 min-h-[44px] rounded-xl text-sm font-medium flex items-center gap-2 disabled:opacity-50"
                >
                  <Save className="w-4 h-4" /> {saveMutation.isPending ? 'Saving...' : 'Save Changes'}
                </button>
              </div>
            )}
          </div>
          {!canEdit && !isEditing && (
            <p className="mb-3 text-xs text-[var(--text-secondary)] italic">
              View only — editing requires party admin or district coordinator role.
            </p>
          )}
          <div className="grid md:grid-cols-3 gap-3">
            <input
              value={String(currentForm.first_name || '')}
              onChange={(e) => updateDraft({ first_name: e.target.value })}
              className="border border-[var(--border-soft)] rounded-xl px-3 py-2 disabled:bg-[var(--surface-bg)] disabled:text-[var(--text-primary)]"
              disabled={!isEditing}
              placeholder="First Name"
            />
            <input
              value={String(currentForm.middle_name || '')}
              onChange={(e) => updateDraft({ middle_name: e.target.value })}
              className="border border-[var(--border-soft)] rounded-xl px-3 py-2 disabled:bg-[var(--surface-bg)] disabled:text-[var(--text-primary)]"
              disabled={!isEditing}
              placeholder="Middle Name"
            />
            <input
              value={String(currentForm.last_name || '')}
              onChange={(e) => updateDraft({ last_name: e.target.value })}
              className="border border-[var(--border-soft)] rounded-xl px-3 py-2 disabled:bg-[var(--surface-bg)] disabled:text-[var(--text-primary)]"
              disabled={!isEditing}
              placeholder="Last Name"
            />
            <input
              value={String(currentForm.contact_number || '')}
              onChange={(e) => updateDraft({ contact_number: e.target.value })}
              className="border border-[var(--border-soft)] rounded-xl px-3 py-2 disabled:bg-[var(--surface-bg)] disabled:text-[var(--text-primary)]"
              disabled={!isEditing}
              placeholder="Phone Number"
            />
            <input
              value={String(currentForm.email || '')}
              onChange={(e) => updateDraft({ email: e.target.value })}
              className="border border-[var(--border-soft)] rounded-xl px-3 py-2 disabled:bg-[var(--surface-bg)] disabled:text-[var(--text-primary)]"
              disabled={!isEditing}
              placeholder="Email"
            />
            <input
              type="date"
              value={String(currentForm.dob || '')}
              onChange={(e) => updateDraft({ dob: e.target.value })}
              className="border border-[var(--border-soft)] rounded-xl px-3 py-2 disabled:bg-[var(--surface-bg)] disabled:text-[var(--text-primary)]"
              disabled={!isEditing}
            />
            <input
              value={String(currentForm.street_address || '')}
              onChange={(e) => updateDraft({ street_address: e.target.value })}
              className="border border-[var(--border-soft)] rounded-xl px-3 py-2 md:col-span-2 disabled:bg-[var(--surface-bg)] disabled:text-[var(--text-primary)]"
              disabled={!isEditing}
              placeholder="Street Address"
            />
            <select
              value={String(currentForm.village_id || '')}
              onChange={(e) => {
                const nextVillageId = Number(e.target.value);
                const nextVillage = villages.find((v) => v.id === nextVillageId);
                const nextPrecinctId = assignPrecinctIdByLastName(currentForm.last_name, nextVillage?.precincts || []);

                updateDraft({
                  village_id: nextVillageId,
                  precinct_id: nextPrecinctId,
                });
              }}
              className="border border-[var(--border-soft)] rounded-xl px-3 py-2 bg-[var(--surface-raised)] disabled:bg-[var(--surface-bg)] disabled:text-[var(--text-primary)]"
              disabled={!isEditing}
            >
              {villages.map((v) => (
                <option key={v.id} value={v.id}>{v.name}</option>
              ))}
            </select>
            <select
              value={currentForm.precinct_id ? String(currentForm.precinct_id) : ''}
              onChange={(e) => updateDraft({ precinct_id: e.target.value ? Number(e.target.value) : null })}
              className="border border-[var(--border-soft)] rounded-xl px-3 py-2 bg-[var(--surface-raised)] disabled:bg-[var(--surface-bg)] disabled:text-[var(--text-primary)]"
              disabled={!isEditing}
            >
              <option value="">Not assigned</option>
              {(selectedVillage?.precincts || []).map((p) => (
                <option key={p.id} value={p.id}>Precinct {p.number} ({p.alpha_range})</option>
              ))}
            </select>
            <select
              value={String(currentForm.contact_classification || 'new_intake')}
              onChange={(e) => updateDraft({ contact_classification: e.target.value })}
              className="border border-[var(--border-soft)] rounded-xl px-3 py-2 bg-[var(--surface-raised)] disabled:bg-[var(--surface-bg)] disabled:text-[var(--text-primary)]"
              disabled={!isEditing}
            >
              {CONTACT_CLASSIFICATION_OPTIONS.map((option) => (
                <option key={option.value} value={option.value}>{option.label}</option>
              ))}
            </select>
            <select
              value={String(currentForm.registered_voter_status || 'not_sure')}
              onChange={(e) => updateDraft({
                registered_voter_status: e.target.value,
                self_reported_registered_voter: e.target.value === 'yes' ? true : e.target.value === 'no' ? false : null,
                registered_voter_location_note: e.target.value === 'yes' ? currentForm.registered_voter_location_note : '',
              })}
              className="border border-[var(--border-soft)] rounded-xl px-3 py-2 bg-[var(--surface-raised)] disabled:bg-[var(--surface-bg)] disabled:text-[var(--text-primary)]"
              disabled={!isEditing}
            >
              <option value="yes">Self-reported voter: Yes</option>
              <option value="no">Self-reported voter: No</option>
              <option value="not_sure">Self-reported voter: Not sure</option>
            </select>
            <input
              value={String(currentForm.registered_voter_location_note || '')}
              onChange={(e) => updateDraft({ registered_voter_location_note: e.target.value })}
              className="border border-[var(--border-soft)] rounded-xl px-3 py-2 md:col-span-2 disabled:bg-[var(--surface-bg)] disabled:text-[var(--text-primary)]"
              disabled={!isEditing || currentForm.registered_voter_status !== 'yes'}
              placeholder="Votes elsewhere note"
            />
            <input
              value={String(currentForm.referred_by_name || '')}
              onChange={(e) => updateDraft({ referred_by_name: e.target.value })}
              className="border border-[var(--border-soft)] rounded-xl px-3 py-2 disabled:bg-[var(--surface-bg)] disabled:text-[var(--text-primary)]"
              disabled={!isEditing}
              placeholder="Referred by"
            />
          </div>

          {isEditing ? (
            <>
              <div className="flex flex-wrap gap-4 mt-3 text-sm text-[var(--text-primary)]">
                <label className="flex items-center gap-2">
                  <input
                    type="checkbox"
                    checked={Boolean(currentForm.self_reported_registered_voter)}
                    onChange={(e) => updateDraft({ self_reported_registered_voter: e.target.checked })}
                    disabled={!isEditing}
                  />
                  Self-reported registered voter
                </label>
                
                
                <label className="flex items-center gap-2">
                  <input
                    type="checkbox"
                    checked={Boolean(currentForm.needs_voter_registration_help)}
                    onChange={(e) => updateDraft({ needs_voter_registration_help: e.target.checked })}
                    disabled={!isEditing}
                  />
                  Registration help
                </label>
                <label className="flex items-center gap-2">
                  <input
                    type="checkbox"
                    checked={Boolean(currentForm.needs_absentee_ballot_help)}
                    onChange={(e) => updateDraft({ needs_absentee_ballot_help: e.target.checked })}
                    disabled={!isEditing}
                  />
                  Absentee help
                </label>
                <label className="flex items-center gap-2">
                  <input
                    type="checkbox"
                    checked={Boolean(currentForm.needs_homebound_voting_help)}
                    onChange={(e) => updateDraft({ needs_homebound_voting_help: e.target.checked })}
                    disabled={!isEditing}
                  />
                  Homebound help
                </label>
                <label className="flex items-center gap-2">
                  <input
                    type="checkbox"
                    checked={Boolean(currentForm.needs_election_day_ride)}
                    onChange={(e) => updateDraft({ needs_election_day_ride: e.target.checked })}
                    disabled={!isEditing}
                  />
                  Ride to polls
                </label>
                <label className="flex items-center gap-2">
                  <input
                    type="checkbox"
                    checked={Boolean(currentForm.wants_to_volunteer)}
                    onChange={(e) => updateDraft({ wants_to_volunteer: e.target.checked })}
                    disabled={!isEditing}
                  />
                  Volunteer
                </label>
              </div>
              <div className="flex flex-wrap gap-4 mt-3 pt-3 border-t border-[var(--border-soft)]">
                <label className="flex items-center gap-2">
                  <input
                    type="checkbox"
                    checked={Boolean(currentForm.opt_in_text)}
                    onChange={(e) => updateDraft({ opt_in_text: e.target.checked })}
                    disabled={!isEditing}
                  />
                  Text updates
                </label>
                <label className="flex items-center gap-2">
                  <input
                    type="checkbox"
                    checked={Boolean(currentForm.opt_in_email)}
                    onChange={(e) => updateDraft({ opt_in_email: e.target.checked })}
                    disabled={!isEditing}
                  />
                  Email updates
                </label>
              </div>
            </>
          ) : (
            <>
              <div className="mt-3 flex flex-wrap gap-2">
                {detailFlagChips([
                  { label: 'Self-reported registered voter', active: Boolean(currentForm.self_reported_registered_voter), tone: 'blue' },
                  { label: 'Registration help', active: Boolean(currentForm.needs_voter_registration_help), tone: 'amber' },
                  { label: 'Absentee help', active: Boolean(currentForm.needs_absentee_ballot_help), tone: 'amber' },
                  { label: 'Homebound help', active: Boolean(currentForm.needs_homebound_voting_help), tone: 'amber' },
                  { label: 'Ride to polls', active: Boolean(currentForm.needs_election_day_ride), tone: 'amber' },
                  { label: 'Volunteer', active: Boolean(currentForm.wants_to_volunteer), tone: 'green' },
                ]).map((flag) => (
                  <span key={flag.label} className={`inline-block rounded-full px-3 py-1 text-xs font-semibold ${flag.className}`}>
                    {flag.label}
                  </span>
                ))}
                {detailFlagChips([
                  { label: 'Self-reported registered voter', active: Boolean(currentForm.self_reported_registered_voter), tone: 'blue' },
                  { label: 'Registration help', active: Boolean(currentForm.needs_voter_registration_help), tone: 'amber' },
                  { label: 'Absentee help', active: Boolean(currentForm.needs_absentee_ballot_help), tone: 'amber' },
                  { label: 'Homebound help', active: Boolean(currentForm.needs_homebound_voting_help), tone: 'amber' },
                  { label: 'Ride to polls', active: Boolean(currentForm.needs_election_day_ride), tone: 'amber' },
                  { label: 'Volunteer', active: Boolean(currentForm.wants_to_volunteer), tone: 'green' },
                ]).length === 0 && (
                  <span className="text-sm text-[var(--text-secondary)]">No voter-help flags selected.</span>
                )}
              </div>
              <div className="mt-3 flex flex-wrap gap-2 border-t border-[var(--border-soft)] pt-3">
                {detailFlagChips([
                  { label: 'Text updates', active: Boolean(currentForm.opt_in_text), tone: 'blue' },
                  { label: 'Email updates', active: Boolean(currentForm.opt_in_email), tone: 'blue' },
                ]).map((flag) => (
                  <span key={flag.label} className={`inline-block rounded-full px-3 py-1 text-xs font-semibold ${flag.className}`}>
                    {flag.label}
                  </span>
                ))}
                {detailFlagChips([
                  { label: 'Text updates', active: Boolean(currentForm.opt_in_text), tone: 'blue' },
                  { label: 'Email updates', active: Boolean(currentForm.opt_in_email), tone: 'blue' },
                ]).length === 0 && (
                  <span className="text-sm text-[var(--text-secondary)]">No party updates selected.</span>
                )}
              </div>
            </>
          )}

          {hasAssignmentHistory(supporter) && (
            <div className="mt-4 rounded-xl border border-purple-200 bg-purple-50 px-4 py-3">
              <div className="flex flex-wrap items-center gap-2">
                <h3 className="text-sm font-semibold text-[var(--text-primary)]">Assignment History</h3>
                <span className="inline-block px-2 py-0.5 rounded-full text-xs font-medium bg-purple-100 text-purple-700">
                  Village Referral
                </span>
              </div>
              <div className="mt-3 grid gap-3 md:grid-cols-3">
                {assignmentHistoryDetail(supporter).map((item) => (
                  <div key={item.label}>
                    <p className="text-xs uppercase tracking-wide text-[var(--text-muted)]">{item.label}</p>
                    <p className="mt-1 text-sm font-medium text-[var(--text-primary)]">{item.value}</p>
                  </div>
                ))}
              </div>
              <p className="mt-3 text-sm text-purple-700">
                {supporter.review_status === 'approved'
                  ? 'This contact appears on the Referral List report as an approved referral.'
                  : 'This contact should appear on the Referral List report once reviewed.'}
              </p>
            </div>
          )}
        </section>

        <section className="app-card p-4">
          <h2 className="font-semibold text-[var(--text-primary)] mb-2">Contact Classification</h2>
          <div className="space-y-3">
            <div className="flex flex-wrap items-center gap-2">
              <span className="text-sm text-[var(--text-secondary)]">Current classification:</span>
              <span className={`inline-block px-3 py-1.5 rounded-full text-sm font-semibold ${contactClassificationClass(supporter.contact_classification)}`}>
                {contactClassificationLabel(supporter.contact_classification)}
              </span>
            </div>
            <p className="text-sm text-[var(--text-secondary)]">
              {supporterStatusLabel(supporter)}. {supporterStatusDetail(supporter)}
            </p>
          </div>
        </section>

        <section className="app-card p-4">
          <h2 className="font-semibold text-[var(--text-primary)] mb-2">Voter Check</h2>
          <div className="space-y-3">
            <div className="flex flex-wrap items-center gap-2">
              <span className="text-sm text-[var(--text-secondary)]">Current voter check:</span>
              <span className={`inline-block px-3 py-1.5 rounded-full text-sm font-semibold ${
                supporter.verification_status === 'verified' ? 'bg-green-100 text-green-700' :
                supporter.verification_status === 'flagged' ? 'bg-red-100 text-red-700' :
                'bg-yellow-100 text-yellow-800'
              }`}>
                {verificationStatusLabel(supporter)}
              </span>
              {supporter.status === 'removed' && (
                <span className="inline-block px-3 py-1.5 rounded-full text-sm font-semibold bg-gray-200 text-gray-700">
                  Removed
                </span>
              )}
            </div>
            <p className="text-sm text-[var(--text-secondary)]">
              {verificationStatusDetail(supporter)}
            </p>

            {canEdit && (
              <>
                <p className="text-sm text-[var(--text-secondary)]">Update voter check:</p>
                <div className="flex flex-wrap items-center gap-2">
                  {canMarkVerifiedVoter && (
                    <button
                      type="button"
                      disabled={supporter.verification_status === 'verified'}
                      onClick={async () => {
                        try {
                          await verifySupporter(supporter.id, 'verified');
                          refetch();
                        } catch {
                          alert('Failed to mark supporter as matched to GEC. A current GEC match is required.');
                        }
                      }}
                      className="min-h-[40px] px-3.5 py-2 bg-green-600 text-white text-sm font-medium rounded-lg hover:bg-green-700 disabled:opacity-50 disabled:cursor-not-allowed"
                    >
                      Mark Matched To GEC
                    </button>
                  )}
                  <button
                    type="button"
                    disabled={supporter.verification_status === 'flagged'}
                    onClick={async () => {
                      try {
                        await verifySupporter(supporter.id, 'flagged');
                        refetch();
                      } catch {
                        alert('Failed to flag supporter. You may not have permission.');
                      }
                    }}
                    className="min-h-[40px] px-3.5 py-2 bg-red-600 text-white text-sm font-medium rounded-lg hover:bg-red-700 disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    Flag For Review
                  </button>
                  <button
                    type="button"
                    disabled={supporter.verification_status === 'unverified'}
                    onClick={async () => {
                      try {
                        await verifySupporter(supporter.id, 'unverified');
                        refetch();
                      } catch {
                        alert('Failed to reset verification. You may not have permission.');
                      }
                    }}
                    className="min-h-[40px] px-3.5 py-2 border border-[var(--border-soft)] text-[var(--text-primary)] text-sm font-medium rounded-lg hover:bg-[var(--surface-bg)] disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    Reset Voter Check
                  </button>
                </div>

                {!canMarkVerifiedVoter && (
                  <p className="text-xs text-[var(--text-secondary)]">
                    Marking someone as matched to GEC is only available when the contact has a current GEC match. This contact can still stay in DPG's workspace for follow-up.
                  </p>
                )}

                <div className="pt-1">
                  {supporter.status !== 'removed' ? (
                    <button
                      type="button"
                      onClick={async () => {
                        if (!window.confirm('Remove this supporter? They will be excluded from all counts but kept in the audit log.')) return;
                        try {
                          await updateSupporter(supporter.id, { status: 'removed' });
                          refetch();
                        } catch {
                          alert('Failed to remove supporter.');
                        }
                      }}
                      className="min-h-[40px] px-3.5 py-2 bg-red-50 border border-red-300 text-red-700 text-sm font-medium rounded-lg hover:bg-red-100"
                    >
                      Remove from active list
                    </button>
                  ) : (
                    <button
                      type="button"
                      onClick={async () => {
                        try {
                          await updateSupporter(supporter.id, { status: 'active' });
                          refetch();
                        } catch {
                          alert('Failed to restore supporter.');
                        }
                      }}
                      className="min-h-[40px] px-3.5 py-2 bg-blue-50 border border-blue-300 text-blue-700 text-sm font-medium rounded-lg hover:bg-blue-100"
                    >
                      Restore to active list
                    </button>
                  )}
                </div>
              </>
            )}

            {canEdit && (
              <p className="text-xs text-[var(--text-secondary)]">
                Contact classification and voter check are tracked separately. Classification describes the relationship to DPG, while voter check shows whether the person matched the current voter list.
              </p>
            )}
          </div>
          {supporter.verified_at && (
            <p className="text-xs text-[var(--text-muted)] mt-2">
              Voter check last updated: {formatDateTime(supporter.verified_at)}
            </p>
          )}
        </section>

        <section className="app-card p-4">
          <h2 className="font-semibold text-[var(--text-primary)] mb-2">Follow-Up Workflow</h2>
          <div className="space-y-3">
            {supporter.registration_outreach_status === 'registered' && (
              <div className="rounded-xl border border-green-200 bg-green-50 px-4 py-3">
                <p className="text-sm font-semibold text-green-800">Registered via follow-up</p>
                <p className="mt-1 text-sm text-green-700">
                  This supporter was not matched in the current imported GEC list, but staff marked them as registered after party follow-up.
                </p>
              </div>
            )}
            <div className="flex flex-wrap items-center gap-2">
              <span className="text-sm text-[var(--text-secondary)]">Self-reported registered voter:</span>
              <span className={`inline-block px-3 py-1.5 rounded-full text-sm font-semibold ${
                supporter.registered_voter_status === 'yes' ? 'bg-blue-100 text-blue-700' : supporter.registered_voter_status === 'no' ? 'bg-gray-100 text-gray-700' : 'bg-amber-100 text-amber-800'
              }`}>
                {selfReportedRegisteredStatusLabel(supporter.registered_voter_status, supporter.self_reported_registered_voter)}
              </span>
            </div>
            {supporter.registered_voter_location_note && (
              <div>
                <span className="text-sm text-[var(--text-secondary)]">Votes elsewhere note:</span>
                <p className="text-sm text-[var(--text-primary)] mt-1">{supporter.registered_voter_location_note}</p>
              </div>
            )}
            {supporter.referred_by_name && (
              <div>
                <span className="text-sm text-[var(--text-secondary)]">Referred by:</span>
                <p className="text-sm text-[var(--text-primary)] mt-1">{supporter.referred_by_name}</p>
              </div>
            )}
            <div className="flex flex-wrap items-center gap-2">
              <span className="text-sm text-[var(--text-secondary)]">Current GEC match:</span>
              <span className={`inline-block px-3 py-1.5 rounded-full text-sm font-semibold ${
                supporter.current_gec_match ? 'bg-green-100 text-green-700' : supporter.registered_voter ? 'bg-amber-100 text-amber-800' : 'bg-gray-100 text-gray-700'
              }`}>
                {gecMatchLabel(supporter)}
              </span>
              {!supporter.current_gec_match && supporter.registered_voter && (
                <span className={`text-sm ${gecMatchClass(supporter)}`}>Review still needed before this supporter is treated as linked to the election-day voter list.</span>
              )}
            </div>
            <div className="flex flex-wrap items-center gap-2">
              <span className="text-sm text-[var(--text-secondary)]">Registration follow-up:</span>
              <span className={`inline-block px-3 py-1.5 rounded-full text-sm font-semibold ${registrationFollowUpStatusClass(supporter.registration_outreach_status)}`}>
                {registrationFollowUpStatusLabel(supporter.registration_outreach_status)}
              </span>
            </div>
            <div>
              <span className="text-sm text-[var(--text-secondary)]">Voter-help requests:</span>
              <div className="mt-2 flex flex-wrap gap-2">
                {supportRequestBadges(supporter).map((badge) => (
                  <span key={badge} className="inline-block rounded-full bg-amber-100 px-3 py-1 text-xs font-semibold text-amber-800">
                    {badge}
                  </span>
                ))}
                {supportRequestBadges(supporter).length === 0 && (
                  <span className="text-sm text-[var(--text-secondary)]">No special requests recorded.</span>
                )}
              </div>
            </div>
            {hasSupportServiceFollowUp(supporter) && (
              <div className="flex flex-wrap items-center gap-2">
                <span className="text-sm text-[var(--text-secondary)]">Support follow-up:</span>
                <span className={`inline-block px-3 py-1.5 rounded-full text-sm font-semibold ${supportFollowUpStatusClass(supporter.support_follow_up_status)}`}>
                  {supportFollowUpStatusLabel(supporter.support_follow_up_status)}
                </span>
              </div>
            )}
            <div className="flex flex-wrap items-center gap-2">
              <span className="text-sm text-[var(--text-secondary)]">Update registration follow-up:</span>
              {canEdit ? (
                <select
                  value={supporter.registration_outreach_status || ''}
                  onChange={async (e) => {
                    try {
                      await updateOutreachStatus(supporter.id, { registration_outreach_status: e.target.value || null });
                      refetch();
                    } catch {
                      alert('Failed to update registration follow-up status.');
                    }
                  }}
                  className="border border-[var(--border-soft)] rounded-xl px-3 py-2 text-sm bg-[var(--surface-raised)]"
                >
                  <option value="">Not contacted</option>
                  <option value="contacted">Contacted</option>
                  <option value="registered">Registered via follow-up</option>
                  <option value="declined">Declined</option>
                </select>
              ) : (
                <span className={`inline-block px-3 py-1.5 rounded-full text-sm font-semibold ${registrationFollowUpStatusClass(supporter.registration_outreach_status)}`}>
                  {registrationFollowUpStatusLabel(supporter.registration_outreach_status)}
                </span>
              )}
            </div>
            {canEdit && (
              <div>
                <label className="text-sm text-[var(--text-secondary)] block mb-1">Registration follow-up notes</label>
                <textarea
                  defaultValue={supporter.registration_outreach_notes || ''}
                  onBlur={async (e) => {
                    const newNotes = e.target.value;
                    if (newNotes !== (supporter.registration_outreach_notes || '')) {
                      try {
                        await updateOutreachStatus(supporter.id, { registration_outreach_notes: newNotes });
                        refetch();
                      } catch {
                        alert('Failed to save registration follow-up notes.');
                      }
                    }
                  }}
                  rows={2}
                  className="w-full border border-[var(--border-soft)] rounded-xl px-3 py-2 text-sm"
                  placeholder="Notes about registration outreach..."
                />
              </div>
            )}
            {!canEdit && supporter.registration_outreach_notes && (
              <div>
                <span className="text-sm text-[var(--text-secondary)]">Registration notes:</span>
                <p className="text-sm text-[var(--text-primary)] mt-1">{supporter.registration_outreach_notes}</p>
              </div>
            )}
            {supporter.registration_outreach_date && (
              <p className="text-xs text-[var(--text-muted)]">
                Last registration outreach: {formatDateTime(supporter.registration_outreach_date)}
              </p>
            )}
            {hasSupportServiceFollowUp(supporter) && (
              <>
                <div className="flex flex-wrap items-center gap-2">
                  <span className="text-sm text-[var(--text-secondary)]">Update support follow-up:</span>
                  {canEdit ? (
                    <select
                      value={supporter.support_follow_up_status || ''}
                      onChange={async (e) => {
                        try {
                          await updateOutreachStatus(supporter.id, { support_follow_up_status: e.target.value || null });
                          refetch();
                        } catch {
                          alert('Failed to update support follow-up progress.');
                        }
                      }}
                      className="border border-[var(--border-soft)] rounded-xl px-3 py-2 text-sm bg-[var(--surface-raised)]"
                    >
                      <option value="">Not started</option>
                      <option value="in_progress">In progress</option>
                      <option value="completed">Completed</option>
                      <option value="declined">Declined</option>
                    </select>
                  ) : (
                    <span className={`inline-block px-3 py-1.5 rounded-full text-sm font-semibold ${supportFollowUpStatusClass(supporter.support_follow_up_status)}`}>
                      {supportFollowUpStatusLabel(supporter.support_follow_up_status)}
                    </span>
                  )}
                </div>
                {canEdit && (
                  <div>
                    <label className="text-sm text-[var(--text-secondary)] block mb-1">Support follow-up notes</label>
                    <textarea
                      defaultValue={supporter.support_follow_up_notes || ''}
                      onBlur={async (e) => {
                        const newNotes = e.target.value;
                        if (newNotes !== (supporter.support_follow_up_notes || '')) {
                          try {
                            await updateOutreachStatus(supporter.id, { support_follow_up_notes: newNotes });
                            refetch();
                          } catch {
                            alert('Failed to save support follow-up notes.');
                          }
                        }
                      }}
                      rows={2}
                      className="w-full border border-[var(--border-soft)] rounded-xl px-3 py-2 text-sm"
                      placeholder="Notes about volunteer / absentee / ride follow-up..."
                    />
                  </div>
                )}
                {!canEdit && supporter.support_follow_up_notes && (
                  <div>
                    <span className="text-sm text-[var(--text-secondary)]">Support notes:</span>
                    <p className="text-sm text-[var(--text-primary)] mt-1">{supporter.support_follow_up_notes}</p>
                  </div>
                )}
                {supporter.support_follow_up_date && (
                  <p className="text-xs text-[var(--text-muted)]">
                    Last support follow-up: {formatDateTime(supporter.support_follow_up_date)}
                  </p>
                )}
              </>
            )}
          </div>
        </section>

        {supporter.household_group_id && (
          <section className="app-card p-4">
            <h2 className="font-semibold text-[var(--text-primary)] mb-2">Household</h2>
            <div className="space-y-3">
              <div className="flex flex-wrap items-center gap-2">
                <span className="inline-block rounded-full bg-indigo-100 px-3 py-1 text-xs font-semibold text-indigo-700">
                  {supporter.household_primary ? 'Primary household contact' : 'Household member'}
                </span>
                <span className="text-sm text-[var(--text-secondary)]">
                  {supporter.household_member_count || 0} linked supporter{(supporter.household_member_count || 0) === 1 ? '' : 's'} in this household group.
                </span>
              </div>
              {supporter.household_members && supporter.household_members.length > 0 ? (
                <div className="space-y-2">
                  {supporter.household_members.map((member) => (
                    <Link
                      key={member.id}
                      to={supporterDetailPath(member.id)}
                      className="block rounded-xl border border-[var(--border-soft)] px-4 py-3 hover:bg-[var(--surface-bg)]"
                    >
                      <div className="font-medium text-[var(--text-primary)]">
                        {[ member.first_name, member.middle_name, member.last_name ].filter(Boolean).join(' ')}
                      </div>
                      <div className="mt-1 text-xs text-[var(--text-secondary)]">
                        {member.village_name || 'Unknown village'} · {selfReportedRegisteredStatusLabel(member.registered_voter_status)}
                      </div>
                    </Link>
                  ))}
                </div>
              ) : (
                <p className="text-sm text-[var(--text-secondary)]">No additional household supporters are linked yet.</p>
              )}
            </div>
          </section>
        )}


        <section className="app-card p-4">
          <div className="mb-3">
            <h2 className="font-semibold text-[var(--text-primary)]">Audit History ({auditLogs.length})</h2>
            <p className="text-sm text-[var(--text-secondary)] mt-1">
              Clear timeline of who changed this supporter, when it changed, and exactly what changed.
            </p>
          </div>
          {auditLogs.length === 0 ? (
            <p className="text-sm text-[var(--text-secondary)]">No changes logged yet.</p>
          ) : (
            <div className="space-y-3">
              {auditLogs.map((log) => {
                const changedFields = Object.entries(log.changed_data || {});
                const sortedChangedFields = [ ...changedFields ].sort(([a], [b]) => {
                  const aIdx = PRIMARY_AUDIT_FIELD_ORDER.indexOf(a);
                  const bIdx = PRIMARY_AUDIT_FIELD_ORDER.indexOf(b);
                  const normalizedA = aIdx === -1 ? Number.MAX_SAFE_INTEGER : aIdx;
                  const normalizedB = bIdx === -1 ? Number.MAX_SAFE_INTEGER : bIdx;
                  return normalizedA - normalizedB;
                });
                const primaryChanges = sortedChangedFields.filter(([field, diff]) => !TECHNICAL_AUDIT_FIELDS.has(field) && isMeaningfulAuditDiff(diff));
                const technicalChanges = sortedChangedFields.filter(([field, diff]) => TECHNICAL_AUDIT_FIELDS.has(field) && isMeaningfulAuditDiff(diff));
                const actionLabel = (log.action_label || log.action || 'Updated').replaceAll('_', ' ');
                const actorLabel = log.actor_name || 'System/Public';

                const renderAuditValue = (field: string, value: unknown) => {
                  if (value === null || value === undefined || value === '') return 'empty';
                  if (field === 'merged_supporter_id') {
                    const numericValue = Number(value);
                    return Number.isFinite(numericValue) ? `Supporter #${numericValue}` : String(value);
                  }
                  if (field === 'referral_code_id') {
                    const numericValue = Number(value);
                    if (
                      supporter.referral_code_id &&
                      Number.isFinite(numericValue) &&
                      numericValue === supporter.referral_code_id
                    ) {
                      const name = supporter.referral_display_name || 'Unknown referrer';
                      const code = supporter.leader_code;
                      return code ? `${name} (${code})` : name;
                    }
                    return `Referral #${numericValue}`;
                  }
                  if (field === 'leader_code') {
                    const codeValue = String(value);
                    if (supporter.leader_code && codeValue === supporter.leader_code && supporter.referral_display_name) {
                      return `${supporter.referral_display_name} (${codeValue})`;
                    }
                    return codeValue;
                  }
                  if (field === 'village_id') {
                    const mapped = villageNameById.get(Number(value));
                    if (mapped) return mapped;
                  }
                  if (field === 'precinct_id') {
                    const mapped = precinctNameById.get(Number(value));
                    if (mapped) return mapped;
                  }
                  return humanizeAuditValue(value, field);
                };

                return (
                  <details key={log.id} className="border border-[var(--border-soft)] rounded-xl bg-[var(--surface-raised)] group">
                    <summary className="cursor-pointer list-none p-4">
                      <div className="flex flex-wrap items-start justify-between gap-3">
                        <div>
                          <p className="text-base font-semibold text-[var(--text-primary)]">{actionLabel}</p>
                          <p className="text-sm text-[var(--text-secondary)]">
                            Changed by <span className="font-medium text-[var(--text-primary)]">{actorLabel}</span> ({humanizeRole(log.actor_role)}) on {formatDateTime(log.created_at)}
                          </p>
                          {primaryChanges.length > 0 && (
                            <p className="text-sm text-[var(--text-secondary)] mt-1">
                              {auditFieldLabel(primaryChanges[0][0])}
                              {primaryChanges.length > 1 ? ` + ${primaryChanges.length - 1} more` : ''}
                            </p>
                          )}
                        </div>
                        <span className="text-xs rounded-full bg-[var(--surface-bg)] px-2 py-1 text-[var(--text-secondary)]">
                          {changedFields.length} change{changedFields.length === 1 ? '' : 's'}
                        </span>
                      </div>
                      <p className="text-xs text-[var(--text-muted)] mt-2">Tap to expand details</p>
                    </summary>

                    <div className="px-4 pb-4 border-t border-[var(--border-soft)]">
                      {primaryChanges.length > 0 ? (
                        <div className="mt-3 space-y-2">
                          {primaryChanges.map(([field, diff]) => {
                            const normalizedDiff = auditDiffParts(diff);
                            const showCompactChange = [ 'resolution', 'merged_supporter_id' ].includes(field) && isEmptyAuditValue(normalizedDiff.from);
                            return (
                            <div key={field} className="rounded-lg border border-[var(--border-soft)] bg-white px-3 py-2.5">
                              <p className="text-sm font-semibold uppercase tracking-wide text-[var(--text-secondary)]">{auditFieldLabel(field)}</p>
                              {showCompactChange ? (
                                <div className="mt-1.5 flex flex-wrap items-center gap-2 text-base">
                                  <span className="rounded-md bg-blue-200 text-blue-900 px-2.5 py-1 font-medium">{renderAuditValue(field, normalizedDiff.to)}</span>
                                </div>
                              ) : (
                                <div className="mt-1.5 flex flex-wrap items-center gap-2 text-base">
                                  <span className="rounded-md bg-gray-200 text-gray-900 px-2.5 py-1">{renderAuditValue(field, normalizedDiff.from)}</span>
                                  <span className="text-[var(--text-secondary)] font-medium">to</span>
                                  <span className="rounded-md bg-blue-200 text-blue-900 px-2.5 py-1 font-medium">{renderAuditValue(field, normalizedDiff.to)}</span>
                                </div>
                              )}
                            </div>
                          )})}
                        </div>
                      ) : (
                        <p className="text-sm text-[var(--text-secondary)] mt-3">No user-facing field changes captured for this action.</p>
                      )}

                      {technicalChanges.length > 0 && (
                        <details className="mt-3">
                          <summary className="cursor-pointer text-xs text-[var(--text-secondary)]">Show system details</summary>
                          <div className="mt-2 space-y-1">
                            {technicalChanges.map(([field, diff]) => {
                              const normalizedDiff = auditDiffParts(diff);
                              return (
                              <p key={field} className="text-xs text-[var(--text-secondary)]">
                                <span className="font-medium">{auditFieldLabel(field)}:</span>{' '}
                                {renderAuditValue(field, normalizedDiff.from)} {'->'} {renderAuditValue(field, normalizedDiff.to)}
                              </p>
                            )})}
                          </div>
                        </details>
                      )}
                    </div>
                  </details>
                );
              })}
            </div>
          )}
        </section>
      </div>
    </WorkspacePage>
  );
}
