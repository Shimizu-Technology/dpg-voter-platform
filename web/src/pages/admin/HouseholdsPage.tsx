import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { AlertTriangle, CheckCircle2, Database, Home, Link as LinkIcon, MapPin, MessageSquare, Search, Users } from 'lucide-react';
import WorkspacePage from '../../components/WorkspacePage';
import { createContactFromGecVoter, getGecHouseholds, getSupporters, linkContactToGecVoter, updateSupporterCanvass } from '../../lib/api';
import { CONTACT_ATTEMPT_CHANNEL_OPTIONS, CONTACT_ATTEMPT_OUTCOME_OPTIONS } from '../../lib/contactAttempt';
import { formatDateTime } from '../../lib/datetime';
import {
  ACTIVE_RELATIONSHIP_OPTIONS,
  contactClassificationChipClass,
  contactClassificationLabel,
} from '../../lib/contactClassification';

type GecVoter = {
  id: number;
  first_name: string;
  middle_name?: string | null;
  last_name: string;
  address?: string | null;
  village_name?: string | null;
  precinct_number?: string | null;
  voter_registration_number?: string | null;
  linked_contact_count?: number;
  linked_contact?: HouseholdContact | null;
  possible_contact_count?: number;
  possible_contact?: HouseholdContact | null;
};

type HouseholdContact = {
  id: number;
  print_name?: string | null;
  first_name: string;
  middle_name?: string | null;
  last_name: string;
  contact_number?: string | null;
  email?: string | null;
  street_address?: string | null;
  village_name?: string | null;
  contact_classification?: string | null;
  review_status?: string | null;
  verification_status?: string | null;
  verification_reason?: string | null;
  current_gec_match?: boolean | null;
  registered_voter_status?: string | null;
  latest_contact_attempt?: {
    channel: string;
    outcome: string;
    note?: string | null;
    recorded_at?: string | null;
    recorded_by_name?: string | null;
  } | null;
};

type Household = {
  address: string;
  village_name?: string | null;
  gec_voters: GecVoter[];
  contacts: HouseholdContact[];
};

type ContactResult = {
  id: number;
  print_name?: string | null;
  first_name: string;
  last_name: string;
  contact_number?: string | null;
  email?: string | null;
  street_address?: string | null;
  village_name?: string | null;
};

type CanvassDraft = {
  contact_classification: string;
  channel: string;
  outcome: string;
  note: string;
};

function fullName(person: Pick<GecVoter | HouseholdContact, 'first_name' | 'middle_name' | 'last_name'>) {
  return [person.first_name, person.middle_name, person.last_name].filter(Boolean).join(' ');
}

function voterLabel(voter: GecVoter) {
  return [voter.precinct_number ? `Pct ${voter.precinct_number}` : null, voter.voter_registration_number].filter(Boolean).join(' · ') || 'GEC voter';
}

function contactName(contact: Pick<HouseholdContact, 'print_name' | 'first_name' | 'middle_name' | 'last_name'>) {
  return contact.print_name || fullName(contact);
}

function getErrorMessage(error: unknown) {
  if (error instanceof Error) return error.message;
  if (typeof error === 'object' && error && 'response' in error) {
    const response = (error as { response?: { data?: { message?: string; error?: string } } }).response;
    return response?.data?.message || response?.data?.error || 'The request failed.';
  }
  return 'The request failed.';
}

