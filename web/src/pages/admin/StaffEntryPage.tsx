import { useState, useRef, useCallback, useMemo } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { getVillages, createSupporter, checkDuplicate } from '../../lib/api';
import { useSession } from '../../hooks/useSession';
import { Check, AlertTriangle, Loader2 } from 'lucide-react';
import WorkspacePage from '../../components/WorkspacePage';

interface Village {
  id: number;
  name: string;
}

type RegisteredVoterStatus = 'yes' | 'no' | 'not_sure';

type StaffForm = {
  first_name: string;
  middle_name: string;
  last_name: string;
  contact_number: string;
  email: string;
  dob: string;
  street_address: string;
  village_id: string;
  registered_voter_status: RegisteredVoterStatus;
  registered_voter_location_note: string;
  referred_by_name: string;
  wants_to_volunteer: boolean;
  needs_absentee_ballot_help: boolean;
  needs_homebound_voting_help: boolean;
  needs_voter_registration_help: boolean;
  needs_election_day_ride: boolean;
  opt_in_email: boolean;
  opt_in_text: boolean;
};

type SaveFeedback = {
  name: string;
  verificationStatus: 'unverified' | 'verified' | 'flagged' | string;
};

const SUPPORT_NEED_OPTIONS = [
  { key: 'wants_to_volunteer', label: 'Get involved with the party' },
  { key: 'needs_absentee_ballot_help', label: 'Absentee ballot help' },
  { key: 'needs_homebound_voting_help', label: 'Homebound voting help' },
  { key: 'needs_voter_registration_help', label: 'Register to vote help' },
  { key: 'needs_election_day_ride', label: 'Ride to the polls' },
] as const;

function voterStatusChipClass(active: boolean) {
  return active
    ? 'border-primary bg-primary text-white'
    : 'border-slate-200 bg-white text-slate-600 hover:border-slate-300';
}

const emptyForm = {
  first_name: '',
  middle_name: '',
  last_name: '',
  contact_number: '',
  email: '',
  dob: '',
  street_address: '',
  village_id: '',
  registered_voter_status: 'not_sure' as RegisteredVoterStatus,
  registered_voter_location_note: '',
  referred_by_name: '',
  wants_to_volunteer: false,
  needs_absentee_ballot_help: false,
  needs_homebound_voting_help: false,
  needs_voter_registration_help: false,
  needs_election_day_ride: false,
  opt_in_email: false,
  opt_in_text: false,
};

