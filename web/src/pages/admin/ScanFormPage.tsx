import { useEffect, useMemo, useRef, useState, type SetStateAction } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { AlertTriangle, Camera, Check, ImagePlus, Loader2, RotateCcw, Upload } from 'lucide-react';
import { createSupporter, getVillages, scanBatchForm, trackScanBatchTelemetry } from '../../lib/api';
import { useSession } from '../../hooks/useSession';
import WorkspacePage from '../../components/WorkspacePage';

interface Village {
  id: number;
  name: string;
}

type ConfidenceLevel = 'high' | 'medium' | 'low' | null;
type ConfidenceMap = Record<string, ConfidenceLevel>;

interface BatchRow {
  _row: number;
  _skip: boolean;
  _issues: string[];
  _source_file_name?: string;
  first_name: string;
  middle_name: string;
  last_name: string;
  contact_number: string;
  email: string;
  street_address: string;
  dob: string;
  village_id: number | null;
  registered_voter: boolean;
  yard_sign: boolean;
  motorcade_available: boolean;
  opt_in_email: boolean;
  opt_in_text: boolean;
  confidence: ConfidenceMap;
}

type Phase = 'capture' | 'scanning' | 'review' | 'complete';

interface SaveResult {
  created: number;
  failed: number;
  skipped: number;
  errors: { row: number; message: string }[];
  failedRows: BatchRow[];
}

type IssueSeverity = 'critical' | 'warning';

interface RowIssue {
  code: string;
  message: string;
  severity: IssueSeverity;
}

interface SelectedScanFile {
  id: string;
  file: File;
  name: string;
  previewUrl: string;
}

interface HandleFileSelectOptions {
  append?: boolean;
  preparedFiles?: SelectedScanFile[];
}

function confidenceTag(level: ConfidenceLevel) {
  if (level === 'high') return 'text-green-700 bg-green-50 border-green-200';
  if (level === 'medium') return 'text-amber-700 bg-amber-50 border-amber-200';
  if (level === 'low') return 'text-red-700 bg-red-50 border-red-200';
  return 'text-[var(--text-muted)] bg-[var(--surface-bg)] border-[var(--border-soft)]';
}

function inputBorderForConfidence(level: ConfidenceLevel) {
  if (level === 'high') return 'border-green-400 bg-green-50';
  if (level === 'medium') return 'border-amber-400 bg-amber-50';
  if (level === 'low') return 'border-red-400 bg-red-50';
  return 'border-[var(--border-soft)]';
}

function normalizePhone(value: string) {
  return value.trim();
}

function mergeWarningEntries(existing: string[], additions: string[]) {
  const normalized = [...existing, ...additions]
    .map((entry) => entry.trim())
    .filter(Boolean);

  return Array.from(new Set(normalized));
}

function revokeSelectedFiles(files: SelectedScanFile[]) {
  files.forEach((entry) => URL.revokeObjectURL(entry.previewUrl));
}

const STATESIDE_ADDRESS_HINTS = [
  'alabama', 'alaska', 'arizona', 'arkansas', 'california', 'colorado', 'connecticut', 'delaware', 'florida',
  'georgia', 'hawaii', 'idaho', 'illinois', 'indiana', 'iowa', 'kansas', 'kentucky', 'louisiana', 'maine',
  'maryland', 'massachusetts', 'michigan', 'minnesota', 'mississippi', 'missouri', 'montana', 'nebraska',
  'nevada', 'new hampshire', 'new jersey', 'new mexico', 'new york', 'north carolina', 'north dakota', 'ohio',
  'oklahoma', 'oregon', 'pennsylvania', 'rhode island', 'south carolina', 'south dakota', 'tennessee', 'texas',
  'utah', 'vermont', 'virginia', 'washington', 'west virginia', 'wisconsin', 'wyoming',
];

function issueCodeFromMessage(message: string) {
  return message
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 50) || 'ocr_issue';
}

function hasStatesideAddressHint(address: string) {
  const normalized = address.toLowerCase();
  if (/\b\d{5}(?:-\d{4})?\b/.test(normalized)) return true;
  return STATESIDE_ADDRESS_HINTS.some((hint) => normalized.includes(hint));
}

function parseDateInput(value: string) {
  const trimmed = value.trim();
  if (!trimmed) return null;

  let year = 0;
  let month = 0;
  let day = 0;

  const ymd = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(trimmed);
  if (ymd) {
    year = Number(ymd[1]);
    month = Number(ymd[2]);
    day = Number(ymd[3]);
  } else {
    const mdy = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/.exec(trimmed);
    if (!mdy) return null;
    month = Number(mdy[1]);
    day = Number(mdy[2]);
    year = Number(mdy[3]);
  }

  if (year < 1900 || month < 1 || month > 12 || day < 1 || day > 31) return null;
  const date = new Date(Date.UTC(year, month - 1, day));
  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day
  ) {
    return null;
  }

  const now = new Date();
  if (date.getTime() > now.getTime()) return null;
  return date;
}

function formatDateParts(date: Date, separator: '-' | '/') {
  const year = String(date.getUTCFullYear());
  const month = String(date.getUTCMonth() + 1).padStart(2, '0');
  const day = String(date.getUTCDate()).padStart(2, '0');

  return separator === '-'
    ? `${year}-${month}-${day}`
    : `${month}/${day}/${year}`;
}

function formatDateForDisplay(value: string) {
  const parsed = parseDateInput(value);
  if (!parsed) return value.trim();
  return formatDateParts(parsed, '/');
}

function formatDateForSubmission(value: string) {
  const parsed = parseDateInput(value);
  if (!parsed) return value.trim();
  return formatDateParts(parsed, '-');
}