export default function HouseholdsPage() {
  const queryClient = useQueryClient();
  const [search, setSearch] = useState('');
  const [submittedSearch, setSubmittedSearch] = useState('');
  const [linkVoterId, setLinkVoterId] = useState<number | null>(null);
  const [contactSearch, setContactSearch] = useState('');
  const [submittedContactSearch, setSubmittedContactSearch] = useState('');
  const [expandedContactId, setExpandedContactId] = useState<number | null>(null);
  const [canvassDrafts, setCanvassDrafts] = useState<Record<number, CanvassDraft>>({});
  const [actionMessage, setActionMessage] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);

  const householdsQuery = useQuery({
    queryKey: ['households-workspace', submittedSearch],
    queryFn: () => getGecHouseholds({ q: submittedSearch }),
    enabled: submittedSearch.trim().length >= 3,
  });

  const households = useMemo<Household[]>(() => householdsQuery.data?.households ?? [], [householdsQuery.data]);
  const voterCount = householdsQuery.data?.voter_count ?? households.reduce((sum, household) => sum + household.gec_voters.length, 0);
  const contactCount = householdsQuery.data?.contact_count ?? households.reduce((sum, household) => sum + household.contacts.length, 0);
  const contactResultsQuery = useQuery({
    queryKey: ['household-link-contact-candidates', linkVoterId, submittedContactSearch],
    queryFn: () => getSupporters({ search: submittedContactSearch, per_page: 10 }),
    enabled: Boolean(linkVoterId) && submittedContactSearch.trim().length >= 2,
  });
  const contactResults = useMemo<ContactResult[]>(() => contactResultsQuery.data?.supporters ?? [], [contactResultsQuery.data]);

  const createContactMutation = useMutation({
    mutationFn: (voterId: number) => createContactFromGecVoter(voterId),
    onSuccess: () => {
      setActionError(null);
      setActionMessage('Created a pending intake contact and linked it to this GEC voter.');
      setLinkVoterId(null);
      setContactSearch('');
      setSubmittedContactSearch('');
      void queryClient.invalidateQueries({ queryKey: ['households-workspace'] });
      void queryClient.invalidateQueries({ queryKey: ['gec-voters'] });
      void queryClient.invalidateQueries({ queryKey: ['gec-households'] });
      void queryClient.invalidateQueries({ queryKey: ['session'] });
    },
    onError: (error: unknown) => {
      setActionMessage(null);
      setActionError(getErrorMessage(error));
    },
  });

  const linkContactMutation = useMutation({
    mutationFn: ({ voterId, supporterId }: { voterId: number; supporterId: number }) => linkContactToGecVoter(voterId, supporterId),
    onSuccess: () => {
      setActionError(null);
      setActionMessage('Linked the existing DPG contact to the GEC voter.');
      setLinkVoterId(null);
      setContactSearch('');
      setSubmittedContactSearch('');
      void queryClient.invalidateQueries({ queryKey: ['households-workspace'] });
      void queryClient.invalidateQueries({ queryKey: ['gec-voters'] });
      void queryClient.invalidateQueries({ queryKey: ['gec-households'] });
      void queryClient.invalidateQueries({ queryKey: ['session'] });
      void queryClient.invalidateQueries({ queryKey: ['household-link-contact-candidates'] });
    },
    onError: (error: unknown) => {
      setActionMessage(null);
      setActionError(getErrorMessage(error));
    },
  });

  const canvassMutation = useMutation({
    mutationFn: ({ contact, draft }: { contact: HouseholdContact; draft: CanvassDraft }) =>
      updateSupporterCanvass(contact.id, {
        contact_classification: draft.contact_classification,
        contact_attempt: {
          channel: draft.channel,
          outcome: draft.outcome,
          note: draft.note.trim() || undefined,
        },
      }),
    onSuccess: () => {
      setActionError(null);
      setActionMessage('Saved the household canvassing update.');
      setExpandedContactId(null);
      void queryClient.invalidateQueries({ queryKey: ['households-workspace'] });
      void queryClient.invalidateQueries({ queryKey: ['supporters'] });
      void queryClient.invalidateQueries({ queryKey: ['outreach-supporters'] });
      void queryClient.invalidateQueries({ queryKey: ['dashboard'] });
    },
    onError: (error: unknown) => {
      setActionMessage(null);
      setActionError(getErrorMessage(error));
    },
  });

  const draftForContact = (contact: HouseholdContact): CanvassDraft => canvassDrafts[contact.id] || {
    contact_classification: contact.contact_classification || 'active_contact',
    channel: 'in_person',
    outcome: 'reached',
    note: '',
  };

  const updateCanvassDraft = (contact: HouseholdContact, updates: Partial<CanvassDraft>) => {
    setCanvassDrafts((current) => ({
      ...current,
      [contact.id]: { ...draftForContact(contact), ...updates },
    }));
  };

  const saveCanvassUpdate = (contact: HouseholdContact) => {
    canvassMutation.mutate({ contact, draft: draftForContact(contact) });
  };

  return (
    <WorkspacePage width="full" className="space-y-6">
      <div className="flex flex-col gap-4 xl:flex-row xl:items-end xl:justify-between">
        <div>
          <div className="mb-2 inline-flex items-center gap-2 rounded-full bg-blue-50 px-3 py-1 text-xs font-semibold uppercase tracking-[0.12em] text-blue-700">
            <Home className="h-3.5 w-3.5" />
            Address workspace
          </div>
          <h1 className="text-2xl font-bold tracking-tight text-slate-950">Households</h1>
          <p className="mt-1 max-w-3xl text-sm text-slate-500">
            Search an address to see who appears there in the public GEC voter file and which DPG contacts are already connected to that household.
          </p>
        </div>
      </div>

      <section className="app-card p-4 sm:p-5">
        <form
          className="flex flex-col gap-3 md:flex-row"
          onSubmit={(event) => {
            event.preventDefault();
            setActionMessage(null);
            setActionError(null);
            setSubmittedSearch(search.trim());
          }}
        >
          <div className="relative flex-1">
            <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" />
            <input
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              placeholder="Search by house number, street, or village address"
              className="w-full rounded-xl border border-slate-200 bg-white py-3 pl-10 pr-3 text-sm"
            />
          </div>
          <button type="submit" className="app-btn-primary min-h-11 justify-center">
            <Search className="h-4 w-4" />
            Search Households
          </button>
        </form>
        <div className="mt-3 text-xs text-slate-500">
          Enter at least 3 characters. Village-scoped users only see households in their assigned village.
        </div>
      </section>

      {actionMessage && (
        <div className="flex items-start gap-2 rounded-xl bg-green-50 px-3 py-2 text-sm text-green-800">
          <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0" />
          {actionMessage}
        </div>
      )}
      {actionError && (
        <div className="flex items-start gap-2 rounded-xl bg-red-50 px-3 py-2 text-sm text-red-800">
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
          {actionError}
        </div>
      )}

      {submittedSearch && (
        <div className="grid gap-3 md:grid-cols-3">
          <div className="app-card p-4">
            <div className="text-xs font-semibold uppercase tracking-[0.1em] text-slate-500">Households</div>
            <div className="mt-2 text-2xl font-bold text-slate-950">{households.length}</div>
          </div>
          <div className="app-card p-4">
            <div className="text-xs font-semibold uppercase tracking-[0.1em] text-slate-500">GEC voters</div>
            <div className="mt-2 text-2xl font-bold text-slate-950">{voterCount}</div>
          </div>
          <div className="app-card p-4">
            <div className="text-xs font-semibold uppercase tracking-[0.1em] text-slate-500">DPG contacts</div>
            <div className="mt-2 text-2xl font-bold text-slate-950">{contactCount}</div>
          </div>
        </div>
      )}

      <section className="space-y-4">
        {!submittedSearch ? (
          <div className="app-card flex flex-col items-center justify-center px-4 py-16 text-center">
            <MapPin className="h-10 w-10 text-slate-300" />
            <h2 className="mt-3 font-semibold text-slate-900">Search an address to begin</h2>
            <p className="mt-1 max-w-md text-sm text-slate-500">
              This view is designed for canvassing prep and in-office lookup when someone asks who DPG has already contacted at a house.
            </p>
          </div>
        ) : householdsQuery.isFetching ? (
          <div className="app-card px-4 py-12 text-center text-sm text-slate-500">Searching households...</div>
        ) : households.length === 0 ? (
          <div className="app-card px-4 py-12 text-center text-sm text-slate-500">No households found for that address.</div>
        ) : households.map((household) => (
          <article key={`${household.village_name || 'unknown'}-${household.address}`} className="app-card overflow-hidden">
            <div className="border-b border-slate-200 p-4 sm:p-5">
              <div className="flex flex-col gap-2 md:flex-row md:items-start md:justify-between">
                <div>
                  <h2 className="text-lg font-semibold text-slate-950">{household.address}</h2>
                  <p className="mt-1 text-sm text-slate-500">{household.village_name || 'Unknown village'}</p>
                </div>
                <div className="flex flex-wrap gap-2">
                  <span className="inline-flex items-center gap-1 rounded-full bg-blue-50 px-3 py-1 text-xs font-semibold text-blue-700">
                    <Database className="h-3.5 w-3.5" />
                    {household.gec_voters.length} GEC
                  </span>
                  <span className="inline-flex items-center gap-1 rounded-full bg-green-50 px-3 py-1 text-xs font-semibold text-green-700">
                    <Users className="h-3.5 w-3.5" />
                    {household.contacts.length} DPG records
                  </span>
                </div>
              </div>
            </div>
            <div className="grid gap-0 lg:grid-cols-2">
              <div className="border-b border-slate-200 p-4 lg:border-b-0 lg:border-r sm:p-5">
                <h3 className="mb-3 flex items-center gap-2 text-sm font-semibold uppercase tracking-[0.08em] text-slate-500">
                  <Database className="h-4 w-4" />
                  GEC voters at this address
                </h3>
                {household.gec_voters.length === 0 ? (
                  <p className="text-sm text-slate-500">No current GEC voters found at this address.</p>
                ) : (
                  <div className="space-y-2">
                    {household.gec_voters.map((voter) => {
                      const linkedContact = voter.linked_contact;
                      const possibleContact = voter.possible_contact;
                      const isLinked = Boolean(voter.linked_contact_count);
                      const hasPossibleMatch = !isLinked && Boolean(possibleContact);

                      return (
                      <div
                        key={voter.id}
                        className={`rounded-xl border p-3 ${
                          isLinked ? 'border-green-100 bg-green-50/50' : hasPossibleMatch ? 'border-amber-200 bg-amber-50/45' : 'border-slate-200'
                        }`}
                      >
                        <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                          <div className="min-w-0">
                            <div className="font-semibold text-slate-950">{fullName(voter)}</div>
                            <div className="mt-1 text-xs text-slate-500">{voterLabel(voter)}</div>
                            {isLinked ? (
                              <div className="mt-2 space-y-1 text-xs">
                                <span className="inline-flex rounded-full bg-green-100 px-2 py-0.5 font-semibold text-green-800">DPG contact</span>
                                {linkedContact && (
                                  <Link
                                    to={`/admin/supporters/${linkedContact.id}?return_to=${encodeURIComponent('/admin/households')}`}
                                    className="block font-semibold text-green-900 hover:underline"
                                  >
                                    {contactName(linkedContact)}
                                  </Link>
                                )}
                              </div>
                            ) : hasPossibleMatch && possibleContact ? (
                              <div className="mt-2 space-y-1 text-xs">
                                <span className="inline-flex rounded-full bg-amber-100 px-2 py-0.5 font-semibold text-amber-800">Possible DPG match</span>
                                <Link
                                  to={`/admin/supporters/${possibleContact.id}?return_to=${encodeURIComponent('/admin/households')}`}
                                  className="block font-semibold text-amber-900 hover:underline"
                                >
                                  {contactName(possibleContact)}
                                </Link>
                                <div className="text-amber-700">
                                  {contactClassificationLabel(possibleContact.contact_classification)} · not linked yet
                                </div>
                              </div>
                            ) : (
                              <div className="mt-2 text-xs font-medium text-slate-600">No DPG contact linked</div>
                            )}
                          </div>
                          <div className="flex shrink-0 flex-wrap gap-2">
                            {isLinked && linkedContact ? (
                              <Link
                                to={`/admin/supporters/${linkedContact.id}?return_to=${encodeURIComponent('/admin/households')}`}
                                className="inline-flex min-h-9 items-center justify-center gap-2 rounded-lg border border-green-200 bg-white px-2.5 text-xs font-semibold text-green-800 hover:bg-green-50"
                              >
                                <Users className="h-3.5 w-3.5" />
                                Open Contact
                              </Link>
                            ) : hasPossibleMatch && possibleContact ? (
                              <Link
                                to={`/admin/supporters/${possibleContact.id}?return_to=${encodeURIComponent('/admin/households')}`}
                                className="inline-flex min-h-9 items-center justify-center gap-2 rounded-lg border border-amber-200 bg-white px-2.5 text-xs font-semibold text-amber-800 hover:bg-amber-50"
                              >
                                <AlertTriangle className="h-3.5 w-3.5" />
                                Review Match
                              </Link>
                            ) : (
                            <button
                              type="button"
                              disabled={createContactMutation.isPending}
                              onClick={() => createContactMutation.mutate(voter.id)}
                              className="inline-flex min-h-9 items-center justify-center gap-2 rounded-lg border border-slate-200 px-2.5 text-xs font-semibold text-slate-700 hover:bg-slate-50 disabled:cursor-not-allowed disabled:opacity-45"
                            >
                              <Users className="h-3.5 w-3.5" />
                              Create Contact
                            </button>
                            )}
                            <button
                              type="button"
                              disabled={linkContactMutation.isPending || isLinked}
                              onClick={() => {
                                const nextVoterId = linkVoterId === voter.id ? null : voter.id;
                                setLinkVoterId(nextVoterId);
                                setContactSearch(nextVoterId ? fullName(voter) : '');
                                setSubmittedContactSearch('');
                              }}
                              className="inline-flex min-h-9 items-center justify-center gap-2 rounded-lg border border-slate-200 px-2.5 text-xs font-semibold text-slate-700 hover:bg-slate-50 disabled:cursor-not-allowed disabled:opacity-45"
                            >
                              <LinkIcon className="h-3.5 w-3.5" />
                              Link Existing
                            </button>
                          </div>
                        </div>
                        {linkVoterId === voter.id && (
                          <div className="mt-3 rounded-lg bg-slate-50 p-3">
                            <form
                              className="flex flex-col gap-2 sm:flex-row"
                              onSubmit={(event) => {
                                event.preventDefault();
                                setSubmittedContactSearch(contactSearch.trim());
                              }}
                            >
                              <input
                                value={contactSearch}
                                onChange={(event) => setContactSearch(event.target.value)}
                                placeholder="Search existing DPG contacts by name, phone, email, or address"
                                className="min-w-0 flex-1 rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm"
                              />
                              <button type="submit" className="app-btn-secondary min-h-10 justify-center">
                                <Search className="h-4 w-4" />
                                Find Contact
                              </button>
                            </form>
                            <div className="mt-3 space-y-2">
                              {contactResultsQuery.isFetching ? (
                                <div className="text-sm text-slate-500">Searching contacts...</div>
                              ) : submittedContactSearch && contactResults.length === 0 ? (
                                <div className="text-sm text-slate-500">No matching contacts found.</div>
                              ) : contactResults.map((contact) => (
                                <div key={contact.id} className="flex flex-col gap-2 rounded-lg border border-slate-200 bg-white p-2 sm:flex-row sm:items-center sm:justify-between">
                                  <div className="min-w-0">
                                    <div className="font-semibold text-slate-900">{contact.print_name || `${contact.first_name} ${contact.last_name}`}</div>
                                    <div className="text-xs text-slate-500">
                                      {[contact.contact_number, contact.email, contact.village_name, contact.street_address].filter(Boolean).join(' · ') || 'No contact details'}
                                    </div>
                                  </div>
                                  <button
                                    type="button"
                                    disabled={linkContactMutation.isPending}
                                    onClick={() => linkContactMutation.mutate({ voterId: voter.id, supporterId: contact.id })}
                                    className="inline-flex min-h-9 items-center justify-center gap-2 rounded-lg bg-primary px-3 text-xs font-semibold text-white disabled:opacity-50"
                                  >
                                    <LinkIcon className="h-3.5 w-3.5" />
                                    Link
                                  </button>
                                </div>
                              ))}
                            </div>
                          </div>
                        )}
                      </div>
                    )})}
                  </div>
                )}
              </div>

              <div className="p-4 sm:p-5">
                <h3 className="mb-3 flex items-center gap-2 text-sm font-semibold uppercase tracking-[0.08em] text-slate-500">
                  <Users className="h-4 w-4" />
                  DPG records at this address
                </h3>
                {household.contacts.length === 0 ? (
                  <p className="text-sm text-slate-500">No DPG records found at this address yet.</p>
                ) : (
	                  <div className="space-y-2">
	                    {household.contacts.map((contact) => {
	                      const draft = draftForContact(contact);
	                      const isExpanded = expandedContactId === contact.id;
	                      return (
	                        <div key={contact.id} className="rounded-xl border border-slate-200 p-3">
	                          <div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
	                            <div className="min-w-0">
	                              <div className="font-semibold text-slate-950">{contact.print_name || fullName(contact)}</div>
	                              <div className="mt-1 text-xs text-slate-500">
	                                {[contact.contact_number, contact.email].filter(Boolean).join(' · ') || 'No phone or email'}
	                              </div>
	                            </div>
	                            <span className={`w-fit rounded-full px-2 py-0.5 text-xs font-semibold ${contactClassificationChipClass(contact.contact_classification || 'new_intake')}`}>
	                              {contactClassificationLabel(contact.contact_classification || 'new_intake')}
	                            </span>
	                          </div>
	                          <div className="mt-2 flex flex-col gap-2 text-xs font-medium text-slate-600 sm:flex-row sm:items-center sm:justify-between">
	                            <span>{contact.current_gec_match ? 'Linked to current GEC voter' : 'No current GEC link'}</span>
	                            {contact.latest_contact_attempt ? (
	                              <span>
	                                Last: {contact.latest_contact_attempt.channel.replaceAll('_', ' ')} / {contact.latest_contact_attempt.outcome.replaceAll('_', ' ')}
	                                {contact.latest_contact_attempt.recorded_at ? ` on ${formatDateTime(contact.latest_contact_attempt.recorded_at)}` : ''}
	                              </span>
	                            ) : (
	                              <span>No outreach logged yet</span>
	                            )}
	                          </div>
	                          <div className="mt-3 flex flex-wrap gap-2">
	                            <button
	                              type="button"
	                              onClick={() => setExpandedContactId(isExpanded ? null : contact.id)}
	                              className="inline-flex min-h-9 items-center justify-center gap-2 rounded-lg bg-primary px-2.5 text-xs font-semibold text-white"
	                            >
	                              <MessageSquare className="h-3.5 w-3.5" />
	                              Log canvass
	                            </button>
	                            <Link
	                              to={`/admin/supporters/${contact.id}?return_to=${encodeURIComponent('/admin/households')}`}
	                              className="inline-flex min-h-9 items-center justify-center gap-2 rounded-lg border border-slate-200 px-2.5 text-xs font-semibold text-slate-700 hover:bg-slate-50"
	                            >
	                              Open Record
	                            </Link>
	                          </div>
	                          {isExpanded && (
	                            <div className="mt-3 rounded-lg bg-slate-50 p-3">
	                              <div className="grid gap-2 sm:grid-cols-3">
	                                <select
	                                  value={draft.contact_classification}
	                                  onChange={(event) => updateCanvassDraft(contact, { contact_classification: event.target.value })}
	                                  className="rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm"
	                                  aria-label="Relationship status"
	                                >
	                                  {ACTIVE_RELATIONSHIP_OPTIONS.map((option) => (
	                                    <option key={option.value} value={option.value}>{option.label}</option>
	                                  ))}
	                                </select>
	                                <select
	                                  value={draft.channel}
	                                  onChange={(event) => updateCanvassDraft(contact, { channel: event.target.value })}
	                                  className="rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm"
	                                  aria-label="Contact method"
	                                >
	                                  {CONTACT_ATTEMPT_CHANNEL_OPTIONS.map((option) => (
	                                    <option key={option.value} value={option.value}>{option.label}</option>
	                                  ))}
	                                </select>
	                                <select
	                                  value={draft.outcome}
	                                  onChange={(event) => updateCanvassDraft(contact, { outcome: event.target.value })}
	                                  className="rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm"
	                                  aria-label="Contact outcome"
	                                >
	                                  {CONTACT_ATTEMPT_OUTCOME_OPTIONS.map((option) => (
	                                    <option key={option.value} value={option.value}>{option.label}</option>
	                                  ))}
	                                </select>
	                              </div>
	                              <textarea
	                                value={draft.note}
	                                onChange={(event) => updateCanvassDraft(contact, { note: event.target.value })}
	                                rows={2}
	                                placeholder="Canvassing note"
	                                className="mt-2 w-full rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm"
	                              />
	                              <div className="mt-2 flex justify-end">
	                                <button
	                                  type="button"
	                                  onClick={() => saveCanvassUpdate(contact)}
	                                  disabled={canvassMutation.isPending}
	                                  className="inline-flex min-h-9 items-center justify-center gap-2 rounded-lg bg-primary px-3 text-xs font-semibold text-white disabled:opacity-50"
	                                >
	                                  <CheckCircle2 className="h-3.5 w-3.5" />
	                                  Save update
	                                </button>
	                              </div>
	                            </div>
	                          )}
	                        </div>
	                      );
	                    })}
	                  </div>
                )}
              </div>
            </div>
          </article>
        ))}
      </section>
    </WorkspacePage>
  );
}