export default function StaffEntryPage() {
  const queryClient = useQueryClient();
  const [form, setForm] = useState(emptyForm);
  const [successCount, setSuccessCount] = useState(0);
  const [saveFeedback, setSaveFeedback] = useState<SaveFeedback | null>(null);

  const { data: villageData } = useQuery({
    queryKey: ['villages'],
    queryFn: getVillages,
  });
  const { data: sessionData } = useSession();
  const scopedVillageIds = sessionData?.user?.scoped_village_ids ?? null;
  const villages: Village[] = useMemo(() => {
    const all = villageData?.villages || [];
    if (!scopedVillageIds) return all;
    return all.filter((v: Village) => scopedVillageIds.includes(v.id));
  }, [villageData, scopedVillageIds]);
  // Duplicate detection
  const [duplicateWarning, setDuplicateWarning] = useState('');
  const dupeTimerRef = useRef<ReturnType<typeof setTimeout>>(null);

  const checkForDuplicate = useCallback((name: string, villageId: string, firstName?: string, lastName?: string) => {
    if (dupeTimerRef.current) clearTimeout(dupeTimerRef.current);
    if (!name.trim() || !villageId) return;
    dupeTimerRef.current = setTimeout(async () => {
      try {
        const result = await checkDuplicate(name.trim(), Number(villageId), firstName, lastName);
        if (result.duplicates && result.duplicates.length > 0) {
          const villageName = villages.find(v => v.id === Number(villageId))?.name || 'this village';
          setDuplicateWarning(`A supporter with this name already exists in ${villageName}`);
        } else {
          setDuplicateWarning('');
        }
      } catch {
        // silently ignore
      }
    }, 500);
  }, [villages]);

  const submit = useMutation({
    mutationFn: (data: Record<string, unknown>) => createSupporter(data, undefined, 'staff', 'manual'),
    onSuccess: (response) => {
      const savedSupporter = response?.supporter as { first_name?: string; middle_name?: string; last_name?: string; verification_status?: string } | undefined;
      const savedName = [savedSupporter?.first_name, savedSupporter?.middle_name, savedSupporter?.last_name].filter(Boolean).join(' ').trim() || 'Supporter';

      setSuccessCount(prev => prev + 1);
      setSaveFeedback({
        name: savedName,
        verificationStatus: savedSupporter?.verification_status || 'unverified',
      });
      setDuplicateWarning('');
      // Reset form but keep village for bulk entry
      setForm({
        ...emptyForm,
        village_id: form.village_id,
      });
      queryClient.invalidateQueries({ queryKey: ['dashboard'] });
      queryClient.invalidateQueries({ queryKey: ['supporters'] });
      queryClient.invalidateQueries({ queryKey: ['vetting-queue'] });
      queryClient.invalidateQueries({ queryKey: ['duplicates'] });
      queryClient.invalidateQueries({ queryKey: ['public-review'] });
      queryClient.invalidateQueries({ queryKey: ['session'] });
      // Focus name field for next entry
      document.getElementById('first_name')?.focus();
    },
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    submit.mutate({
      ...form,
      registered_voter_location_note: form.registered_voter_status === 'yes' ? form.registered_voter_location_note : '',
      self_reported_registered_voter:
        form.registered_voter_status === 'yes' ? true : form.registered_voter_status === 'no' ? false : null,
      contact_number: form.contact_number.trim() || null,
      village_id: Number(form.village_id),
    });
  };

  const updateField = <K extends keyof StaffForm>(field: K, value: StaffForm[K]) => {
    setForm(prev => {
      const next = { ...prev, [field]: value };
      if (field === 'registered_voter_status' && value !== 'yes') {
        next.registered_voter_location_note = '';
      }
      return next;
    });
    if (saveFeedback) setSaveFeedback(null);
  };

  const successTone = (status: string) => {
    if (status === 'verified') {
      return {
        container: 'bg-green-50 border-green-200 text-green-700',
        badge: 'bg-green-100 text-green-700',
        detail: 'Saved and sent to the Supporter Review Queue. The voter check found a current GEC match.',
      };
    }
    if (status === 'flagged') {
      return {
        container: 'bg-amber-50 border-amber-200 text-amber-700',
        badge: 'bg-amber-100 text-amber-700',
        detail: 'Saved and sent to the Supporter Review Queue. The voter check needs manual follow-up.',
      };
    }
    return {
      container: 'bg-blue-50 border-blue-200 text-blue-700',
      badge: 'bg-blue-100 text-blue-700',
      detail: 'Saved and sent to the Supporter Review Queue. This person is not in the official supporter list until the data team approves them.',
    };
  };

  const voterCheckBadgeLabel = (status: string) => {
    if (status === 'verified') return 'Voter check: Matched to GEC';
    if (status === 'flagged') return 'Voter check: Flagged for review';
    if (status === 'unverified') return 'Voter check: Needs voter review';
    return `Voter check: ${status.replace(/_/g, ' ')}`;
  };

  const inputClass = (field?: string) => {
    void field;
    return 'w-full px-3 py-3 border border-[var(--border-soft)] rounded-lg text-lg focus:ring-2 focus:ring-primary focus:border-transparent';
  };

  return (
    <WorkspacePage width="full" className="space-y-6">
      {/* Header */}
      <div>
        <div className="flex items-center justify-between">
          <h1 className="text-xl font-bold text-gray-900">Staff Entry Form</h1>
          <div className="flex items-center gap-2">
            {successCount > 0 && (
              <span className="bg-green-100 text-green-700 px-3 py-1 rounded-full text-sm font-medium">
                {successCount} entered
              </span>
            )}
          </div>
        </div>
      </div>

      {/* Success Feedback */}
      {saveFeedback && (
        <div className="mt-4">
          <div className={`border px-4 py-3 rounded-lg flex items-start gap-3 ${successTone(saveFeedback.verificationStatus).container}`}>
            <Check className="w-5 h-5 shrink-0 mt-0.5" />
            <div className="min-w-0">
              <div className="font-semibold">
                {saveFeedback.name} saved and sent to Supporter Review.
              </div>
              <div className="text-sm mt-1">
                {successTone(saveFeedback.verificationStatus).detail}
              </div>
            </div>
            <span className={`ml-auto shrink-0 text-xs font-semibold px-2 py-1 rounded-full ${successTone(saveFeedback.verificationStatus).badge}`}>
              {voterCheckBadgeLabel(saveFeedback.verificationStatus)}
            </span>
          </div>
        </div>
      )}

      {/* Duplicate Warning */}
      {duplicateWarning && (
        <div className="mt-4">
          <div className="bg-yellow-500/10 border border-yellow-500/30 text-yellow-700 px-4 py-3 rounded-lg flex items-center gap-2">
            <AlertTriangle className="w-5 h-5 shrink-0" /> {duplicateWarning}
          </div>
        </div>
      )}

      {/* Submit Error */}
      {submit.isError && (
        <div className="mt-4">
          <div className="bg-yellow-500/10 border border-yellow-500/30 text-yellow-700 px-4 py-3 rounded-lg flex items-center gap-2">
            <AlertTriangle className="w-5 h-5" /> Error saving. Check all fields and try again.
          </div>
        </div>
      )}

      {/* Form */}
      <form onSubmit={handleSubmit} className="space-y-4">
        {/* Village (sticky for bulk entry) */}
        <div>
          <label className="block text-sm font-medium text-[var(--text-primary)] mb-1">Village *</label>
          <select
            required
            value={form.village_id}
            onChange={e => updateField('village_id', e.target.value)}
            className={`${inputClass('village_id')} bg-[var(--surface-raised)]`}
          >
            <option value="">Select village</option>
            {villages.map(v => (
              <option key={v.id} value={v.id}>{v.name}</option>
            ))}
          </select>
        </div>

        {/* Name */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
          <div>
            <label className="block text-sm font-medium text-[var(--text-primary)] mb-1">First Name *</label>
            <input
              id="first_name"
              type="text"
              required
              autoFocus
              value={form.first_name}
              onChange={e => updateField('first_name', e.target.value)}
              className={inputClass("first_name")}
              placeholder="First Name"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-[var(--text-primary)] mb-1">Middle Name</label>
            <input
              type="text"
              value={form.middle_name}
              onChange={e => updateField('middle_name', e.target.value)}
              className={inputClass("middle_name")}
              placeholder="Middle Name"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-[var(--text-primary)] mb-1">Last Name *</label>
            <input
              id="last_name"
              type="text"
              required
              value={form.last_name}
              onChange={e => updateField('last_name', e.target.value)}
              onBlur={() => checkForDuplicate(`${form.first_name} ${form.last_name}`, form.village_id, form.first_name, form.last_name)}
              className={inputClass("last_name")}
              placeholder="Last Name"
            />
          </div>
        </div>

        {/* Phone */}
        <div>
          <label className="block text-sm font-medium text-[var(--text-primary)] mb-1">Contact Number (optional)</label>
          <input
            type="tel"
            value={form.contact_number}
            onChange={e => updateField('contact_number', e.target.value)}
            className={inputClass("contact_number")}
            placeholder="+1671XXXXXXX"
          />
        </div>

        {/* DOB */}
        <div>
          <label className="block text-sm font-medium text-[var(--text-primary)] mb-1">Date of Birth</label>
          <input
            type="date"
            value={form.dob}
            onChange={e => updateField('dob', e.target.value)}
            className={inputClass("dob")}
          />
        </div>

        {/* Email */}
        <div>
          <label className="block text-sm font-medium text-[var(--text-primary)] mb-1">Email</label>
          <input
            type="email"
            value={form.email}
            onChange={e => updateField('email', e.target.value)}
            className={inputClass("email")}
            placeholder="email@example.com"
          />
        </div>

        {/* Address */}
        <div>
          <label className="block text-sm font-medium text-[var(--text-primary)] mb-1">Street Address</label>
          <input
            type="text"
            value={form.street_address}
            onChange={e => updateField('street_address', e.target.value)}
            className={inputClass("street_address")}
            placeholder="123 Marine Corps Dr"
          />
        </div>

        <div className="space-y-3 rounded-xl border border-[var(--border-soft)] bg-[var(--surface-raised)] p-4">
          <div>
            <p className="text-sm font-medium text-[var(--text-primary)]">Self-reported voter status</p>
            <p className="mt-1 text-xs text-[var(--text-muted)]">Capture what the supporter says, even if the GEC check later disagrees.</p>
          </div>
          <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
            {[
              { value: 'yes' as const, label: 'Yes, registered' },
              { value: 'no' as const, label: 'No, not registered' },
              { value: 'not_sure' as const, label: 'Not sure' },
            ].map((option) => (
              <button
                key={option.value}
                type="button"
                onClick={() => updateField('registered_voter_status', option.value)}
                className={`min-h-[44px] rounded-xl border px-4 py-3 text-sm font-semibold transition ${voterStatusChipClass(form.registered_voter_status === option.value)}`}
              >
                {option.label}
              </button>
            ))}
          </div>
          {form.registered_voter_status === 'yes' && (
            <div>
              <label className="mb-1 block text-sm font-medium text-[var(--text-primary)]">If registered somewhere else, where?</label>
              <input
                type="text"
                value={form.registered_voter_location_note}
                onChange={e => updateField('registered_voter_location_note', e.target.value)}
                className={inputClass('registered_voter_location_note')}
                placeholder="Optional note"
              />
            </div>
          )}
        </div>

        <div className="space-y-3 rounded-xl border border-[var(--border-soft)] bg-[var(--surface-raised)] p-4">
          <div>
            <p className="text-sm font-medium text-[var(--text-primary)]">Support requests</p>
            <p className="mt-1 text-xs text-[var(--text-muted)]">Track any campaign or voter help this supporter asked for.</p>
          </div>
          <div className="space-y-3">
            {SUPPORT_NEED_OPTIONS.map((option) => (
              <label key={option.key} className="flex items-center gap-3">
                <input
                  type="checkbox"
                  checked={form[option.key]}
                  onChange={e => updateField(option.key, e.target.checked)}
                  className="h-5 w-5 rounded text-primary"
                />
                <span className="text-[var(--text-primary)]">{option.label}</span>
              </label>
            ))}
          </div>
        </div>

        <div>
          <label className="block text-sm font-medium text-[var(--text-primary)] mb-1">Who referred them?</label>
          <input
            type="text"
            value={form.referred_by_name}
            onChange={e => updateField('referred_by_name', e.target.value)}
            className={inputClass('referred_by_name')}
            placeholder="Optional name"
          />
        </div>


        {/* Communication Opt-In */}
        <div className="border-t border-[var(--border-soft)] pt-3 space-y-2">
          <p className="text-sm font-medium text-[var(--text-primary)]">Communication Opt-In</p>
          <label className="flex items-center gap-3">
            <input type="checkbox" checked={form.opt_in_text} onChange={e => updateField('opt_in_text', e.target.checked)} className="w-5 h-5 rounded text-primary" />
            <span className="text-[var(--text-primary)]">Text Updates</span>
          </label>
          <label className="flex items-center gap-3">
            <input type="checkbox" checked={form.opt_in_email} onChange={e => updateField('opt_in_email', e.target.checked)} className="w-5 h-5 rounded text-primary" />
            <span className="text-[var(--text-primary)]">Email Updates</span>
          </label>
          <p className="text-xs text-[var(--text-muted)]">Supporter consents to receive party communications.</p>
        </div>

        {/* Submit */}
        <button
          type="submit"
          disabled={submit.isPending}
          className="w-full bg-cta hover:bg-cta-hover text-white font-bold py-4 rounded-xl text-lg shadow-lg transition-all disabled:opacity-50 flex items-center justify-center gap-2"
        >
          {submit.isPending ? (
            <><Loader2 className="w-5 h-5 animate-spin" /> Saving...</>
          ) : (
            'Save & Next Entry'
          )}
        </button>
      </form>
    </WorkspacePage>
  );
}
