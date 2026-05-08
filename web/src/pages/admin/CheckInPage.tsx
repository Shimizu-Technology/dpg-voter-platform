import { useState } from 'react';
import { useParams, Link } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { getEvent, getEventAttendees, checkInAttendee } from '../../lib/api';
import { ArrowLeft, Search, CheckCircle, Loader2, Users } from 'lucide-react';
import WorkspacePage from '../../components/WorkspacePage';

interface Attendee {
  rsvp_id: number;
  supporter_id: number;
  print_name: string;
  village: string;
  contact_number: string;
  attended: boolean;
}

export default function CheckInPage() {
  const { id } = useParams();
  const hasValidId = !!id && !Number.isNaN(Number(id));
  const eventId = Number(id);
  const queryClient = useQueryClient();
  const [search, setSearch] = useState('');

  const { data: eventData } = useQuery({
    queryKey: ['event', id],
    queryFn: () => getEvent(eventId),
    enabled: hasValidId,
  });
  const { data: attendeeData } = useQuery({
    queryKey: ['attendees', id, search],
    queryFn: () => getEventAttendees(eventId, search || undefined),
    refetchInterval: 5000,
    enabled: hasValidId,
  });

  const checkIn = useMutation({
    mutationFn: (supporterId: number) => checkInAttendee(eventId, supporterId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['event', id] });
      queryClient.invalidateQueries({ queryKey: ['attendees', id] });
    },
  });

  const event = eventData?.event;
  const stats = attendeeData?.stats;
  const attendees: Attendee[] = attendeeData?.attendees || [];

  if (!hasValidId) {
    return <div className="min-h-screen flex items-center justify-center text-[var(--text-muted)]">Invalid event link.</div>;
  }

  if (!event) return <div className="min-h-screen flex items-center justify-center text-[var(--text-muted)]">Loading...</div>;

  return (
    <WorkspacePage width="full" className="space-y-6">
      {/* Header */}
      <div className="app-card p-4 sticky top-0 z-10">
        <div>
          <Link to={`/admin/events/${id}`} className="flex items-center gap-2 text-gray-500 hover:text-gray-700 text-sm mb-2">
            <ArrowLeft className="w-4 h-4" /> Event Detail
          </Link>
          <h1 className="text-xl font-bold text-gray-900 tracking-tight">{event.name} — Check In</h1>

          {/* Live Counter */}
          {stats && (
            <div className="flex items-center gap-4 mt-2">
              <div className="flex items-center gap-1">
                <Users className="w-4 h-4 text-gray-500" />
                <span className="text-2xl font-bold text-gray-900">{stats.attended}</span>
                <span className="text-gray-500">/ {event.quota || stats.total_invited}</span>
              </div>
              <div className={`px-2 py-0.5 rounded text-sm font-medium ${
                event.quota && stats.attended >= event.quota ? 'bg-green-500' : 'bg-yellow-500 text-black'
              }`}>
                {event.quota && stats.attended >= event.quota ? 'QUOTA MET!' : `${event.quota ? event.quota - stats.attended : '—'} more needed`}
              </div>
            </div>
          )}

          {/* Search */}
          <div className="relative mt-3">
            <Search className="w-5 h-5 absolute left-3 top-3 text-blue-700" />
            <input
              type="text"
              autoFocus
              value={search}
              onChange={e => setSearch(e.target.value)}
              placeholder="Search supporter name..."
              className="app-input text-lg"
            />
          </div>
        </div>
      </div>

      {/* Attendee List */}
      <div>
        {attendees.map((a) => (
          <div key={a.rsvp_id}
            className={`flex items-center justify-between p-4 mb-2 rounded-2xl border ${
              a.attended ? 'bg-green-50 border-green-200' : 'bg-[var(--surface-raised)] border-[var(--border-soft)]'
            }`}
          >
            <div>
              <div className="font-medium text-[var(--text-primary)]">{a.print_name}</div>
              <div className="text-sm text-[var(--text-secondary)]">{a.village} · {a.contact_number}</div>
            </div>
            {a.attended ? (
              <div className="flex items-center gap-1 text-green-600">
                <CheckCircle className="w-5 h-5" />
                <span className="text-sm font-medium">In</span>
              </div>
            ) : (
              <button
                onClick={() => checkIn.mutate(a.supporter_id)}
                disabled={checkIn.isPending}
                className="bg-primary hover:bg-primary-dark text-white px-4 py-2 min-h-[44px] rounded-xl font-medium text-sm flex items-center gap-1"
              >
                {checkIn.isPending ? <Loader2 className="w-4 h-4 animate-spin" /> : 'Check In'}
              </button>
            )}
          </div>
        ))}
        {attendees.length === 0 && (
          <div className="text-center text-[var(--text-muted)] py-12">
            {search ? 'No matching supporters found' : 'No attendees for this event yet'}
          </div>
        )}
      </div>
    </WorkspacePage>
  );
}
