import { useState } from 'react';
import { useQuery, useMutation } from '@tanstack/react-query';
import { useParams, Link } from 'react-router-dom';
import { getEvent, getEventAttendees, sendEventSms, sendEventEmail } from '../../lib/api';
import { CheckCircle, XCircle, ClipboardCheck, MessageSquare, Mail, Send, AlertTriangle } from 'lucide-react';
import WorkspacePage from '../../components/WorkspacePage';

interface Attendee {
  rsvp_id: number;
  print_name: string;
  village: string;
  attended: boolean;
}

type MessageTab = 'sms' | 'email';

interface MessageResult {
  sent: number;
  failed: number;
  errors?: string[];
  total: number;
  dry_run?: boolean;
  recipient_count?: number;
}

export default function EventDetailPage() {
  const { id } = useParams();
  const eventId = Number(id);
  const { data: eventData } = useQuery({ queryKey: ['event', id], queryFn: () => getEvent(eventId) });
  const { data: attendeeData } = useQuery({ queryKey: ['attendees', id], queryFn: () => getEventAttendees(eventId) });

  // Messaging state
  const [messageTab, setMessageTab] = useState<MessageTab>('sms');
  const [smsMessage, setSmsMessage] = useState('');
  const [emailSubject, setEmailSubject] = useState('');
  const [emailBody, setEmailBody] = useState('');
  const [showConfirm, setShowConfirm] = useState(false);
  const [messageResult, setMessageResult] = useState<MessageResult | null>(null);

  // Dry run queries for counts
  const { data: smsDryRun } = useQuery({
    queryKey: ['eventSmsDryRun', id],
    queryFn: () => sendEventSms(eventId, { message: 'test', dry_run: 'true' }),
    enabled: !!id,
  });

  const { data: emailDryRun } = useQuery({
    queryKey: ['eventEmailDryRun', id],
    queryFn: () => sendEventEmail(eventId, { subject: 'test', body: 'test', dry_run: 'true' }),
    enabled: !!id,
  });

  const smsMutation = useMutation({
    mutationFn: (message: string) => sendEventSms(eventId, { message }),
    onSuccess: (data: MessageResult) => {
      setMessageResult(data);
      setSmsMessage('');
    },
  });

  const emailMutation = useMutation({
    mutationFn: (params: { subject: string; body: string }) => sendEventEmail(eventId, params),
    onSuccess: (data: MessageResult) => {
      setMessageResult(data);
      setEmailSubject('');
      setEmailBody('');
    },
  });

  const handleSend = () => {
    setShowConfirm(false);
    setMessageResult(null);
    if (messageTab === 'sms') {
      smsMutation.mutate(smsMessage);
    } else {
      emailMutation.mutate({ subject: emailSubject, body: emailBody });
    }
  };

  const isSending = smsMutation.isPending || emailMutation.isPending;
  const sendError = smsMutation.error || emailMutation.error;

  const event = eventData?.event;
  const stats = attendeeData?.stats;
  const attendees: Attendee[] = attendeeData?.attendees || [];

  if (!event) return <div className="min-h-screen flex items-center justify-center text-[var(--text-muted)]">Loading...</div>;

  return (
    <WorkspacePage width="full" className="space-y-6">
      {/* Header */}
      <div>
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-bold text-gray-900 tracking-tight">{event.name}</h1>
            <p className="text-gray-500 text-sm">{event.date} · {event.location} · {event.village_name || 'All accessible villages'}</p>
          </div>
          <Link to={`/admin/events/${id}/checkin`}
            className="app-btn-danger">
            <ClipboardCheck className="w-4 h-4" /> Check In
          </Link>
        </div>
      </div>

      <div>
        {/* Stats */}
        {stats && (
          <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-4 gap-4 mb-8">
            <div className="app-card p-4 text-center">
              <div className="text-2xl font-bold text-[var(--text-primary)]">{stats.total_invited}</div>
              <div className="text-sm text-[var(--text-secondary)]">Invited</div>
            </div>
            <div className="app-card p-4 text-center">
              <div className="text-2xl font-bold text-[var(--text-primary)]">{stats.confirmed}</div>
              <div className="text-sm text-[var(--text-secondary)]">Confirmed</div>
            </div>
            <div className="app-card p-4 text-center">
              <div className="text-2xl font-bold text-green-600">{stats.attended}</div>
              <div className="text-sm text-[var(--text-secondary)]">Attended</div>
            </div>
            <div className="app-card p-4 text-center">
              <div className={`text-2xl font-bold ${stats.show_up_rate >= 70 ? 'text-green-600' : stats.show_up_rate >= 50 ? 'text-yellow-600' : 'text-red-600'}`}>
                {stats.show_up_rate}%
              </div>
              <div className="text-sm text-[var(--text-secondary)]">Show-up Rate</div>
            </div>
          </div>
        )}

        {/* Quota progress */}
        {event.quota && stats && (
          <div className="app-card p-4 mb-6">
            <div className="flex justify-between mb-2">
              <span className="font-semibold">Quota: {event.quota}</span>
              <span className={event.quota_met ? 'text-green-600 font-medium' : 'text-red-600 font-medium'}>
                {event.quota_met ? 'Met!' : `Need ${event.quota - stats.attended} more`}
              </span>
            </div>
            <div className="w-full bg-[var(--surface-overlay)] rounded-full h-3">
              <div
                className={`h-3 rounded-full ${event.quota_met ? 'bg-green-500' : 'bg-yellow-500'}`}
                style={{ width: `${Math.min((stats.attended / event.quota) * 100, 100)}%` }}
              />
            </div>
          </div>
        )}

        {/* Message RSVPs */}
        <div className="app-card p-4 mb-6">
          <h2 className="app-section-title text-lg mb-4">Message RSVPs</h2>

          {/* Tabs */}
          <div className="flex gap-2 mb-4">
            <button
              onClick={() => { setMessageTab('sms'); setMessageResult(null); }}
              className={`flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium transition ${messageTab === 'sms' ? 'bg-[var(--brand-primary)] text-white' : 'bg-[var(--surface-overlay)] text-[var(--text-secondary)]'}`}
            >
              <MessageSquare className="w-4 h-4" /> SMS
            </button>
            <button
              onClick={() => { setMessageTab('email'); setMessageResult(null); }}
              className={`flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium transition ${messageTab === 'email' ? 'bg-[var(--brand-primary)] text-white' : 'bg-[var(--surface-overlay)] text-[var(--text-secondary)]'}`}
            >
              <Mail className="w-4 h-4" /> Email
            </button>
          </div>

          {messageTab === 'sms' ? (
            <div className="space-y-3">
              <p className="text-sm text-[var(--text-secondary)]">
                Will send to {smsDryRun?.recipient_count ?? '...'} RSVPs with phone numbers
              </p>
              <textarea
                value={smsMessage}
                onChange={(e) => setSmsMessage(e.target.value)}
                placeholder="Type your SMS message..."
                rows={3}
                className="app-input w-full"
              />
              <button
                onClick={() => setShowConfirm(true)}
                disabled={isSending || !smsMessage.trim()}
                className="app-btn-danger flex items-center gap-2"
              >
                <Send className="w-4 h-4" /> {isSending ? 'Sending...' : 'Send SMS'}
              </button>
            </div>
          ) : (
            <div className="space-y-3">
              <p className="text-sm text-[var(--text-secondary)]">
                Will send to {emailDryRun?.recipient_count ?? '...'} RSVPs with email addresses
              </p>
              <input
                type="text"
                value={emailSubject}
                onChange={(e) => setEmailSubject(e.target.value)}
                placeholder="Subject"
                className="app-input w-full"
              />
              <textarea
                value={emailBody}
                onChange={(e) => setEmailBody(e.target.value)}
                placeholder="Email body (HTML supported)..."
                rows={5}
                className="app-input w-full"
              />
              <button
                onClick={() => setShowConfirm(true)}
                disabled={isSending || !emailSubject.trim() || !emailBody.trim()}
                className="app-btn-danger flex items-center gap-2"
              >
                <Send className="w-4 h-4" /> {isSending ? 'Sending...' : 'Send Email'}
              </button>
            </div>
          )}

          {/* Confirmation Dialog */}
          {showConfirm && (
            <div className="mt-4 p-4 bg-yellow-50 border border-yellow-200 rounded-lg">
              <div className="flex items-start gap-2">
                <AlertTriangle className="w-5 h-5 text-yellow-600 flex-shrink-0 mt-0.5" />
                <div>
                  <p className="font-medium text-yellow-800">
                    {messageTab === 'sms'
                      ? `Send SMS to ${smsDryRun?.recipient_count ?? 0} recipients?`
                      : `Send email to ${emailDryRun?.recipient_count ?? 0} recipients?`}
                  </p>
                  <div className="flex gap-2 mt-3">
                    <button onClick={handleSend} className="app-btn-danger text-sm">Confirm Send</button>
                    <button onClick={() => setShowConfirm(false)} className="app-btn text-sm">Cancel</button>
                  </div>
                </div>
              </div>
            </div>
          )}

          {/* Result Toast */}
          {messageResult && (
            <div className="mt-4 p-4 bg-green-50 border border-green-200 rounded-lg">
              <div className="flex items-center gap-2">
                <CheckCircle className="w-5 h-5 text-green-600" />
                <span className="text-green-800 font-medium">
                  Sent: {messageResult.sent} | Failed: {messageResult.failed}
                </span>
              </div>
              {messageResult.errors && messageResult.errors.length > 0 && (
                <ul className="mt-2 text-sm text-red-600">
                  {messageResult.errors.map((e, i) => <li key={i}>{e}</li>)}
                </ul>
              )}
            </div>
          )}

          {/* Error Toast */}
          {sendError && (
            <div className="mt-4 p-4 bg-red-50 border border-red-200 rounded-lg">
              <div className="flex items-center gap-2">
                <AlertTriangle className="w-5 h-5 text-red-600" />
                <span className="text-red-800 font-medium">
                  {sendError instanceof Error ? sendError.message : 'Failed to send messages'}
                </span>
              </div>
            </div>
          )}
        </div>

        {/* Attendee List */}
        <h2 className="app-section-title text-xl mb-4">Attendees ({attendees.length})</h2>
        <div className="app-card overflow-hidden">
          {attendees.map((a) => (
            <div key={a.rsvp_id} className="flex items-center justify-between px-4 py-3 border-b last:border-0">
              <div>
                <span className="font-medium text-[var(--text-primary)]">{a.print_name}</span>
                <span className="text-sm text-[var(--text-secondary)] ml-2">{a.village}</span>
              </div>
              <div className="flex items-center gap-2">
                {a.attended ? (
                  <span className="flex items-center gap-1 text-green-600 text-sm">
                    <CheckCircle className="w-4 h-4" /> Checked in
                  </span>
                ) : (
                  <span className="flex items-center gap-1 text-[var(--text-muted)] text-sm">
                    <XCircle className="w-4 h-4" /> Not yet
                  </span>
                )}
              </div>
            </div>
          ))}
          {attendees.length === 0 && (
            <div className="px-4 py-8 text-center text-[var(--text-muted)]">No attendees yet</div>
          )}
        </div>
      </div>
    </WorkspacePage>
  );
}
