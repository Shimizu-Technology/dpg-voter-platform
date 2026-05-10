import { useState } from 'react';
import { useNavigate, useParams, Link } from 'react-router-dom';
import { useQuery, useMutation } from '@tanstack/react-query';
import { getVillages, createSupporter, getCampaignInfo } from '../lib/api';
import { captureAnalyticsEvent } from '../lib/analytics';
import { formatElectionDate } from '../lib/datetime';
import { DEFAULT_GUAM_PHONE_PREFIX } from '../lib/phone';
import { ArrowLeft, Loader2, Megaphone, Plus, ShieldCheck, Trash2, Users } from 'lucide-react';
import PublicWordmark from '../components/PublicWordmark';
import { publicSiteConfig } from '../lib/publicSite';

interface Village {
  id: number;
  name: string;
}

interface CampaignInfo {
  signup_share_prompt?: string | null;
  primary_election_date?: string | null;
  general_election_date?: string | null;
}

type RegisteredVoterStatus = 'yes' | 'no' | 'not_sure';

type HouseholdMemberForm = {
  first_name: string;
  middle_name: string;
  last_name: string;
  dob: string;
  registered_voter_status: RegisteredVoterStatus;
  registered_voter_location_note: string;
  wants_to_volunteer: boolean;
  needs_absentee_ballot_help: boolean;
  needs_homebound_voting_help: boolean;
  needs_voter_registration_help: boolean;
  needs_election_day_ride: boolean;
};

type SignupForm = {
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
  household_members: HouseholdMemberForm[];
};

const MAX_HOUSEHOLD_MEMBERS = 8;

