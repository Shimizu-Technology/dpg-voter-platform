import { useState } from 'react';
import { useQuery, useMutation } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { MessageSquare, Send, Users, Zap, DollarSign, CheckCircle, AlertTriangle, Phone, Settings } from 'lucide-react';
import { getSmsStatus, sendTestSms, sendSmsBlast, getSmsBlasts, getSmsBlastStatus } from '../../lib/api';
import { useSession } from '../../hooks/useSession';
import { DEFAULT_GUAM_PHONE_PREFIX } from '../../lib/phone';
import type { OutreachRecipient } from '../../lib/outreachTypes';
import WorkspacePage from '../../components/WorkspacePage';

type Tab = 'blast' | 'test';

interface SmsBlastResult {
  dry_run?: boolean;
  queued?: boolean;
  blast_id?: number;
  recipient_count?: number;
  total_targeted?: number;
  recipients?: OutreachRecipient[];
  preview_limit?: number;
  sent?: number;
  failed?: number;
  skipped?: number;
}

interface SmsTestResult {
  success: boolean;
  message_id?: string;
  error?: string;
}

interface SmsStatus {
  configured?: boolean;
  live_enabled?: boolean;
  balance?: number;
  sender_id?: string;
}

const SMS_TEMPLATES = [
  {
    label: 'Registration reminder',
    message: "Hafa adai {first_name}, this is the Democratic Party of Guam. Do you need help checking your voter registration or getting registered? Reply YES and our team can follow up."
  },
  {
    label: 'Event reminder',
    message: "Hafa adai {first_name}, DPG has an upcoming community event and we would love to see you there. Reply if you would like details or help getting connected."
  },
  {
    label: 'Volunteer follow-up',
    message: "Hafa adai {first_name}, thank you for connecting with DPG. Are you interested in helping with voter outreach, events, or election-season volunteer work?"
  }
];

