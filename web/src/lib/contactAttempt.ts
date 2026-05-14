export const CONTACT_ATTEMPT_CHANNEL_OPTIONS = [
  { value: 'in_person', label: 'In person' },
  { value: 'call', label: 'Call' },
  { value: 'sms', label: 'SMS' },
  { value: 'email', label: 'Email' },
] as const;

export const CONTACT_ATTEMPT_OUTCOME_OPTIONS = [
  { value: 'reached', label: 'Reached' },
  { value: 'attempted', label: 'Attempted' },
  { value: 'unavailable', label: 'Unavailable' },
  { value: 'wrong_number', label: 'Wrong number' },
  { value: 'refused', label: 'Refused' },
] as const;

export const OPTIONAL_CONTACT_ATTEMPT_CHANNEL_OPTIONS = [
  { value: '', label: 'No initial outreach logged' },
  ...CONTACT_ATTEMPT_CHANNEL_OPTIONS,
] as const;

export const OPTIONAL_CONTACT_ATTEMPT_OUTCOME_OPTIONS = [
  { value: '', label: 'Select outcome' },
  ...CONTACT_ATTEMPT_OUTCOME_OPTIONS,
] as const;

export function contactAttemptChannelLabel(channel?: string | null) {
  return CONTACT_ATTEMPT_CHANNEL_OPTIONS.find((option) => option.value === channel)?.label || channel?.replaceAll('_', ' ') || '';
}

export function contactAttemptOutcomeLabel(outcome?: string | null) {
  return CONTACT_ATTEMPT_OUTCOME_OPTIONS.find((option) => option.value === outcome)?.label || outcome?.replaceAll('_', ' ') || '';
}