const EMPTY_HOUSEHOLD_MEMBER: HouseholdMemberForm = {
  first_name: '',
  middle_name: '',
  last_name: '',
  dob: '',
  registered_voter_status: 'not_sure',
  registered_voter_location_note: '',
  wants_to_volunteer: false,
  needs_absentee_ballot_help: false,
  needs_homebound_voting_help: false,
  needs_voter_registration_help: false,
  needs_election_day_ride: false,
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

function supportRequestCount(form: Pick<SignupForm, typeof SUPPORT_NEED_OPTIONS[number]['key']>) {
  return SUPPORT_NEED_OPTIONS.filter((option) => form[option.key]).length;
}

export default function SignupPage() {
  const navigate = useNavigate();
  const { leaderCode } = useParams();

  const [form, setForm] = useState<SignupForm>({
    first_name: '',
    middle_name: '',
    last_name: '',
    contact_number: DEFAULT_GUAM_PHONE_PREFIX,
    email: '',
    dob: '',
    street_address: '',
    village_id: '',
    registered_voter_status: 'not_sure',
    registered_voter_location_note: '',
    referred_by_name: '',
    wants_to_volunteer: false,
    needs_absentee_ballot_help: false,
    needs_homebound_voting_help: false,
    needs_voter_registration_help: false,
    needs_election_day_ride: false,
    opt_in_email: false,
    opt_in_text: false,
    household_members: [],
  });

  const { data: villageData } = useQuery({
    queryKey: ['villages'],
    queryFn: getVillages,
  });
  const villages: Village[] = villageData?.villages || [];

  const { data: campaignInfo } = useQuery<CampaignInfo>({
    queryKey: ['campaignInfo'],
    queryFn: getCampaignInfo,
    staleTime: 300_000,
  });

  const publicSite = publicSiteConfig;
  const primaryElectionDate = formatElectionDate(campaignInfo?.primary_election_date);
  const generalElectionDate = formatElectionDate(campaignInfo?.general_election_date);
  const showPreSubmitReminder = Boolean(
    campaignInfo?.signup_share_prompt || primaryElectionDate || generalElectionDate
  );

  const signup = useMutation({
    mutationFn: (data: Record<string, unknown>) => createSupporter(data, leaderCode),
    onSuccess: () => {
      captureAnalyticsEvent('public_signup_submitted', {
        has_leader_code: Boolean(leaderCode),
        village_id: form.village_id ? Number(form.village_id) : undefined,
        registered_voter_status: form.registered_voter_status,
        help_request_count: supportRequestCount(form),
        opted_in_email: form.opt_in_email,
        opted_in_text: form.opt_in_text,
        household_member_count: form.household_members.length,
      });
      navigate('/thank-you');
    },
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    signup.mutate({
      ...form,
      registered_voter_location_note: form.registered_voter_status === 'yes' ? form.registered_voter_location_note : '',
      self_reported_registered_voter:
        form.registered_voter_status === 'yes' ? true : form.registered_voter_status === 'no' ? false : null,
      village_id: Number(form.village_id),
      household_members: form.household_members.map((member) => ({
        ...member,
        registered_voter_location_note: member.registered_voter_status === 'yes' ? member.registered_voter_location_note : '',
        self_reported_registered_voter:
          member.registered_voter_status === 'yes' ? true : member.registered_voter_status === 'no' ? false : null,
      })),
    });
  };

  const updateField = <K extends keyof SignupForm>(field: K, value: SignupForm[K]) =>
    setForm((prev) => {
      const next = { ...prev, [field]: value };
      if (field === 'registered_voter_status' && value !== 'yes') {
        next.registered_voter_location_note = '';
      }
      return next;
    });

  const updateHouseholdMember = <K extends keyof HouseholdMemberForm>(index: number, field: K, value: HouseholdMemberForm[K]) => {
    setForm((prev) => ({
      ...prev,
      household_members: prev.household_members.map((member, memberIndex) => (
        memberIndex === index
          ? {
              ...member,
              [field]: value,
              ...(field === 'registered_voter_status' && value !== 'yes' ? { registered_voter_location_note: '' } : {}),
            }
          : member
      )),
    }));
  };

  const addHouseholdMember = () => {
    if (form.household_members.length >= MAX_HOUSEHOLD_MEMBERS) return;

    setForm((prev) => ({
      ...prev,
      household_members: [ ...prev.household_members, { ...EMPTY_HOUSEHOLD_MEMBER } ],
    }));
  };

  const removeHouseholdMember = (index: number) => {
    setForm((prev) => ({
      ...prev,
      household_members: prev.household_members.filter((_, memberIndex) => memberIndex !== index),
    }));
  };

  return (
    <div className="min-h-screen overflow-hidden bg-[#f7fbfc]">
      <div className="relative bg-[#123d70] px-4 py-3 text-center text-[10px] font-bold uppercase leading-5 tracking-[0.2em] text-white shadow-sm sm:text-[11px] sm:tracking-[0.28em]">
        <div className="absolute inset-0 bg-[linear-gradient(90deg,rgba(255,255,255,0.08),transparent,rgba(128,199,232,0.22))]" />
        <span className="relative">{publicSite.topBar}</span>
      </div>

      <header className="relative border-b border-[#dce8ef] bg-white/90 backdrop-blur-xl">
        <div className="absolute inset-x-0 bottom-0 h-px bg-linear-to-r from-transparent via-[#83c8e8] to-transparent" />
        <div className="mx-auto flex w-full max-w-6xl items-center justify-between gap-4 px-4 py-4 md:px-6">
          <Link to="/" className="min-w-0">
            <PublicWordmark size="sm" />
          </Link>
          <Link to="/" className="inline-flex min-h-[44px] shrink-0 items-center gap-2 rounded-full border border-[#cfe0e8] bg-white/80 px-4 text-sm font-bold text-slate-600 shadow-sm transition hover:-translate-y-0.5 hover:border-[#83c8e8] hover:bg-[#f2fbff] hover:text-[#123d70] md:px-5">
            <ArrowLeft className="h-4 w-4" />
            <span className="hidden sm:inline">Back to home</span>
            <span className="sr-only sm:hidden">Back to home</span>
          </Link>
        </div>
      </header>

      <section className="relative border-b border-[#dce8ef]">
        <div className="absolute inset-0 -z-10 bg-[radial-gradient(circle_at_10%_10%,rgba(131,200,232,0.32),transparent_28%),radial-gradient(circle_at_88%_4%,rgba(213,163,50,0.18),transparent_30%),linear-gradient(180deg,#f7fbfc_0%,#eef6fb_100%)]" />
        <div className="mx-auto grid w-full max-w-6xl gap-8 overflow-hidden px-4 py-8 md:px-6 md:py-14 lg:grid-cols-[1.02fr_0.98fr] lg:items-center">
          <div className="max-w-[calc(100vw-2rem)] space-y-6 md:max-w-none">
            <div className="inline-flex max-w-full rounded-full border border-[#d8ecf4] bg-white/80 px-4 py-2 text-center text-[11px] font-bold uppercase leading-5 tracking-[0.16em] text-[#123d70] shadow-sm md:text-sm">
              {publicSite.heroEyebrow}
            </div>

            <div className="space-y-4">
              <h1 className="max-w-3xl text-balance text-[2.45rem] leading-[0.96] font-black tracking-[-0.045em] text-[#071326] sm:text-[3rem] md:text-6xl">
                {publicSite.signupHeroTitle}
              </h1>
              <p className="max-w-2xl text-lg leading-8 text-slate-600 md:text-xl md:leading-9">
                {publicSite.signupHeroDescription}
              </p>
            </div>
          </div>

          <div className="relative hidden lg:block">
            <div className="absolute -left-4 top-8 hidden h-24 w-24 rounded-full bg-[#83c8e8]/30 blur-2xl md:block" />
            <div className="absolute -right-3 bottom-5 hidden h-32 w-32 rounded-full bg-[#d5a332]/20 blur-2xl md:block" />
            <div className="relative overflow-hidden rounded-[34px] border border-white bg-white/86 p-5 shadow-[0_28px_80px_-42px_rgba(18,61,112,0.7)] backdrop-blur">
              <div className="rounded-[28px] bg-[linear-gradient(135deg,#123d70_0%,#2468ad_58%,#84c7e8_100%)] p-5 text-white">
                <p className="text-[11px] font-bold uppercase tracking-[0.28em] text-white/75">
                  {publicSite.signupHeroKicker}
                </p>
                <div className="mt-5 rounded-[24px] bg-white/95 p-5 shadow-inner shadow-[#123d70]/10">
                  <p className="mb-4 text-xl font-black leading-tight text-[#123d70]">
                    {publicSite.signupNetworkTitle}
                  </p>
                  <img
                    src={publicSite.wordmark.imageSrc || publicSite.signupNetworkImageSrc}
                    srcSet={publicSite.wordmark.imageSrcSet}
                    sizes="(min-width: 1024px) 430px, 100vw"
                    alt={publicSite.wordmark.imageAlt || publicSite.signupNetworkImageAlt}
                    className="mx-auto h-32 w-full object-contain md:h-40"
                  />
                </div>
              </div>
              <div className="mt-4 rounded-[26px] border border-[#dce8ef] bg-[#f7fbfc] p-5">
                <p className="text-xs font-bold uppercase tracking-[0.24em] text-[#b17812]">
                  {publicSite.featurePanelKicker}
                </p>
                <p className="mt-3 text-base font-semibold leading-8 text-slate-700 md:text-lg">
                  {publicSite.featurePanelText}
                </p>
              </div>
            </div>
          </div>
        </div>
      </section>

      <div className="relative mx-auto max-w-6xl px-4 py-6 md:px-6 md:py-8">
        <div className="absolute inset-0 -z-10 bg-[radial-gradient(circle_at_8%_0%,rgba(131,200,232,0.18),transparent_32%),linear-gradient(180deg,#eef6fb_0%,#f7fbfc_42%,#ffffff_100%)]" />
        {leaderCode && (
          <div className="mb-5 rounded-2xl border border-[#b9dff1] bg-[#eef9fe] px-4 py-3 text-center text-sm font-bold text-[#123d70]">
            You were invited by an organizer.
          </div>
        )}

        <div className="mb-5 rounded-[26px] border border-[#dce8ef] bg-white/90 p-4 shadow-sm lg:hidden">
          <div className="flex items-center gap-4">
            <div className="flex h-16 w-16 shrink-0 items-center justify-center rounded-full bg-[#eef9fe] p-2">
              <img
                src={publicSite.signupNetworkImageSrc}
                srcSet={publicSite.signupNetworkImageSrcSet}
                sizes="64px"
                alt={publicSite.signupNetworkImageAlt}
                className="h-full w-full object-contain"
              />
            </div>
            <div>
              <p className="text-[11px] font-bold uppercase tracking-[0.24em] text-[#123d70]">
                Ready when you are
              </p>
              <p className="mt-2 text-sm leading-6 text-slate-600">
                The form below takes a few minutes and supports household members too.
              </p>
            </div>
          </div>
        </div>

        <div className="grid gap-6 lg:grid-cols-[0.88fr_1.12fr] lg:items-start">
          <aside className="order-2 space-y-4 lg:order-1">
            <div className="rounded-[30px] border border-[#dce8ef] bg-white/92 p-6 shadow-[0_18px_50px_-38px_rgba(18,61,112,0.55)]">
              <p className="text-xs font-bold uppercase tracking-[0.22em] text-[#123d70]">What happens next</p>
              <div className="mt-5 space-y-4">
                <div className="flex gap-3">
                  <div className="mt-0.5 flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-[#e8f7fc] text-[#123d70]">
                    <Users className="h-5 w-5" />
                  </div>
                  <div>
                    <p className="font-semibold text-slate-900">{publicSite.signupSteps.recordTitle}</p>
                    <p className="mt-1 text-sm leading-6 text-slate-600">
                      {publicSite.signupSteps.recordBody}
                    </p>
                  </div>
                </div>

                <div className="flex gap-3">
                  <div className="mt-0.5 flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-[#fff1ef] text-[#ce243c]">
                    <Megaphone className="h-5 w-5" />
                  </div>
                  <div>
                    <p className="font-semibold text-slate-900">{publicSite.signupSteps.helpTitle}</p>
                    <p className="mt-1 text-sm leading-6 text-slate-600">
                      {publicSite.signupSteps.helpBody}
                    </p>
                  </div>
                </div>

                <div className="flex gap-3">
                  <div className="mt-0.5 flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-[#eef9fe] text-[#2468ad]">
                    <ShieldCheck className="h-5 w-5" />
                  </div>
                  <div>
                    <p className="font-semibold text-slate-900">{publicSite.signupSteps.householdTitle}</p>
                    <p className="mt-1 text-sm leading-6 text-slate-600">
                      {publicSite.signupSteps.householdBody}
                    </p>
                  </div>
                </div>
              </div>
            </div>

            <div className="rounded-[30px] border border-[#f0d9a4] bg-[#fffaf0] p-6 shadow-sm">
              <p className="text-xs font-bold uppercase tracking-[0.22em] text-[#93650d]">Party note</p>
              <p className="mt-3 text-sm leading-7 text-slate-700">
                By submitting this form, you are sharing your information with the Democratic Party of Guam so the team can stay in touch, share voter information, and organize supporter outreach.
              </p>
            </div>
          </aside>

          <form onSubmit={handleSubmit} className="order-1 rounded-[34px] border border-[#dce8ef] bg-white p-5 shadow-[0_28px_80px_-44px_rgba(18,61,112,0.65)] md:p-6 lg:order-2">
            <div className="space-y-6">
              <div>
                <h2 className="text-2xl font-bold text-slate-950">Supporter information</h2>
                <p className="mt-2 text-sm leading-6 text-slate-500">
                  Fill out the form below to join the voter engagement effort.
                </p>
              </div>

              <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
                <div>
                  <label className="mb-1 block text-sm font-medium text-gray-700">First Name *</label>
                  <input
                    type="text"
                    required
                    value={form.first_name}
                    onChange={(e) => updateField('first_name', e.target.value)}
                    className="w-full rounded-2xl border border-gray-300 px-3 py-3 text-lg focus:border-transparent focus:ring-2 focus:ring-primary"
                    placeholder="Juan"
                  />
                </div>
                <div>
                  <label className="mb-1 block text-sm font-medium text-gray-700">Middle Name</label>
                  <input
                    type="text"
                    value={form.middle_name}
                    onChange={(e) => updateField('middle_name', e.target.value)}
                    className="w-full rounded-2xl border border-gray-300 px-3 py-3 text-lg focus:border-transparent focus:ring-2 focus:ring-primary"
                    placeholder="Maria"
                  />
                </div>
                <div>
                  <label className="mb-1 block text-sm font-medium text-gray-700">Last Name *</label>
                  <input
                    type="text"
                    required
                    value={form.last_name}
                    onChange={(e) => updateField('last_name', e.target.value)}
                    className="w-full rounded-2xl border border-gray-300 px-3 py-3 text-lg focus:border-transparent focus:ring-2 focus:ring-primary"
                    placeholder="dela Cruz"
                  />
                </div>
              </div>

              <div>
                <label className="mb-1 block text-sm font-medium text-gray-700">Phone Number *</label>
                <input
                  type="tel"
                  required
                  value={form.contact_number}
                  onChange={(e) => updateField('contact_number', e.target.value)}
                  className="w-full rounded-2xl border border-gray-300 px-3 py-3 text-lg focus:border-transparent focus:ring-2 focus:ring-primary"
                  placeholder="+1671XXXXXXX"
                />
                <p className="mt-1 text-xs text-slate-400">
                  This shared household phone will also be used for any added household supporters.
                </p>
              </div>

              <div className="grid gap-3 sm:grid-cols-2">
                <div>
                  <label className="mb-1 block text-sm font-medium text-gray-700">Village *</label>
                  <select
                    required
                    value={form.village_id}
                    onChange={(e) => updateField('village_id', e.target.value)}
                    className="w-full rounded-2xl border border-gray-300 bg-white px-3 py-3 text-lg focus:border-transparent focus:ring-2 focus:ring-primary"
                  >
                    <option value="">Select your village</option>
                    {villages.map((village) => (
                      <option key={village.id} value={village.id}>{village.name}</option>
                    ))}
                  </select>
                </div>
                <div>
                  <label className="mb-1 block text-sm font-medium text-gray-700">Date of Birth</label>
                  <input
                    type="date"
                    value={form.dob}
                    onChange={(e) => updateField('dob', e.target.value)}
                    className="w-full rounded-2xl border border-gray-300 px-3 py-3 text-lg focus:border-transparent focus:ring-2 focus:ring-primary"
                  />
                </div>
              </div>

              <div>
                <label className="mb-1 block text-sm font-medium text-gray-700">Street Address</label>
                <input
                  type="text"
                  value={form.street_address}
                  onChange={(e) => updateField('street_address', e.target.value)}
                  className="w-full rounded-2xl border border-gray-300 px-3 py-3 text-lg focus:border-transparent focus:ring-2 focus:ring-primary"
                  placeholder="123 Marine Corps Dr"
                />
              </div>

              <div>
                <label className="mb-1 block text-sm font-medium text-gray-700">Email</label>
                <input
                  type="email"
                  value={form.email}
                  onChange={(e) => updateField('email', e.target.value)}
                  className="w-full rounded-2xl border border-gray-300 px-3 py-3 text-lg focus:border-transparent focus:ring-2 focus:ring-primary"
                  placeholder="juan@example.com"
                />
                <p className="mt-1 text-xs text-slate-400">
                  This shared household email will also be used for any added household supporters.
                </p>
              </div>

              <section className="rounded-[24px] border border-slate-200 bg-slate-50 px-4 py-4">
                <p className="text-sm font-semibold text-slate-900">Are you currently a registered voter?</p>
                <div className="mt-3 grid gap-2 sm:grid-cols-3">
                  {[
                    { value: 'yes' as const, label: 'Yes' },
                    { value: 'no' as const, label: 'No' },
                    { value: 'not_sure' as const, label: 'Not sure' },
                  ].map((option) => (
                    <button
                      key={option.value}
                      type="button"
                      onClick={() => updateField('registered_voter_status', option.value)}
                      className={`min-h-[48px] rounded-2xl border px-4 py-3 text-sm font-semibold transition ${voterStatusChipClass(form.registered_voter_status === option.value)}`}
                    >
                      {option.label}
                    </button>
                  ))}
                </div>

                {form.registered_voter_status === 'yes' && (
                  <div className="mt-4">
                    <label className="mb-1 block text-sm font-medium text-gray-700">
                      If yes, where do you vote if different from where you live?
                    </label>
                    <input
                      type="text"
                      value={form.registered_voter_location_note}
                      onChange={(e) => updateField('registered_voter_location_note', e.target.value)}
                      className="w-full rounded-2xl border border-gray-300 px-3 py-3 text-base focus:border-transparent focus:ring-2 focus:ring-primary"
                      placeholder="Example: I vote in Dededo"
                    />
                  </div>
                )}
              </section>

              <section className="rounded-[24px] border border-slate-200 bg-white px-4 py-4">
                <p className="text-sm font-semibold text-slate-900">How can the party help?</p>
                <div className="mt-3 space-y-2">
                  {SUPPORT_NEED_OPTIONS.map((option) => (
                    <label key={option.key} className="flex min-h-[44px] cursor-pointer items-center gap-3 rounded-2xl border border-slate-200 px-3 py-2">
                      <input
                        type="checkbox"
                        checked={form[option.key]}
                        onChange={(e) => updateField(option.key, e.target.checked)}
                        className="h-5 w-5 shrink-0 rounded text-primary"
                      />
                      <span className="text-gray-700">{option.label}</span>
                    </label>
                  ))}
                </div>
              </section>

              {!leaderCode && (
                <div>
                  <label className="mb-1 block text-sm font-medium text-gray-700">Who referred you?</label>
                  <input
                    type="text"
                    value={form.referred_by_name}
                    onChange={(e) => updateField('referred_by_name', e.target.value)}
                    className="w-full rounded-2xl border border-gray-300 px-3 py-3 text-lg focus:border-transparent focus:ring-2 focus:ring-primary"
                    placeholder="Optional name"
                  />
                </div>
              )}

              <section className="rounded-[28px] border border-slate-200 bg-[#f8fbff] px-4 py-4">
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <p className="text-sm font-semibold text-slate-900">Household supporters</p>
                    <p className="mt-1 text-sm leading-6 text-slate-500">
                      Add other supporters in this household. They will become separate supporter records with the shared address and contact information above.
                    </p>
                    <p className="mt-1 text-xs font-medium uppercase tracking-[0.14em] text-slate-400">
                      Up to {MAX_HOUSEHOLD_MEMBERS} additional supporters per submission
                    </p>
                  </div>
                  <button
                    type="button"
                    onClick={addHouseholdMember}
                    disabled={form.household_members.length >= MAX_HOUSEHOLD_MEMBERS}
                    className="inline-flex min-h-[44px] items-center gap-2 rounded-full border border-primary/20 bg-white px-4 py-2 text-sm font-semibold text-primary hover:border-primary/40 disabled:cursor-not-allowed disabled:border-slate-200 disabled:text-slate-400"
                  >
                    <Plus className="h-4 w-4" />
                    {form.household_members.length >= MAX_HOUSEHOLD_MEMBERS ? 'Household limit reached' : 'Add another supporter'}
                  </button>
                </div>

                {form.household_members.length > 0 && (
                  <div className="mt-4 space-y-4">
                    {form.household_members.map((member, index) => (
                      <div key={`household-member-${index}`} className="rounded-[24px] border border-slate-200 bg-white p-4">
                        <div className="flex items-center justify-between gap-3">
                          <p className="text-sm font-semibold text-slate-900">Household supporter {index + 1}</p>
                          <button
                            type="button"
                            onClick={() => removeHouseholdMember(index)}
                            className="inline-flex min-h-[40px] items-center gap-1 rounded-full px-3 py-2 text-sm font-medium text-red-600 hover:bg-red-50"
                          >
                            <Trash2 className="h-4 w-4" />
                            Remove
                          </button>
                        </div>

                        <div className="mt-3 grid gap-3 sm:grid-cols-3">
                          <input
                            type="text"
                            required
                            value={member.first_name}
                            onChange={(e) => updateHouseholdMember(index, 'first_name', e.target.value)}
                            className="rounded-2xl border border-gray-300 px-3 py-3 text-base focus:border-transparent focus:ring-2 focus:ring-primary"
                            placeholder="First name"
                          />
                          <input
                            type="text"
                            value={member.middle_name}
                            onChange={(e) => updateHouseholdMember(index, 'middle_name', e.target.value)}
                            className="rounded-2xl border border-gray-300 px-3 py-3 text-base focus:border-transparent focus:ring-2 focus:ring-primary"
                            placeholder="Middle name"
                          />
                          <input
                            type="text"
                            required
                            value={member.last_name}
                            onChange={(e) => updateHouseholdMember(index, 'last_name', e.target.value)}
                            className="rounded-2xl border border-gray-300 px-3 py-3 text-base focus:border-transparent focus:ring-2 focus:ring-primary"
                            placeholder="Last name"
                          />
                        </div>

                        <div className="mt-3 grid gap-3 sm:grid-cols-2">
                          <div>
                            <label className="mb-1 block text-sm font-medium text-gray-700">Date of Birth</label>
                            <input
                              type="date"
                              value={member.dob}
                              onChange={(e) => updateHouseholdMember(index, 'dob', e.target.value)}
                              className="w-full rounded-2xl border border-gray-300 px-3 py-3 text-base focus:border-transparent focus:ring-2 focus:ring-primary"
                            />
                          </div>
                        </div>

                        <div className="mt-4">
                          <p className="text-sm font-medium text-slate-900">Registered voter status</p>
                          <div className="mt-2 grid gap-2 sm:grid-cols-3">
                            {[
                              { value: 'yes' as const, label: 'Yes' },
                              { value: 'no' as const, label: 'No' },
                              { value: 'not_sure' as const, label: 'Not sure' },
                            ].map((option) => (
                              <button
                                key={option.value}
                                type="button"
                                onClick={() => updateHouseholdMember(index, 'registered_voter_status', option.value)}
                                className={`min-h-[44px] rounded-2xl border px-4 py-3 text-sm font-semibold transition ${voterStatusChipClass(member.registered_voter_status === option.value)}`}
                              >
                                {option.label}
                              </button>
                            ))}
                          </div>
                        </div>

                        {member.registered_voter_status === 'yes' && (
                          <div className="mt-3">
                            <label className="mb-1 block text-sm font-medium text-gray-700">
                              If yes, where do they vote if different from where they live?
                            </label>
                            <input
                              type="text"
                              value={member.registered_voter_location_note}
                              onChange={(e) => updateHouseholdMember(index, 'registered_voter_location_note', e.target.value)}
                              className="w-full rounded-2xl border border-gray-300 px-3 py-3 text-base focus:border-transparent focus:ring-2 focus:ring-primary"
                              placeholder="Optional voting-location note"
                            />
                          </div>
                        )}

                        <div className="mt-4">
                          <p className="text-sm font-medium text-slate-900">How can the party help this supporter?</p>
                          <div className="mt-2 space-y-2">
                            {SUPPORT_NEED_OPTIONS.map((option) => (
                              <label key={`${option.key}-${index}`} className="flex min-h-[44px] cursor-pointer items-center gap-3 rounded-2xl border border-slate-200 px-3 py-2">
                                <input
                                  type="checkbox"
                                  checked={member[option.key]}
                                  onChange={(e) => updateHouseholdMember(index, option.key, e.target.checked)}
                                  className="h-5 w-5 shrink-0 rounded text-primary"
                                />
                                <span className="text-gray-700">{option.label}</span>
                              </label>
                            ))}
                          </div>
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </section>


              <div className="rounded-[24px] border border-slate-200 bg-white px-4 py-4">
                <p className="mb-2 text-sm font-medium text-gray-700">Stay updated by the party:</p>
                <label htmlFor="opt_in_text" className="flex min-h-[44px] cursor-pointer items-center gap-3 py-1">
                  <input
                    type="checkbox"
                    id="opt_in_text"
                    checked={form.opt_in_text}
                    onChange={(e) => updateField('opt_in_text', e.target.checked)}
                    className="h-5 w-5 shrink-0 rounded text-primary"
                  />
                  <span className="text-gray-700">Send me text updates</span>
                </label>
                <label htmlFor="opt_in_email" className="flex min-h-[44px] cursor-pointer items-center gap-3 py-1">
                  <input
                    type="checkbox"
                    id="opt_in_email"
                    checked={form.opt_in_email}
                    onChange={(e) => updateField('opt_in_email', e.target.checked)}
                    className="h-5 w-5 shrink-0 rounded text-primary"
                  />
                  <span className="text-gray-700">Send me email updates</span>
                </label>
                <p className="mt-2 text-xs leading-5 text-gray-400">
                  By checking the above, you agree to receive party communications from {publicSite.consentName}. You can opt out at any time.
                </p>
              </div>

              {showPreSubmitReminder && (
                <div className="rounded-[24px] border border-[#d7e5ff] bg-[#f5f9ff] px-4 py-4">
                  <p className="text-xs font-semibold uppercase tracking-[0.18em] text-primary">
                    Before you submit
                  </p>

                  {campaignInfo?.signup_share_prompt && (
                    <p className="mt-2 text-sm leading-6 text-slate-700">
                      {campaignInfo.signup_share_prompt}
                    </p>
                  )}

                  {(primaryElectionDate || generalElectionDate) && (
                    <div className="mt-3 space-y-2 rounded-[18px] bg-white/80 px-4 py-3">
                      <p className="text-xs font-semibold uppercase tracking-[0.16em] text-slate-500">
                        Important election dates
                      </p>
                      {primaryElectionDate && (
                        <p className="text-sm font-medium text-slate-800">
                          Primary Election: <span className="font-semibold">{primaryElectionDate}</span>
                        </p>
                      )}
                      {generalElectionDate && (
                        <p className="text-sm font-medium text-slate-800">
                          General Election: <span className="font-semibold">{generalElectionDate}</span>
                        </p>
                      )}
                    </div>
                  )}
                </div>
              )}

              {signup.isError && (
                <div className="rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-red-700">
                  Something went wrong. Please try again.
                </div>
              )}

              <button
                type="submit"
                disabled={signup.isPending}
                className="flex min-h-[56px] w-full items-center justify-center gap-2 rounded-full bg-cta px-6 text-lg font-bold text-white shadow-lg shadow-red-500/20 transition hover:bg-cta-hover disabled:opacity-50"
              >
                {signup.isPending ? (
                  <>
                    <Loader2 className="h-5 w-5 animate-spin" />
                    Signing up...
                  </>
                ) : (
                  'Sign up now'
                )}
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
  );
}