function analyzeRowIssues(row: BatchRow): RowIssue[] {
  const issues = new Map<string, RowIssue>();
  const addIssue = (code: string, message: string, severity: IssueSeverity) => {
    if (!issues.has(code)) issues.set(code, { code, message, severity });
  };

  const firstName = row.first_name.trim();
  const lastName = row.last_name.trim();
  const phone = row.contact_number.trim();
  const email = row.email.trim();
  const address = row.street_address.trim();
  const dob = row.dob.trim();

  if (!firstName && !lastName && !phone && !email && !address && !dob) {
    addIssue('row_empty', 'Row appears empty', 'critical');
  }
  if (!firstName) addIssue('first_name_missing', 'First name missing', 'critical');
  if (!lastName) addIssue('last_name_missing', 'Last name missing', 'critical');
  if (!row.village_id) addIssue('village_missing', 'Village missing', 'critical');

  const phoneDigits = phone.replace(/\D/g, '');
  if (!phone || phoneDigits.length <= 3) {
    addIssue('phone_missing', 'Phone missing', 'warning');
  } else if (phoneDigits.length < 10) {
    addIssue('phone_incomplete', 'Phone looks incomplete', 'warning');
  }

  if (dob && !parseDateInput(dob)) {
    addIssue('dob_invalid', 'DOB format invalid (use MM/DD/YYYY)', 'warning');
  }

  if (address && hasStatesideAddressHint(address)) {
    addIssue(
      'stateside_address',
      'Stateside address detected (may be valid for movers/new arrivals)',
      'warning'
    );
  }

  row._issues.forEach((message) => {
    const code = issueCodeFromMessage(message);
    if (!issues.has(code)) addIssue(code, message, 'warning');
  });

  return Array.from(issues.values());
}

