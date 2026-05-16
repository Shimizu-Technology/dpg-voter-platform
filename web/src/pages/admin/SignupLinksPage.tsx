import { useEffect, useMemo, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import QRCode from 'qrcode';
import { Check, Copy, ExternalLink, Plus, QrCode, Share2 } from 'lucide-react';
import WorkspacePage from '../../components/WorkspacePage';
import { useSession } from '../../hooks/useSession';
import { createReferralCode, getReferralCodes, getUsers, getVillages, updateReferralCode } from '../../lib/api';

interface VillageOption {
  id: number;
  name: string;
}

interface UserOption {
  id: number;
  name: string | null;
  email: string;
  role: string;
  assigned_village_id: number | null;
}

interface SignupLink {
  id: number;
  code: string;
  display_name: string;
  active: boolean;
  village_id: number;
  village_name: string;
  assigned_user_id: number | null;
  assigned_user_name: string | null;
  source_type: string;
  precinct_id: string | null;
  notes: string | null;
  signup_count: number;
  signup_url: string;
  created_at: string;
}

interface ReferralCodesResponse {
  referral_codes: SignupLink[];
  signup_base_url: string;
}

interface UsersResponse {
  users: UserOption[];
}

interface DraftState {
  display_name: string;
  source_type: string;
  village_id: string;
  assigned_user_id: string;
  notes: string;
}

const sourceTypes = [
  { value: 'village', label: 'Village' },
  { value: 'precinct', label: 'Precinct' },
  { value: 'canvasser', label: 'Canvasser' },
  { value: 'outreach', label: 'Outreach Push' },
  { value: 'custom', label: 'Custom' },
];

function sourceLabel(value: string) {
  return sourceTypes.find((type) => type.value === value)?.label || 'Custom';
}

function QrPreview({ url, label }: { url: string; label: string }) {
  const [src, setSrc] = useState('');

  useEffect(() => {
    let cancelled = false;
    QRCode.toDataURL(url, { margin: 1, width: 220, color: { dark: '#0f2a5b', light: '#ffffff' } })
      .then((dataUrl) => {
        if (!cancelled) setSrc(dataUrl);
      })
      .catch(() => {
        if (!cancelled) setSrc('');
      });
    return () => {
      cancelled = true;
    };
  }, [url]);

  if (!src) {
    return <div className="h-28 w-28 animate-pulse rounded-lg bg-slate-100" aria-label={`QR loading for ${label}`} />;
  }

  return <img src={src} alt={`QR code for ${label}`} className="h-28 w-28 rounded-lg border border-slate-200 bg-white p-2" />;
}

export default function SignupLinksPage() {
  const queryClient = useQueryClient();
  const { data: sessionData } = useSession();
  const [draft, setDraft] = useState<DraftState>({
    display_name: '',
    source_type: 'village',
    village_id: '',
    assigned_user_id: '',
    notes: '',
  });
  const [copied, setCopied] = useState<string | null>(null);
  const [notice, setNotice] = useState<{ type: 'success' | 'error'; message: string } | null>(null);

  const { data, isLoading } = useQuery<ReferralCodesResponse>({
    queryKey: ['referral-codes'],
    queryFn: getReferralCodes,
  });
  const { data: villagesData } = useQuery<{ villages: VillageOption[] }>({
    queryKey: ['villages'],
    queryFn: getVillages,
  });
  const { data: usersData } = useQuery<UsersResponse>({
    queryKey: ['users'],
    queryFn: getUsers,
    enabled: Boolean(sessionData?.permissions?.can_manage_users),
  });

  const villages = useMemo(() => villagesData?.villages ?? [], [villagesData]);
  const users = useMemo(() => usersData?.users ?? [], [usersData]);
  const signupLinks = data?.referral_codes ?? [];
  const generalSignupUrl = `${(data?.signup_base_url || window.location.origin).replace(/\/$/, '')}/signup`;

  const createMutation = useMutation({
    mutationFn: () => createReferralCode({
      display_name: draft.display_name,
      source_type: draft.source_type,
      village_id: Number(draft.village_id),
      assigned_user_id: draft.assigned_user_id ? Number(draft.assigned_user_id) : undefined,
      notes: draft.notes || undefined,
    }),
    onSuccess: () => {
      setDraft({ display_name: '', source_type: 'village', village_id: '', assigned_user_id: '', notes: '' });
      void queryClient.invalidateQueries({ queryKey: ['referral-codes'] });
    },
  });

  const toggleMutation = useMutation({
    mutationFn: ({ id, active }: { id: number; active: boolean }) => updateReferralCode(id, { active }),
    onSuccess: () => {
      setNotice({ type: 'success', message: 'Signup link status updated.' });
      void queryClient.invalidateQueries({ queryKey: ['referral-codes'] });
    },
    onError: () => {
      setNotice({ type: 'error', message: 'Could not update this signup link. Refresh and try again.' });
    },
  });

  const copyUrl = async (key: string, url: string) => {
    try {
      await navigator.clipboard.writeText(url);
      setCopied(key);
      setNotice({ type: 'success', message: 'Signup link copied.' });
      window.setTimeout(() => setCopied(null), 1800);
    } catch {
      setNotice({ type: 'error', message: 'Could not copy the link. Select and copy the URL manually.' });
    }
  };

  const canCreate = draft.display_name.trim().length > 1 && draft.village_id && !createMutation.isPending;

  return (
    <WorkspacePage width="full" className="space-y-6">
      <div className="flex flex-col gap-3 md:flex-row md:items-end md:justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-gray-900">Signup Links</h1>
          <p className="mt-1 max-w-3xl text-sm text-slate-600">
            Create DPG-branded public signup links for villages, canvassers, and outreach pushes. New contacts keep the source code for attribution.
          </p>
        </div>
        <a href={generalSignupUrl} target="_blank" rel="noreferrer" className="app-btn-secondary inline-flex items-center gap-2">
          <ExternalLink className="h-4 w-4" />
          Open General Signup
        </a>
      </div>

      <section className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_360px]">
        <div className="app-card p-5">
          <div className="flex items-start gap-4">
            <QrPreview url={generalSignupUrl} label="general signup" />
            <div className="min-w-0 flex-1">
              <div className="flex flex-wrap items-center gap-2">
                <h2 className="text-base font-semibold text-slate-950">General signup</h2>
                <span className="rounded-full bg-slate-100 px-2.5 py-1 text-xs font-semibold text-slate-600">No attribution code</span>
              </div>
              <p className="mt-2 text-sm text-slate-600">Use this when DPG wants a broad signup link without tying it to a village or staff source.</p>
              <div className="mt-4 flex flex-wrap items-center gap-2">
                <code className="max-w-full truncate rounded-lg bg-slate-100 px-3 py-2 text-xs text-slate-700">{generalSignupUrl}</code>
                <button type="button" className="app-btn-secondary inline-flex items-center gap-2" onClick={() => copyUrl('general', generalSignupUrl)}>
                  {copied === 'general' ? <Check className="h-4 w-4" /> : <Copy className="h-4 w-4" />}
                  {copied === 'general' ? 'Copied' : 'Copy'}
                </button>
              </div>
            </div>
          </div>
        </div>

        <form
          className="app-card space-y-4 p-5"
          onSubmit={(event) => {
            event.preventDefault();
            if (canCreate) createMutation.mutate();
          }}
        >
          <div className="flex items-center gap-2">
            <Plus className="h-5 w-5 text-primary" />
            <h2 className="text-base font-semibold text-slate-950">Create Source Link</h2>
          </div>
          <label className="block text-sm">
            <span className="font-medium text-slate-700">Label</span>
            <input
              value={draft.display_name}
              onChange={(event) => setDraft((value) => ({ ...value, display_name: event.target.value }))}
              className="mt-1 w-full rounded-lg border border-slate-200 px-3 py-2 text-sm"
              placeholder="Tamuning canvass team"
            />
          </label>
          <label className="block text-sm">
            <span className="font-medium text-slate-700">Source type</span>
            <select
              value={draft.source_type}
              onChange={(event) => setDraft((value) => ({ ...value, source_type: event.target.value }))}
              className="mt-1 w-full rounded-lg border border-slate-200 px-3 py-2 text-sm"
            >
              {sourceTypes.map((type) => <option key={type.value} value={type.value}>{type.label}</option>)}
            </select>
          </label>
          <label className="block text-sm">
            <span className="font-medium text-slate-700">Village</span>
            <select
              value={draft.village_id}
              onChange={(event) => setDraft((value) => ({ ...value, village_id: event.target.value }))}
              className="mt-1 w-full rounded-lg border border-slate-200 px-3 py-2 text-sm"
            >
              <option value="">Choose village</option>
              {villages.map((village) => <option key={village.id} value={village.id}>{village.name}</option>)}
            </select>
          </label>
          {sessionData?.permissions?.can_manage_users && (
            <label className="block text-sm">
              <span className="font-medium text-slate-700">Assigned staff</span>
              <select
                value={draft.assigned_user_id}
                onChange={(event) => setDraft((value) => ({ ...value, assigned_user_id: event.target.value }))}
                className="mt-1 w-full rounded-lg border border-slate-200 px-3 py-2 text-sm"
              >
                <option value="">No staff assignment</option>
                {users.map((user) => (
                  <option key={user.id} value={user.id}>{user.name || user.email}</option>
                ))}
              </select>
            </label>
          )}
          <label className="block text-sm">
            <span className="font-medium text-slate-700">Notes</span>
            <textarea
              value={draft.notes}
              onChange={(event) => setDraft((value) => ({ ...value, notes: event.target.value }))}
              className="mt-1 w-full rounded-lg border border-slate-200 px-3 py-2 text-sm"
              rows={3}
              placeholder="Optional context for staff"
            />
          </label>
          <button type="submit" className="app-btn-primary inline-flex w-full items-center justify-center gap-2" disabled={!canCreate}>
            <QrCode className="h-4 w-4" />
            {createMutation.isPending ? 'Creating...' : 'Create Link'}
          </button>
          {createMutation.isError && (
            <p className="rounded-lg bg-red-50 px-3 py-2 text-sm text-red-700">Could not create this link. Check the fields and try again.</p>
          )}
        </form>
      </section>

      <section className="app-card overflow-hidden">
        <div className="border-b border-slate-100 px-5 py-4">
          <h2 className="text-base font-semibold text-slate-950">Attributed Signup Links</h2>
          <p className="mt-1 text-sm text-slate-600">Each link routes to the public signup form and stores the source code on created contacts.</p>
          {notice && (
            <p
              className={`mt-3 rounded-lg px-3 py-2 text-sm ${
                notice.type === 'error' ? 'bg-red-50 text-red-700' : 'bg-emerald-50 text-emerald-700'
              }`}
            >
              {notice.message}
            </p>
          )}
        </div>
        {isLoading ? (
          <div className="p-8 text-sm text-slate-500">Loading signup links...</div>
        ) : signupLinks.length === 0 ? (
          <div className="p-8 text-sm text-slate-500">No attributed signup links yet.</div>
        ) : (
          <div className="divide-y divide-slate-100">
            {signupLinks.map((link) => (
              <div key={link.id} className={`grid gap-4 p-5 lg:grid-cols-[128px_minmax(0,1fr)_auto] ${link.active ? '' : 'bg-slate-50 opacity-75'}`}>
                <QrPreview url={link.signup_url} label={link.display_name} />
                <div className="min-w-0">
                  <div className="flex flex-wrap items-center gap-2">
                    <h3 className="text-base font-semibold text-slate-950">{link.display_name}</h3>
                    <span className="rounded-full bg-blue-50 px-2.5 py-1 text-xs font-semibold text-blue-700">{sourceLabel(link.source_type)}</span>
                    <span className="rounded-full bg-slate-100 px-2.5 py-1 text-xs font-semibold text-slate-600">{link.village_name}</span>
                    {!link.active && <span className="rounded-full bg-red-50 px-2.5 py-1 text-xs font-semibold text-red-700">Inactive</span>}
                  </div>
                  <p className="mt-2 text-sm text-slate-600">
                    {link.assigned_user_name ? `Assigned to ${link.assigned_user_name}. ` : ''}
                    {link.notes || 'No notes.'}
                  </p>
                  <div className="mt-3 flex flex-wrap items-center gap-2">
                    <code className="max-w-full truncate rounded-lg bg-slate-100 px-3 py-2 text-xs text-slate-700">{link.signup_url}</code>
                    <span className="rounded-lg bg-emerald-50 px-3 py-2 text-xs font-semibold text-emerald-700">{link.signup_count} signup{link.signup_count === 1 ? '' : 's'}</span>
                  </div>
                </div>
                <div className="flex flex-col gap-2 sm:flex-row lg:flex-col">
                  <button type="button" className="app-btn-secondary inline-flex items-center justify-center gap-2" onClick={() => copyUrl(link.code, link.signup_url)}>
                    {copied === link.code ? <Check className="h-4 w-4" /> : <Copy className="h-4 w-4" />}
                    {copied === link.code ? 'Copied' : 'Copy'}
                  </button>
                  <a href={link.signup_url} target="_blank" rel="noreferrer" className="app-btn-secondary inline-flex items-center justify-center gap-2">
                    <ExternalLink className="h-4 w-4" />
                    Open
                  </a>
                  <button
                    type="button"
                    className="app-btn-secondary inline-flex items-center justify-center gap-2"
                    disabled={toggleMutation.isPending && toggleMutation.variables?.id === link.id}
                    onClick={() => toggleMutation.mutate({ id: link.id, active: !link.active })}
                  >
                    <Share2 className="h-4 w-4" />
                    {toggleMutation.isPending && toggleMutation.variables?.id === link.id ? 'Updating...' : link.active ? 'Deactivate' : 'Activate'}
                  </button>
                </div>
              </div>
            ))}
          </div>
        )}
      </section>
    </WorkspacePage>
  );
}
