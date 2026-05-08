import { useEffect, useMemo, useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { getEvents, createEvent, getVillages } from '../../lib/api';
import { Link, useSearchParams } from 'react-router-dom';
import { Plus, Calendar, MapPin, Search, Users, X } from 'lucide-react';
import { useSession } from '../../hooks/useSession';
import WorkspacePage from '../../components/WorkspacePage';

interface EventForm {
  name: string;
  event_type: string;
  date: string;
  time: string;
  location: string;
  description: string;
  village_id: string;
  quota: string;
}

interface VillageOption {
  id: number;
  name: string;
}

interface EventItem {
  id: number;
  name: string;
  event_type: string;
  status?: string;
  date: string;
  location?: string;
  village_name?: string;
  attended_count: number;
  invited_count: number;
  quota?: number;
  show_up_rate: number;
}

type EventSortField = 'date' | 'name' | 'event_type' | 'attended_count' | 'show_up_rate';

export default function EventsPage() {
  const queryClient = useQueryClient();
  const { data: sessionData } = useSession();
  const [searchParams, setSearchParams] = useSearchParams();
  const [showCreate, setShowCreate] = useState(false);
  const [form, setForm] = useState<EventForm>({
    name: '', event_type: 'motorcade', date: '', time: '', location: '',
    description: '', village_id: '', quota: '',
  });

  const { data: eventsData, isFetching } = useQuery({ queryKey: ['events'], queryFn: () => getEvents() });
  const { data: villageData } = useQuery({ queryKey: ['villages'], queryFn: getVillages });
  const [search, setSearch] = useState(searchParams.get('search') || '');
  const [typeFilter, setTypeFilter] = useState(searchParams.get('type') || '');
  const [statusFilter, setStatusFilter] = useState(searchParams.get('status') || '');
  const [sortBy, setSortBy] = useState<EventSortField>((searchParams.get('sort_by') as EventSortField) || 'date');
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>((searchParams.get('sort_dir') as 'asc' | 'desc') || 'desc');

  const create = useMutation({
    mutationFn: (data: Record<string, unknown>) => createEvent(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['events'] });
      setShowCreate(false);
      setForm({ name: '', event_type: 'motorcade', date: '', time: '', location: '', description: '', village_id: '', quota: '' });
    },
  });

  const events: EventItem[] = useMemo(() => eventsData?.events || [], [eventsData]);
  const villagesAll: VillageOption[] = useMemo(() => villageData?.villages || [], [villageData]);
  const scopedVillageIds = sessionData?.user?.scoped_village_ids ?? null;
  const villages: VillageOption[] = useMemo(() => {
    if (scopedVillageIds === null) return villagesAll;
    const allowed = new Set(scopedVillageIds);
    return villagesAll.filter((v) => allowed.has(v.id));
  }, [scopedVillageIds, villagesAll]);
  const filteredEvents = useMemo(() => {
    const q = search.trim().toLowerCase();
    const filtered = events.filter((e) => {
      const searchHit = q.length === 0 ||
        e.name.toLowerCase().includes(q) ||
        (e.location || '').toLowerCase().includes(q) ||
        (e.village_name || '').toLowerCase().includes(q);
      const typeHit = typeFilter ? e.event_type === typeFilter : true;
      const statusHit = statusFilter ? (e.status || '') === statusFilter : true;
      return searchHit && typeHit && statusHit;
    });

    return [...filtered].sort((a, b) => {
      const dir = sortDir === 'asc' ? 1 : -1;
      if (sortBy === 'date') {
        const aDate = new Date(a.date).getTime();
        const bDate = new Date(b.date).getTime();
        return (aDate - bDate) * dir;
      }
      if (sortBy === 'name') return a.name.localeCompare(b.name) * dir;
      if (sortBy === 'event_type') return a.event_type.localeCompare(b.event_type) * dir;
      if (sortBy === 'attended_count') return (a.attended_count - b.attended_count) * dir;
      return (a.show_up_rate - b.show_up_rate) * dir;
    });
  }, [events, search, typeFilter, statusFilter, sortBy, sortDir]);

  useEffect(() => {
    const params = new URLSearchParams();
    if (search) params.set('search', search);
    if (typeFilter) params.set('type', typeFilter);
    if (statusFilter) params.set('status', statusFilter);
    params.set('sort_by', sortBy);
    params.set('sort_dir', sortDir);
    setSearchParams(params, { replace: true });
  }, [search, typeFilter, statusFilter, sortBy, sortDir, setSearchParams]);

  const typeColors: Record<string, string> = {
    motorcade: 'bg-blue-100 text-blue-700',
    rally: 'bg-purple-100 text-purple-700',
    fundraiser: 'bg-green-100 text-green-700',
    meeting: 'bg-yellow-100 text-yellow-700',
    other: 'bg-[var(--surface-overlay)] text-[var(--text-primary)]',
  };

  return (
    <WorkspacePage width="full" className="space-y-6">
      {/* Header */}
      <div>
        <div className="flex items-center justify-between">
          <h1 className="text-2xl font-bold text-gray-900 tracking-tight">Events</h1>
          <button onClick={() => setShowCreate(true)} className="app-btn-danger flex items-center gap-1">
            <Plus className="w-4 h-4" /> New Event
          </button>
        </div>
      </div>

      <div>
        {/* Create Modal */}
        {showCreate && (
          <div className="app-card p-6 mb-6">
            <div className="flex items-center justify-between mb-4">
              <h2 className="text-lg font-semibold">Create Event</h2>
              <button onClick={() => setShowCreate(false)} className="p-2 min-h-[44px] min-w-[44px] flex items-center justify-center"><X className="w-5 h-5 text-[var(--text-muted)]" /></button>
            </div>
            <form onSubmit={e => { e.preventDefault(); create.mutate({
              ...form,
              village_id: form.village_id ? Number(form.village_id) : null,
              quota: form.quota ? Number(form.quota) : null,
            }); }} className="space-y-3">
              <input required value={form.name} onChange={e => setForm(f => ({...f, name: e.target.value}))}
                placeholder="Event name" className="w-full px-3 py-2 border border-[var(--border-soft)] rounded-xl" />
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <select value={form.event_type} onChange={e => setForm(f => ({...f, event_type: e.target.value}))}
                  className="px-3 py-2 border border-[var(--border-soft)] rounded-xl bg-[var(--surface-raised)]">
                  <option value="motorcade">Motorcade</option>
                  <option value="rally">Rally</option>
                  <option value="fundraiser">Fundraiser</option>
                  <option value="meeting">Meeting</option>
                  <option value="other">Other</option>
                </select>
                <input required type="date" value={form.date} onChange={e => setForm(f => ({...f, date: e.target.value}))}
                  className="px-3 py-2 border border-[var(--border-soft)] rounded-xl" />
              </div>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <input type="time" value={form.time} onChange={e => setForm(f => ({...f, time: e.target.value}))}
                  className="px-3 py-2 border border-[var(--border-soft)] rounded-xl" placeholder="Time" />
                <input value={form.location} onChange={e => setForm(f => ({...f, location: e.target.value}))}
                  className="px-3 py-2 border border-[var(--border-soft)] rounded-xl" placeholder="Location" />
              </div>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <select value={form.village_id} onChange={e => setForm(f => ({...f, village_id: e.target.value}))}
                  className="px-3 py-2 border border-[var(--border-soft)] rounded-xl bg-[var(--surface-raised)]">
                  <option value="">{scopedVillageIds === null ? 'All villages' : 'All accessible villages'}</option>
                  {villages.map((v) => <option key={v.id} value={v.id}>{v.name}</option>)}
                </select>
                <input type="number" value={form.quota} onChange={e => setForm(f => ({...f, quota: e.target.value}))}
                  className="px-3 py-2 border border-[var(--border-soft)] rounded-xl" placeholder="Quota (min attendees)" />
              </div>
              <textarea value={form.description} onChange={e => setForm(f => ({...f, description: e.target.value}))}
                className="w-full px-3 py-2 border border-[var(--border-soft)] rounded-xl" rows={2} placeholder="Description (optional)" />
              <button type="submit" disabled={create.isPending}
                className="w-full bg-primary hover:bg-primary-dark text-white font-bold py-3 rounded-xl">
                {create.isPending ? 'Creating...' : 'Create Event'}
              </button>
            </form>
          </div>
        )}

        {/* Events List */}
        <div className="app-card p-4 mb-4 grid grid-cols-1 md:grid-cols-5 gap-3">
          <div className="relative md:col-span-2">
            <Search className="w-4 h-4 absolute left-3 top-3 text-[var(--text-muted)]" />
            <input
              type="text"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search events, location, or village..."
              className="w-full pl-9 pr-3 py-2 border border-[var(--border-soft)] rounded-xl min-h-[44px]"
            />
          </div>
          <select
            value={typeFilter}
            onChange={(e) => setTypeFilter(e.target.value)}
            className="border border-[var(--border-soft)] rounded-xl px-3 py-2 bg-[var(--surface-raised)] min-h-[44px]"
          >
            <option value="">All event types</option>
            <option value="motorcade">Motorcade</option>
            <option value="rally">Rally</option>
            <option value="fundraiser">Fundraiser</option>
            <option value="meeting">Meeting</option>
            <option value="other">Other</option>
          </select>
          <select
            value={statusFilter}
            onChange={(e) => setStatusFilter(e.target.value)}
            className="border border-[var(--border-soft)] rounded-xl px-3 py-2 bg-[var(--surface-raised)] min-h-[44px]"
          >
            <option value="">All statuses</option>
            <option value="upcoming">Upcoming</option>
            <option value="active">Active</option>
            <option value="completed">Completed</option>
            <option value="cancelled">Cancelled</option>
          </select>
          <select
            value={`${sortBy}:${sortDir}`}
            onChange={(e) => {
              const [field, dir] = e.target.value.split(':') as [EventSortField, 'asc' | 'desc'];
              setSortBy(field);
              setSortDir(dir);
            }}
            className="border border-[var(--border-soft)] rounded-xl px-3 py-2 bg-[var(--surface-raised)] min-h-[44px]"
          >
            <option value="date:desc">Newest first</option>
            <option value="date:asc">Oldest first</option>
            <option value="name:asc">Name A-Z</option>
            <option value="name:desc">Name Z-A</option>
            <option value="attended_count:desc">Most attended</option>
            <option value="attended_count:asc">Least attended</option>
            <option value="show_up_rate:desc">Highest show-up</option>
            <option value="show_up_rate:asc">Lowest show-up</option>
          </select>
        </div>
        <div className="mb-2">
          <p
            aria-live="polite"
            className={`text-xs text-[var(--text-muted)] transition-opacity duration-200 ${isFetching ? 'opacity-100' : 'opacity-0'}`}
          >
            Updating...
          </p>
        </div>

        <div className={`space-y-4 transition-opacity duration-200 ${isFetching ? 'opacity-70' : 'opacity-100'}`}>
          {filteredEvents.map((e) => (
            <Link key={e.id} to={`/admin/events/${e.id}`}
              className="block app-card p-4 hover:shadow-md transition-shadow">
              <div className="flex items-center justify-between mb-2">
                <h3 className="font-semibold text-[var(--text-primary)]">{e.name}</h3>
                <span className={`app-chip ${typeColors[e.event_type] || typeColors.other}`}>
                  {e.event_type}
                </span>
              </div>
              <div className="flex items-center gap-4 text-sm text-[var(--text-secondary)]">
                <span className="flex items-center gap-1"><Calendar className="w-3.5 h-3.5" /> {e.date}</span>
                {e.location && <span className="flex items-center gap-1"><MapPin className="w-3.5 h-3.5" /> {e.location}</span>}
                {e.village_name && <span>{e.village_name}</span>}
              </div>
              <div className="flex items-center gap-4 text-sm mt-2">
                <span className="flex items-center gap-1 text-[var(--text-secondary)]"><Users className="w-3.5 h-3.5" /> {e.attended_count} / {e.invited_count} attended</span>
                {e.quota && <span className="text-[var(--text-secondary)]">Quota: {e.quota}</span>}
                <span className="text-[var(--text-secondary)]">{e.show_up_rate}% show-up</span>
              </div>
            </Link>
          ))}
          {filteredEvents.length === 0 && (
            <div className="text-center text-[var(--text-muted)] py-12">
              No events match current filters.
            </div>
          )}
        </div>
      </div>
    </WorkspacePage>
  );
}
