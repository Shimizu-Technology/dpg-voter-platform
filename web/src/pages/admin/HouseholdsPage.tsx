import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { Database, Home, MapPin, Search, Users } from 'lucide-react';
import WorkspacePage from '../../components/WorkspacePage';
import { getGecHouseholds } from '../../lib/api';
import {
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
  current_gec_match?: boolean | null;
  registered_voter_status?: string | null;
};

type Household = {
  address: string;
  village_name?: string | null;
  gec_voters: GecVoter[];
  contacts: HouseholdContact[];
};

function fullName(person: Pick<GecVoter | HouseholdContact, 'first_name' | 'middle_name' | 'last_name'>) {
  return [person.first_name, person.middle_name, person.last_name].filter(Boolean).join(' ');
}

function voterLabel(voter: GecVoter) {
  return [voter.precinct_number ? `Pct ${voter.precinct_number}` : null, voter.voter_registration_number].filter(Boolean).join(' · ') || 'GEC voter';
}

export default function HouseholdsPage() {
  const [search, setSearch] = useState('');
  const [submittedSearch, setSubmittedSearch] = useState('');

  const householdsQuery = useQuery({
    queryKey: ['households-workspace', submittedSearch],
    queryFn: () => getGecHouseholds({ q: submittedSearch }),
    enabled: submittedSearch.trim().length >= 3,
  });

  const households = useMemo<Household[]>(() => householdsQuery.data?.households ?? [], [householdsQuery.data]);
  const voterCount = householdsQuery.data?.voter_count ?? households.reduce((sum, household) => sum + household.gec_voters.length, 0);
  const contactCount = householdsQuery.data?.contact_count ?? households.reduce((sum, household) => sum + household.contacts.length, 0);

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
                    {household.contacts.length} DPG
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
                    {household.gec_voters.map((voter) => (
                      <div key={voter.id} className="rounded-xl border border-slate-200 p-3">
                        <div className="font-semibold text-slate-950">{fullName(voter)}</div>
                        <div className="mt-1 text-xs text-slate-500">{voterLabel(voter)}</div>
                        <div className="mt-2 text-xs font-medium text-slate-600">
                          {voter.linked_contact_count ? `${voter.linked_contact_count} linked DPG contact${voter.linked_contact_count === 1 ? '' : 's'}` : 'No DPG contact linked'}
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </div>

              <div className="p-4 sm:p-5">
                <h3 className="mb-3 flex items-center gap-2 text-sm font-semibold uppercase tracking-[0.08em] text-slate-500">
                  <Users className="h-4 w-4" />
                  DPG contacts at this address
                </h3>
                {household.contacts.length === 0 ? (
                  <p className="text-sm text-slate-500">No DPG contacts found at this address yet.</p>
                ) : (
                  <div className="space-y-2">
                    {household.contacts.map((contact) => (
                      <Link
                        key={contact.id}
                        to={`/admin/supporters/${contact.id}?return_to=${encodeURIComponent('/admin/households')}`}
                        className="block rounded-xl border border-slate-200 p-3 hover:bg-slate-50"
                      >
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
                        <div className="mt-2 text-xs font-medium text-slate-600">
                          {contact.current_gec_match ? 'Linked to current GEC voter' : 'No current GEC link'}
                        </div>
                      </Link>
                    ))}
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
