import { useMemo, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { AlertTriangle, CheckCircle, ClipboardList, Phone, RadioTower, RotateCcw, Save, Users } from 'lucide-react';
import WorkspacePage from '../../components/WorkspacePage';
import {
  activateElectionEvent,
  closeElectionEvent,
  createElectionEvent,
  getElectionDayCommandCenter,
  getElectionEvents,
  logElectionDayContact,
} from '../../lib/api';
import { formatDateTime } from '../../lib/datetime';
import { getErrorMessage } from '../../lib/contactAttempt';

type ElectionEvent = {
  id: number;
  name: string;
  election_type: string;
  election_date: string;
  status: string;
  gec_import_id?: number | null;
  gec_list_date?: string | null;
  gec_import_filename?: string | null;
};

type GecImportOption = {
  id: number;
  filename: string;
  gec_list_date?: string | null;
  status: string;
  total_records?: number | null;
};

type VillageSummary = {
  name: string;
  total_voters: number;
  voted: number;
  not_yet_voted: number;
  unknown: number;
  observed_elsewhere: number;
  linked_contacts: number;
  linked_not_yet_voted: number;
  contacted_today: number;
  not_contacted_today: number;
  ride_requests: number;
};

type ChaseContact = {
  supporter_id: number;
  gec_voter_id: number;
  name: string;
  phone?: string | null;
  email?: string | null;
  dpg_village?: string | null;
  dpg_precinct?: string | null;
  gec_village?: string | null;
  gec_precinct?: string | null;
  needs_ride: boolean;
  support_status?: string | null;
  contacted_today: boolean;
  latest_contact_attempt?: {
    channel: string;
    outcome: string;
    note?: string | null;
    recorded_at?: string | null;
    recorded_by_name?: string | null;
  } | null;
};

type ExceptionRow = {
  id: number;
  name: string;
  registered_village?: string | null;
  registered_precinct?: string | null;
  observed_village?: string | null;
  observed_precinct?: string | null;
  note?: string | null;
  updated_at?: string | null;
};

type PollReportRow = {
  id: number;
  precinct_number?: string | null;
  village_name?: string | null;
  report_type: string;
  voter_count: number;
  notes?: string | null;
  reported_at?: string | null;
  user_name?: string | null;
};

type CommandCenterData = {
  setup_required?: boolean;
  message?: string;
  compliance_note?: string;
  active_election?: ElectionEvent | null;
  stats?: {
    total_voters: number;
    voted: number;
    not_yet_voted: number;
    unknown: number;
    observed_elsewhere: number;
    chase_list_count: number;
    contacted_today: number;
    not_contacted_today: number;
    ride_requests: number;
    exceptions: number;
  };
  villages?: VillageSummary[];
  chase_list?: ChaseContact[];
  exceptions?: ExceptionRow[];
  recent_reports?: PollReportRow[];
};

type ElectionEventsData = {
  active_election?: ElectionEvent | null;
  election_events: ElectionEvent[];
  completed_gec_imports: GecImportOption[];
};

const defaultElectionName = `DPG ${new Date().getFullYear()} Election`;

export default function ElectionDayCommandCenterPage() {
  const queryClient = useQueryClient();
  const [setupOpen, setSetupOpen] = useState(false);
  const [draft, setDraft] = useState({
    name: defaultElectionName,
    election_type: 'primary',
    election_date: new Date().toISOString().slice(0, 10),
    gec_import_id: '',
  });
  const [villageFilter, setVillageFilter] = useState('');
  const [contactFilter, setContactFilter] = useState<'all' | 'not_contacted' | 'contacted' | 'rides'>('not_contacted');
  const [contactDrafts, setContactDrafts] = useState<Record<number, { channel: string; outcome: string; note: string }>>({});

  const eventsQuery = useQuery<ElectionEventsData>({ queryKey: ['election-events'], queryFn: getElectionEvents });
  const commandQuery = useQuery<CommandCenterData>({ queryKey: ['election-day-command-center'], queryFn: getElectionDayCommandCenter, refetchInterval: 30_000 });

  const createMutation = useMutation({
    mutationFn: () => createElectionEvent({ ...draft, gec_import_id: draft.gec_import_id ? Number(draft.gec_import_id) : null }),
    onSuccess: () => {
      setSetupOpen(false);
      void queryClient.invalidateQueries({ queryKey: ['election-events'] });
    },
  });

  const activateMutation = useMutation({
    mutationFn: (id: number) => activateElectionEvent(id),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ['election-events'] });
      void queryClient.invalidateQueries({ queryKey: ['election-day-command-center'] });
      void queryClient.invalidateQueries({ queryKey: ['poll-watcher'] });
    },
  });

  const closeMutation = useMutation({
    mutationFn: (id: number) => closeElectionEvent(id),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ['election-events'] });
      void queryClient.invalidateQueries({ queryKey: ['election-day-command-center'] });
    },
  });

  const contactMutation = useMutation({
    mutationFn: ({ supporterId, payload }: { supporterId: number; payload: { channel: string; outcome: string; note: string } }) =>
      logElectionDayContact(supporterId, payload),
    onSuccess: (_data, variables) => {
      setContactDrafts((prev) => ({ ...prev, [variables.supporterId]: { channel: 'call', outcome: 'attempted', note: '' } }));
      void queryClient.invalidateQueries({ queryKey: ['election-day-command-center'] });
    },
  });

  const events = eventsQuery.data?.election_events || [];
  const imports = eventsQuery.data?.completed_gec_imports || [];
  const command = commandQuery.data;
  const stats = command?.stats;
  const villages = useMemo(() => command?.villages || [], [command?.villages]);
  const activeElection = command?.active_election || eventsQuery.data?.active_election || null;
  const villageOptions = useMemo(() => villages.map((v) => v.name), [villages]);
  const filteredChase = (command?.chase_list || []).filter((contact) => {
    const villageHit = !villageFilter || contact.gec_village === villageFilter || contact.dpg_village === villageFilter;
    const contactHit = contactFilter === 'all'
      ? true
      : contactFilter === 'not_contacted'
        ? !contact.contacted_today
        : contactFilter === 'contacted'
          ? contact.contacted_today
          : contact.needs_ride;
    return villageHit && contactHit;
  });

  const createError = createMutation.error ? getErrorMessage(createMutation.error, 'Could not create this election.') : '';
  const contactError = contactMutation.error ? getErrorMessage(contactMutation.error, 'Could not log this contact attempt.') : '';

  return (
    <WorkspacePage width="full" className="mx-auto max-w-[1600px] space-y-6">
      <div className="flex flex-col gap-4 xl:flex-row xl:items-start xl:justify-between">
        <div>
          <div className="inline-flex items-center gap-2 rounded-full border border-emerald-100 bg-emerald-50 px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.16em] text-emerald-700">
            <RadioTower className="h-3.5 w-3.5" /> Election Day Command Center
          </div>
          <h1 className="mt-3 text-2xl font-bold tracking-tight text-gray-950">Election Day</h1>
          <p className="mt-1 max-w-3xl text-sm text-gray-500">
            Track the active election, official GEC list, turnout, not-yet-voted DPG contact follow-up, ride requests, and polling-place exceptions.
          </p>
        </div>
        <button type="button" onClick={() => setSetupOpen((value) => !value)} className="app-btn-secondary w-fit">
          {setupOpen ? 'Hide setup' : 'Election setup'}
        </button>
      </div>

      {activeElection ? (
        <section className="rounded-2xl border border-emerald-100 bg-emerald-50/70 p-4">
          <div className="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
            <div>
              <p className="text-xs font-semibold uppercase tracking-[0.14em] text-emerald-700">Active election</p>
              <h2 className="mt-1 text-lg font-semibold text-slate-950">{activeElection.name}</h2>
              <p className="mt-1 text-sm text-slate-600">
                {activeElection.election_type} · {new Date(`${activeElection.election_date}T00:00:00`).toLocaleDateString()} · GEC list {activeElection.gec_list_date || 'not selected'}
              </p>
              {activeElection.gec_import_filename && <p className="mt-1 text-xs text-slate-500">Source: {activeElection.gec_import_filename}</p>}
            </div>
            <button type="button" onClick={() => activeElection && closeMutation.mutate(activeElection.id)} className="app-btn-secondary text-xs" disabled={closeMutation.isPending}>
              Close election
            </button>
          </div>
        </section>
      ) : (
        <section className="rounded-2xl border border-amber-200 bg-amber-50 p-4 text-amber-900">
          <div className="flex items-start gap-3">
            <AlertTriangle className="mt-0.5 h-5 w-5 shrink-0" />
            <div>
              <h2 className="font-semibold">Election setup required</h2>
              <p className="mt-1 text-sm">Create an election event and attach the GEC import/list that Poll Watcher should use.</p>
            </div>
          </div>
        </section>
      )}

      {setupOpen && (
        <section className="app-card p-5">
          <div className="grid gap-4 xl:grid-cols-[minmax(0,1fr)_minmax(360px,0.8fr)]">
            <div>
              <h2 className="font-semibold text-[var(--text-primary)]">Create election event</h2>
              <div className="mt-4 grid gap-3 md:grid-cols-2">
                <label className="text-sm">
                  <span className="font-medium text-[var(--text-secondary)]">Name</span>
                  <input value={draft.name} onChange={(e) => setDraft((prev) => ({ ...prev, name: e.target.value }))} className="mt-1 w-full rounded-xl border border-[var(--border-soft)] px-3 py-2" />
                </label>
                <label className="text-sm">
                  <span className="font-medium text-[var(--text-secondary)]">Election type</span>
                  <select value={draft.election_type} onChange={(e) => setDraft((prev) => ({ ...prev, election_type: e.target.value }))} className="mt-1 w-full rounded-xl border border-[var(--border-soft)] bg-white px-3 py-2">
                    <option value="primary">Primary</option>
                    <option value="general">General</option>
                    <option value="runoff">Runoff</option>
                    <option value="special">Special</option>
                    <option value="other">Other</option>
                  </select>
                </label>
                <label className="text-sm">
                  <span className="font-medium text-[var(--text-secondary)]">Election date</span>
                  <input type="date" value={draft.election_date} onChange={(e) => setDraft((prev) => ({ ...prev, election_date: e.target.value }))} className="mt-1 w-full rounded-xl border border-[var(--border-soft)] px-3 py-2" />
                </label>
                <label className="text-sm">
                  <span className="font-medium text-[var(--text-secondary)]">GEC list</span>
                  <select value={draft.gec_import_id} onChange={(e) => setDraft((prev) => ({ ...prev, gec_import_id: e.target.value }))} className="mt-1 w-full rounded-xl border border-[var(--border-soft)] bg-white px-3 py-2">
                    <option value="">Select completed import</option>
                    {imports.map((row) => (
                      <option key={row.id} value={row.id}>{row.gec_list_date || 'No date'} · {row.filename}</option>
                    ))}
                  </select>
                </label>
              </div>
              {createError && <p className="mt-3 text-sm text-red-600">{createError}</p>}
              <button type="button" onClick={() => createMutation.mutate()} disabled={createMutation.isPending || !draft.name || !draft.election_date} className="app-btn-primary mt-4">
                <Save className="h-4 w-4" /> Create election
              </button>
            </div>
            <div>
              <h2 className="font-semibold text-[var(--text-primary)]">Recent elections</h2>
              <div className="mt-3 space-y-2">
                {events.map((event) => (
                  <div key={event.id} className="rounded-xl border border-[var(--border-soft)] px-3 py-2 text-sm">
                    <div className="flex items-start justify-between gap-3">
                      <div>
                        <p className="font-semibold text-[var(--text-primary)]">{event.name}</p>
                        <p className="text-xs text-[var(--text-muted)]">{event.status} · {event.gec_list_date || 'No GEC list'}</p>
                      </div>
                      {event.status !== 'active' && event.gec_import_id && (
                        <button type="button" onClick={() => activateMutation.mutate(event.id)} className="rounded-lg bg-emerald-600 px-2.5 py-1 text-xs font-semibold text-white" disabled={activateMutation.isPending}>
                          Activate
                        </button>
                      )}
                    </div>
                  </div>
                ))}
                {events.length === 0 && <p className="text-sm text-[var(--text-muted)]">No election events yet.</p>}
              </div>
            </div>
          </div>
        </section>
      )}

      {stats && (
        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-5">
          <MetricCard label="Voted" value={stats.voted} detail={`${stats.total_voters.toLocaleString()} total voters`} tone="green" />
          <MetricCard label="Not yet voted" value={stats.not_yet_voted} detail="Official GEC rows" tone="amber" />
          <MetricCard label="Chase list" value={stats.chase_list_count} detail="Linked DPG contacts" tone="blue" />
          <MetricCard label="Not contacted today" value={stats.not_contacted_today} detail={`${stats.contacted_today.toLocaleString()} contacted`} tone="red" />
          <MetricCard label="Ride requests" value={stats.ride_requests} detail={`${stats.exceptions.toLocaleString()} exceptions`} tone="slate" />
        </div>
      )}

      {command?.compliance_note && (
        <p className="rounded-xl border border-slate-200 bg-slate-50 px-4 py-3 text-xs text-slate-600">{command.compliance_note}</p>
      )}

      <div className="grid gap-6 xl:grid-cols-[minmax(0,0.95fr)_minmax(0,1.25fr)]">
        <section className="app-card p-5">
          <h2 className="font-semibold text-[var(--text-primary)]">Village turnout</h2>
          <div className="mt-4 max-h-[620px] overflow-auto">
            <table className="w-full min-w-[720px] text-sm">
              <thead className="sticky top-0 bg-white">
                <tr className="border-b text-xs uppercase tracking-wide text-[var(--text-muted)]">
                  <th className="px-3 py-2 text-left">GEC village</th>
                  <th className="px-3 py-2 text-right">Voted</th>
                  <th className="px-3 py-2 text-right">Not yet</th>
                  <th className="px-3 py-2 text-right">Contacts</th>
                  <th className="px-3 py-2 text-right">Not called</th>
                  <th className="px-3 py-2 text-right">Rides</th>
                </tr>
              </thead>
              <tbody>
                {villages.map((village) => (
                  <tr key={village.name} className="border-b border-[var(--border-soft)] hover:bg-[var(--surface-bg)]">
                    <td className="px-3 py-2 font-medium text-[var(--text-primary)]">{village.name}</td>
                    <td className="px-3 py-2 text-right text-emerald-700">{village.voted.toLocaleString()}</td>
                    <td className="px-3 py-2 text-right text-amber-700">{village.not_yet_voted.toLocaleString()}</td>
                    <td className="px-3 py-2 text-right">{village.linked_contacts.toLocaleString()}</td>
                    <td className="px-3 py-2 text-right text-red-700">{village.not_contacted_today.toLocaleString()}</td>
                    <td className="px-3 py-2 text-right">{village.ride_requests.toLocaleString()}</td>
                  </tr>
                ))}
                {villages.length === 0 && (
                  <tr><td className="px-3 py-8 text-center text-[var(--text-muted)]" colSpan={6}>No active election turnout yet.</td></tr>
                )}
              </tbody>
            </table>
          </div>
        </section>

        <section className="app-card p-5">
          <div className="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
            <div>
              <h2 className="font-semibold text-[var(--text-primary)]">Not-yet-voted chase list</h2>
              <p className="mt-1 text-xs text-[var(--text-muted)]">Linked DPG contacts whose official GEC voter row is not marked voted.</p>
            </div>
            <div className="flex flex-wrap gap-2">
              <select value={villageFilter} onChange={(e) => setVillageFilter(e.target.value)} className="rounded-xl border border-[var(--border-soft)] bg-white px-3 py-2 text-sm">
                <option value="">All villages</option>
                {villageOptions.map((name) => <option key={name} value={name}>{name}</option>)}
              </select>
              <select value={contactFilter} onChange={(e) => setContactFilter(e.target.value as typeof contactFilter)} className="rounded-xl border border-[var(--border-soft)] bg-white px-3 py-2 text-sm">
                <option value="not_contacted">Not contacted today</option>
                <option value="contacted">Contacted today</option>
                <option value="rides">Needs ride</option>
                <option value="all">All</option>
              </select>
            </div>
          </div>
          {contactError && <p className="mt-3 rounded-xl bg-red-50 px-3 py-2 text-sm text-red-700">{contactError}</p>}
          <div className="mt-4 space-y-3">
            {filteredChase.map((contact) => {
              const draftForContact = contactDrafts[contact.supporter_id] || { channel: 'call', outcome: 'attempted', note: '' };
              return (
                <div key={`${contact.supporter_id}-${contact.gec_voter_id}`} className="rounded-2xl border border-[var(--border-soft)] p-4">
                  <div className="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
                    <div>
                      <div className="flex flex-wrap items-center gap-2">
                        <h3 className="font-semibold text-[var(--text-primary)]">{contact.name}</h3>
                        {contact.contacted_today && <span className="rounded-full bg-green-100 px-2 py-0.5 text-xs font-semibold text-green-700">Contacted today</span>}
                        {contact.needs_ride && <span className="rounded-full bg-amber-100 px-2 py-0.5 text-xs font-semibold text-amber-800">Needs ride</span>}
                      </div>
                      <p className="mt-1 text-sm text-[var(--text-secondary)]">{contact.phone || 'No phone'} · GEC {contact.gec_village || 'Unknown'} / Precinct {contact.gec_precinct || 'unknown'}</p>
                      <p className="mt-0.5 text-xs text-[var(--text-muted)]">DPG contact village: {contact.dpg_village || 'Unknown'}{contact.dpg_precinct ? ` / ${contact.dpg_precinct}` : ''}</p>
                      {contact.latest_contact_attempt?.recorded_at && (
                        <p className="mt-1 text-xs text-[var(--text-muted)]">Last contact: {formatDateTime(contact.latest_contact_attempt.recorded_at)} · {contact.latest_contact_attempt.outcome}</p>
                      )}
                    </div>
                    <div className="grid w-full gap-2 lg:w-[420px]">
                      <div className="grid grid-cols-2 gap-2">
                        <select value={draftForContact.channel} onChange={(e) => setContactDrafts((prev) => ({ ...prev, [contact.supporter_id]: { ...draftForContact, channel: e.target.value } }))} className="rounded-xl border border-[var(--border-soft)] bg-white px-3 py-2 text-sm">
                          <option value="call">Call</option>
                          <option value="sms">SMS</option>
                          <option value="in_person">In person</option>
                        </select>
                        <select value={draftForContact.outcome} onChange={(e) => setContactDrafts((prev) => ({ ...prev, [contact.supporter_id]: { ...draftForContact, outcome: e.target.value } }))} className="rounded-xl border border-[var(--border-soft)] bg-white px-3 py-2 text-sm">
                          <option value="attempted">Attempted</option>
                          <option value="reached">Reached</option>
                          <option value="left_message">Left message</option>
                          <option value="wrong_number">Wrong number</option>
                          <option value="declined">Refused</option>
                        </select>
                      </div>
                      <input value={draftForContact.note} onChange={(e) => setContactDrafts((prev) => ({ ...prev, [contact.supporter_id]: { ...draftForContact, note: e.target.value } }))} placeholder="Election Day note: plans to vote, needs ride, already voted..." className="rounded-xl border border-[var(--border-soft)] px-3 py-2 text-sm" />
                      <button type="button" onClick={() => contactMutation.mutate({ supporterId: contact.supporter_id, payload: draftForContact })} disabled={contactMutation.isPending} className="app-btn-primary justify-center text-sm">
                        <Phone className="h-4 w-4" /> Log contact
                      </button>
                    </div>
                  </div>
                </div>
              );
            })}
            {filteredChase.length === 0 && <p className="py-8 text-center text-sm text-[var(--text-muted)]">No contacts match this chase-list filter.</p>}
          </div>
        </section>
      </div>

      <div className="grid gap-6 xl:grid-cols-2">
        <section className="app-card p-5">
          <h2 className="font-semibold text-[var(--text-primary)]">Exceptions and reconciliation</h2>
          <div className="mt-3 space-y-2">
            {(command?.exceptions || []).map((row) => (
              <div key={row.id} className="rounded-xl border border-amber-100 bg-amber-50/60 px-3 py-2 text-sm">
                <p className="font-semibold text-amber-950">{row.name}</p>
                <p className="text-xs text-amber-900">Registered {row.registered_village || 'Unknown'} / {row.registered_precinct || 'unknown'} · observed {row.observed_village || 'Unknown'} / {row.observed_precinct || 'unknown'}</p>
                {row.note && <p className="mt-1 text-xs text-amber-900">{row.note}</p>}
              </div>
            ))}
            {(command?.exceptions || []).length === 0 && <p className="text-sm text-[var(--text-muted)]">No observed-elsewhere exceptions yet.</p>}
          </div>
        </section>
        <section className="app-card p-5">
          <h2 className="font-semibold text-[var(--text-primary)]">Recent poll watcher reports</h2>
          <div className="mt-3 space-y-2">
            {(command?.recent_reports || []).map((report) => (
              <div key={report.id} className="rounded-xl border border-[var(--border-soft)] px-3 py-2 text-sm">
                <div className="flex items-start justify-between gap-3">
                  <p className="font-semibold text-[var(--text-primary)]">{report.report_type.replace(/_/g, ' ')}</p>
                  <span className="text-xs text-[var(--text-muted)]">{report.reported_at ? formatDateTime(report.reported_at) : ''}</span>
                </div>
                <p className="text-xs text-[var(--text-secondary)]">{report.village_name || 'Unknown'} · Precinct {report.precinct_number || 'unknown'} · Count {report.voter_count}</p>
                {report.notes && <p className="mt-1 text-xs text-[var(--text-muted)]">{report.notes}</p>}
              </div>
            ))}
            {(command?.recent_reports || []).length === 0 && <p className="text-sm text-[var(--text-muted)]">No reports yet.</p>}
          </div>
        </section>
      </div>
    </WorkspacePage>
  );
}

