export const CONTACT_CLASSIFICATION_OPTIONS = [
  { value: 'new_intake', label: 'New intake' },
  { value: 'active_contact', label: 'Active contact' },
  { value: 'duplicate', label: 'Duplicate' },
  { value: 'invalid', label: 'Invalid' },
  { value: 'archived', label: 'Archived' },
] as const;

export const ACTIVE_RELATIONSHIP_OPTIONS = CONTACT_CLASSIFICATION_OPTIONS.filter(
  (option) => option.value === 'active_contact'
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
