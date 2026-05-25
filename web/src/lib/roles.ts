const ROLE_LABELS: Record<string, string> = {
  campaign_admin: 'Administrator',
  data_team: 'Data Manager',
  district_coordinator: 'Field Organizer',
  village_chief: 'Village Coordinator',
  block_leader: 'Canvasser',
  poll_watcher: 'Poll Watcher',
};

export function formatRoleLabel(role: unknown): string {
  if (typeof role !== 'string') return '';
  return ROLE_LABELS[role] || role.replaceAll('_', ' ');
}