function MetricCard({ label, value, detail, tone }: { label: string; value: number; detail: string; tone: 'green' | 'amber' | 'blue' | 'red' | 'slate' }) {
  const toneClass = {
    green: 'border-green-100 bg-green-50 text-green-700',
    amber: 'border-amber-100 bg-amber-50 text-amber-700',
    blue: 'border-blue-100 bg-blue-50 text-blue-700',
    red: 'border-red-100 bg-red-50 text-red-700',
    slate: 'border-slate-200 bg-slate-50 text-slate-700',
  }[tone];

  return (
    <div className={`rounded-2xl border p-4 ${toneClass}`}>
      <div className="flex items-center justify-between gap-3">
        <span className="text-xs font-semibold uppercase tracking-[0.12em] opacity-75">{label}</span>
        {tone === 'green' ? <CheckCircle className="h-4 w-4" /> : tone === 'red' ? <AlertTriangle className="h-4 w-4" /> : tone === 'blue' ? <Users className="h-4 w-4" /> : tone === 'amber' ? <ClipboardList className="h-4 w-4" /> : <RotateCcw className="h-4 w-4" />}
      </div>
      <div className="mt-3 text-3xl font-bold">{Number(value || 0).toLocaleString()}</div>
      <div className="mt-1 text-xs opacity-75">{detail}</div>
    </div>
  );
}