export default function SmsPage() {
  const { data: sessionData } = useSession();
  const [activeTab, setActiveTab] = useState<Tab>('blast');

  const { data: smsStatus, isLoading: statusLoading } = useQuery<SmsStatus>({
    queryKey: ['smsStatus'],
    queryFn: getSmsStatus,
  });


  if (statusLoading) {
    return (
      <div className="flex items-center justify-center py-20">
        <div className="text-[var(--text-muted)] text-sm font-medium">Loading SMS status...</div>
      </div>
    );
  }

  return (
    <WorkspacePage width="full" className="space-y-6">
      {/* Header */}
      <div>
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-green-100 flex items-center justify-center">
              <MessageSquare className="w-5 h-5 text-green-600" />
            </div>
            <div>
              <h1 className="text-2xl font-bold text-gray-900 tracking-tight">SMS Center</h1>
              <p className="text-gray-500 text-sm">Send texts to supporters</p>
            </div>
          </div>
          {sessionData?.permissions?.can_manage_configuration && (
            <Link
              to="/admin/sms/settings"
              className="flex items-center gap-1.5 bg-gray-100 hover:bg-gray-200 text-gray-700 px-3 py-2 rounded-lg text-sm font-medium"
            >
              <Settings className="w-4 h-4" /> Settings
            </Link>
          )}
        </div>
      </div>

      <div className="space-y-4">
        {/* Status Banner */}
        <div className="app-card p-4 mb-6">
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 text-center">
            <div>
              <Zap className={`w-5 h-5 mx-auto mb-1 ${smsStatus?.configured ? 'text-green-500' : 'text-red-500'}`} />
              <div className="text-xs text-[var(--text-secondary)]">Status</div>
              <div className={`text-sm font-semibold ${smsStatus?.configured ? 'text-green-600' : 'text-red-600'}`}>
                {smsStatus?.configured ? 'Active' : 'Not Configured'}
              </div>
            </div>
            <div>
              <DollarSign className="w-5 h-5 mx-auto mb-1 text-[var(--text-muted)]" />
              <div className="text-xs text-[var(--text-secondary)]">Balance</div>
              <div className="text-sm font-semibold text-[var(--text-primary)]">
                {smsStatus?.balance != null ? `$${smsStatus.balance.toFixed(2)}` : '—'}
              </div>
            </div>
            <div>
              <Phone className="w-5 h-5 mx-auto mb-1 text-[var(--text-muted)]" />
              <div className="text-xs text-[var(--text-secondary)]">Sender</div>
              <div className="text-sm font-semibold text-[var(--text-primary)]">{smsStatus?.sender_id || '—'}</div>
            </div>
          </div>
        </div>

        {!smsStatus?.configured && (
          <div className="bg-red-50 border border-red-200 rounded-2xl p-4 mb-6 flex items-start gap-3">
            <AlertTriangle className="w-5 h-5 text-red-500 mt-0.5 shrink-0" />
            <div>
              <p className="text-red-800 font-medium">ClickSend not configured</p>
              <p className="text-red-600 text-sm">Add CLICKSEND_USERNAME and CLICKSEND_API_KEY to your environment variables.</p>
            </div>
          </div>
        )}

        {/* Tabs */}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-2 mb-6">
          {([
            { key: 'blast', label: 'Blast', icon: Users },
            { key: 'test', label: 'Test SMS', icon: Send },
          ] as const).map(({ key, label, icon: Icon }) => (
            <button
              key={key}
              onClick={() => setActiveTab(key)}
              className={`flex items-center justify-center gap-2 px-4 py-2 min-h-[44px] rounded-xl text-sm font-medium transition-all ${
                activeTab === key
                  ? 'bg-primary text-white shadow-sm'
                  : 'bg-[var(--surface-raised)] text-[var(--text-secondary)] border hover:bg-[var(--surface-bg)]'
              }`}
            >
              <Icon className="w-4 h-4" />
              {label}
            </button>
          ))}
        </div>

        {!smsStatus?.live_enabled && (
          <div className="rounded-2xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-800">
            Live SMS sending is off for this environment. Preview/dry-run is available; enable DPG_LIVE_OUTREACH_ENABLED only in approved DPG environments with sender credentials configured.
          </div>
        )}

        {activeTab === 'blast' && <BlastTab liveEnabled={Boolean(smsStatus?.live_enabled)} />}
        {activeTab === 'test' && <TestTab liveEnabled={Boolean(smsStatus?.live_enabled)} />}
      </div>
    </WorkspacePage>
  );
}

