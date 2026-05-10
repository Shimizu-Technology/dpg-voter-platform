import { Fragment, useEffect, useMemo, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useSearchParams } from 'react-router-dom';
import { ChevronDown, ChevronRight, Mail, Pencil, Plus, Save, Search, Trash2, Users, X, Check } from 'lucide-react';
import { createUser, deleteUser, getDistricts, getUsers, getVillages, resendUserInvite, updateUser } from '../../lib/api';
import { useSession } from '../../hooks/useSession';
import WorkspacePage from '../../components/WorkspacePage';
import { formatRoleLabel } from '../../lib/roles';

interface VillageOption {
  id: number;
  name: string;
}

interface DistrictOption {
  id: number;
  name: string;
  villages: { id: number; name: string }[];
}

interface UserItem {
  id: number;
  email: string;
  name: string | null;
  role: string;
  created_at?: string;
  assigned_district_id: number | null;
  assigned_village_id: number | null;
  assigned_block_id: number | null;
}

interface UsersResponse {
  users: UserItem[];
  roles: string[];
}

interface RoleGuideRow {
  role: string;
  level: string;
  who: string;
  can: string;
}

interface UserDraft {
  firstName: string;
  lastName: string;
  email: string;
  role: string;
  assigned_district_id: number | null;
  assigned_village_id: number | null;
}

function splitName(fullName: string | null): { firstName: string; lastName: string } {
  if (!fullName) return { firstName: '', lastName: '' };
  const parts = fullName.trim().split(/\s+/);
  if (parts.length === 1) return { firstName: parts[0], lastName: '' };
  return { firstName: parts[0], lastName: parts.slice(1).join(' ') };
}

function joinName(first: string, last: string): string {
  return [first.trim(), last.trim()].filter(Boolean).join(' ');
}

const ROLE_GUIDE: RoleGuideRow[] = [
  {
    role: 'campaign_admin',
    level: 'Level 1',
    who: 'DPG leadership / trusted admins',
    can: 'Full system access across Data Ops and DPG tools, including setup, users, outreach, and reports',
  },
  {
    role: 'data_team',
    level: 'Level 2',
    who: 'Monthly voter-list and reporting staff',
    can: 'Import GEC lists, vet supporters, review public signups, resolve duplicates, audit changes, and generate reports island-wide',
  },
  {
    role: 'district_coordinator',
    level: 'Level 3',
    who: 'DPG district coordinators',
    can: 'Manage supporter activity for villages in an approved DPG-defined district',
  },
  {
    role: 'village_chief',
    level: 'Level 4',
    who: 'Village coordinators',
    can: 'View and coordinate village execution for their assigned village',
  },
  {
    role: 'block_leader',
    level: 'Level 5',
    who: 'Community organizers',
    can: 'Submit and track supporter activity for their assigned area',
  },
];

type PermissionKey =
  | 'can_manage_users'
  | 'can_manage_configuration'
  | 'can_manage_data_configuration'
  | 'can_send_sms'
  | 'can_send_email'
  | 'can_edit_supporters'
  | 'can_view_supporters'
  | 'can_create_staff_supporters'
  | 'can_import_supporters'
  | 'can_access_duplicates'
  | 'can_access_audit_logs'
  | 'can_access_data_team'
  | 'can_access_reports'
  | 'can_upload_gec'
  | 'can_bulk_vet'
  | 'can_review_public';

const PERMISSION_KEYS: PermissionKey[] = [
  'can_manage_users',
  'can_manage_configuration',
  'can_manage_data_configuration',
  'can_send_sms',
  'can_send_email',
  'can_edit_supporters',
  'can_view_supporters',
  'can_create_staff_supporters',
  'can_import_supporters',
  'can_access_duplicates',
  'can_access_audit_logs',
  'can_access_data_team',
  'can_access_reports',
  'can_upload_gec',
  'can_bulk_vet',
  'can_review_public',
];

const PERMISSION_LABELS: Record<PermissionKey, string> = {
  can_manage_users: 'Manage users',
  can_manage_configuration: 'Manage configuration',
  can_manage_data_configuration: 'Manage data configuration',
  can_send_sms: 'Send SMS',
  can_send_email: 'Send email',
  can_edit_supporters: 'Edit supporters',
  can_view_supporters: 'View supporters',
  can_create_staff_supporters: 'Create staff supporters',
  can_import_supporters: 'Excel import supporters',
  can_access_duplicates: 'Duplicates review',
  can_access_audit_logs: 'Activity log',
  can_access_data_team: 'Data Ops workspace',
  can_access_reports: 'Reports',
  can_upload_gec: 'GEC imports',
  can_bulk_vet: 'Bulk vetting',
  can_review_public: 'Public signup review',
};

// Keep in sync with api/app/controllers/concerns/authenticatable.rb permission methods.
const ROLE_PERMISSION_MAP: Record<string, PermissionKey[]> = {
  campaign_admin: PERMISSION_KEYS,
  data_team: [
    'can_view_supporters',
    'can_edit_supporters',
    'can_create_staff_supporters',
    'can_import_supporters',
    'can_access_duplicates',
    'can_access_audit_logs',
    'can_access_data_team',
    'can_access_reports',
    'can_upload_gec',
    'can_bulk_vet',
    'can_review_public',
  ],
  district_coordinator: [
    'can_manage_users',
    'can_send_sms',
    'can_send_email',
    'can_edit_supporters',
    'can_view_supporters',
    'can_create_staff_supporters',
    'can_import_supporters',
    'can_access_reports',
            ],
  village_chief: [
    'can_view_supporters',
    'can_create_staff_supporters',
    'can_import_supporters',
          ],
  block_leader: [
    'can_view_supporters',
    'can_create_staff_supporters',
    'can_import_supporters',
        ],
};

function roleLabel(role: string) {
  return formatRoleLabel(role);
}

/** Which area assignment field does this role need? */
function roleAssignmentType(role: string): 'none' | 'district' | 'village' {
  if (role === 'campaign_admin' || role === 'data_team') return 'none';
  if (role === 'district_coordinator') return 'district';
  return 'village'; // village_chief, block_leader
}

