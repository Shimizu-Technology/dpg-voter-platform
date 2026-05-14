export const CONTACT_CLASSIFICATION_OPTIONS = [
  { value: 'new_intake', label: 'New intake' },
  { value: 'active_contact', label: 'Active contact' },
  { value: 'supporter', label: 'Supporter' },
  { value: 'member', label: 'Member' },
  { value: 'volunteer', label: 'Volunteer' },
  { value: 'undecided', label: 'Undecided' },
  { value: 'not_supporting', label: 'Not supporting' },
  { value: 'duplicate', label: 'Duplicate' },
  { value: 'invalid', label: 'Invalid' },
  { value: 'archived', label: 'Archived' },
] as const;

export const ACTIVE_RELATIONSHIP_OPTIONS = CONTACT_CLASSIFICATION_OPTIONS.filter(
  (option) => !['new_intake', 'duplicate', 'invalid', 'archived'].includes(option.value)
);

export const INTAKE_REVIEW_CLASSIFICATION_OPTIONS = CONTACT_CLASSIFICATION_OPTIONS.filter(
  (option) => option.value !== 'new_intake'
);

export function contactClassificationLabel(status?: string | null) {
  return CONTACT_CLASSIFICATION_OPTIONS.find((entry) => entry.value === status)?.label || 'Contact';
}

export function contactClassificationChipClass(status?: string | null) {
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
    case 'duplicate':
      return 'bg-orange-100 text-orange-700';
    case 'invalid':
      return 'bg-zinc-200 text-zinc-700';
    case 'archived':
      return 'bg-slate-200 text-slate-700';
    default:
      return 'bg-gray-100 text-gray-700';
  }
}