function BlastTab({ liveEnabled }: { liveEnabled: boolean }) {
  const [message, setMessage] = useState('');
  const [filters, setFilters] = useState({ registered: false });
  const [result, setResult] = useState<SmsBlastResult | null>(null);
  const [recipientReviewAccepted, setRecipientReviewAccepted] = useState(false);
  const [activeBlastId, setActiveBlastId] = useState<number | null>(null);

  const resetReview = () => {
    setResult(null);
    setRecipientReviewAccepted(false);
  };

  // Poll active blast progress
  const { data: blastProgress } = useQuery({
    queryKey: ['smsBlastProgress', activeBlastId],
    queryFn: () => getSmsBlastStatus(activeBlastId!),
    enabled: activeBlastId !== null,
    refetchInterval: (query) => {
      const data = query.state.data;
      return data?.finished ? false : 2000;
    },
    refetchOnWindowFocus: false,
    refetchIntervalInBackground: false,
  });

  // Recent blast history
  const { data: blastsData } = useQuery({
    queryKey: ['smsBlasts'],
    queryFn: getSmsBlasts,
    refetchInterval: activeBlastId && !blastProgress?.finished ? 5000 : false,
  });

  const dryRunMutation = useMutation({
    mutationFn: () => sendSmsBlast({
      message,
      registered_voter: filters.registered ? 'true' : undefined,
      dry_run: 'true',
    }),
    onSuccess: (data) => {
      setResult(data);
      setRecipientReviewAccepted(false);
    },
  });

  const sendMutation = useMutation({
    mutationFn: () => sendSmsBlast({
      message,
      registered_voter: filters.registered ? 'true' : undefined,
      recipient_reviewed: recipientReviewAccepted,
      expected_recipient_count: result?.recipient_count || 0,
    }),
    onSuccess: (data) => {
      setResult(data);
      if (data.blast_id) setActiveBlastId(data.blast_id);
    },
  });

  const charCount = message.length;
  const smsSegments = Math.ceil(charCount / 160) || 1;
  const recentBlasts = blastsData?.blasts || [];
  const canSend = Boolean(liveEnabled && message.trim() && result?.dry_run && recipientReviewAccepted);

  return (
    <div className="space-y-4">
      <div className="app-card p-4">
        <h3 className="font-semibold text-[var(--text-primary)] mb-3">Compose Blast Message</h3>

        <textarea
          value={message}
          onChange={(e) => {
            setMessage(e.target.value);
            resetReview();
          }}
          placeholder="Type your message to supporters..."
          className="w-full border border-[var(--border-soft)] rounded-xl p-3 h-32 text-sm resize-none focus:ring-2 focus:ring-primary focus:border-transparent"
          maxLength={480}
        />
        <div className="flex justify-between text-xs text-[var(--text-muted)] mt-1">
          <span>{charCount}/480 characters</span>
          <span>{smsSegments} SMS segment{smsSegments > 1 ? 's' : ''}</span>
        </div>
        <div className="mt-3 flex flex-wrap gap-2">
          {SMS_TEMPLATES.map((template) => (
            <button
              key={template.label}
              type="button"
              onClick={() => {
                setMessage(template.message);
                resetReview();
              }}
              className="rounded-lg border border-[var(--border-soft)] px-3 py-2 text-xs font-semibold text-[var(--text-secondary)] hover:border-primary hover:text-primary"
            >
              {template.label}
            </button>
          ))}
        </div>
      </div>

      <div className="app-card p-4">
        <h3 className="font-semibold text-[var(--text-primary)] mb-3">Filters</h3>
        <div className="space-y-2">
          <label className="flex items-center gap-2 text-sm min-h-[44px]">
            <input
              type="checkbox"
              checked={filters.registered}
              onChange={(e) => {
                setFilters(f => ({ ...f, registered: e.target.checked }));
                resetReview();
              }}
              className="rounded border-[var(--border-soft)] text-primary focus:ring-primary"
            />
            Registered voters only
          </label>

        </div>
      </div>

      <div className="flex gap-3">
        <button
          onClick={() => dryRunMutation.mutate()}
          disabled={!message.trim() || dryRunMutation.isPending || (activeBlastId !== null && !blastProgress?.finished)}
          className="flex-1 bg-[var(--surface-raised)] border border-primary text-primary py-3 rounded-xl font-semibold text-sm hover:bg-blue-50 disabled:opacity-50 transition-all"
        >
          {dryRunMutation.isPending ? 'Counting...' : 'Preview (Dry Run)'}
        </button>
        <button
          onClick={() => {
            if (window.confirm(`Send this message to ${result?.recipient_count || 'all matching'} supporters?`)) {
              sendMutation.mutate();
            }
          }}
          disabled={!canSend || sendMutation.isPending || (activeBlastId !== null && !blastProgress?.finished)}
          className="flex-1 bg-cta text-white py-3 rounded-xl font-semibold text-sm hover:bg-red-700 disabled:opacity-50 transition-all flex items-center justify-center gap-2"
        >
          <Send className="w-4 h-4" />
          {sendMutation.isPending ? 'Sending...' : liveEnabled ? 'Send Blast' : 'Live Sending Disabled'}
        </button>
      </div>

      {/* Dry run result */}
      {result?.dry_run && (
        <div className="rounded-xl border p-4 bg-blue-50 border-blue-200 space-y-3">
          <div className="flex items-start gap-2">
            <Users className="w-5 h-5 text-blue-600 mt-0.5" />
            <div>
              <p className="text-blue-800 font-medium">
                Would send to <strong>{result.recipient_count}</strong> opted-in contacts
              </p>
              <p className="text-xs text-blue-700">
                Showing the first {Math.min(result.recipients?.length || 0, result.preview_limit || 0)} recipients for review before live sending.
              </p>
            </div>
          </div>
          {Boolean(result.recipients?.length) && (
            <div className="max-h-56 overflow-auto rounded-lg border border-blue-100 bg-white">
              {result.recipients!.map((recipient) => (
                <div key={recipient.id} className="flex items-center justify-between gap-3 border-b border-blue-50 px-3 py-2 text-sm last:border-b-0">
                  <div className="min-w-0">
                    <p className="truncate font-semibold text-slate-800">{recipient.name}</p>
                    <p className="truncate text-xs text-slate-500">{recipient.village_name || 'Unknown village'} · {recipient.contact_classification?.replaceAll('_', ' ') || 'contact'}</p>
                  </div>
                  <span className="shrink-0 text-xs font-medium text-slate-600">{recipient.contact_number || 'No phone'}</span>
                </div>
              ))}
            </div>
          )}
          <label className="flex min-h-[44px] items-center gap-2 text-sm font-medium text-blue-900">
            <input
              type="checkbox"
              checked={recipientReviewAccepted}
              onChange={(e) => setRecipientReviewAccepted(e.target.checked)}
              className="rounded border-blue-300 text-primary focus:ring-primary"
            />
            I reviewed this recipient count and sample list.
          </label>
        </div>
      )}

      {/* Active blast progress */}
      {blastProgress && !blastProgress.finished && (
        <div className="app-card p-4">
          <div className="flex items-center justify-between mb-2">
            <h3 className="font-semibold text-[var(--text-primary)] text-sm">Sending in progress...</h3>
            <span className="text-sm text-[var(--text-secondary)]">{blastProgress.progress_pct}%</span>
          </div>
          <div className="w-full bg-[var(--surface-overlay)] rounded-full h-3 mb-2">
            <div
              className="bg-primary h-3 rounded-full transition-all duration-500"
              style={{ width: `${blastProgress.progress_pct}%` }}
            />
          </div>
          <div className="flex justify-between text-xs text-[var(--text-secondary)]">
            <span>{blastProgress.sent_count} sent · {blastProgress.failed_count} failed</span>
            <span>{blastProgress.total_recipients} total</span>
          </div>
        </div>
      )}

      {/* Blast completed */}
      {blastProgress?.finished && (
        <div className={`rounded-xl border p-4 ${blastProgress.status === 'completed' ? 'bg-green-50 border-green-200' : 'bg-red-50 border-red-200'}`}>
          <div className="flex items-center gap-2 mb-1">
            {blastProgress.status === 'completed' ? (
              <CheckCircle className="w-5 h-5 text-green-600" />
            ) : (
              <AlertTriangle className="w-5 h-5 text-red-600" />
            )}
            <span className={blastProgress.status === 'completed' ? 'text-green-800 font-medium' : 'text-red-800 font-medium'}>
              {blastProgress.status === 'completed' ? 'Blast complete!' : 'Blast failed'}
            </span>
          </div>
          <div className="text-sm text-[var(--text-primary)]">
            Sent: {blastProgress.sent_count} · Failed: {blastProgress.failed_count} · Total: {blastProgress.total_recipients}
          </div>
          {blastProgress.error_log?.length > 0 && (
            <details className="mt-2">
              <summary className="text-xs text-[var(--text-secondary)] cursor-pointer">View errors ({blastProgress.error_log.length})</summary>
              <div className="mt-1 text-xs text-red-600 space-y-0.5">
                {blastProgress.error_log.map((err: string, i: number) => <p key={i}>{err}</p>)}
              </div>
            </details>
          )}
        </div>
      )}

      {/* Recent blast history */}
      {recentBlasts.length > 0 && (
        <div className="app-card p-4">
          <h3 className="font-semibold text-[var(--text-primary)] mb-3 text-sm">Recent Blasts</h3>
          <div className="space-y-2">
            {recentBlasts.slice(0, 5).map((blast: { id: number; status: string; message: string; sent_count: number; failed_count: number; total_recipients: number; started_at: string; initiated_by: string }) => (
              <div key={blast.id} className="flex items-center justify-between text-sm border-b border-[var(--border-subtle)] pb-2">
                <div className="min-w-0 flex-1">
                  <p className="text-[var(--text-primary)] truncate">{blast.message}</p>
                  <p className="text-xs text-[var(--text-muted)]">
                    {blast.initiated_by} · {blast.started_at ? new Date(blast.started_at).toLocaleString() : 'pending'}
                  </p>
                </div>
                <div className="text-right ml-3 flex-shrink-0">
                  <span className={`text-xs px-2 py-0.5 rounded-full ${
                    blast.status === 'completed' ? 'bg-green-100 text-green-600' :
                    blast.status === 'sending' ? 'bg-blue-100 text-blue-700' :
                    blast.status === 'failed' ? 'bg-red-100 text-red-600' :
                    'bg-[var(--surface-overlay)] text-[var(--text-secondary)]'
                  }`}>
                    {blast.status}
                  </span>
                  <p className="text-xs text-[var(--text-secondary)] mt-0.5">{blast.sent_count}/{blast.total_recipients}</p>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

function TestTab({ liveEnabled }: { liveEnabled: boolean }) {
  const [phone, setPhone] = useState(DEFAULT_GUAM_PHONE_PREFIX);
  const [message, setMessage] = useState('Test message from DPG Voter Platform.');
  const [result, setResult] = useState<SmsTestResult | null>(null);

  const mutation = useMutation({
    mutationFn: () => sendTestSms(phone, message),
    onSuccess: (data) => setResult(data),
  });

  return (
    <div className="space-y-4">
      <div className="app-card p-4">
        <h3 className="font-semibold text-[var(--text-primary)] mb-3">Send Test SMS</h3>
        <div className="space-y-3">
          <div>
            <label className="block text-sm font-medium text-[var(--text-primary)] mb-1">Phone Number</label>
            <input
              type="tel"
              value={phone}
              onChange={(e) => setPhone(e.target.value)}
              placeholder="+1671XXXXXXX"
              className="w-full border border-[var(--border-soft)] rounded-xl p-2.5 text-sm focus:ring-2 focus:ring-primary"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-[var(--text-primary)] mb-1">Message</label>
            <textarea
              value={message}
              onChange={(e) => setMessage(e.target.value)}
              className="w-full border border-[var(--border-soft)] rounded-xl p-3 h-24 text-sm resize-none focus:ring-2 focus:ring-primary"
            />
          </div>
        </div>
      </div>

      <button
        onClick={() => mutation.mutate()}
        disabled={!liveEnabled || !phone.trim() || !message.trim() || mutation.isPending}
        className="w-full bg-primary text-white py-3 rounded-xl font-semibold text-sm hover:bg-blue-900 disabled:opacity-50 transition-all flex items-center justify-center gap-2"
      >
        <Send className="w-4 h-4" />
        {mutation.isPending ? 'Sending...' : liveEnabled ? 'Send Test' : 'Live Sending Disabled'}
      </button>

      {result && (
        <div className={`rounded-xl border p-4 ${result.success ? 'bg-green-50 border-green-200' : 'bg-red-50 border-red-200'}`}>
          <div className="flex items-center gap-2">
            {result.success ? (
              <CheckCircle className="w-5 h-5 text-green-600" />
            ) : (
              <AlertTriangle className="w-5 h-5 text-red-600" />
            )}
            <span className={result.success ? 'text-green-800' : 'text-red-800'}>
              {result.success ? `Sent! Message ID: ${result.message_id}` : `Failed: ${result.error}`}
            </span>
          </div>
        </div>
      )}
    </div>
  );
}
