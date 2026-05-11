import { Fragment, useMemo, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import {
  AlertTriangle,
  CheckCircle2,
  Database,
  Home,
  Link as LinkIcon,
  Loader2,
  Search,
  Upload,
  Users,
} from 'lucide-react';
import {
  activateGecImport,
  createContactFromGecVoter,
  getGecHouseholds,
  getGecImports,
  getGecStats,
  getGecVoters,
  getSupporters,
  linkContactToGecVoter,
  previewGecList,
  uploadGecList,
} from '../../lib/api';
import { useSession } from '../../hooks/useSession';

type GecVoter = {
  id: number;
  first_name: string;
  middle_name?: string | null;
  last_name: string;
  birth_year?: number | null;
  address?: string | null;
  village_name: string;
  precinct_number?: string | null;
  voter_registration_number?: string | null;
  gec_list_date: string;
  linked_contact_count?: number;
};

type Household = {
  address: string;
  village_name: string;
  gec_voters: GecVoter[];
  contacts: Array<{
    id: number;
    print_name?: string | null;
    first_name: string;
    last_name: string;
    contact_classification: string;
    current_gec_match: boolean;
  }>;
};

type GecImport = {
  id: number;
  gec_list_date: string;
  filename: string;
  total_records: number;
  new_records: number;
  updated_records: number;
  removed_records: number;
  transferred_records: number;
  status: string;
  created_at: string;
  uploaded_by_email?: string | null;
  active_election_day?: boolean;
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
  contact_classification?: string | null;
  current_gec_match?: boolean | null;
};

const today = new Date().toISOString().slice(0, 10);

function getErrorMessage(error: unknown) {
  if (error instanceof Error) return error.message;
  if (typeof error === 'object' && error && 'response' in error) {
    const response = (error as { response?: { data?: { message?: string; error?: string } } }).response;
    return response?.data?.message || response?.data?.error || 'The request failed.';
  }
  return 'The request failed.';
}

function fullName(voter: Pick<GecVoter, 'first_name' | 'middle_name' | 'last_name'>) {
  return [voter.first_name, voter.middle_name, voter.last_name].filter(Boolean).join(' ');
}

function formatDate(value?: string | null) {
  if (!value) return '—';
  return new Date(`${value}T00:00:00Z`).toLocaleDateString('en-US', { timeZone: 'Pacific/Guam' });
}

export default function GecVotersPage() {
  const queryClient = useQueryClient();
  const { data: session } = useSession();
  const canUploadGec = Boolean(session?.permissions?.can_upload_gec);
  const [search, setSearch] = useState('');
  const [submittedSearch, setSubmittedSearch] = useState('');
  const [householdSearch, setHouseholdSearch] = useState('');
  const [submittedHouseholdSearch, setSubmittedHouseholdSearch] = useState('');
  const [file, setFile] = useState<File | null>(null);
  const [listDate, setListDate] = useState(today);
  const [importType, setImportType] = useState('full_list');
  const [uploadMessage, setUploadMessage] = useState<string | null>(null);
  const [uploadError, setUploadError] = useState<string | null>(null);
  const [actionMessage, setActionMessage] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [linkVoterId, setLinkVoterId] = useState<number | null>(null);
  const [contactSearch, setContactSearch] = useState('');
  const [submittedContactSearch, setSubmittedContactSearch] = useState('');

  const statsQuery = useQuery({ queryKey: ['gec-stats'], queryFn: getGecStats });
  const importsQuery = useQuery({ queryKey: ['gec-imports'], queryFn: getGecImports, enabled: canUploadGec });
  const votersQuery = useQuery({
    queryKey: ['gec-voters', submittedSearch],
    queryFn: () => getGecVoters({ q: submittedSearch, per_page: 50 }),
  });
  const householdsQuery = useQuery({
    queryKey: ['gec-households', submittedHouseholdSearch],
    queryFn: () => getGecHouseholds({ q: submittedHouseholdSearch }),
    enabled: submittedHouseholdSearch.trim().length >= 3,
  });
  const contactResultsQuery = useQuery({
    queryKey: ['gec-link-contact-candidates', linkVoterId, submittedContactSearch],
    queryFn: () => getSupporters({ search: submittedContactSearch, per_page: 10 }),
    enabled: Boolean(linkVoterId) && submittedContactSearch.trim().length >= 2,
  });

  const previewMutation = useMutation({
    mutationFn: async () => {
      if (!file) throw new Error('Choose a file first.');
      return previewGecList(file, listDate);
    },
    onSuccess: (data) => {
      setUploadError(null);
      setUploadMessage(`Preview found ${data.row_count ?? 0} rows and mapped ${Object.keys(data.column_map ?? {}).length} columns.`);
    },
    onError: (error: unknown) => {
      setUploadMessage(null);
      setUploadError(getErrorMessage(error));
    },
  });

  const uploadMutation = useMutation({
    mutationFn: async () => {
      if (!file) throw new Error('Choose a file first.');
      return uploadGecList(file, listDate, importType);
    },
    onSuccess: (data) => {
      setUploadError(null);
      setUploadMessage(`Imported ${data.stats?.total ?? 0} GEC rows. New: ${data.stats?.new ?? 0}, updated: ${data.stats?.updated ?? 0}, removed: ${data.stats?.removed ?? 0}.`);
      void queryClient.invalidateQueries({ queryKey: ['gec-stats'] });
      void queryClient.invalidateQueries({ queryKey: ['gec-imports'] });
      void queryClient.invalidateQueries({ queryKey: ['gec-voters'] });
    },
    onError: (error: unknown) => {
      setUploadMessage(null);
      setUploadError(getErrorMessage(error));
    },
  });

  const createContactMutation = useMutation({
    mutationFn: (voterId: number) => createContactFromGecVoter(voterId),
    onSuccess: () => {
      setActionError(null);
      setActionMessage('Created and linked the DPG contact.');
      void queryClient.invalidateQueries({ queryKey: ['gec-voters'] });
      void queryClient.invalidateQueries({ queryKey: ['gec-households'] });
      void queryClient.invalidateQueries({ queryKey: ['session'] });
    },
    onError: (error: unknown) => {
      setActionMessage(null);
      setActionError(getErrorMessage(error));
    },
  });

  const activateImportMutation = useMutation({
    mutationFn: (importId: number) => activateGecImport(importId),
    onSuccess: () => {
      setActionError(null);
      setActionMessage('Activated the selected GEC import.');
      void queryClient.invalidateQueries({ queryKey: ['gec-stats'] });
      void queryClient.invalidateQueries({ queryKey: ['gec-imports'] });
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
      void queryClient.invalidateQueries({ queryKey: ['gec-voters'] });
      void queryClient.invalidateQueries({ queryKey: ['gec-households'] });
      void queryClient.invalidateQueries({ queryKey: ['gec-link-contact-candidates'] });
    },
    onError: (error: unknown) => {
      setActionMessage(null);
      setActionError(getErrorMessage(error));
    },
  });

  const voters = useMemo<GecVoter[]>(() => votersQuery.data?.gec_voters ?? [], [votersQuery.data]);
  const households = useMemo<Household[]>(() => householdsQuery.data?.households ?? [], [householdsQuery.data]);
  const imports = useMemo<GecImport[]>(() => importsQuery.data?.imports ?? [], [importsQuery.data]);
  const contactResults = useMemo<ContactResult[]>(() => contactResultsQuery.data?.supporters ?? [], [contactResultsQuery.data]);

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
        <div>
          <div className="mb-2 inline-flex items-center gap-2 rounded-full bg-blue-50 px-3 py-1 text-xs font-semibold uppercase tracking-[0.12em] text-blue-700">
            <Database className="h-3.5 w-3.5" />
            Public voter file
          </div>
          <h1 className="text-2xl font-bold text-slate-950">GEC Voter List</h1>
          <p className="mt-1 max-w-3xl text-sm text-slate-500">
            Search official voter records by name, address, village, precinct, or registration number, then link voters into DPG contacts for follow-up.
          </p>
        </div>
      </div>

      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard label="Active GEC voters" value={statsQuery.data?.total_voters ?? 0} />
        <StatCard label="Linked DPG contacts" value={statsQuery.data?.linked_contacts ?? 0} />
        <StatCard label="Latest list" value={formatDate(statsQuery.data?.latest_list_date)} />
        <StatCard label="Removed records" value={statsQuery.data?.removed_voters ?? 0} />
      </div>

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

      {canUploadGec && (
        <section className="app-card p-4 sm:p-5">
          <div className="mb-4 flex items-center gap-2">
            <Upload className="h-5 w-5 text-blue-600" />
            <h2 className="text-lg font-semibold text-slate-950">Import GEC List</h2>
          </div>
          <div className="grid gap-3 lg:grid-cols-[minmax(0,1fr)_160px_160px_auto_auto] lg:items-end">
            <label className="block">
              <span className="mb-1 block text-xs font-semibold uppercase tracking-[0.08em] text-slate-500">File</span>
              <input
                type="file"
                accept=".csv,.xlsx,.xls"
                onChange={(event) => setFile(event.target.files?.[0] ?? null)}
                className="block w-full rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm"
              />
            </label>
            <label className="block">
              <span className="mb-1 block text-xs font-semibold uppercase tracking-[0.08em] text-slate-500">List date</span>
              <input
                type="date"
                value={listDate}
                onChange={(event) => setListDate(event.target.value)}
                className="block w-full rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm"
              />
            </label>
            <label className="block">
              <span className="mb-1 block text-xs font-semibold uppercase tracking-[0.08em] text-slate-500">Type</span>
              <select
                value={importType}
                onChange={(event) => setImportType(event.target.value)}
                className="block w-full rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm"
              >
                <option value="full_list">Full list</option>
                <option value="changes_only">Changes only</option>
              </select>
            </label>
            <button
              type="button"
              disabled={!file || previewMutation.isPending}
              onClick={() => previewMutation.mutate()}
              className="app-btn-secondary min-h-11 justify-center"
            >
              {previewMutation.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Search className="h-4 w-4" />}
              Preview
            </button>
            <button
              type="button"
              disabled={!file || !listDate || uploadMutation.isPending}
              onClick={() => uploadMutation.mutate()}
              className="app-btn-primary min-h-11 justify-center"
            >
              {uploadMutation.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Upload className="h-4 w-4" />}
              Import
            </button>
          </div>
          {uploadMessage && (
            <div className="mt-3 flex items-start gap-2 rounded-xl bg-green-50 px-3 py-2 text-sm text-green-800">
              <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0" />
              {uploadMessage}
            </div>
          )}
          {uploadError && (
            <div className="mt-3 flex items-start gap-2 rounded-xl bg-red-50 px-3 py-2 text-sm text-red-800">
              <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
              {uploadError}
            </div>
          )}
        </section>
      )}

      <section className="grid gap-6 xl:grid-cols-[minmax(0,1fr)_420px]">
        <div className="app-card overflow-hidden">
          <div className="border-b border-slate-200 p-4 sm:p-5">
            <form
              className="flex flex-col gap-3 sm:flex-row"
              onSubmit={(event) => {
                event.preventDefault();
                setSubmittedSearch(search.trim());
              }}
            >
              <div className="relative flex-1">
                <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" />
                <input
                  value={search}
                  onChange={(event) => setSearch(event.target.value)}
                  placeholder="Search name, address, precinct, village, or voter number"
                  className="w-full rounded-xl border border-slate-200 bg-white py-3 pl-10 pr-3 text-sm"
                />
              </div>
              <button type="submit" className="app-btn-primary min-h-11 justify-center">
                <Search className="h-4 w-4" />
                Search
              </button>
            </form>
          </div>

          <div className="overflow-x-auto">
            <table className="w-full min-w-[760px] text-sm">
              <thead className="bg-slate-50 text-left text-xs uppercase tracking-[0.08em] text-slate-500">
                <tr>
                  <th className="px-4 py-3">Voter</th>
                  <th className="px-4 py-3">Address</th>
                  <th className="px-4 py-3">Village</th>
                  <th className="px-4 py-3">Precinct</th>
                  <th className="px-4 py-3">DPG Contact</th>
                  <th className="px-4 py-3 text-right">Action</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {votersQuery.isLoading ? (
                  <tr><td colSpan={6} className="px-4 py-12 text-center text-slate-500">Loading voters...</td></tr>
                ) : voters.length === 0 ? (
                  <tr><td colSpan={6} className="px-4 py-12 text-center text-slate-500">No GEC voters found</td></tr>
                ) : voters.map((voter) => (
                  <Fragment key={voter.id}>
                    <tr className="align-top">
                      <td className="px-4 py-3">
                        <div className="font-semibold text-slate-950">{fullName(voter)}</div>
                        <div className="text-xs text-slate-500">{voter.voter_registration_number || 'No voter number'}{voter.birth_year ? ` · Born ${voter.birth_year}` : ''}</div>
                      </td>
                      <td className="px-4 py-3 text-slate-600">{voter.address || '—'}</td>
                      <td className="px-4 py-3 text-slate-600">{voter.village_name}</td>
                      <td className="px-4 py-3 text-slate-600">{voter.precinct_number || '—'}</td>
                      <td className="px-4 py-3 text-slate-600">
                        {voter.linked_contact_count ? `${voter.linked_contact_count} linked` : 'Not linked'}
                      </td>
                      <td className="px-4 py-3 text-right">
                        <div className="flex flex-col items-end gap-2">
                          <button
                            type="button"
                            disabled={createContactMutation.isPending}
                            onClick={() => createContactMutation.mutate(voter.id)}
                            className="inline-flex min-h-10 items-center justify-center gap-2 rounded-xl border border-slate-200 px-3 text-xs font-semibold text-slate-700 hover:bg-slate-50 disabled:opacity-50"
                          >
                            <LinkIcon className="h-4 w-4" />
                            Create Contact
                          </button>
                          <button
                            type="button"
                            onClick={() => {
                              const nextId = linkVoterId === voter.id ? null : voter.id;
                              setLinkVoterId(nextId);
                              setContactSearch('');
                              setSubmittedContactSearch('');
                            }}
                            className="inline-flex min-h-10 items-center justify-center gap-2 rounded-xl border border-slate-200 px-3 text-xs font-semibold text-slate-700 hover:bg-slate-50"
                          >
                            <Users className="h-4 w-4" />
                            Link Existing
                          </button>
                        </div>
                      </td>
                    </tr>
                    {linkVoterId === voter.id && (
                      <tr>
                        <td colSpan={6} className="bg-slate-50 px-4 py-4">
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
                              className="min-w-0 flex-1 rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm"
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
                              <div key={contact.id} className="flex flex-col gap-2 rounded-xl border border-slate-200 bg-white p-3 sm:flex-row sm:items-center sm:justify-between">
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
                                  className="inline-flex min-h-10 items-center justify-center gap-2 rounded-xl bg-primary px-3 text-xs font-semibold text-white disabled:opacity-50"
                                >
                                  <LinkIcon className="h-4 w-4" />
                                  Link
                                </button>
                              </div>
                            ))}
                          </div>
                        </td>
                      </tr>
                    )}
                  </Fragment>
                ))}
              </tbody>
            </table>
          </div>
        </div>

        <div className="space-y-6">
          <section className="app-card p-4 sm:p-5">
            <div className="mb-4 flex items-center gap-2">
              <Home className="h-5 w-5 text-blue-600" />
              <h2 className="text-lg font-semibold text-slate-950">Address Lookup</h2>
            </div>
            <form
              className="flex gap-2"
              onSubmit={(event) => {
                event.preventDefault();
                setSubmittedHouseholdSearch(householdSearch.trim());
              }}
            >
              <input
                value={householdSearch}
                onChange={(event) => setHouseholdSearch(event.target.value)}
                placeholder="Enter street or house number"
                className="min-w-0 flex-1 rounded-xl border border-slate-200 bg-white px-3 py-3 text-sm"
              />
              <button type="submit" className="app-btn-primary min-h-11 justify-center px-3">
                <Search className="h-4 w-4" />
              </button>
            </form>
            <div className="mt-4 space-y-3">
              {householdsQuery.isFetching ? (
                <div className="rounded-xl bg-slate-50 p-4 text-sm text-slate-500">Searching addresses...</div>
              ) : households.map((household) => (
                <div key={`${household.village_name}-${household.address}`} className="rounded-xl border border-slate-200 p-3">
                  <div className="font-semibold text-slate-950">{household.address}</div>
                  <div className="text-xs text-slate-500">{household.village_name}</div>
                  <div className="mt-3 grid gap-2 text-sm sm:grid-cols-2 xl:grid-cols-1">
                    <div className="rounded-lg bg-blue-50 p-2 text-blue-900">
                      <div className="mb-1 flex items-center gap-1 text-xs font-semibold uppercase tracking-[0.08em]">
                        <Database className="h-3.5 w-3.5" />
                        GEC voters
                      </div>
                      {household.gec_voters.length || 0} found
                    </div>
                    <div className="rounded-lg bg-green-50 p-2 text-green-900">
                      <div className="mb-1 flex items-center gap-1 text-xs font-semibold uppercase tracking-[0.08em]">
                        <Users className="h-3.5 w-3.5" />
                        DPG contacts
                      </div>
                      {household.contacts.length || 0} found
                    </div>
                  </div>
                  <div className="mt-3 space-y-1">
                    {household.gec_voters.slice(0, 8).map((voter) => (
                      <div key={voter.id} className="text-sm text-slate-700">{fullName(voter)}{voter.precinct_number ? ` · Pct ${voter.precinct_number}` : ''}</div>
                    ))}
                  </div>
                </div>
              ))}
              {submittedHouseholdSearch && !householdsQuery.isFetching && households.length === 0 && (
                <div className="rounded-xl bg-slate-50 p-4 text-sm text-slate-500">No households found for that address.</div>
              )}
            </div>
          </section>

          {canUploadGec && (
            <section className="app-card p-4 sm:p-5">
              <h2 className="mb-3 text-lg font-semibold text-slate-950">Recent Imports</h2>
              <div className="space-y-2">
                {imports.length === 0 ? (
                  <div className="rounded-xl bg-slate-50 p-4 text-sm text-slate-500">No GEC imports yet.</div>
                ) : imports.slice(0, 6).map((row) => (
                  <div key={row.id} className="rounded-xl border border-slate-200 p-3">
                    <div className="flex items-start justify-between gap-3">
                      <div className="min-w-0">
                        <div className="truncate font-semibold text-slate-900">{row.filename}</div>
                        <div className="text-xs text-slate-500">{formatDate(row.gec_list_date)} · {row.status}{row.active_election_day ? ' · Active' : ''}</div>
                      </div>
                      <div className="flex shrink-0 flex-col items-end gap-2">
                        <div className="text-right text-xs font-semibold text-slate-500">{row.total_records || 0} rows</div>
                        {row.status === 'completed' && !row.active_election_day ? (
                          <button
                            type="button"
                            disabled={activateImportMutation.isPending}
                            onClick={() => activateImportMutation.mutate(row.id)}
                            className="inline-flex min-h-8 items-center rounded-lg border border-slate-200 px-2 text-xs font-semibold text-slate-700 hover:bg-slate-50 disabled:opacity-50"
                          >
                            Activate
                          </button>
                        ) : null}
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </section>
          )}
        </div>
      </section>
    </div>
  );
}

function StatCard({ label, value }: { label: string; value: string | number }) {
  return (
    <div className="app-card p-4">
      <div className="text-xs font-semibold uppercase tracking-[0.1em] text-slate-500">{label}</div>
      <div className="mt-2 text-2xl font-bold text-slate-950">{value}</div>
    </div>
  );
}