function AssignmentDropdown({
  role,
  villageId,
  districtId,
  onVillageChange,
  onDistrictChange,
  villages,
  districts,
}: {
  role: string;
  villageId: number | null;
  districtId: number | null;
  onVillageChange: (id: number | null) => void;
  onDistrictChange: (id: number | null) => void;
  villages: VillageOption[];
  districts: DistrictOption[];
}) {
  const type = roleAssignmentType(role);
  if (type === 'none') return null;

  if (type === 'district') {
    return (
      <select
        value={districtId ?? ''}
        onChange={(e) => onDistrictChange(e.target.value ? Number(e.target.value) : null)}
        className="border border-[var(--border-soft)] rounded-xl px-3 py-2 bg-[var(--surface-raised)] min-h-[44px] w-full"
      >
        <option value="">Select district...</option>
        {districts.map((d) => (
          <option key={d.id} value={d.id}>{d.name} ({d.villages.length} villages)</option>
        ))}
        {districts.length === 0 && (
          <option disabled>No districts configured yet</option>
        )}
      </select>
    );
  }

  return (
    <select
      value={villageId ?? ''}
      onChange={(e) => onVillageChange(e.target.value ? Number(e.target.value) : null)}
      className="border border-[var(--border-soft)] rounded-xl px-3 py-2 bg-[var(--surface-raised)] min-h-[44px] w-full"
    >
      <option value="">Select village...</option>
      {villages.map((v) => (
        <option key={v.id} value={v.id}>{v.name}</option>
      ))}
    </select>
  );
}

function assignmentLabel(
  user: UserItem,
  villages: VillageOption[],
  districts: DistrictOption[],
): string {
  const type = roleAssignmentType(user.role);
  if (type === 'district' && user.assigned_district_id) {
    const d = districts.find((d) => d.id === user.assigned_district_id);
    return d ? `District: ${d.name}` : `District #${user.assigned_district_id}`;
  }
  if (type === 'village' && user.assigned_village_id) {
    const v = villages.find((v) => v.id === user.assigned_village_id);
    return v ? `Village: ${v.name}` : `Village #${user.assigned_village_id}`;
  }
  if (type === 'none') return '';
  return 'No area assigned';
}

function roleHasPermission(role: string, permission: PermissionKey): boolean {
  return (ROLE_PERMISSION_MAP[role] || []).includes(permission);
}

