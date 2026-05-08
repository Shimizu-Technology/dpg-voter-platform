export type PrecinctAssignmentOption = {
  id: number;
  alpha_range?: string | null;
};

// Matches the backend PrecinctAssigner boundary comparison. Ranges may use
// different-length prefixes on each side, such as "A-Md" or "Me-Z".
function inAlphaRange(lastName: string, alphaRange: string): boolean {
  const hyphenIdx = alphaRange.indexOf('-');
  if (hyphenIdx === -1) return false;

  const start = alphaRange.slice(0, hyphenIdx).trim().toLowerCase();
  const end = alphaRange.slice(hyphenIdx + 1).trim().toLowerCase();
  if (!start || !end) return false;

  const normalizedName = lastName.trim().toLowerCase();
  const startPrefix = normalizedName.slice(0, start.length);
  const endPrefix = normalizedName.slice(0, end.length);

  return startPrefix >= start && endPrefix <= end;
}

export function assignPrecinctIdByLastName(
  lastName: string | null | undefined,
  precincts: PrecinctAssignmentOption[],
): number | null {
  if (!precincts.length) return null;
  if (precincts.length === 1) return precincts[0].id;

  const normalizedLastName = lastName?.trim();
  if (!normalizedLastName) return null;

  for (const precinct of precincts) {
    if (!precinct.alpha_range) continue;
    if (inAlphaRange(normalizedLastName, precinct.alpha_range)) {
      return precinct.id;
    }
  }

  return precincts[precincts.length - 1]?.id ?? null;
}
