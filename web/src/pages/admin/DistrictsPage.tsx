import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import {
  assignVillagesToDistrict,
  createDistrict,
  deleteDistrict,
  getDistricts,
  updateDistrict,
} from '../../lib/api';
import { useSession } from '../../hooks/useSession';
import {
  ChevronDown,
  ChevronUp,
  MapPin,
  Pencil,
  Plus,
  Save,
  Trash2,
  Users,
  X,
} from 'lucide-react';
import WorkspacePage from '../../components/WorkspacePage';

interface VillageSummary {
  id: number;
  name: string;
  verified_count?: number;
  total_count?: number;
  supporter_count: number;
  registered_voters: number;
}

interface District {
  id: number;
  name: string;
  description: string | null;
  villages: VillageSummary[];
  verified_count?: number;
  total_count?: number;
  supporter_count: number;
  registered_voters: number;
}

interface DistrictsResponse {
  districts: District[];
  unassigned_villages: VillageSummary[];
}

export default function DistrictsPage() {
  const queryClient = useQueryClient();
  const { data: sessionData } = useSession();
  const { data, isLoading } = useQuery<DistrictsResponse>({
    queryKey: ['districts'],
    queryFn: getDistricts,
  });

  const [newName, setNewName] = useState('');
  const [newDescription, setNewDescription] = useState('');
  const [expandedId, setExpandedId] = useState<number | null>(null);
  const [editingId, setEditingId] = useState<number | null>(null);
  const [editName, setEditName] = useState('');
  const [editDescription, setEditDescription] = useState('');
  const [assigningId, setAssigningId] = useState<number | null>(null);
  const [selectedVillageIds, setSelectedVillageIds] = useState<number[]>([]);

  const districts = data?.districts || [];
  const unassignedVillages = data?.unassigned_villages || [];
  const canManageDistricts = sessionData?.user?.role === 'campaign_admin';

  // All villages for assignment UI
  const allVillages = [
    ...districts.flatMap((d) => d.villages),
    ...unassignedVillages,
  ].sort((a, b) => a.name.localeCompare(b.name));

  const createMutation = useMutation({
    mutationFn: () => createDistrict({ name: newName, description: newDescription || null }),
    onSuccess: () => {
      setNewName('');
      setNewDescription('');
      queryClient.invalidateQueries({ queryKey: ['districts'] });
    },
  });

  const updateMutation = useMutation({
    mutationFn: (id: number) => updateDistrict(id, { name: editName, description: editDescription || null }),
    onSuccess: () => {
      setEditingId(null);
      queryClient.invalidateQueries({ queryKey: ['districts'] });
    },
  });

  const deleteMutation = useMutation({
    mutationFn: (id: number) => deleteDistrict(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['districts'] });
    },
  });

  const assignMutation = useMutation({
    mutationFn: (id: number) => assignVillagesToDistrict(id, selectedVillageIds),
    onSuccess: () => {
      setAssigningId(null);
      setSelectedVillageIds([]);
      queryClient.invalidateQueries({ queryKey: ['districts'] });
      queryClient.invalidateQueries({ queryKey: ['villages'] });
    },
  });

  const startEdit = (district: District) => {
    setEditingId(district.id);
    setEditName(district.name);
    setEditDescription(district.description || '');
  };

  const startAssign = (district: District) => {
    setAssigningId(district.id);
    setSelectedVillageIds(district.villages.map((v) => v.id));
  };

  const toggleVillage = (villageId: number) => {
    setSelectedVillageIds((prev) =>
      prev.includes(villageId) ? prev.filter((id) => id !== villageId) : [...prev, villageId]
    );
  };

  return (
    <WorkspacePage width="full" className="space-y-6">
      <div>
        <h1 className="flex items-center gap-2 text-2xl font-bold tracking-tight text-gray-900">
          <MapPin className="w-5 h-5 text-primary" /> District Management
        </h1>
        <p className="text-gray-500 text-sm">
          Organize villages into districts for coordinator-level management. District coordinators see all villages in their assigned district.
        </p>
      </div>

      {/* Create district */}
      {canManageDistricts ? (
        <section className="app-card p-4">
          <h2 className="app-section-title text-lg mb-2">Create District</h2>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
            <input
              type="text"
              value={newName}
              onChange={(e) => setNewName(e.target.value)}
              placeholder="District name (e.g. North, Central, South)"
              className="border border-[var(--border-soft)] rounded-xl px-3 py-2 md:col-span-2 min-h-[44px]"
            />
            <input
              type="text"
              value={newDescription}
              onChange={(e) => setNewDescription(e.target.value)}
              placeholder="Description (optional)"
              className="border border-[var(--border-soft)] rounded-xl px-3 py-2 min-h-[44px]"
            />
          </div>
          <button
            type="button"
            onClick={() => createMutation.mutate()}
            disabled={!newName.trim() || createMutation.isPending}
            className="mt-3 bg-primary text-white px-4 py-2 rounded-xl min-h-[44px] text-sm font-medium flex items-center gap-2 disabled:opacity-50"
          >
            <Plus className="w-4 h-4" /> {createMutation.isPending ? 'Creating...' : 'Create District'}
          </button>
          {createMutation.isError && (
            <p className="text-sm text-red-600 mt-2">Could not create district. Check name and try again.</p>
          )}
        </section>
      ) : (
        <section className="app-card p-4">
          <p className="text-sm text-[var(--text-secondary)]">
            District structure is read-only for your role.
          </p>
        </section>
      )}

      {/* Districts list */}
      {isLoading ? (
        <div className="text-sm text-[var(--text-muted)] py-8">Loading districts...</div>
      ) : districts.length === 0 ? (
        <section className="app-card p-6 text-center">
          <MapPin className="w-8 h-8 text-[var(--text-muted)] mx-auto mb-2" />
          <p className="text-[var(--text-secondary)] text-sm">No districts configured yet.</p>
          <p className="text-[var(--text-muted)] text-xs mt-1">Create your first district above, then assign villages to it.</p>
        </section>
      ) : (
        <section className="space-y-3">
          {districts.map((district) => {
            const isExpanded = expandedId === district.id;
            const isEditing = editingId === district.id;
            const isAssigning = assigningId === district.id;

            return (
              <div key={district.id} className="app-card overflow-hidden">
                {/* Header */}
                <div className="px-4 py-3 flex items-center justify-between gap-3">
                  <button
                    type="button"
                    onClick={() => setExpandedId(isExpanded ? null : district.id)}
                    className="flex-1 text-left flex items-center gap-3"
                  >
                    <div>
                      <h3 className="font-bold text-[var(--text-primary)]">{district.name}</h3>
                      {district.description && (
                        <p className="text-xs text-[var(--text-secondary)]">{district.description}</p>
                      )}
                      <div className="flex items-center gap-3 mt-1 text-xs text-[var(--text-muted)]">
                        <span className="flex items-center gap-1">
                          <MapPin className="w-3 h-3" /> {district.villages.length} village{district.villages.length !== 1 ? 's' : ''}
                        </span>
                        <span className="flex items-center gap-1">
                          <Users className="w-3 h-3" /> {district.supporter_count.toLocaleString()} supporter{district.supporter_count !== 1 ? 's' : ''}
                        </span>
                        <span>{district.registered_voters.toLocaleString()} registered voters</span>
                      </div>
                    </div>
                    {isExpanded ? <ChevronUp className="w-4 h-4 text-[var(--text-muted)] shrink-0" /> : <ChevronDown className="w-4 h-4 text-[var(--text-muted)] shrink-0" />}
                  </button>
                </div>

                {/* Expanded content */}
                {isExpanded && (
                  <div className="px-4 pb-4 border-t border-[var(--border-soft)] pt-3 space-y-3">
                    {/* Action buttons */}
                    {canManageDistricts && (
                      <div className="flex flex-wrap gap-2">
                        <button
                          type="button"
                          onClick={() => startEdit(district)}
                          className="text-xs px-3 py-1.5 rounded-lg border border-[var(--border-soft)] text-[var(--text-secondary)] hover:bg-[var(--surface-bg)] flex items-center gap-1"
                        >
                          <Pencil className="w-3 h-3" /> Edit
                        </button>
                        <button
                          type="button"
                          onClick={() => startAssign(district)}
                          className="text-xs px-3 py-1.5 rounded-lg border border-[var(--border-soft)] text-[var(--text-secondary)] hover:bg-[var(--surface-bg)] flex items-center gap-1"
                        >
                          <MapPin className="w-3 h-3" /> Assign Villages
                        </button>
                        <button
                          type="button"
                          onClick={() => {
                            if (!window.confirm(`Delete district "${district.name}"? Villages will be unassigned but not deleted.`)) return;
                            deleteMutation.mutate(district.id);
                          }}
                          disabled={deleteMutation.isPending}
                          className="text-xs px-3 py-1.5 rounded-lg border border-red-200 text-red-600 hover:bg-red-50 flex items-center gap-1 disabled:opacity-50"
                        >
                          <Trash2 className="w-3 h-3" /> Delete
                        </button>
                      </div>
                    )}

                    {/* Edit form */}
                    {isEditing && (
                      <div className="bg-[var(--surface-bg)] rounded-xl p-3 space-y-2">
                        <input
                          type="text"
                          value={editName}
                          onChange={(e) => setEditName(e.target.value)}
                          placeholder="District name"
                          className="w-full border border-[var(--border-soft)] rounded-xl px-3 py-2 min-h-[44px]"
                        />
                        <input
                          type="text"
                          value={editDescription}
                          onChange={(e) => setEditDescription(e.target.value)}
                          placeholder="Description (optional)"
                          className="w-full border border-[var(--border-soft)] rounded-xl px-3 py-2 min-h-[44px]"
                        />
                        <div className="flex gap-2">
                          <button
                            type="button"
                            onClick={() => updateMutation.mutate(district.id)}
                            disabled={!editName.trim() || updateMutation.isPending}
                            className="bg-primary text-white px-3 py-2 rounded-xl min-h-[44px] text-xs font-medium flex items-center gap-1 disabled:opacity-50"
                          >
                            <Save className="w-3.5 h-3.5" /> Save
                          </button>
                          <button
                            type="button"
                            onClick={() => setEditingId(null)}
                            className="border border-[var(--border-soft)] px-3 py-2 rounded-xl min-h-[44px] text-xs font-medium flex items-center gap-1"
                          >
                            <X className="w-3.5 h-3.5" /> Cancel
                          </button>
                        </div>
                      </div>
                    )}

                    {/* Assign villages */}
                    {isAssigning && (
                      <div className="bg-[var(--surface-bg)] rounded-xl p-3 space-y-2">
                        <p className="text-xs text-[var(--text-secondary)] mb-2">
                          Check the villages that belong to this district. Villages can only belong to one district at a time.
                        </p>
                        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-1.5 max-h-[300px] overflow-y-auto">
                          {allVillages.map((v) => (
                            <label
                              key={v.id}
                              className={`flex items-center gap-2 px-3 py-2 rounded-lg cursor-pointer text-sm ${
                                selectedVillageIds.includes(v.id)
                                  ? 'bg-blue-50 border border-blue-200'
                                  : 'bg-[var(--surface-raised)] border border-[var(--border-soft)]'
                              }`}
                            >
                              <input
                                type="checkbox"
                                checked={selectedVillageIds.includes(v.id)}
                                onChange={() => toggleVillage(v.id)}
                                className="rounded"
                              />
                              <span className="truncate">{v.name}</span>
                            </label>
                          ))}
                        </div>
                        <div className="flex gap-2 pt-1">
                          <button
                            type="button"
                            onClick={() => assignMutation.mutate(district.id)}
                            disabled={assignMutation.isPending}
                            className="bg-primary text-white px-3 py-2 rounded-xl min-h-[44px] text-xs font-medium flex items-center gap-1 disabled:opacity-50"
                          >
                            <Save className="w-3.5 h-3.5" /> {assignMutation.isPending ? 'Saving...' : `Save (${selectedVillageIds.length} villages)`}
                          </button>
                          <button
                            type="button"
                            onClick={() => { setAssigningId(null); setSelectedVillageIds([]); }}
                            className="border border-[var(--border-soft)] px-3 py-2 rounded-xl min-h-[44px] text-xs font-medium flex items-center gap-1"
                          >
                            <X className="w-3.5 h-3.5" /> Cancel
                          </button>
                        </div>
                      </div>
                    )}

                    {/* Villages list */}
                    {!isAssigning && (
                      district.villages.length > 0 ? (
                        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2">
                          {district.villages.map((v) => (
                            <div key={v.id} className="bg-[var(--surface-raised)] border border-[var(--border-soft)] rounded-xl p-3">
                              <p className="font-medium text-sm text-[var(--text-primary)]">{v.name}</p>
                              <div className="text-xs text-[var(--text-muted)] mt-1 space-y-0.5">
                                <p>{v.supporter_count} supporter{v.supporter_count !== 1 ? 's' : ''}</p>
                                <p>{v.registered_voters.toLocaleString()} registered voters</p>
                              </div>
                            </div>
                          ))}
                        </div>
                      ) : (
                        <p className="text-xs text-[var(--text-muted)]">No villages assigned yet. Click "Assign Villages" to add them.</p>
                      )
                    )}
                  </div>
                )}
              </div>
            );
          })}
        </section>
      )}

      {/* Unassigned villages */}
      {unassignedVillages.length > 0 && (
        <section className="app-card p-4">
          <h2 className="app-section-title text-lg mb-2 flex items-center gap-2">
            <MapPin className="w-4 h-4 text-amber-500" /> Unassigned Villages
          </h2>
          <p className="text-xs text-[var(--text-secondary)] mb-3">
            These {unassignedVillages.length} village{unassignedVillages.length !== 1 ? 's are' : ' is'} not assigned to any district.
            {districts.length > 0 ? ' Expand a district above and click "Assign Villages" to organize them.' : ' Create a district first, then assign villages to it.'}
          </p>
          <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-2">
            {unassignedVillages.map((v) => (
              <div key={v.id} className="bg-amber-50 border border-amber-200 rounded-xl p-3">
                <p className="font-medium text-sm text-[var(--text-primary)]">{v.name}</p>
                <p className="text-xs text-[var(--text-muted)] mt-1">{v.registered_voters.toLocaleString()} voters</p>
              </div>
            ))}
          </div>
        </section>
      )}
    </WorkspacePage>
  );
}
