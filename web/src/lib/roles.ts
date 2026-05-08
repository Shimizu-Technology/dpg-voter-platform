export function formatRoleLabel(role: unknown): string {
  if (typeof role !== 'string') return '';
  return role.replaceAll('_', ' ');
}
