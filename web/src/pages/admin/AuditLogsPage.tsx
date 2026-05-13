import { useMemo, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { getAuditLogs } from '../../lib/api';
import WorkspacePage from '../../components/WorkspacePage';

interface AuditLogEntry {
  id: number;
  action: string;
  action_label: string;
  auditable_type: string;
  auditable_id: number;
  auditable_label: string;
  actor_user_id: number | null;
  actor_name: string | null;
  actor_email: string | null;
  actor_role: string | null;
  changed_data: Record<string, unknown>;
  metadata: Record<string, unknown>;
  created_at: string;
}

interface AuditLogsResponse {
  audit_logs: AuditLogEntry[];
  filters?: {
    actions: string[];
    auditable_types: string[];
  };
  pagination: {
    page: number;
    per_page: number;
    total: number;
    pages: number;
  };
}

const ACTION_LABEL_OVERRIDES: Record<string, string> = {
  bulk_import: 'Bulk import',
  settings_updated: 'Settings updated',
  verification_changed: 'Verification changed',
  duplicate_resolved: 'Duplicate resolved',
};

function changedFieldCount(changedData: Record<string, unknown>) {
  return Object.keys(changedData || {}).length;
}

function changedFieldList(changedData: Record<string, unknown>) {
  const fields = Object.keys(changedData || {});
  if (fields.length === 0) return 'No field details';
  if (fields.length <= 3) return fields.join(', ');
  return `${fields.slice(0, 3).join(', ')} +${fields.length - 3} more`;
}

function prettyDate(value: string) {
  if (!value) return 'Unknown time';
  return new Date(value).toLocaleString('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });
}

function formatFieldName(field: string) {
  return field.replaceAll('_', ' ');
}

function formatActionLabel(action: string) {
  const normalized = action.toLowerCase();
  if (ACTION_LABEL_OVERRIDES[normalized]) return ACTION_LABEL_OVERRIDES[normalized];

  return normalized
    .replaceAll('_', ' ')
    .replace(/\b\w/g, (match) => match.toUpperCase());
}

function toDisplayValue(value: unknown) {
  if (value == null || value === '') return 'empty';
  if (typeof value === 'boolean') return value ? 'Yes' : 'No';
  if (typeof value === 'number') return String(value);
  if (typeof value === 'string') return value;
  return JSON.stringify(value);
}

function parseChangeValue(raw: unknown): { from: unknown; to: unknown } {
  if (raw && typeof raw === 'object' && 'from' in (raw as Record<string, unknown>) && 'to' in (raw as Record<string, unknown>)) {
    const value = raw as Record<string, unknown>;
    return { from: value.from, to: value.to };
  }
  if (Array.isArray(raw) && raw.length === 2) {
    return { from: raw[0], to: raw[1] };
  }
  return { from: null, to: raw };
}

export default function AuditLogsPage() {
  const [page, setPage] = useState(1);
  const [q, setQ] = useState('');
  const [action, setAction] = useState('');
  const [auditableType, setAuditableType] = useState('');
  const [expandedIds, setExpandedIds] = useState<Set<number>>(new Set());

  const queryParams = useMemo(
    () => ({
      page,
      per_page: 25,
      q: q.trim() || undefined,
      audit_action: action || undefined,
      auditable_type: auditableType || undefined,
    }),
    [page, q, action, auditableType]
  );

  const { data, isLoading } = useQuery<AuditLogsResponse>({
    queryKey: ['audit-logs', queryParams],
    queryFn: () => getAuditLogs(queryParams),
  });

  const logs = data?.audit_logs || [];
  const pagination = data?.pagination;
  const filterActions = data?.filters?.actions || Array.from(new Set(logs.map((log) => log.action))).sort();
  const filterTypes = data?.filters?.auditable_types || Array.from(new Set(logs.map((log) => log.auditable_type))).sort();

  return (
    <WorkspacePage width="full" className="space-y-4">
      <div>
        <h1 className="text-2xl font-bold tracking-tight text-gray-900">Activity Log</h1>
        <p className="text-sm text-[var(--text-secondary)]">
          Master history of who did what across supporters, imports, vetting, duplicates, and configuration.
        </p>
      </div>

      <section className="app-card p-4 space-y-3">
        <div className="grid grid-cols-1 md:grid-cols-4 gap-2">
          <input
            value={q}
            onChange={(e) => {
              setPage(1);
              setQ(e.target.value);
            }}
            placeholder="Search action, actor, type..."
            className="border border-[var(--border-soft)] rounded-xl px-3 py-2"
          />
          <select
            value={action}
            onChange={(e) => {
              setPage(1);
              setAction(e.target.value);
            }}
            className="border border-[var(--border-soft)] rounded-xl px-3 py-2"
          >
            <option value="">All actions</option>
            {filterActions.map((entryAction) => (
              <option key={entryAction} value={entryAction}>
                {formatActionLabel(entryAction)}
              </option>
            ))}
          </select>
          <select
            value={auditableType}
            onChange={(e) => {
              setPage(1);
              setAuditableType(e.target.value);
            }}
            className="border border-[var(--border-soft)] rounded-xl px-3 py-2"
          >
            <option value="">All target types</option>
            {filterTypes.map((entryType) => (
              <option key={entryType} value={entryType}>
                {entryType}
              </option>
            ))}
          </select>
          <button
            type="button"
            onClick={() => {
              setPage(1);
              setQ('');
              setAction('');
              setAuditableType('');
            }}
            className="bg-[var(--surface-overlay)] hover:bg-gray-200 rounded-xl px-3 py-2 text-sm"
          >
            Clear filters
          </button>
        </div>
        <p className="text-xs text-[var(--text-secondary)]">
          {pagination ? `${pagination.total} total entries` : 'Loading entries...'}
        </p>
      </section>

      <section className="space-y-2">
        {isLoading ? (
          <div className="app-card p-6 text-sm text-[var(--text-secondary)]">Loading activity...</div>
        ) : logs.length === 0 ? (
          <div className="app-card p-6 text-sm text-[var(--text-secondary)]">No activity logs found for these filters.</div>
        ) : (
          logs.map((log) => (
            <article key={log.id} className="app-card p-4">
              <div className="flex flex-col md:flex-row md:items-start md:justify-between gap-2">
                <div>
                  <p className="font-semibold text-[var(--text-primary)]">{formatActionLabel(log.action)}</p>
                  <p className="text-sm text-[var(--text-secondary)]">
                    {log.actor_name || log.actor_email || 'System/Public'} ({log.actor_role?.replaceAll('_', ' ') || 'public/system'})
                  </p>
                  <p className="text-sm text-[var(--text-secondary)]">
                    Target: {log.auditable_label} ({log.auditable_type})
                  </p>
                </div>
                <p className="text-xs text-[var(--text-muted)]">{prettyDate(log.created_at)}</p>
              </div>
              <div className="mt-3 rounded-lg border border-[var(--border-soft)] bg-[var(--surface-bg)] px-3 py-2 text-sm">
                <p className="font-medium text-[var(--text-primary)]">
                  {changedFieldCount(log.changed_data)} changed field{changedFieldCount(log.changed_data) === 1 ? '' : 's'}
                </p>
                <p className="text-[var(--text-secondary)]">{changedFieldList(log.changed_data)}</p>
              </div>
              <div className="mt-2 flex items-center justify-between">
                <button
                  type="button"
                  onClick={() => setExpandedIds((prev) => {
                    const next = new Set(prev);
                    if (next.has(log.id)) next.delete(log.id);
                    else next.add(log.id);
                    return next;
                  })}
                  className="text-sm text-primary hover:underline"
                >
                  {expandedIds.has(log.id) ? 'Hide details' : 'Show details'}
                </button>
              </div>
              {expandedIds.has(log.id) && (
                <div className="mt-3 space-y-2">
                  {Object.entries(log.changed_data || {}).length === 0 ? (
                    <div className="rounded-lg border border-[var(--border-soft)] px-3 py-2 text-sm text-[var(--text-secondary)]">
                      No field-level details recorded for this action.
                    </div>
                  ) : (
                    Object.entries(log.changed_data || {}).map(([field, value]) => {
                      const change = parseChangeValue(value);
                      return (
                        <div key={field} className="rounded-lg border border-[var(--border-soft)] px-3 py-2">
                          <p className="text-xs uppercase font-semibold text-[var(--text-muted)]">{formatFieldName(field)}</p>
                          <p className="text-sm text-[var(--text-primary)]">
                            {toDisplayValue(change.from)} {'->'} {toDisplayValue(change.to)}
                          </p>
                        </div>
                      );
                    })
                  )}
                </div>
              )}
            </article>
          ))
        )}
      </section>

      {pagination && pagination.pages > 1 && (
        <div className="flex items-center justify-between">
          <button
            type="button"
            disabled={pagination.page <= 1}
            onClick={() => setPage((p) => Math.max(1, p - 1))}
            className="bg-[var(--surface-overlay)] disabled:opacity-50 px-3 py-2 rounded-lg text-sm"
          >
            Previous
          </button>
          <p className="text-sm text-[var(--text-secondary)]">Page {pagination.page} of {pagination.pages}</p>
          <button
            type="button"
            disabled={pagination.page >= pagination.pages}
            onClick={() => setPage((p) => p + 1)}
            className="bg-[var(--surface-overlay)] disabled:opacity-50 px-3 py-2 rounded-lg text-sm"
          >
            Next
          </button>
        </div>
      )}
    </WorkspacePage>
  );
}