function RolePermissionsDisclosure({ role }: { role: string }) {
  const allowed = PERMISSION_KEYS.filter((permission) => roleHasPermission(role, permission));
  const restricted = PERMISSION_KEYS.filter((permission) => !roleHasPermission(role, permission));

  return (
    <details className="mt-1.5 group">
      <summary className="cursor-pointer list-none inline-flex items-center gap-1 text-[11px] text-primary hover:text-primary/80">
        <ChevronRight className="w-3 h-3 transition-transform group-open:rotate-90" />
        <span>Access details ({allowed.length}/{PERMISSION_KEYS.length})</span>
      </summary>
      <div className="mt-2 rounded-lg border border-[var(--border-soft)] bg-[var(--surface-raised)] p-2.5">
        <div className="grid gap-2 sm:grid-cols-2">
          <div>
            <p className="text-[10px] font-semibold uppercase tracking-wide text-emerald-700 mb-1.5">Allowed</p>
            <div className="space-y-1">
              {allowed.map((permission) => (
                <div key={permission} className="inline-flex w-full items-center gap-1.5 rounded-md bg-emerald-50 px-2 py-1 text-[10px] text-emerald-800 border border-emerald-200">
                  <Check className="w-3 h-3 shrink-0" />
                  <span>{PERMISSION_LABELS[permission]}</span>
                </div>
              ))}
            </div>
          </div>
          <div>
            <p className="text-[10px] font-semibold uppercase tracking-wide text-[var(--text-muted)] mb-1.5">Restricted</p>
            <div className="space-y-1">
              {restricted.map((permission) => (
                <div key={permission} className="inline-flex w-full items-center gap-1.5 rounded-md bg-gray-100 px-2 py-1 text-[10px] text-gray-600 border border-gray-200">
                  <X className="w-3 h-3 shrink-0" />
                  <span>{PERMISSION_LABELS[permission]}</span>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </details>
  );
}

function roleScopeRule(role: string): string {
  if (role === 'campaign_admin') return 'Scope rule: full access to all villages';
  if (role === 'data_team') return 'Scope rule: island-wide Data Ops access';
  if (role === 'district_coordinator') return 'Scope rule: assigned district (or all villages if no district assigned)';
  return 'Scope rule: assigned village only';
}

function scopeLabelForRole(
  role: string,
  assignedDistrictId: number | null,
  assignedVillageId: number | null,
  villages: VillageOption[],
  districts: DistrictOption[]
): string {
  if (role === 'campaign_admin') return 'Scope: all villages';
  if (role === 'data_team') return 'Scope: island-wide Data Ops';
  if (role === 'district_coordinator') {
    if (!assignedDistrictId) return 'Scope: all villages (no district assigned)';
    const district = districts.find((d) => d.id === assignedDistrictId);
    return `Scope: assigned district (${district?.name || `District #${assignedDistrictId}`})`;
  }

  if (!assignedVillageId) return 'Scope: no village assigned (no scoped data)';
  const village = villages.find((v) => v.id === assignedVillageId);
  return `Scope: assigned village (${village?.name || `Village #${assignedVillageId}`})`;
}

function RolePermissionChips({ role }: { role: string }) {
  const allowedCount = PERMISSION_KEYS.filter((permission) => roleHasPermission(role, permission)).length;

  return (
    <div className="rounded-lg border border-[var(--border-soft)] bg-[var(--surface-bg)] p-2.5">
      <p className="text-xs text-[var(--text-secondary)] mb-2">
        {roleScopeRule(role)} · {allowedCount} of {PERMISSION_KEYS.length} permissions enabled
      </p>
      <div className="flex flex-wrap gap-1.5">
        {PERMISSION_KEYS.map((permission) => {
          const allowed = roleHasPermission(role, permission);
          return (
            <span
              key={permission}
              className={`text-[11px] px-2 py-1 rounded-full border ${
                allowed
                  ? 'bg-green-50 border-green-200 text-green-700'
                  : 'bg-gray-100 border-gray-200 text-gray-500'
              }`}
            >
              {allowed ? 'Can' : "Can't"} {PERMISSION_LABELS[permission]}
            </span>
          );
        })}
      </div>
    </div>
  );
}

type UserSortField = 'name' | 'email' | 'role' | 'created_at';
const SORT_FIELDS: UserSortField[] = ['name', 'email', 'role', 'created_at'];

function parseSortField(value: string | null): UserSortField {
  return SORT_FIELDS.includes(value as UserSortField) ? (value as UserSortField) : 'role';
}

export default function UsersPage() {
  const queryClient = useQueryClient();
  const [searchParams, setSearchParams] = useSearchParams();
  const { data, isLoading, error, refetch, isFetching } = useQuery<UsersResponse>({
    queryKey: ['users'],
    queryFn: getUsers,
    // During local dev/hot-reload, token sync can briefly race API calls.
    // Retry a few times so the page self-recovers without manual refresh.
    retry: (failureCount, err: unknown) => {
      const status = (err as { response?: { status?: number } })?.response?.status;
      if (status === 401) return failureCount < 3;
      return failureCount < 2;
    },
    retryDelay: (attemptIndex) => Math.min((attemptIndex + 1) * 800, 2500),
    refetchOnWindowFocus: true,
  });

  const { data: villagesData } = useQuery<{ villages: VillageOption[] }>({
    queryKey: ['villages'],
    queryFn: getVillages,
  });
  const { data: districtsData } = useQuery<{ districts: DistrictOption[] }>({
    queryKey: ['districts'],
    queryFn: getDistricts,
  });
  const villages = useMemo(() => villagesData?.villages || [], [villagesData]);
  const districts = useMemo(() => districtsData?.districts || [], [districtsData]);

  const [newEmail, setNewEmail] = useState('');
  const [newRole, setNewRole] = useState('block_leader');
  const [newAssignedVillageId, setNewAssignedVillageId] = useState<number | null>(null);
  const [newAssignedDistrictId, setNewAssignedDistrictId] = useState<number | null>(null);
  const [draftByUser, setDraftByUser] = useState<Record<number, UserDraft>>({});
  const [inviteNotice, setInviteNotice] = useState<string | null>(null);
  const [search, setSearch] = useState(searchParams.get('search') || '');
  const [roleFilter, setRoleFilter] = useState(searchParams.get('role') || '');
  const [sortBy, setSortBy] = useState<UserSortField>(parseSortField(searchParams.get('sort_by')));
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>((searchParams.get('sort_dir') as 'asc' | 'desc') || 'asc');
  const [expandedRoles, setExpandedRoles] = useState<Set<string>>(new Set());
  const [expandedUserPermissions, setExpandedUserPermissions] = useState<Set<number>>(new Set());

  const roles = useMemo(() => data?.roles || [], [data]);
  const users = useMemo(() => data?.users || [], [data]);
  const filteredUsers = useMemo(() => {
    const lowered = search.trim().toLowerCase();
    const filtered = users.filter((u) => {
      const searchHit = lowered.length === 0 ||
        (u.name || '').toLowerCase().includes(lowered) ||
        u.email.toLowerCase().includes(lowered);
      const roleHit = roleFilter ? u.role === roleFilter : true;
      return searchHit && roleHit;
    });

    const sorted = [...filtered].sort((a, b) => {
      const dir = sortDir === 'asc' ? 1 : -1;
      if (sortBy === 'created_at') {
        const aVal = a.created_at ? new Date(a.created_at).getTime() : 0;
        const bVal = b.created_at ? new Date(b.created_at).getTime() : 0;
        return (aVal - bVal) * dir;
      }
      if (sortBy === 'name') {
        return ((a.name || '').localeCompare(b.name || '')) * dir;
      }
      if (sortBy === 'role') {
        return a.role.localeCompare(b.role) * dir;
      }
      return a.email.localeCompare(b.email) * dir;
    });

    return sorted;
  }, [users, search, roleFilter, sortBy, sortDir]);

  useEffect(() => {
    const params = new URLSearchParams();
    if (search) params.set('search', search);
    if (roleFilter) params.set('role', roleFilter);
    params.set('sort_by', sortBy);
    params.set('sort_dir', sortDir);
    setSearchParams(params, { replace: true });
  }, [search, roleFilter, sortBy, sortDir, setSearchParams]);

  const createMutation = useMutation({
    mutationFn: () => {
      const assignType = roleAssignmentType(newRole);
      return createUser({
        email: newEmail,
        role: newRole,
        assigned_village_id: assignType === 'village' ? newAssignedVillageId : null,
        assigned_district_id: assignType === 'district' ? newAssignedDistrictId : null,
      });
    },
    onSuccess: () => {
      setNewEmail('');
      setNewRole('block_leader');
      setNewAssignedVillageId(null);
      setNewAssignedDistrictId(null);
      queryClient.invalidateQueries({ queryKey: ['users'] });
    },
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, payload }: { id: number; payload: UserDraft }) => {
      const assignType = roleAssignmentType(payload.role);
      return updateUser(id, {
        name: joinName(payload.firstName, payload.lastName) || null,
        email: payload.email.trim(),
        role: payload.role,
        assigned_village_id: assignType === 'village' ? payload.assigned_village_id : null,
        assigned_district_id: assignType === 'district' ? payload.assigned_district_id : null,
      });
    },
    onSuccess: (_data, variables) => {
      setDraftByUser((prev) => {
        const next = { ...prev };
        delete next[variables.id];
        return next;
      });
      queryClient.invalidateQueries({ queryKey: ['users'] });
    },
  });

  const { data: session } = useSession();
  const currentUserId = session?.user?.id;

  const [deleteError, setDeleteError] = useState<string | null>(null);

  const deleteMutation = useMutation({
    mutationFn: (id: number) => deleteUser(id),
    onSuccess: () => {
      setDeleteError(null);
      queryClient.invalidateQueries({ queryKey: ['users'] });
    },
    onError: (err: unknown) => {
      const message = (err as { response?: { data?: { error?: string } } })?.response?.data?.error
        || 'Failed to remove user. Please try again.';
      setDeleteError(message);
      setTimeout(() => setDeleteError(null), 5000);
    },
  });

  const resendInviteMutation = useMutation({
    mutationFn: (id: number) => resendUserInvite(id),
    onSuccess: (_data, id) => {
      const user = users.find((u) => u.id === id);
      setInviteNotice(`Invite email queued for ${user?.email || 'user'}`);
      setTimeout(() => setInviteNotice(null), 4000);
    },
  });

  const getDraft = (user: UserItem): UserDraft => {
    if (draftByUser[user.id]) return draftByUser[user.id];
    const { firstName, lastName } = splitName(user.name);
    return {
      firstName, lastName, email: user.email, role: user.role,
      assigned_district_id: user.assigned_district_id,
      assigned_village_id: user.assigned_village_id,
    };
  };

  const startEdit = (user: UserItem) => {
    const { firstName, lastName } = splitName(user.name);
    setDraftByUser((prev) => ({
      ...prev,
      [user.id]: {
        firstName, lastName, email: user.email, role: user.role,
        assigned_district_id: user.assigned_district_id,
        assigned_village_id: user.assigned_village_id,
      },
    }));
  };

  const cancelEdit = (userId: number) => {
    setDraftByUser((prev) => {
      const next = { ...prev };
      delete next[userId];
      return next;
    });
    setExpandedUserPermissions((prev) => {
      if (!prev.has(userId)) return prev;
      const next = new Set(prev);
      next.delete(userId);
      return next;
    });
  };

  const toggleUserPermissions = (userId: number) => {
    setExpandedUserPermissions((prev) => {
      const next = new Set(prev);
      if (next.has(userId)) next.delete(userId);
      else next.add(userId);
      return next;
    });
  };

  const hasChanges = (user: UserItem, draft: UserDraft) => (
    (user.name || '') !== joinName(draft.firstName, draft.lastName) ||
    user.email !== draft.email.trim().toLowerCase() ||
    user.role !== draft.role ||
    user.assigned_village_id !== draft.assigned_village_id ||
    user.assigned_district_id !== draft.assigned_district_id
  );

  const pendingSaves = useMemo(
    () => Object.entries(draftByUser).filter(([id, draft]) => {
      const user = users.find((u) => u.id === Number(id));
      if (!user) return false;
      return hasChanges(user, draft);
    }),
    [draftByUser, users]
  );

  const handleSort = (field: UserSortField) => {
    if (sortBy === field) {
      setSortDir((prev) => (prev === 'asc' ? 'desc' : 'asc'));
      return;
    }
    setSortBy(field);
    setSortDir(field === 'created_at' ? 'desc' : 'asc');
  };

  const toggleRoleExpanded = (role: string) => {
    setExpandedRoles((prev) => {
      const next = new Set(prev);
      if (next.has(role)) {
        next.delete(role);
      } else {
        next.add(role);
      }
      return next;
    });
  };

  const expandAllRoles = () => {
    setExpandedRoles(new Set(ROLE_GUIDE.map((row) => row.role)));
  };

  const collapseAllRoles = () => {
    setExpandedRoles(new Set());
  };

  const allRolesExpanded = expandedRoles.size === ROLE_GUIDE.length;

  return (
    <WorkspacePage width="full" className="space-y-5 sm:space-y-6">
      <div>
        <h1 className="text-xl font-bold text-gray-900 flex items-center gap-2">
          <Users className="w-5 h-5 text-primary" /> User Management
        </h1>
        <p className="text-gray-500 text-sm">Authorized managers can invite users and assign allowed party roles.</p>
      </div>

      <div className="space-y-6">
        <section className="app-card p-4">
          <h2 className="app-section-title text-xl mb-2">Add User</h2>
          <p className="text-xs text-[var(--text-secondary)] mb-3">
            Use the same email they will use with Clerk. Name comes from Clerk profile on first login.
          </p>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
            <input
              type="email"
              value={newEmail}
              onChange={(e) => setNewEmail(e.target.value)}
              placeholder="Email"
              className="border border-[var(--border-soft)] rounded-xl px-3 py-2 md:col-span-2 min-h-[44px]"
            />
            <select
              value={newRole}
              onChange={(e) => {
                setNewRole(e.target.value);
                setNewAssignedVillageId(null);
                setNewAssignedDistrictId(null);
              }}
              className="border border-[var(--border-soft)] rounded-xl px-3 py-2 bg-[var(--surface-raised)] min-h-[44px]"
            >
              {roles.map((role) => (
                <option key={role} value={role}>{roleLabel(role)}</option>
              ))}
            </select>
          </div>
          {roleAssignmentType(newRole) !== 'none' && (
            <div className="mt-3 max-w-sm">
              <label className="block text-xs text-[var(--text-secondary)] mb-1">
                {roleAssignmentType(newRole) === 'district' ? 'Assign to district' : 'Assign to village'}
              </label>
              <AssignmentDropdown
                role={newRole}
                villageId={newAssignedVillageId}
                districtId={newAssignedDistrictId}
                onVillageChange={setNewAssignedVillageId}
                onDistrictChange={setNewAssignedDistrictId}
                villages={villages}
                districts={districts}
              />
            </div>
          )}
          <button
            type="button"
            onClick={() => createMutation.mutate()}
            disabled={!newEmail || createMutation.isPending || (roleAssignmentType(newRole) === 'village' && !newAssignedVillageId) || (roleAssignmentType(newRole) === 'district' && !newAssignedDistrictId)}
            className="mt-3 w-full sm:w-auto bg-primary text-white px-4 py-2 rounded-xl min-h-[44px] text-sm font-medium inline-flex items-center justify-center gap-2 disabled:opacity-50"
          >
            <Plus className="w-4 h-4" /> {createMutation.isPending ? 'Adding...' : 'Add User'}
          </button>
          {createMutation.isError && (
            <p className="text-sm text-red-600 mt-2">Could not add user. Check email/role and try again.</p>
          )}
          {inviteNotice && (
            <p className="text-sm text-green-700 mt-2">{inviteNotice}</p>
          )}
          {deleteError && (
            <p className="text-sm text-red-600 mt-2">{deleteError}</p>
          )}
        </section>

        <section className="app-card overflow-hidden">
          <details>
            <summary className="cursor-pointer px-4 py-3 border-b bg-[var(--surface-bg)]">
              <h2 className="app-section-title text-lg inline">Role Matrix</h2>
              <p className="text-xs text-[var(--text-secondary)] mt-1">Reference guide for each role. Expand a row for exact access details.</p>
            </summary>
            <div className="px-4 py-2.5 border-b bg-[var(--surface-raised)] flex items-center justify-end gap-2">
              {!allRolesExpanded ? (
                <button
                  type="button"
                  onClick={expandAllRoles}
                  className="text-xs text-primary border border-primary/30 bg-white hover:bg-primary/5 rounded-lg px-2.5 py-1.5"
                >
                  Expand all
                </button>
              ) : (
                <button
                  type="button"
                  onClick={collapseAllRoles}
                  className="text-xs text-primary border border-primary/30 bg-white hover:bg-primary/5 rounded-lg px-2.5 py-1.5"
                >
                  Collapse all
                </button>
              )}
            </div>
            <div className="md:hidden divide-y">
              {ROLE_GUIDE.map((row) => {
                const isExpanded = expandedRoles.has(row.role);
                return (
                  <div key={row.role} className="p-4 space-y-1.5">
                    <div className="flex items-center justify-between">
                      <span className="text-sm font-semibold text-[var(--text-primary)]">{roleLabel(row.role)}</span>
                      <span className="text-xs app-chip bg-[var(--surface-overlay)] text-[var(--text-primary)]">{row.level}</span>
                    </div>
                    <p className="text-xs text-[var(--text-secondary)]">{row.who}</p>
                    <p className="text-xs text-[var(--text-primary)]">{row.can}</p>
                    <button
                      type="button"
                      onClick={() => toggleRoleExpanded(row.role)}
                      className="mt-2 inline-flex items-center gap-1.5 text-sm text-primary min-h-[40px]"
                    >
                      {isExpanded ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4" />}
                      {isExpanded ? 'Hide exact access' : 'View exact access'}
                    </button>
                    {isExpanded && (
                      <div className="mt-2">
                        <RolePermissionChips role={row.role} />
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
            <div className="hidden md:block overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b bg-[var(--surface-bg)]">
                    <th className="text-left px-4 py-3 font-medium text-[var(--text-secondary)]">Role</th>
                    <th className="text-left px-4 py-3 font-medium text-[var(--text-secondary)]">Hierarchy</th>
                    <th className="text-left px-4 py-3 font-medium text-[var(--text-secondary)]">Typical User</th>
                    <th className="text-left px-4 py-3 font-medium text-[var(--text-secondary)]">Primary Permissions</th>
                    <th className="text-left px-4 py-3 font-medium text-[var(--text-secondary)]">Access Details</th>
                  </tr>
                </thead>
                <tbody>
                  {ROLE_GUIDE.map((row) => {
                    const isExpanded = expandedRoles.has(row.role);
                    return (
                      <Fragment key={row.role}>
                        <tr className={isExpanded ? 'bg-[var(--surface-raised)]' : 'border-b'}>
                          <td className="px-4 py-3 text-[var(--text-primary)] font-medium">{roleLabel(row.role)}</td>
                          <td className="px-4 py-3 text-[var(--text-secondary)]">{row.level}</td>
                          <td className="px-4 py-3 text-[var(--text-secondary)]">{row.who}</td>
                          <td className="px-4 py-3 text-[var(--text-primary)]">{row.can}</td>
                          <td className="px-4 py-3">
                            <button
                              type="button"
                              onClick={() => toggleRoleExpanded(row.role)}
                              className="inline-flex items-center gap-1.5 text-xs font-medium text-primary hover:text-primary-dark"
                            >
                              {isExpanded ? <ChevronDown className="w-3.5 h-3.5" /> : <ChevronRight className="w-3.5 h-3.5" />}
                              {isExpanded ? 'Collapse' : 'Expand'}
                            </button>
                          </td>
                        </tr>
                        {isExpanded && (
                          <tr className="border-b bg-[var(--surface-raised)]">
                            <td colSpan={5} className="px-4 pb-4">
                              <RolePermissionChips role={row.role} />
                            </td>
                          </tr>
                        )}
                      </Fragment>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </details>
        </section>

        <section className="app-card overflow-hidden">
          <div className="px-4 py-3 border-b bg-[var(--surface-bg)] flex items-center justify-between">
            <h2 className="app-section-title text-lg">Existing Users</h2>
            {pendingSaves.length > 0 && (
              <span className="text-xs text-amber-700">{pendingSaves.length} unsaved role change(s)</span>
            )}
          </div>
          {isLoading ? (
            <div className="p-4 text-sm text-[var(--text-muted)]">Loading users...</div>
          ) : error ? (
            <div className="p-4 text-sm text-red-600 space-y-2">
                  Could not load users. Please try again.
              <div>
                <button
                  type="button"
                  onClick={() => refetch()}
                  disabled={isFetching}
                  className="bg-primary text-white px-3 py-2 rounded-xl min-h-[44px] text-xs font-medium disabled:opacity-50"
                >
                  {isFetching ? 'Retrying...' : 'Retry'}
                </button>
              </div>
            </div>
          ) : (
            <>
              <div className="p-4 border-b bg-[var(--surface-raised)] grid grid-cols-1 md:grid-cols-4 gap-3">
                <div className="relative md:col-span-2">
                  <Search className="w-4 h-4 absolute left-3 top-3 text-[var(--text-muted)]" />
                  <input
                    type="text"
                    value={search}
                    onChange={(e) => setSearch(e.target.value)}
                    placeholder="Search by name or email..."
                    className="w-full pl-9 pr-3 py-2 border border-[var(--border-soft)] rounded-xl min-h-[44px]"
                  />
                </div>
                <select
                  value={roleFilter}
                  onChange={(e) => setRoleFilter(e.target.value)}
                  className="border border-[var(--border-soft)] rounded-xl px-3 py-2 bg-[var(--surface-raised)] min-h-[44px]"
                >
                  <option value="">All roles</option>
                  {roles.map((role) => (
                    <option key={role} value={role}>{roleLabel(role)}</option>
                  ))}
                </select>
                <select
                  value={`${sortBy}:${sortDir}`}
                  onChange={(e) => {
                    const [field, dir] = e.target.value.split(':') as [UserSortField, 'asc' | 'desc'];
                    setSortBy(field);
                    setSortDir(dir);
                  }}
                  className="border border-[var(--border-soft)] rounded-xl px-3 py-2 bg-[var(--surface-raised)] min-h-[44px]"
                >
                  <option value="role:asc">Role A-Z</option>
                  <option value="role:desc">Role Z-A</option>
                  <option value="name:asc">Name A-Z</option>
                  <option value="name:desc">Name Z-A</option>
                  <option value="email:asc">Email A-Z</option>
                  <option value="email:desc">Email Z-A</option>
                  <option value="created_at:desc">Newest first</option>
                  <option value="created_at:asc">Oldest first</option>
                </select>
              </div>
              <div className="px-4 pt-2">
                <p
                  aria-live="polite"
                  className={`text-xs text-[var(--text-muted)] transition-opacity duration-200 ${isFetching ? 'opacity-100' : 'opacity-0'}`}
                >
                  Updating...
                </p>
              </div>

              <div className={`md:hidden divide-y transition-opacity duration-200 ${isFetching ? 'opacity-70' : 'opacity-100'}`}>
                {filteredUsers.map((user) => {
                  const isEditing = Boolean(draftByUser[user.id]);
                  const draft = getDraft(user);
                  const changed = hasChanges(user, draft);

                  return (
                    <div key={user.id} className="p-4 space-y-3">
                      {isEditing ? (
                        <div className="grid grid-cols-1 gap-2">
                          <div className="grid grid-cols-2 gap-2">
                            <input
                              type="text"
                              value={draft.firstName}
                              onChange={(e) => setDraftByUser((prev) => ({ ...prev, [user.id]: { ...draft, firstName: e.target.value } }))}
                              placeholder="First Name"
                              className="border border-[var(--border-soft)] rounded-xl px-3 py-2 min-h-[44px]"
                            />
                            <input
                              type="text"
                              value={draft.lastName}
                              onChange={(e) => setDraftByUser((prev) => ({ ...prev, [user.id]: { ...draft, lastName: e.target.value } }))}
                              placeholder="Last Name"
                              className="border border-[var(--border-soft)] rounded-xl px-3 py-2 min-h-[44px]"
                            />
                          </div>
                          <input
                            type="email"
                            value={draft.email}
                            onChange={(e) => setDraftByUser((prev) => ({ ...prev, [user.id]: { ...draft, email: e.target.value } }))}
                            placeholder="Email"
                            className="border border-[var(--border-soft)] rounded-xl px-3 py-2 min-h-[44px]"
                          />
                          <select
                            value={draft.role}
                            onChange={(e) => {
                              const newRole = e.target.value;
                              const oldType = roleAssignmentType(draft.role);
                              const newType = roleAssignmentType(newRole);
                              setDraftByUser((prev) => ({
                                ...prev,
                                [user.id]: {
                                  ...draft,
                                  role: newRole,
                                  assigned_village_id: newType === oldType ? draft.assigned_village_id : null,
                                  assigned_district_id: newType === oldType ? draft.assigned_district_id : null,
                                },
                              }));
                            }}
                            className="border border-[var(--border-soft)] rounded-xl px-3 py-2 bg-[var(--surface-raised)] min-h-[44px]"
                          >
                            {roles.map((role) => (
                              <option key={role} value={role}>{roleLabel(role)}</option>
                            ))}
                          </select>
                          {roleAssignmentType(draft.role) !== 'none' && (
                            <AssignmentDropdown
                              role={draft.role}
                              villageId={draft.assigned_village_id}
                              districtId={draft.assigned_district_id}
                              onVillageChange={(id) => setDraftByUser((prev) => ({ ...prev, [user.id]: { ...draft, assigned_village_id: id } }))}
                              onDistrictChange={(id) => setDraftByUser((prev) => ({ ...prev, [user.id]: { ...draft, assigned_district_id: id } }))}
                              villages={villages}
                              districts={districts}
                            />
                          )}
                          <div className="grid grid-cols-2 gap-2">
                            <button
                              type="button"
                              disabled={!changed || updateMutation.isPending}
                              onClick={() => updateMutation.mutate({ id: user.id, payload: draft })}
                              className="bg-primary text-white px-3 py-2 rounded-xl min-h-[44px] text-xs font-medium flex items-center justify-center gap-1 disabled:opacity-50"
                            >
                              <Save className="w-3.5 h-3.5" /> Save
                            </button>
                            <button
                              type="button"
                              onClick={() => cancelEdit(user.id)}
                              className="bg-[var(--surface-raised)] border border-[var(--border-soft)] text-[var(--text-primary)] px-3 py-2 rounded-xl min-h-[44px] text-xs font-medium flex items-center justify-center gap-1"
                            >
                              <X className="w-3.5 h-3.5" /> Cancel
                            </button>
                            <button
                              type="button"
                              disabled={resendInviteMutation.isPending}
                              onClick={() => resendInviteMutation.mutate(user.id)}
                              className="col-span-2 bg-[var(--surface-raised)] border border-[var(--border-soft)] text-[var(--text-primary)] px-3 py-2 rounded-xl min-h-[44px] text-xs font-medium flex items-center justify-center gap-1 disabled:opacity-50"
                            >
                              <Mail className="w-3.5 h-3.5" /> Resend
                            </button>
                          </div>
                        </div>
                      ) : (
                        <>
                          <div>
                            <p className="text-sm font-medium text-[var(--text-primary)]">{user.name || 'Unnamed user'}</p>
                            <p className="text-xs text-[var(--text-secondary)] break-all">{user.email}</p>
                            <p className="text-xs text-[var(--text-secondary)] mt-1">Role: {roleLabel(user.role)}</p>
                            {assignmentLabel(user, villages, districts) && (
                              <p className={`text-xs mt-0.5 ${user.assigned_village_id || user.assigned_district_id ? 'text-[var(--text-secondary)]' : 'text-amber-600'}`}>
                                {assignmentLabel(user, villages, districts)}
                              </p>
                            )}
                            <p className="text-xs text-[var(--text-muted)] mt-1">
                              {scopeLabelForRole(user.role, user.assigned_district_id, user.assigned_village_id, villages, districts)}
                            </p>
                            <RolePermissionsDisclosure role={user.role} />
                          </div>
                          <div className="grid grid-cols-2 gap-2">
                            <button
                              type="button"
                              onClick={() => startEdit(user)}
                              className="bg-primary text-white px-3 py-2 rounded-xl min-h-[44px] text-xs font-medium flex items-center justify-center gap-1"
                            >
                              <Pencil className="w-3.5 h-3.5" /> Edit
                            </button>
                            <button
                              type="button"
                              disabled={resendInviteMutation.isPending}
                              onClick={() => resendInviteMutation.mutate(user.id)}
                              className="bg-[var(--surface-raised)] border border-[var(--border-soft)] text-[var(--text-primary)] px-3 py-2 rounded-xl min-h-[44px] text-xs font-medium flex items-center justify-center gap-1 disabled:opacity-50"
                            >
                              <Mail className="w-3.5 h-3.5" /> Resend
                            </button>
                            {user.id !== currentUserId && (
                              <button
                                type="button"
                                disabled={deleteMutation.isPending}
                                onClick={() => {
                                  if (!window.confirm(`Remove ${user.name || user.email}? They will lose access to the app.`)) return;
                                  deleteMutation.mutate(user.id);
                                }}
                                className="col-span-2 bg-red-50 border border-red-200 text-red-600 px-3 py-2 rounded-xl min-h-[44px] text-xs font-medium flex items-center justify-center gap-1 disabled:opacity-50"
                              >
                                <Trash2 className="w-3.5 h-3.5" /> Remove
                              </button>
                            )}
                          </div>
                        </>
                      )}
                    </div>
                  );
                })}
                {filteredUsers.length === 0 && (
                  <div className="p-4 text-sm text-[var(--text-muted)]">No users match current filters.</div>
                )}
              </div>

              <div className={`hidden md:block overflow-x-auto transition-opacity duration-200 ${isFetching ? 'opacity-80' : 'opacity-100'}`}>
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b bg-[var(--surface-bg)]">
                      <th className="text-left px-4 py-3 font-medium text-[var(--text-secondary)]">
                        <button type="button" onClick={() => handleSort('name')} className="hover:text-[var(--text-primary)]">Name</button>
                      </th>
                      <th className="text-left px-4 py-3 font-medium text-[var(--text-secondary)]">
                        <button type="button" onClick={() => handleSort('email')} className="hover:text-[var(--text-primary)]">Email</button>
                      </th>
                      <th className="text-left px-4 py-3 font-medium text-[var(--text-secondary)]">
                        <button type="button" onClick={() => handleSort('role')} className="hover:text-[var(--text-primary)]">Role</button>
                      </th>
                      <th className="text-left px-4 py-3 font-medium text-[var(--text-secondary)]">Area</th>
                      <th className="text-left px-4 py-3 font-medium text-[var(--text-secondary)]">Action</th>
                    </tr>
                  </thead>
                  <tbody>
                    {filteredUsers.map((user) => {
                      const isEditing = Boolean(draftByUser[user.id]);
                      const draft = getDraft(user);
                      const changed = hasChanges(user, draft);
                      const isPermissionsExpanded = expandedUserPermissions.has(user.id);

                      return (
                        <Fragment key={user.id}>
                          <tr className="border-b">
                            <td className="px-4 py-3 text-[var(--text-primary)]">
                              {isEditing ? (
                                <div className="flex gap-2">
                                  <input
                                    type="text"
                                    value={draft.firstName}
                                    onChange={(e) => setDraftByUser((prev) => ({ ...prev, [user.id]: { ...draft, firstName: e.target.value } }))}
                                    placeholder="First"
                                    className="border border-[var(--border-soft)] rounded-xl px-3 py-2 bg-[var(--surface-raised)] min-h-[44px] w-full"
                                  />
                                  <input
                                    type="text"
                                    value={draft.lastName}
                                    onChange={(e) => setDraftByUser((prev) => ({ ...prev, [user.id]: { ...draft, lastName: e.target.value } }))}
                                    placeholder="Last"
                                    className="border border-[var(--border-soft)] rounded-xl px-3 py-2 bg-[var(--surface-raised)] min-h-[44px] w-full"
                                  />
                                </div>
                              ) : (
                                user.name || '—'
                              )}
                            </td>
                            <td className="px-4 py-3 text-[var(--text-secondary)]">
                              {isEditing ? (
                                <input
                                  type="email"
                                  value={draft.email}
                                  onChange={(e) => setDraftByUser((prev) => ({ ...prev, [user.id]: { ...draft, email: e.target.value } }))}
                                  className="border border-[var(--border-soft)] rounded-xl px-3 py-2 bg-[var(--surface-raised)] min-h-[44px] w-full"
                                />
                              ) : (
                                user.email
                              )}
                            </td>
                            <td className="px-4 py-3">
                              {isEditing ? (
                                <select
                                  value={draft.role}
                                  onChange={(e) => {
                                    const newRole = e.target.value;
                                    const oldType = roleAssignmentType(draft.role);
                                    const newType = roleAssignmentType(newRole);
                                    setDraftByUser((prev) => ({
                                      ...prev,
                                      [user.id]: {
                                        ...draft,
                                        role: newRole,
                                        assigned_village_id: newType === oldType ? draft.assigned_village_id : null,
                                        assigned_district_id: newType === oldType ? draft.assigned_district_id : null,
                                      },
                                    }));
                                  }}
                                  className="border border-[var(--border-soft)] rounded-xl px-3 py-2 bg-[var(--surface-raised)] min-h-[44px]"
                                >
                                  {roles.map((role) => (
                                    <option key={role} value={role}>{roleLabel(role)}</option>
                                  ))}
                                </select>
                              ) : (
                                roleLabel(user.role)
                              )}
                            </td>
                            <td className="px-4 py-3">
                              {isEditing ? (
                                roleAssignmentType(draft.role) !== 'none' ? (
                                  <AssignmentDropdown
                                    role={draft.role}
                                    villageId={draft.assigned_village_id}
                                    districtId={draft.assigned_district_id}
                                    onVillageChange={(id) => setDraftByUser((prev) => ({ ...prev, [user.id]: { ...draft, assigned_village_id: id } }))}
                                    onDistrictChange={(id) => setDraftByUser((prev) => ({ ...prev, [user.id]: { ...draft, assigned_district_id: id } }))}
                                    villages={villages}
                                    districts={districts}
                                  />
                                ) : (
                                  <span className="text-xs text-[var(--text-muted)]">Full access</span>
                                )
                              ) : (
                                <div>
                                  <span className={`block text-xs font-medium ${user.assigned_village_id || user.assigned_district_id ? 'text-[var(--text-primary)]' : roleAssignmentType(user.role) === 'none' ? 'text-[var(--text-muted)]' : 'text-amber-600'}`}>
                                    {assignmentLabel(user, villages, districts) || 'Full access'}
                                  </span>
                                  <span className="block text-[11px] text-[var(--text-muted)] mt-0.5">
                                    {scopeLabelForRole(user.role, user.assigned_district_id, user.assigned_village_id, villages, districts)}
                                  </span>
                                  <button
                                    type="button"
                                    onClick={() => toggleUserPermissions(user.id)}
                                    className="mt-1 inline-flex items-center gap-1 text-[11px] text-primary hover:text-primary/80"
                                  >
                                    {isPermissionsExpanded ? <ChevronDown className="w-3 h-3" /> : <ChevronRight className="w-3 h-3" />}
                                    <span>Access details ({PERMISSION_KEYS.filter((permission) => roleHasPermission(user.role, permission)).length}/{PERMISSION_KEYS.length})</span>
                                  </button>
                                </div>
                              )}
                            </td>
                            <td className="px-4 py-3">
                              <div className="flex items-center gap-2">
                                {isEditing ? (
                                  <>
                                    <button
                                      type="button"
                                      disabled={!changed || updateMutation.isPending}
                                      onClick={() => updateMutation.mutate({ id: user.id, payload: draft })}
                                      className="bg-primary text-white px-3 py-2 rounded-xl min-h-[44px] text-xs font-medium flex items-center gap-1 disabled:opacity-50"
                                    >
                                      <Save className="w-3.5 h-3.5" /> Save
                                    </button>
                                    <button
                                      type="button"
                                      onClick={() => cancelEdit(user.id)}
                                      className="bg-[var(--surface-raised)] border border-[var(--border-soft)] text-[var(--text-primary)] px-3 py-2 rounded-xl min-h-[44px] text-xs font-medium flex items-center gap-1"
                                    >
                                      <X className="w-3.5 h-3.5" /> Cancel
                                    </button>
                                  </>
                                ) : (
                                  <button
                                    type="button"
                                    onClick={() => startEdit(user)}
                                    className="bg-primary text-white px-3 py-2 rounded-xl min-h-[44px] text-xs font-medium flex items-center gap-1"
                                  >
                                    <Pencil className="w-3.5 h-3.5" /> Edit
                                  </button>
                                )}
                                <button
                                  type="button"
                                  disabled={resendInviteMutation.isPending}
                                  onClick={() => resendInviteMutation.mutate(user.id)}
                                  className="bg-[var(--surface-raised)] border border-[var(--border-soft)] text-[var(--text-primary)] px-3 py-2 rounded-xl min-h-[44px] text-xs font-medium flex items-center gap-1 disabled:opacity-50"
                                >
                                  <Mail className="w-3.5 h-3.5" /> Resend
                                </button>
                                {user.id !== currentUserId && (
                                  <button
                                    type="button"
                                    disabled={deleteMutation.isPending}
                                    onClick={() => {
                                      if (!window.confirm(`Remove ${user.name || user.email}? They will lose access to the app.`)) return;
                                      deleteMutation.mutate(user.id);
                                    }}
                                    className="bg-red-50 border border-red-200 text-red-600 px-3 py-2 rounded-xl min-h-[44px] text-xs font-medium flex items-center gap-1 disabled:opacity-50"
                                  >
                                    <Trash2 className="w-3.5 h-3.5" /> Remove
                                  </button>
                                )}
                              </div>
                            </td>
                          </tr>
                          {!isEditing && isPermissionsExpanded && (
                            <tr className="border-b bg-[var(--surface-raised)]">
                              <td colSpan={5} className="px-4 py-3">
                                <RolePermissionChips role={user.role} />
                              </td>
                            </tr>
                          )}
                        </Fragment>
                      );
                    })}
                    {filteredUsers.length === 0 && (
                      <tr>
                        <td colSpan={5} className="px-4 py-8 text-center text-[var(--text-muted)]">
                          No users match current filters.
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>
            </>
          )}
        </section>
      </div>
    </WorkspacePage>
  );
}
