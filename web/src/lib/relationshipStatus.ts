export const SUPPORT_STATUS_OPTIONS = [
  { value: 'unknown', label: 'Support not reviewed' },
  { value: 'supporter', label: 'Supporter' },
  { value: 'undecided', label: 'Undecided' },
  { value: 'not_supporting', label: 'Not supporting' },
] as const;

export const MEMBERSHIP_STATUS_OPTIONS = [
  { value: 'not_member', label: 'Not a member' },
  { value: 'member', label: 'Member' },
] as const;

export const VOLUNTEER_STATUS_OPTIONS = [
  { value: 'unknown', label: 'Volunteer interest not reviewed' },
  { value: 'interested', label: 'Interested' },
  { value: 'active', label: 'Active volunteer' },
  { value: 'not_interested', label: 'Not interested' },
] as const;

export function supportStatusLabel(status?: string | null) {
  return SUPPORT_STATUS_OPTIONS.find((option) => option.value === status)?.label || 'Support not reviewed';
}

export function membershipStatusLabel(status?: string | null) {
  return MEMBERSHIP_STATUS_OPTIONS.find((option) => option.value === status)?.label || 'Not a member';
}

export function volunteerStatusLabel(status?: string | null) {
  return VOLUNTEER_STATUS_OPTIONS.find((option) => option.value === status)?.label || 'Volunteer interest not reviewed';
}

export function supportStatusChipClass(status?: string | null) {
  switch (status) {
    case 'supporter':
      return 'bg-green-100 text-green-700';
    case 'undecided':
      return 'bg-slate-100 text-slate-700';
    case 'not_supporting':
      return 'bg-red-100 text-red-700';
    default:
      return 'bg-gray-100 text-gray-700';
  }
}

export function membershipStatusChipClass(status?: string | null) {
  return status === 'member' ? 'bg-emerald-100 text-emerald-700' : 'bg-gray-100 text-gray-700';
}

export function volunteerStatusChipClass(status?: string | null) {
  if (status === 'active') return 'bg-indigo-100 text-indigo-700';
  if (status === 'interested') return 'bg-blue-100 text-blue-700';
  if (status === 'not_interested') return 'bg-zinc-100 text-zinc-700';
  return 'bg-gray-100 text-gray-700';
}
