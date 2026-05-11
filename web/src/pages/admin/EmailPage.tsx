import { useState } from 'react';
import { useQuery, useMutation } from '@tanstack/react-query';
import { Mail, Send, Users, Zap, CheckCircle, AlertTriangle, Eye } from 'lucide-react';
import { getEmailStatus, sendEmailBlast, getVillages } from '../../lib/api';
import { useSession } from '../../hooks/useSession';
import WorkspacePage from '../../components/WorkspacePage';

interface EmailBlastResult {
  dry_run?: boolean;
  recipient_count?: number;
  total_targeted?: number;
  queued?: boolean;
  subject?: string;
  preview_subject?: string;
  preview_html?: string;
}

interface Village {
  id: number;
  name: string;
}

export default function EmailPage() {
  const { data: sessionData } = useSession();
  const [subject, setSubject] = useState('');
  const [body, setBody] = useState('');
  const [villageId, setVillageId] = useState('');
  const [registeredVoter, setRegisteredVoter] = useState(false);
  const [previewResult, setPreviewResult] = useState<EmailBlastResult | null>(null);
  const [sentResult, setSentResult] = useState<EmailBlastResult | null>(null);

  const { data: emailStatus, isLoading: statusLoading } = useQuery({
    queryKey: ['emailStatus'],
    queryFn: getEmailStatus,
  });

  const { data: villagesData } = useQuery({
    queryKey: ['villages'],
    queryFn: getVillages,
  });

  const villagesAll: Village[] = villagesData?.villages || [];
  const scopedVillageIds = sessionData?.user?.scoped_village_ids ?? null;
  const villages: Village[] = scopedVillageIds === null
    ? villagesAll
    : villagesAll.filter((v) => scopedVillageIds.includes(v.id));

  const previewMutation = useMutation({
    mutationFn: () =>
      sendEmailBlast({
        subject,
        body,
        village_id: villageId ? Number(villageId) : undefined,
        registered_voter: registeredVoter ? 'true' : undefined,
        dry_run: 'true',
      }),
    onSuccess: (data) => {
      setPreviewResult(data);
      setSentResult(null);
    },
  });

  const sendMutation = useMutation({
    mutationFn: () =>
      sendEmailBlast({
        subject,
        body,
        village_id: villageId ? Number(villageId) : undefined,
        registered_voter: registeredVoter ? 'true' : undefined,
      }),
    onSuccess: (data) => {
      setSentResult(data);
      setPreviewResult(null);
    },
  });

  if (statusLoading) {
    return (
      <div className="flex items-center justify-center py-20">
        <div className="text-[var(--text-muted)] text-sm font-medium">Loading email status...</div>
      </div>
    );
  }

  const isConfigured = emailStatus?.configured;
  const fromEmail = emailStatus?.from_email || '(not set)';

  return (
    <WorkspacePage width="full" className="space-y-6">
      {/* Header */}
      <div>
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-blue-100 flex items-center justify-center">
            <Mail className="w-5 h-5 text-primary" />
          </div>
          <div>
            <h1 className="text-2xl font-bold text-gray-900 tracking-tight">Email Center</h1>
            <p className="text-gray-500 text-sm">Preview and send emails to opted-in supporters</p>
          </div>
        </div>
      </div>

      <div className="space-y-4">
        {/* Status Card */}
        <div className={`app-card p-5 mb-4 ${isConfigured ? 'border-l-4 border-l-green-500' : 'border-l-4 border-l-amber-500'}`}>
          <div className="flex items-center gap-3">
            {isConfigured ? (
              <CheckCircle className="w-6 h-6 text-green-500 flex-shrink-0" />
            ) : (
              <AlertTriangle className="w-6 h-6 text-amber-500 flex-shrink-0" />
            )}
            <div>
              <p className="font-medium text-[var(--text-primary)]">
                {isConfigured ? 'Email is configured' : 'Email not fully configured'}
              </p>
              <p className="text-sm text-[var(--text-secondary)]">
                From: <code className="bg-[var(--surface-overlay)] px-1.5 py-0.5 rounded text-xs">{fromEmail}</code>
              </p>
            </div>
          </div>
        </div>

        {/* Compose Form */}
        <div className="app-card p-5 mb-4">
          <h2 className="text-lg font-bold text-[var(--text-primary)] mb-4 flex items-center gap-2">
            <Send className="w-5 h-5 text-primary" /> Compose Email Blast
          </h2>

          <div className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-[var(--text-primary)] mb-1">Subject</label>
              <input
                type="text"
                value={subject}
                onChange={(e) => setSubject(e.target.value)}
                placeholder="e.g., Join us for the community meeting this Saturday!"
                className="app-input"
                maxLength={200}
              />
              <p className="text-xs text-[var(--text-secondary)] mt-1">
                Tip: Use {'{first_name}'}, {'{last_name}'}, or {'{village}'} to personalize
              </p>
            </div>

            <div>
              <label className="block text-sm font-medium text-[var(--text-primary)] mb-1">Body (HTML supported)</label>
              <textarea
                value={body}
                onChange={(e) => setBody(e.target.value)}
                placeholder="Write your message here..."
                className="app-input min-h-[200px] font-mono text-sm"
                maxLength={10000}
              />
              <p className="text-xs text-[var(--text-secondary)] mt-1">
                Tip: Use {'{first_name}'}, {'{last_name}'}, or {'{village}'} to personalize. Basic HTML allowed.
              </p>
            </div>

            <div className="border-t pt-4">
              <h3 className="text-sm font-medium text-[var(--text-primary)] mb-3 flex items-center gap-2">
                <Users className="w-4 h-4" /> Recipient Filters
              </h3>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm text-[var(--text-secondary)] mb-1">Village (optional)</label>
                  <select
                    value={villageId}
                    onChange={(e) => setVillageId(e.target.value)}
                    className="app-select"
                  >
                    <option value="">{scopedVillageIds === null ? 'All villages' : 'All accessible villages'}</option>
                    {villages.map((v) => (
                      <option key={v.id} value={v.id}>{v.name}</option>
                    ))}
                  </select>
                </div>

                <div className="space-y-2">
                  
                  <label className="flex items-center gap-2 text-sm text-[var(--text-primary)]">
                    <input
                      type="checkbox"
                      checked={registeredVoter}
                      onChange={(e) => setRegisteredVoter(e.target.checked)}
                      className="rounded border-[var(--border-soft)]"
                    />
                    Registered voters only
                  </label>
                  
                </div>
              </div>
              <p className="text-xs text-[var(--text-secondary)] mt-2">
                Only supporters who opted in to email will receive this message.
              </p>
            </div>

            <div className="flex gap-3 pt-2">
              <button
                onClick={() => previewMutation.mutate()}
                disabled={!subject || !body || previewMutation.isPending}
                className="btn-secondary flex-1 flex items-center justify-center gap-2"
              >
                {previewMutation.isPending ? (
                  <>
                    <Zap className="w-4 h-4 animate-spin" /> Calculating...
                  </>
                ) : (
                  <>
                    <Eye className="w-4 h-4" /> Preview Recipients
                  </>
                )}
              </button>
              <button
                onClick={() => {
                  if (confirm(`Send this email blast?\n\nSubject: ${subject}\n\nMake sure you've previewed the recipient count first!`)) {
                    sendMutation.mutate();
                  }
                }}
                disabled={!subject || !body || sendMutation.isPending || !isConfigured || !emailStatus?.live_enabled}
                className="btn-primary flex-1 flex items-center justify-center gap-2"
              >
                {sendMutation.isPending ? (
                  <>
                    <Send className="w-4 h-4 animate-pulse" /> Sending...
                  </>
                ) : (
                  <>
                    <Send className="w-4 h-4" /> {emailStatus?.live_enabled ? 'Send Email Blast' : 'Live Sending Disabled'}
                  </>
                )}
              </button>
            </div>

            {!emailStatus?.live_enabled && (
          <div className="bg-amber-50 border border-amber-200 rounded-2xl p-4 mb-6 flex items-start gap-3">
            <AlertTriangle className="w-5 h-5 text-amber-500 mt-0.5 shrink-0" />
            <div>
              <p className="text-amber-800 font-medium">Live email sending disabled</p>
              <p className="text-amber-700 text-sm">Preview/dry-run is available. Enable DPG_LIVE_OUTREACH_ENABLED only in approved DPG environments with sender credentials configured.</p>
            </div>
          </div>
        )}

        {!isConfigured && (
              <p className="text-sm text-amber-600 text-center">
                Email is not configured. Contact an admin to set up Resend integration.
              </p>
            )}
          </div>
        </div>

        {/* Preview Result */}
        {previewResult && (
          <div className="app-card mb-4 border-l-4 border-l-blue-500">
            <h3 className="font-medium text-[var(--text-primary)] mb-3 flex items-center gap-2">
              <Eye className="w-5 h-5 text-blue-500" /> Preview Results
            </h3>
            <div className="space-y-3">
              <div className="flex items-center gap-4">
                <div className="text-center">
                  <p className="text-3xl font-bold text-primary">{previewResult.recipient_count || 0}</p>
                  <p className="text-xs text-[var(--text-secondary)]">recipients</p>
                </div>
                <div className="flex-1 text-sm text-[var(--text-secondary)]">
                  <p>This email will be sent to supporters who:</p>
                  <ul className="list-disc list-inside mt-1 space-y-0.5">
                    <li>Have an email address on file</li>
                    <li>Opted in to email updates</li>
                    {villageId && <li>Are from the selected village</li>}
                    {registeredVoter && <li>Are registered voters</li>}
                  </ul>
                </div>
              </div>

              {previewResult.preview_subject && (
                <div className="border rounded-lg p-3 bg-[var(--surface-bg)]">
                  <p className="text-xs text-[var(--text-secondary)] mb-1">Preview Subject (personalized)</p>
                  <p className="font-medium text-[var(--text-primary)]">{previewResult.preview_subject}</p>
                </div>
              )}

              {previewResult.preview_html && (
                <div>
                  <p className="text-xs text-[var(--text-secondary)] mb-1">Preview Email Body</p>
                  <div
                    className="border rounded-lg p-4 bg-[var(--surface-raised)] text-sm overflow-auto max-h-[300px]"
                    dangerouslySetInnerHTML={{ __html: previewResult.preview_html }}
                  />
                </div>
              )}
            </div>
          </div>
        )}

        {/* Sent Result */}
        {sentResult && (
          <div className="app-card mb-4 border-l-4 border-l-green-500">
            <div className="flex items-center gap-3">
              <CheckCircle className="w-6 h-6 text-green-500 flex-shrink-0" />
              <div>
                <p className="font-medium text-[var(--text-primary)]">Email blast queued!</p>
                <p className="text-sm text-[var(--text-secondary)]">
                  {sentResult.total_targeted || 0} emails will be sent in the background.
                </p>
              </div>
            </div>
          </div>
        )}

        {/* Tips */}
        <div className="app-card p-5 bg-blue-50 border-blue-200">
          <h3 className="font-medium text-gray-900 mb-2">Tips for Better Email Delivery</h3>
          <ul className="text-sm text-gray-600 space-y-1.5 list-disc list-inside">
            <li>Keep subject lines under 50 characters for mobile</li>
            <li>Personalize with {'{first_name}'} to increase engagement</li>
            <li>Always preview recipient count before sending</li>
            <li>Send during business hours (9am-5pm) for best open rates</li>
            <li>Test with a small group before large blasts</li>
          </ul>
        </div>
      </div>
    </WorkspacePage>
  );
}
