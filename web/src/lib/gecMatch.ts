type GecMatchLike = {
  current_gec_match?: boolean | null;
  registered_voter?: boolean | null;
};

export type GecMatchState = 'matched' | 'possible' | 'none';

export function gecMatchState(record: GecMatchLike): GecMatchState {
  if (record.current_gec_match) return 'matched';
  if (record.registered_voter) return 'possible';
  return 'none';
}

export function gecMatchLabel(record: GecMatchLike): string {
  switch (gecMatchState(record)) {
    case 'matched':
      return 'Matched';
    case 'possible':
      return 'Possible match';
    default:
      return 'No match';
  }
}

export function gecMatchClass(record: GecMatchLike): string {
  switch (gecMatchState(record)) {
    case 'matched':
      return 'text-green-600 font-medium';
    case 'possible':
      return 'text-amber-700 font-medium';
    default:
      return 'text-[var(--text-muted)]';
  }
}
