import { useState, useMemo } from 'react';
import { useQuery, useMutation } from '@tanstack/react-query';
import { QrCode, Copy, Check, Download } from 'lucide-react';
import { getQrCodeAssignees, generateQrCode, getVillages } from '../../lib/api';
import WorkspacePage from '../../components/WorkspacePage';
import { formatRoleLabel } from '../../lib/roles';

interface QRResult {
  code: string;
  signup_url: string;
  qr_svg_url: string;
  referral_code?: {
    id: number;
    code: string;
    display_name: string;
    village_id: number;
    village_name: string;
    assigned_user_id: number | null;
    assigned_user_name: string | null;
    assigned_user_email: string | null;
  };
}

interface Village {
  id: number;
  name: string;
}

interface AssigneeOption {
  id: number;
  name: string | null;
  email: string;
  role: string;
  assigned_village_id: number | null;
  assigned_district_id: number | null;
}

type AssignmentMode = 'user' | 'adhoc';

export default function QRCodePage() {
  const apiOrigin = import.meta.env.VITE_API_URL?.replace(/\/$/, '');
  const [assignmentMode, setAssignmentMode] = useState<AssignmentMode>('user');
  const [assigneeId, setAssigneeId] = useState('');
  const [displayName, setDisplayName] = useState('');
  const [villageId, setVillageId] = useState('');
  const [generated, setGenerated] = useState<QRResult | null>(null);
  const [copied, setCopied] = useState(false);

  const { data: villageData } = useQuery({ queryKey: ['villages'], queryFn: getVillages });
  const { data: assigneeData } = useQuery({ queryKey: ['qr-assignees'], queryFn: getQrCodeAssignees });
  const villages: Village[] = useMemo(() => villageData?.villages || [], [villageData]);
  const assignees: AssigneeOption[] = useMemo(() => assigneeData?.users || [], [assigneeData]);
  const selectedVillage = useMemo(
    () => villages.find(v => v.id === Number(villageId)),
    [villages, villageId]
  );
  const selectedAssignee = useMemo(
    () => assignees.find((user) => user.id === Number(assigneeId)),
    [assignees, assigneeId]
  );

  const generate = useMutation({
    mutationFn: () => {
      const payload: Record<string, string | number> = {
        village_id: Number(villageId),
      };

      if (assignmentMode === 'user' && assigneeId) {
        payload.assigned_user_id = Number(assigneeId);
      }

      if (displayName.trim()) {
        payload.display_name = displayName.trim();
      }

      return generateQrCode(payload);
    },
    onSuccess: (data) => setGenerated(data),
  });

  const handleGenerate = (e: React.FormEvent) => {
    e.preventDefault();
    generate.mutate();
  };

  const copyLink = () => {
    if (generated) {
      navigator.clipboard.writeText(generated.signup_url);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }
  };

  const generatedOwnerName = generated?.referral_code?.display_name || displayName || selectedAssignee?.name || selectedAssignee?.email || 'Referral owner';
  const canGenerate = villageId && (
    assignmentMode === 'user'
      ? assigneeId
      : displayName.trim().length > 0
  );

  const qrSvgUrl = generated
    ? (generated.qr_svg_url.startsWith('http')
      ? generated.qr_svg_url
      : (apiOrigin ? `${apiOrigin}${generated.qr_svg_url}` : generated.qr_svg_url))
    : null;

  return (
    <WorkspacePage width="full" className="space-y-6">
      {/* Header */}
      <div>
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-purple-100 flex items-center justify-center">
            <QrCode className="w-5 h-5 text-purple-600" />
          </div>
          <div>
            <h1 className="text-2xl font-bold text-gray-900 tracking-tight">QR Code Generator</h1>
            <p className="text-gray-500 text-sm">Generate unique QR codes for block leaders</p>
          </div>
        </div>
      </div>

      <div>
        {/* Generator Form */}
        <form onSubmit={handleGenerate} className="app-card p-6 mb-6">
          <h2 className="font-semibold text-[var(--text-primary)] mb-4">Generate New QR Code</h2>
          <div className="space-y-3">
            <div>
              <label className="block text-sm font-medium text-[var(--text-primary)] mb-2">Assignment Type</label>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
                <button
                  type="button"
                  onClick={() => {
                    setAssignmentMode('user');
                    setDisplayName(selectedAssignee?.name || selectedAssignee?.email || '');
                  }}
                  className={`rounded-xl border px-3 py-2 text-sm text-left transition-colors ${assignmentMode === 'user'
                    ? 'bg-blue-50 border-blue-300 text-blue-900'
                    : 'bg-[var(--surface-raised)] border-[var(--border-soft)] text-[var(--text-primary)] hover:bg-[var(--surface-bg)]'
                  }`}
                >
                  Assign to existing user
                </button>
                <button
                  type="button"
                  onClick={() => {
                    setAssignmentMode('adhoc');
                    setAssigneeId('');
                  }}
                  className={`rounded-xl border px-3 py-2 text-sm text-left transition-colors ${assignmentMode === 'adhoc'
                    ? 'bg-blue-50 border-blue-300 text-blue-900'
                    : 'bg-[var(--surface-raised)] border-[var(--border-soft)] text-[var(--text-primary)] hover:bg-[var(--surface-bg)]'
                  }`}
                >
                  Ad-hoc volunteer code
                </button>
              </div>
            </div>

            {assignmentMode === 'user' ? (
              <div>
                <label className="block text-sm font-medium text-[var(--text-primary)] mb-1">Assigned User</label>
                <select
                  required
                  value={assigneeId}
                  onChange={(e) => {
                    const nextId = e.target.value;
                    setAssigneeId(nextId);
                    const user = assignees.find((candidate) => String(candidate.id) === nextId);
                    setDisplayName(user?.name || user?.email || '');
                  }}
                  className="w-full px-3 py-2 border border-[var(--border-soft)] rounded-xl focus:ring-2 focus:ring-primary focus:border-transparent bg-[var(--surface-raised)]"
                >
                  <option value="">Select a user...</option>
                  {assignees.map((user) => (
                  <option key={user.id} value={user.id}>
                      {(user.name || user.email)} - {formatRoleLabel(user.role)}
                  </option>
                  ))}
                </select>
                <p className="text-xs text-[var(--text-secondary)] mt-1">
                  Choose a valid staff user for durable referral attribution.
                </p>
              </div>
            ) : (
              <div>
                <label className="block text-sm font-medium text-[var(--text-primary)] mb-1">Ad-hoc Label</label>
                <input
                  type="text"
                  required
                  value={displayName}
                  onChange={e => setDisplayName(e.target.value)}
                  placeholder="Volunteer Team A"
                  className="w-full px-3 py-2 border border-[var(--border-soft)] rounded-xl focus:ring-2 focus:ring-primary focus:border-transparent"
                />
                <p className="text-xs text-[var(--text-secondary)] mt-1">
                  Use this only when the referral owner is not an existing user.
                </p>
              </div>
            )}

            {assignmentMode === 'user' && (
              <div>
                <label className="block text-sm font-medium text-[var(--text-primary)] mb-1">Display Name (optional override)</label>
                <input
                  type="text"
                  value={displayName}
                  onChange={e => setDisplayName(e.target.value)}
                  placeholder="Shown in QR and leaderboard"
                  className="w-full px-3 py-2 border border-[var(--border-soft)] rounded-xl focus:ring-2 focus:ring-primary focus:border-transparent"
                />
              </div>
            )}

            <div>
              <label className="block text-sm font-medium text-[var(--text-primary)] mb-1">Village</label>
              <select
                required
                value={villageId}
                onChange={e => setVillageId(e.target.value)}
                className="w-full px-3 py-2 border border-[var(--border-soft)] rounded-xl focus:ring-2 focus:ring-primary focus:border-transparent bg-[var(--surface-raised)]"
              >
                <option value="">Select a village...</option>
                {villages.map((v) => (
                  <option key={v.id} value={v.id}>{v.name}</option>
                ))}
              </select>
            </div>
            <button
              type="submit"
              disabled={generate.isPending || !canGenerate}
              className="w-full bg-primary hover:bg-primary-dark text-white font-bold py-3 rounded-xl disabled:opacity-50"
            >
              {generate.isPending ? 'Generating...' : 'Generate QR Code'}
            </button>
          </div>
        </form>

        {/* Generated QR */}
        {generated && (
          <div className="app-card p-6 text-center">
            <h2 className="font-semibold text-[var(--text-primary)] mb-2">QR Code for {generatedOwnerName}</h2>
            <p className="text-sm text-[var(--text-secondary)] mb-4">Village: {generated.referral_code?.village_name || selectedVillage?.name} · Code: {generated.code}</p>

            {/* QR Image */}
            <div className="flex justify-center mb-6">
              <img
                src={qrSvgUrl!}
                alt={`QR Code for ${generatedOwnerName}`}
                className="w-64 h-64 border rounded-xl p-2"
              />
            </div>

            {/* Signup URL */}
            <div className="bg-[var(--surface-bg)] rounded-xl p-3 mb-4">
              <p className="text-xs text-[var(--text-secondary)] mb-1">Signup Link</p>
              <p className="text-sm text-primary font-mono break-all">{generated.signup_url}</p>
            </div>

            {/* Actions */}
            <div className="flex gap-3">
              <button
                onClick={copyLink}
                className="flex-1 flex items-center justify-center gap-2 border border-[var(--border-soft)] rounded-xl py-2 px-4 hover:bg-[var(--surface-bg)] text-sm font-medium"
              >
                {copied ? <Check className="w-4 h-4 text-green-600" /> : <Copy className="w-4 h-4" />}
                {copied ? 'Copied!' : 'Copy Link'}
              </button>
              <a
                href={qrSvgUrl!}
                download={`qr-${generated.code}.svg`}
                className="flex-1 flex items-center justify-center gap-2 bg-primary text-white rounded-xl py-2 px-4 hover:bg-primary-dark text-sm font-medium"
              >
                <Download className="w-4 h-4" /> Download SVG
              </a>
            </div>

            <p className="text-xs text-[var(--text-muted)] mt-4">
              Print this QR code on flyers or display on your phone. When supporters scan it, their signup is attributed to {generatedOwnerName}.
            </p>
          </div>
        )}
      </div>
    </WorkspacePage>
  );
}