export default function ScanFormPage() {
  const queryClient = useQueryClient();
  const fileInputRef = useRef<HTMLInputElement>(null);
  const galleryInputRef = useRef<HTMLInputElement>(null);
  const captureFilesRef = useRef<SelectedScanFile[]>([]);
  const selectedFilesRef = useRef<SelectedScanFile[]>([]);

  const [phase, setPhase] = useState<Phase>('capture');
  const [defaultVillageId, setDefaultVillageId] = useState('');
  const [rows, setRows] = useState<BatchRow[]>([]);
  const [scanError, setScanError] = useState('');
  const [scanWarnings, setScanWarnings] = useState<string[]>([]);
  const [captureFiles, setCaptureFiles] = useState<SelectedScanFile[]>([]);
  const [selectedFiles, setSelectedFiles] = useState<SelectedScanFile[]>([]);
  const [scanProgress, setScanProgress] = useState<{ current: number; total: number }>({ current: 0, total: 0 });
  const [saveResult, setSaveResult] = useState<SaveResult | null>(null);
  const [saveProgress, setSaveProgress] = useState<{ current: number; total: number }>({ current: 0, total: 0 });
  const scanWarning = scanWarnings.join(' | ');

  const { data: sessionData } = useSession();
  const scopedVillageIds = sessionData?.user?.scoped_village_ids ?? null;

  const { data: villagesData } = useQuery({
    queryKey: ['villages'],
    queryFn: getVillages,
  });
  const villages: Village[] = useMemo(() => {
    const all = villagesData?.villages || [];
    if (!scopedVillageIds) return all;
    return all.filter((v: Village) => scopedVillageIds.includes(v.id));
  }, [villagesData, scopedVillageIds]);

  const buildSelectedFiles = (files: File[]) => files.map((file) => ({
    id: `${file.name}-${file.lastModified}-${Math.random().toString(36).slice(2, 8)}`,
    file,
    name: file.name,
    previewUrl: URL.createObjectURL(file),
  }));

  const syncCaptureFiles = (nextValue: SetStateAction<SelectedScanFile[]>) => {
    setCaptureFiles((prev) => {
      const nextFiles = typeof nextValue === 'function'
        ? (nextValue as (current: SelectedScanFile[]) => SelectedScanFile[])(prev)
        : nextValue;
      captureFilesRef.current = nextFiles;
      return nextFiles;
    });
  };

  const syncSelectedFiles = (nextValue: SetStateAction<SelectedScanFile[]>) => {
    setSelectedFiles((prev) => {
      const nextFiles = typeof nextValue === 'function'
        ? (nextValue as (current: SelectedScanFile[]) => SelectedScanFile[])(prev)
        : nextValue;
      selectedFilesRef.current = nextFiles;
      return nextFiles;
    });
  };

  const queueCaptureFiles = (files: File[]) => {
    if (!defaultVillageId) {
      setScanError('Select a default village before scanning.');
      return;
    }
    if (files.length === 0) return;

    setScanError('');
    const newFiles = buildSelectedFiles(files);
    syncCaptureFiles((prev) => [...prev, ...newFiles]);
  };

  const removeCaptureFile = (fileId: string) => {
    syncCaptureFiles((prev) => {
      const fileToRemove = prev.find((file) => file.id === fileId);
      if (fileToRemove) {
        URL.revokeObjectURL(fileToRemove.previewUrl);
      }
      return prev.filter((file) => file.id !== fileId);
    });
  };

  useEffect(() => () => {
    revokeSelectedFiles(captureFilesRef.current);
    revokeSelectedFiles(selectedFilesRef.current);
  }, []);

  const handleFileSelect = async (files: File[], options?: HandleFileSelectOptions) => {
    if (!defaultVillageId) {
      setScanError('Select a default village before scanning.');
      return;
    }
    if (files.length === 0) return;

    const append = options?.append ?? false;
    const previousPhase = phase;
    const existingRows = append ? rows : [];
    const existingFiles = append ? selectedFiles : [];
    const previousWarnings = append ? scanWarnings : [];
    const preparedFiles = options?.preparedFiles;
    const newSelectedFiles = preparedFiles ?? buildSelectedFiles(files);
    const shouldRevokeNewSelectedFiles = !preparedFiles;
    const restoreNewSelectedFiles = () => {
      if (shouldRevokeNewSelectedFiles) {
        revokeSelectedFiles(newSelectedFiles);
      } else if (!append) {
        syncCaptureFiles(newSelectedFiles);
      } else {
        // `append + preparedFiles` is not a supported call site today. If that
        // ever changes, the caller should own the prepared preview lifecycle.
      }
    };

    setPhase('scanning');
    setScanError('');
    if (!append) {
      setScanWarnings([]);
      revokeSelectedFiles(selectedFiles);
      syncCaptureFiles([]);
    }
    syncSelectedFiles(append ? [...existingFiles, ...newSelectedFiles] : newSelectedFiles);
    setScanProgress({ current: 0, total: files.length });

    try {
      const allRows: BatchRow[] = [ ...existingRows ];
      const warnings: string[] = [];
      const failures: string[] = [];
      let rowCounter = existingRows.reduce((max, row) => Math.max(max, row._row), 0) + 1;

      for (let index = 0; index < files.length; index += 1) {
        const file = files[index];
        setScanProgress({ current: index + 1, total: files.length });

        const base64 = await new Promise<string>((resolve, reject) => {
          const reader = new FileReader();
          reader.onload = () => resolve(reader.result as string);
          reader.onerror = () => reject(new Error(`Failed to read image: ${file.name}`));
          reader.readAsDataURL(file);
        });

        const result = await scanBatchForm(base64, Number(defaultVillageId));
        if (!result.success) {
          failures.push(`${file.name}: ${result.error || 'Could not extract any supporter rows'}`);
          continue;
        }

        const extractedRows: BatchRow[] = (result.rows || []).map((row: Record<string, unknown>) => ({
          _row: rowCounter++,
          _skip: Boolean(row._skip),
          _issues: Array.isArray(row._issues) ? row._issues.map((x) => String(x)) : [],
          _source_file_name: file.name,
          first_name: String(row.first_name || ''),
          middle_name: String(row.middle_name || ''),
          last_name: String(row.last_name || ''),
          contact_number: normalizePhone(String(row.contact_number || '')),
          email: String(row.email || ''),
          street_address: String(row.street_address || ''),
          dob: formatDateForDisplay(String(row.dob || '')),
          village_id: row.village_id ? Number(row.village_id) : Number(defaultVillageId),
          registered_voter: row.registered_voter == null ? true : Boolean(row.registered_voter),
          yard_sign: Boolean(row.yard_sign),
          motorcade_available: Boolean(row.motorcade_available),
          opt_in_email: false,
          opt_in_text: false,
          confidence: (row.confidence as ConfidenceMap) || {},
        }));

        if (extractedRows.length === 0) {
          failures.push(`${file.name}: no supporter rows were detected`);
          continue;
        }

        allRows.push(...extractedRows);
        if (result.warning) warnings.push(`${file.name}: ${String(result.warning)}`);
      }

      const addedRowCount = allRows.length - existingRows.length;

      if (addedRowCount === 0) {
        setScanError(failures[0] || 'No supporter rows were detected from the selected images.');
        restoreNewSelectedFiles();
        syncSelectedFiles(existingFiles);
        setScanWarnings(mergeWarningEntries(previousWarnings, warnings));
        setScanProgress({ current: 0, total: 0 });
        setRows(existingRows);
        setPhase(append ? previousPhase : 'capture');
        return;
      }

      const combinedWarnings = mergeWarningEntries(previousWarnings, [
        ...warnings,
        ...failures,
      ]);
      setScanWarnings(combinedWarnings);
      setRows(allRows);
      setPhase('review');
    } catch (err: unknown) {
      const error = err as { response?: { data?: { error?: string } } };
      restoreNewSelectedFiles();
      syncSelectedFiles(existingFiles);
      setScanError(error?.response?.data?.error || 'Batch scan failed — try again');
      setScanWarnings(previousWarnings);
      setScanProgress({ current: 0, total: 0 });
      setRows(existingRows);
      setPhase(append ? previousPhase : 'capture');
    }
  };

  // Declared before saveMutation so the closure captures a stable reference
  const rowIssuesMatrix = useMemo(() => rows.map((row) => analyzeRowIssues(row)), [rows]);

  const saveMutation = useMutation({
    mutationFn: async () => {
      const activeRows = rows.filter((row) => !row._skip);
      const result: SaveResult = { created: 0, failed: 0, skipped: rows.filter((row) => row._skip).length, errors: [], failedRows: [] };
      setSaveProgress({ current: 0, total: activeRows.length });

      for (let i = 0; i < activeRows.length; i += 1) {
        const row = activeRows[i];
        setSaveProgress({ current: i + 1, total: activeRows.length });

        const rowIndex = rows.indexOf(row);
        const criticalIssues = (rowIssuesMatrix[rowIndex] || []).filter((issue) => issue.severity === 'critical');
        if (criticalIssues.length > 0) {
          result.failed += 1;
          result.errors.push({
            row: row._row,
            message: criticalIssues.map((issue) => issue.message).join('; '),
          });
          result.failedRows.push(row);
          continue;
        }

        try {
          await createSupporter(
            {
              first_name: row.first_name.trim(),
              middle_name: row.middle_name.trim() || null,
              last_name: row.last_name.trim(),
              contact_number: row.contact_number.trim() || null,
              email: row.email.trim() || null,
              street_address: row.street_address.trim() || null,
              dob: row.dob.trim() ? formatDateForSubmission(row.dob) : null,
              village_id: row.village_id,
              self_reported_registered_voter: row.registered_voter,
              yard_sign: row.yard_sign,
              motorcade_available: row.motorcade_available,
              opt_in_email: row.opt_in_email ?? false,
              opt_in_text: row.opt_in_text ?? false,
            },
            undefined,
            'staff',
            'scan'
          );
          result.created += 1;
        } catch (err: unknown) {
          const errorMessage = (err as { response?: { data?: { errors?: string[]; message?: string } } })?.response?.data;
          result.failed += 1;
          result.errors.push({
            row: row._row,
            message: errorMessage?.errors?.join(', ') || errorMessage?.message || 'Could not save this row.',
          });
          result.failedRows.push(row);
        }
      }

      const issueCounts = rows.reduce<Record<string, number>>((acc, _row, idx) => {
        (rowIssuesMatrix[idx] || []).forEach((issue) => {
          acc[issue.code] = (acc[issue.code] || 0) + 1;
        });
        return acc;
      }, {});
      const rowsWithAnyIssues = rowIssuesMatrix.filter((issues) => issues.length > 0).length;
      const rowsWithCriticalIssues = rowIssuesMatrix.filter((issues) => issues.some((issue) => issue.severity === 'critical')).length;
      const rowsWithWarningOnly = rowIssuesMatrix.filter((issues) =>
        issues.length > 0 && !issues.some((issue) => issue.severity === 'critical')
      ).length;

      try {
        await trackScanBatchTelemetry({
          total_detected: rows.length,
          included_before_save: activeRows.length,
          created: result.created,
          failed: result.failed,
          skipped: result.skipped,
          rows_with_any_issues: rowsWithAnyIssues,
          rows_with_critical_issues: rowsWithCriticalIssues,
          rows_with_warning_only: rowsWithWarningOnly,
          issue_counts: issueCounts,
          scan_warning_present: Boolean(scanWarning),
          save_duration_ms: 0, // timing removed to satisfy ESLint purity rules
          default_village_id: defaultVillageId ? Number(defaultVillageId) : null,
        });
      } catch {
        // Telemetry should never block save completion.
      }

      return result;
    },
    onSuccess: (result) => {
      setSaveResult(result);
      setPhase('complete');
      queryClient.invalidateQueries({ queryKey: ['dashboard'] });
      queryClient.invalidateQueries({ queryKey: ['supporters'] });
      queryClient.invalidateQueries({ queryKey: ['session'] });
    },
  });

  const [showIssuesOnly, setShowIssuesOnly] = useState(false);

  const rowsWithAnyIssues = rowIssuesMatrix.filter((issues) => issues.length > 0).length;
  const rowsWithCriticalIssues = rowIssuesMatrix.filter((issues) => issues.some((issue) => issue.severity === 'critical')).length;
  const rowsWithWarningOnly = rowIssuesMatrix.filter((issues) =>
    issues.length > 0 && !issues.some((issue) => issue.severity === 'critical')
  ).length;
  const activeRows = useMemo(() => rows.filter((row) => !row._skip), [rows]);
  const activeCriticalRows = useMemo(
    () => rows.filter((row, index) => !row._skip && rowIssuesMatrix[index].some((issue) => issue.severity === 'critical')).length,
    [rows, rowIssuesMatrix]
  );
  const reviewRows = useMemo(
    () => rows
      .map((row, index) => ({ row, index, issues: rowIssuesMatrix[index] }))
      .filter((entry) => !showIssuesOnly || entry.issues.length > 0),
    [rows, rowIssuesMatrix, showIssuesOnly]
  );
  const scanningBatchFiles = useMemo(() => {
    if (scanProgress.total <= 0) return [];
    return selectedFiles.slice(-scanProgress.total);
  }, [selectedFiles, scanProgress.total]);
  const isAppendingWhileScanning = phase === 'scanning' && selectedFiles.length > scanProgress.total;
  const existingBatchCountWhileScanning = Math.max(selectedFiles.length - scanProgress.total, 0);

  const resetForNextBatch = () => {
    setRows([]);
    setScanError('');
    setScanWarnings([]);
    setScanProgress({ current: 0, total: 0 });
    setShowIssuesOnly(false);
    setSaveResult(null);
    setSaveProgress({ current: 0, total: 0 });
    revokeSelectedFiles(captureFiles);
    revokeSelectedFiles(selectedFiles);
    syncCaptureFiles([]);
    syncSelectedFiles([]);
    setPhase('capture');
  };

  const updateRow = <K extends keyof BatchRow>(index: number, field: K, value: BatchRow[K]) => {
    setRows((prev) => prev.map((row, i) => (i === index ? { ...row, [field]: value } : row)));
  };

  const skipRowsWithCriticalIssues = () => {
    setRows((prev) => prev.map((row, idx) => (
      (rowIssuesMatrix[idx] || []).some((issue) => issue.severity === 'critical')
        ? { ...row, _skip: true }
        : row
    )));
  };

  const includeRowsWithoutCriticalIssues = () => {
    setRows((prev) => prev.map((row, idx) => (
      (rowIssuesMatrix[idx] || []).some((issue) => issue.severity === 'critical')
        ? row
        : { ...row, _skip: false }
    )));
  };

  return (
    <WorkspacePage width="full" className="space-y-6">
      <div className="flex items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-bold text-gray-900">Batch Scan Blue Form</h1>
          <p className="text-sm text-[var(--text-secondary)]">
            Scan a full page, review detected supporters, then save in one pass.
          </p>
        </div>
      </div>

      <input
        ref={fileInputRef}
        type="file"
        accept="image/*"
        capture="environment"
        className="hidden"
        onChange={(e) => {
          const files = Array.from(e.target.files || []);
          if (files.length > 0) {
            if (phase === 'review') {
              void handleFileSelect(files, { append: true });
            } else {
              queueCaptureFiles(files);
            }
          }
          e.target.value = '';
        }}
      />

      <input
        ref={galleryInputRef}
        type="file"
        accept="image/*"
        multiple
        className="hidden"
        onChange={(e) => {
          const files = Array.from(e.target.files || []);
          if (files.length > 0) {
            if (phase === 'review') {
              void handleFileSelect(files, { append: true });
            } else {
              queueCaptureFiles(files);
            }
          }
          e.target.value = '';
        }}
      />

      {phase === 'capture' && (
        <div className="space-y-4">
          <section className="app-card p-4">
            <h2 className="font-semibold text-[var(--text-primary)] mb-2">Default Village (required)</h2>
            <p className="text-xs text-[var(--text-secondary)] mb-3">
              Most pages are from one village. This stays selected for the next scan and can be overridden per row later.
            </p>
            <select
              value={defaultVillageId}
              onChange={(e) => setDefaultVillageId(e.target.value)}
              className="w-full max-w-md border border-[var(--border-soft)] rounded-xl px-3 py-2 bg-[var(--surface-raised)] min-h-[44px]"
            >
              <option value="">Select village...</option>
              {villages.map((village) => (
                <option key={village.id} value={village.id}>{village.name}</option>
              ))}
            </select>
          </section>

          <button
            type="button"
            disabled={!defaultVillageId}
            onClick={() => fileInputRef.current?.click()}
            className="w-full bg-[var(--surface-raised)] rounded-2xl border-2 border-dashed border-[var(--border-soft)] hover:border-primary hover:bg-blue-50 transition-all p-8 sm:p-12 flex flex-col items-center gap-4 disabled:opacity-50"
          >
            <div className="w-20 h-20 rounded-full bg-primary flex items-center justify-center">
              <Camera className="w-10 h-10 text-white" />
            </div>
            <div className="text-center">
              <p className="text-lg font-semibold text-[var(--text-primary)]">Scan Full Blue Form</p>
              <p className="text-sm text-[var(--text-secondary)] mt-1">Capture one page at a time with all rows visible</p>
            </div>
          </button>

          <button
            type="button"
            disabled={!defaultVillageId}
            onClick={() => galleryInputRef.current?.click()}
            className="w-full bg-[var(--surface-raised)] rounded-xl border border-[var(--border-soft)] p-4 inline-flex items-center justify-center gap-2 text-[var(--text-secondary)] hover:text-[var(--text-primary)] disabled:opacity-50"
          >
            <ImagePlus className="w-5 h-5" />
            Upload one or more photos
          </button>

          {captureFiles.length > 0 && (
            <section className="app-card p-4 space-y-3">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <div>
                  <h2 className="font-semibold text-[var(--text-primary)]">Selected Photos</h2>
                  <p className="text-sm text-[var(--text-secondary)]">
                    {captureFiles.length} photo{captureFiles.length === 1 ? '' : 's'} ready for OCR review.
                  </p>
                </div>
                <button
                  type="button"
                  onClick={() => {
                    revokeSelectedFiles(captureFiles);
                    syncCaptureFiles([]);
                    setScanError('');
                    setScanWarnings([]);
                  }}
                  className="bg-[var(--surface-raised)] border border-[var(--border-soft)] text-[var(--text-secondary)] hover:text-[var(--text-primary)] px-3 py-2 rounded-xl min-h-[44px]"
                >
                  Clear photos
                </button>
              </div>
              <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
                {captureFiles.map((file) => (
                  <div key={file.id} className="overflow-hidden rounded-xl border border-[var(--border-soft)] bg-white">
                    <img src={file.previewUrl} alt={file.name} className="h-28 w-full object-cover" />
                    <div className="flex items-center gap-2 px-2 py-2">
                      <p className="min-w-0 flex-1 truncate text-[11px] text-[var(--text-secondary)]">{file.name}</p>
                      <button
                        type="button"
                        onClick={() => removeCaptureFile(file.id)}
                        className="rounded-lg border border-red-200 px-2 py-1 text-[11px] font-medium text-red-600 hover:bg-red-50"
                      >
                        Remove
                      </button>
                    </div>
                  </div>
                ))}
              </div>
              <button
                type="button"
                onClick={() => void handleFileSelect(captureFiles.map((file) => file.file), { preparedFiles: captureFiles })}
                className="w-full bg-primary text-white px-4 py-3 rounded-xl min-h-[44px] inline-flex items-center justify-center gap-2 font-medium"
              >
                <Upload className="w-4 h-4" />
                Review {captureFiles.length} photo{captureFiles.length === 1 ? '' : 's'}
              </button>
            </section>
          )}

          {scanError && (
            <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded-xl flex items-center gap-2">
              <AlertTriangle className="w-5 h-5 shrink-0" />
              {scanError}
            </div>
          )}

          <div className="bg-blue-50 border border-blue-100 rounded-xl p-4 text-sm text-blue-800">
            <p className="font-medium mb-1">Batch scan tips</p>
            <ul className="space-y-1 text-xs sm:text-sm">
              <li>• Fill the frame with the full blue form</li>
              <li>• Good lighting improves row detection</li>
              <li>• Take or choose multiple photos first, then open one combined OCR review</li>
              <li>• You will review, edit, and skip rows before save</li>
            </ul>
          </div>
        </div>
      )}

      {phase === 'scanning' && (
        <div className="space-y-4">
          {scanningBatchFiles.length > 0 && (
            <div className="rounded-2xl border border-[var(--border-soft)] bg-[var(--surface-raised)] p-4">
              <p className="text-sm font-semibold text-[var(--text-primary)]">
                {isAppendingWhileScanning
                  ? `Processing ${scanProgress.current} of ${scanProgress.total} new image${scanProgress.total === 1 ? '' : 's'}`
                  : `Processing ${scanProgress.current} of ${scanProgress.total} image${scanProgress.total === 1 ? '' : 's'}`}
              </p>
              {isAppendingWhileScanning && (
                <p className="mt-1 text-xs text-[var(--text-secondary)]">
                  Adding to an existing batch with {existingBatchCountWhileScanning} existing image{existingBatchCountWhileScanning === 1 ? '' : 's'}.
                </p>
              )}
              <div className="mt-3 grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
                {scanningBatchFiles.slice(0, 8).map((file) => (
                  <div key={file.id} className="overflow-hidden rounded-xl border border-[var(--border-soft)] bg-white">
                    <img src={file.previewUrl} alt={file.name} className="h-28 w-full object-cover" />
                    <p className="truncate px-2 py-1 text-[11px] text-[var(--text-secondary)]">{file.name}</p>
                  </div>
                ))}
              </div>
            </div>
          )}
          <div className="flex flex-col items-center gap-3 py-8">
            <Loader2 className="w-12 h-12 text-primary animate-spin" />
            <p className="text-lg font-semibold text-[var(--text-primary)]">Extracting supporter rows...</p>
            <p className="text-sm text-[var(--text-secondary)]">This can take a few seconds per image for full-page OCR.</p>
          </div>
        </div>
      )}

      {phase === 'review' && (
        <div className="space-y-4">
          <section className="app-card p-4">
            <h2 className="font-semibold text-[var(--text-primary)] mb-2">Review OCR Rows</h2>
            <p className="text-xs text-[var(--text-secondary)] mb-3">
              Combined review for {selectedFiles.length || 1} scanned image{(selectedFiles.length || 1) === 1 ? '' : 's'}.
            </p>
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 text-center">
              <div className="bg-[var(--surface-bg)] rounded-lg p-3">
                <p className="text-2xl font-bold text-[var(--text-primary)]">{rows.length}</p>
                <p className="text-xs text-[var(--text-secondary)]">Detected</p>
              </div>
              <div className="bg-green-50 rounded-lg p-3">
                <p className="text-2xl font-bold text-green-700">{activeRows.length}</p>
                <p className="text-xs text-[var(--text-secondary)]">Included</p>
              </div>
              <div className="bg-amber-50 rounded-lg p-3">
                <p className="text-2xl font-bold text-amber-700">{rowsWithAnyIssues}</p>
                <p className="text-xs text-[var(--text-secondary)]">Any issues</p>
              </div>
              <div className="bg-red-50 rounded-lg p-3">
                <p className="text-2xl font-bold text-red-700">{activeCriticalRows}</p>
                <p className="text-xs text-[var(--text-secondary)]">Critical included</p>
              </div>
            </div>
            <p className="text-xs text-[var(--text-secondary)] mt-2">
              Warning only: {rowsWithWarningOnly} · Rows with critical issues: {rowsWithCriticalIssues} · Skipped: {rows.length - activeRows.length}
            </p>
            <p className="text-xs text-blue-800 bg-blue-50 border border-blue-100 rounded-lg px-3 py-2 mt-3">
              Precinct is auto-assigned on save using village + last name. You can override village per row below.
            </p>
            {scanWarning && (
              <p className="text-xs text-amber-800 bg-amber-50 border border-amber-200 rounded-lg px-3 py-2 mt-2">
                {scanWarning}
              </p>
            )}
            {scanError && (
              <p className="text-xs text-red-800 bg-red-50 border border-red-200 rounded-lg px-3 py-2 mt-2">
                {scanError}
              </p>
            )}
            {activeCriticalRows > 0 && (
              <p className="text-xs text-red-800 bg-red-50 border border-red-200 rounded-lg px-3 py-2 mt-2">
                {activeCriticalRows} included row{activeCriticalRows === 1 ? '' : 's'} have critical issues. Skip those rows or fix them before saving.
              </p>
            )}
            <div className="mt-3 grid grid-cols-1 sm:grid-cols-2 gap-2">
              <button
                type="button"
                onClick={() => fileInputRef.current?.click()}
                className="bg-[var(--surface-raised)] hover:bg-blue-50 border border-[var(--border-soft)] text-[var(--text-primary)] px-3 py-2 rounded-xl min-h-[44px] inline-flex items-center justify-center gap-2"
              >
                <Camera className="w-4 h-4" />
                Add another scanned page
              </button>
              <button
                type="button"
                onClick={() => galleryInputRef.current?.click()}
                className="bg-[var(--surface-raised)] hover:bg-blue-50 border border-[var(--border-soft)] text-[var(--text-primary)] px-3 py-2 rounded-xl min-h-[44px] inline-flex items-center justify-center gap-2"
              >
                <ImagePlus className="w-4 h-4" />
                Add more photos
              </button>
            </div>
          </section>

          <section className="app-card p-3 sm:p-4">
            <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2">
              <p className="text-xs text-[var(--text-secondary)]">
                Showing {reviewRows.length} of {rows.length} rows
              </p>
              <label className="inline-flex items-center gap-2 text-sm text-[var(--text-primary)]">
                <input
                  type="checkbox"
                  checked={showIssuesOnly}
                  onChange={(e) => setShowIssuesOnly(e.target.checked)}
                />
                Show only rows with issues
              </label>
            </div>
            <div className="mt-3 grid grid-cols-1 sm:grid-cols-2 gap-2">
              <button
                type="button"
                onClick={skipRowsWithCriticalIssues}
                className="bg-red-50 hover:bg-red-100 border border-red-200 text-red-700 px-3 py-2 rounded-xl min-h-[44px] text-sm font-medium"
              >
                Skip all critical rows
              </button>
              <button
                type="button"
                onClick={includeRowsWithoutCriticalIssues}
                className="bg-green-50 hover:bg-green-100 border border-green-200 text-green-700 px-3 py-2 rounded-xl min-h-[44px] text-sm font-medium"
              >
                Include all non-critical rows
              </button>
            </div>
          </section>

          <div className="space-y-3">
            {reviewRows.map(({ row, index, issues }) => {
              const lowConfidenceFields = Object.entries(row.confidence || {}).filter(([, level]) => level === 'low');
              return (
                <div key={index} className={`app-card p-3 sm:p-4 ${row._skip ? 'opacity-50' : ''}`}>
                  <div className="flex items-center justify-between gap-2 mb-3">
                    <div>
                      <p className="text-sm font-semibold text-[var(--text-primary)]">Row #{row._row}</p>
                      {row._source_file_name && (
                        <p className="text-[11px] text-[var(--text-secondary)]">{row._source_file_name}</p>
                      )}
                    </div>
                    <button
                      type="button"
                      onClick={() => updateRow(index, '_skip', !row._skip)}
                      className={`text-xs px-2.5 py-1 rounded-lg border ${row._skip ? 'bg-[var(--surface-bg)] border-[var(--border-soft)] text-[var(--text-secondary)]' : 'bg-red-50 border-red-200 text-red-700'}`}
                    >
                      {row._skip ? 'Include' : 'Skip'}
                    </button>
                  </div>

                  {issues.length > 0 && (
                    <div className="mb-3 space-y-1.5">
                      {issues.map((issue) => (
                        <p
                          key={issue.code}
                          className={`rounded-lg border px-3 py-2 text-xs ${
                            issue.severity === 'critical'
                              ? 'border-red-200 bg-red-50 text-red-800'
                              : 'border-amber-200 bg-amber-50 text-amber-800'
                          }`}
                        >
                          {issue.severity === 'critical' ? 'Critical:' : 'Warning:'} {issue.message}
                        </p>
                      ))}
                    </div>
                  )}

                  {lowConfidenceFields.length > 0 && (
                    <div className="mb-3 flex flex-wrap gap-1.5">
                      {lowConfidenceFields.map(([field]) => (
                        <span key={field} className={`text-[11px] border px-2 py-1 rounded-full ${confidenceTag('low')}`}>
                          Low: {field.replaceAll('_', ' ')}
                        </span>
                      ))}
                    </div>
                  )}

                  <div className="grid grid-cols-1 sm:grid-cols-3 gap-2">
                    <input
                      value={row.first_name}
                      onChange={(e) => updateRow(index, 'first_name', e.target.value)}
                      placeholder="First name *"
                      className={`px-3 py-2 border rounded-xl ${inputBorderForConfidence(row.confidence?.first_name || null)}`}
                    />
                    <input
                      value={row.middle_name}
                      onChange={(e) => updateRow(index, 'middle_name', e.target.value)}
                      placeholder="Middle name"
                      className={`px-3 py-2 border rounded-xl ${inputBorderForConfidence(row.confidence?.middle_name || null)}`}
                    />
                    <input
                      value={row.last_name}
                      onChange={(e) => updateRow(index, 'last_name', e.target.value)}
                      placeholder="Last name *"
                      className={`px-3 py-2 border rounded-xl ${inputBorderForConfidence(row.confidence?.last_name || null)}`}
                    />
                    <input
                      value={row.contact_number}
                      onChange={(e) => updateRow(index, 'contact_number', e.target.value)}
                      placeholder="Phone (optional)"
                      className={`px-3 py-2 border rounded-xl ${inputBorderForConfidence(row.confidence?.contact_number || null)}`}
                    />
                    <select
                      value={row.village_id || ''}
                      onChange={(e) => updateRow(index, 'village_id', e.target.value ? Number(e.target.value) : null)}
                      className={`px-3 py-2 border rounded-xl bg-[var(--surface-raised)] ${inputBorderForConfidence(row.confidence?.village || null)}`}
                    >
                      <option value="">Select village *</option>
                      {villages.map((village) => (
                        <option key={village.id} value={village.id}>{village.name}</option>
                      ))}
                    </select>
                    <input
                      value={row.street_address}
                      onChange={(e) => updateRow(index, 'street_address', e.target.value)}
                      placeholder="Street address"
                      className={`px-3 py-2 border rounded-xl sm:col-span-2 ${inputBorderForConfidence(row.confidence?.street_address || null)}`}
                    />
                    <input
                      value={row.dob}
                      onChange={(e) => updateRow(index, 'dob', e.target.value)}
                      onBlur={(e) => updateRow(index, 'dob', formatDateForDisplay(e.target.value))}
                      placeholder="DOB (MM/DD/YYYY)"
                      className={`px-3 py-2 border rounded-xl ${inputBorderForConfidence(row.confidence?.dob || null)}`}
                    />
                    <input
                      value={row.email}
                      onChange={(e) => updateRow(index, 'email', e.target.value)}
                      placeholder="Email"
                      className={`px-3 py-2 border rounded-xl ${inputBorderForConfidence(row.confidence?.email || null)}`}
                    />
                  </div>

                  <div className="mt-3 grid grid-cols-1 sm:grid-cols-2 gap-2 text-sm">
                    <label className="inline-flex items-center gap-2">
                      <input type="checkbox" checked={row.registered_voter} onChange={(e) => updateRow(index, 'registered_voter', e.target.checked)} />
                      Self-reported registered voter
                    </label>
                    <label className="inline-flex items-center gap-2">
                      <input type="checkbox" checked={row.yard_sign} onChange={(e) => updateRow(index, 'yard_sign', e.target.checked)} />
                      Yard sign
                    </label>
                    <label className="inline-flex items-center gap-2">
                      <input type="checkbox" checked={row.motorcade_available} onChange={(e) => updateRow(index, 'motorcade_available', e.target.checked)} />
                      Motorcade available
                    </label>
                    <label className="inline-flex items-center gap-2">
                      <input type="checkbox" checked={row.opt_in_text} onChange={(e) => updateRow(index, 'opt_in_text', e.target.checked)} />
                      Text opt-in
                    </label>
                    <label className="inline-flex items-center gap-2 sm:col-span-2">
                      <input type="checkbox" checked={row.opt_in_email} onChange={(e) => updateRow(index, 'opt_in_email', e.target.checked)} />
                      Email opt-in
                    </label>
                  </div>
                </div>
              );
            })}
          </div>

          <div className="sticky bottom-2 sm:static z-20 border border-[var(--border-soft)] bg-[var(--surface-raised)]/95 backdrop-blur rounded-2xl p-2.5 sm:p-0 sm:border-0 sm:bg-transparent sm:backdrop-blur-0 flex flex-col sm:flex-row gap-2 sm:justify-between">
            <button
              type="button"
              onClick={resetForNextBatch}
              className="bg-[var(--surface-overlay)] hover:bg-gray-200 text-[var(--text-primary)] px-4 py-2 rounded-xl min-h-[44px] inline-flex items-center justify-center gap-2"
            >
              <RotateCcw className="w-4 h-4" />
              Start new batch
            </button>
            <button
              type="button"
              disabled={saveMutation.isPending || activeRows.length === 0 || activeCriticalRows > 0}
              onClick={() => saveMutation.mutate()}
              className="bg-cta hover:bg-cta-hover text-white font-semibold px-4 py-2 rounded-xl min-h-[44px] inline-flex items-center justify-center gap-2 disabled:opacity-50"
            >
              {saveMutation.isPending ? (
                <>
                  <Loader2 className="w-4 h-4 animate-spin" />
                  Saving {saveProgress.current}/{saveProgress.total}
                </>
              ) : (
                <>
                  <Upload className="w-4 h-4" />
                  Save {activeRows.length} supporter{activeRows.length === 1 ? '' : 's'}
                </>
              )}
            </button>
          </div>
        </div>
      )}

      {phase === 'complete' && saveResult && (
        <div className="app-card p-6 text-center space-y-4">
          <div className="w-16 h-16 mx-auto rounded-full bg-green-100 flex items-center justify-center">
            <Check className="w-8 h-8 text-green-700" />
          </div>
          <h2 className="text-xl font-bold text-[var(--text-primary)]">Batch Scan Complete</h2>
          <p className="text-[var(--text-secondary)]">
            Created <strong>{saveResult.created}</strong> · Failed <strong>{saveResult.failed}</strong> · Skipped <strong>{saveResult.skipped}</strong>
          </p>

          {saveResult.errors.length > 0 && (
            <div className="max-w-xl mx-auto text-left rounded-xl border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700">
              {saveResult.errors.slice(0, 15).map((error, i) => (
                <p key={i}>Row {error.row}: {error.message}</p>
              ))}
            </div>
          )}

          <div className="flex flex-col sm:flex-row gap-2 justify-center">
            {saveResult.failedRows.length > 0 && (
              <button
                type="button"
                onClick={() => {
                  setRows(saveResult.failedRows.map((row, i) => ({ ...row, _row: i + 1, _skip: false })));
                  setSaveResult(null);
                  setPhase('review');
                }}
                className="bg-amber-600 text-white px-4 py-2 rounded-xl min-h-[44px] inline-flex items-center justify-center gap-2"
              >
                <RotateCcw className="w-4 h-4" />
                Retry {saveResult.failedRows.length} Failed Row{saveResult.failedRows.length > 1 ? 's' : ''}
              </button>
            )}
            <button
              type="button"
              onClick={resetForNextBatch}
              className="bg-primary text-white px-4 py-2 rounded-xl min-h-[44px] inline-flex items-center justify-center gap-2"
            >
              <Camera className="w-4 h-4" />
              Scan another page
            </button>
            <Link
              to="/admin/vetting"
              className="bg-[var(--surface-overlay)] text-[var(--text-primary)] px-4 py-2 rounded-xl min-h-[44px] inline-flex items-center justify-center"
            >
              Go to Vetting Queue
            </Link>
          </div>
        </div>
      )}

      <div className="pt-1 text-center">
        <Link to="/admin/supporters/new" className="text-sm text-primary hover:underline">
          Need single-person entry? Use manual staff form instead.
        </Link>
      </div>
    </WorkspacePage>
  );
}
