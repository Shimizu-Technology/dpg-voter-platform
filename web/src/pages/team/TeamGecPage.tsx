import React, { useEffect, useRef, useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  getGecStats,
  getGecImports,
  uploadGecList,
  bulkVetSupporters,
  previewGecList,
  getGecPdfPreviewStatus,
  downloadGecImportFile,
  getGecImportViewData,
  getGecImportOriginalView,
  getGecImportChanges,
  getGecImportSkippedRows,
  previewGecImportSkippedRowResolution,
  resolveGecImportSkippedRow,
  dismissGecImportSkippedRow,
  activateGecElectionDayImport,
} from '../../lib/api';
import {
  Database,
  Upload,
  AlertTriangle,
  Loader2,
  RefreshCw,
  Calendar,
  ChevronDown,
  ChevronRight,
  ChevronLeft,
  Download,
  ExternalLink,
  FileSearch,
  X,
} from 'lucide-react';
import WorkspacePage from '../../components/WorkspacePage';

type PdfQaStatus = 'pass' | 'review' | 'fail' | 'preview';
const CAMPAIGN_TIME_ZONE = 'Pacific/Guam';

/**
 * Keep date-only values stable while displaying them in Guam time.
 * Handles: "2025-12-25", "2025-12-25T00:00:00", "2025-12-25T00:00:00Z"
 */
function formatCampaignDate(dateStr: string | null | undefined): string {
  if (!dateStr) return '—';
  let normalized = dateStr;
  if (!dateStr.includes('T')) {
    normalized = dateStr + 'T00:00:00Z';
  } else if (!/[Zz]|[+-]\d{2}:\d{2}$/.test(dateStr)) {
    normalized = dateStr + 'Z';
  }
  const d = new Date(normalized);
  return d.toLocaleDateString('en-US', { timeZone: CAMPAIGN_TIME_ZONE, year: 'numeric', month: 'numeric', day: 'numeric' });
}

function formatCampaignDateTime(dateStr: string | null | undefined): string {
  if (!dateStr) return '—';
  let normalized = dateStr;
  if (!dateStr.includes('T')) {
    normalized = dateStr + 'T00:00:00Z';
  } else if (!/[Zz]|[+-]\d{2}:\d{2}$/.test(dateStr)) {
    normalized = dateStr + 'Z';
  }
  const d = new Date(normalized);
  return d.toLocaleString('en-US', {
    timeZone: CAMPAIGN_TIME_ZONE,
    year: 'numeric',
    month: 'numeric',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit'
  });
}

function displayImportFilename(imp: Pick<ImportRecord, 'raw_filename' | 'original_filename' | 'filename'>): string {
  return imp.raw_filename || imp.original_filename || imp.filename;
}

type PreviewRow = Record<string, unknown>;
type ViewerTab = 'parsed' | 'changes' | 'skipped' | 'original';
type ImportChangeFilter = 'all' | 'new' | 'changed' | 'updated' | 'removed' | 'transferred' | 'routed_to_unassigned';
type SkippedRowFilter = 'all' | 'pending' | 'resolved' | 'dismissed';

interface PreviewPagination {
  page: number;
  per_page: number;
  total_pages: number;
  total_rows: number;
}

interface PdfPreviewData {
  source_type: 'pdf';
  qa: {
    status: PdfQaStatus;
    quality_score: number | null;
    row_count: number;
    note?: string;
    preview_mode?: boolean;
    pages_sampled?: number;
    page_count?: number;
    sample_limited?: boolean;
  };
  warnings: string[];
  row_count: number;
  available_villages?: string[];
  pagination?: PreviewPagination;
  parse_cache_key: string | null;
  preview_rows: PreviewRow[];
}

interface PdfPreviewAsyncResponse {
  async: true;
  source_type: 'pdf';
  preview_request_id: string;
  status: 'pending' | 'processing' | 'completed' | 'failed';
  error?: string;
}

interface SpreadsheetPreviewData {
  source_type: 'spreadsheet';
  sheets: string[];
  headers: string[];
  column_map: Record<string, number>;
  row_count: number;
  available_villages?: string[];
  pagination?: PreviewPagination;
  preview_rows: PreviewRow[];
}

type PreviewData = PdfPreviewData | SpreadsheetPreviewData;
type PreviewResponse = PreviewData | PdfPreviewAsyncResponse;

interface ImportRecord {
  id: number;
  gec_list_date: string;
  filename: string;
  total_records: number;
  new_records: number;
  updated_records: number;
  removed_records: number;
  transferred_records: number;
  re_vetted_count: number;
  ambiguous_dob_count: number;
  import_type: string;
  status: string;
  created_at: string;
  uploaded_by_email: string | null;
  has_import_artifact: boolean;
  has_original_file: boolean;
  has_downloadable_file: boolean;
  raw_filename: string | null;
  original_filename: string | null;
  raw_content_type: string | null;
  original_content_type: string | null;
  skipped_rows_count?: number;
  pending_skipped_rows_count?: number;
  metadata: {
    stage?: string;
    progress_percent?: number;
    pages_processed?: number;
    page_count?: number;
    matched_unchanged?: number;
    skipped?: number;
    unassigned?: number;
    review_required?: boolean;
    removal_detection_suppressed?: boolean;
    errors?: string[];
    row_error_details?: Array<{
      row_number: number;
      message: string;
      source_name?: string | null;
      voter_registration_number?: string | null;
      first_name?: string | null;
      last_name?: string | null;
      village_name?: string | null;
      birth_year?: number | string | null;
      raw_values?: string[];
    }>;
    error?: string;
    pdf_qa?: Record<string, unknown>;
    pdf_warnings?: string[];
    mode?: string;
    upload_request_id?: string;
    active_job_id?: string;
    enqueued_at?: string;
    [key: string]: unknown;
  };
  active_election_day?: boolean;
  activated_for_election_at?: string | null;
  activated_for_election_by_email?: string | null;
}

function createUploadRequestId() {
  return globalThis.crypto?.randomUUID?.() ?? `gec-upload-${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

function createPreviewRequestId() {
  return globalThis.crypto?.randomUUID?.() ?? `gec-preview-${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

function sleep(ms: number) {
  return new Promise((resolve) => window.setTimeout(resolve, ms));
}

function importMatchesUploadAttempt(
  row: ImportRecord,
  requestId: string,
  file: File,
  listDate: string,
  importType: string,
) {
  const serverAcknowledged = row.status !== 'pending' || Boolean(row.metadata?.active_job_id || row.metadata?.enqueued_at);
  if (row.metadata?.upload_request_id === requestId) return serverAcknowledged;

  const now = Date.now();
  const createdAt = Date.parse(String(row.created_at || ''));
  const isRecent = !Number.isNaN(createdAt) && now - createdAt < 10 * 60 * 1000;
  if (!isRecent) return false;

  const knownNames = [row.filename, row.raw_filename, row.original_filename].filter(Boolean).map((value) => String(value).toLowerCase());
  return knownNames.includes(file.name.toLowerCase())
    && row.gec_list_date === listDate
    && row.import_type === importType
    && serverAcknowledged
    && ['pending', 'processing', 'completed'].includes(row.status);
}

function shouldContinueImportPolling(rows: ImportRecord[]) {
  const now = Date.now();
  return rows.some((row) => {
    if (row.status === 'processing' || row.status === 'pending') return true;
    if (row.status !== 'completed') return false;
    if (row.has_import_artifact) return false;
    const createdAt = Date.parse(String(row.created_at || ''));
    if (Number.isNaN(createdAt)) return false;
    return now - createdAt < 5 * 60 * 1000;
  });
}

function getImportStageLabel(stage: string, isPdfImport: boolean): string {
  switch (stage) {
    case 'queued':
      return 'Queued';
    case 'validating_pdf':
      return 'Validating PDF';
    case 'normalizing_pdf':
      return 'Converting PDF';
    case 'parsing':
      return isPdfImport ? 'Importing Parsed Data' : 'Reading File';
    case 'importing':
      return 'Importing';
    case 'matching':
      return 'Matching Existing Voters';
    case 'detecting_changes':
      return 'Detecting Changes';
    case 're_vetting':
      return 'Re-vetting Supporters';
    case 'saving':
      return 'Saving Results';
    case 'finalizing_artifact':
      return 'Finalizing Import';
    case 'completed':
      return 'Completed';
    case 'failed':
      return 'Failed';
    default:
      return stage.replace(/_/g, ' ');
  }
}

function getImportStageMessage(
  stage: string,
  progressPercent: number,
  isPdfImport: boolean,
  metadata?: ImportRecord['metadata']
): string {
  if (progressPercent === 0 || stage === 'queued') {
    return isPdfImport
      ? 'Your PDF is queued. Full validation and import will run in the background.'
      : 'Waiting to start. You can leave this page while the import stays queued.';
  }

  switch (stage) {
    case 'validating_pdf':
      if (metadata?.page_count && typeof metadata.pages_processed === 'number') {
        return `Validated ${Number(metadata.pages_processed).toLocaleString()} of ${Number(metadata.page_count).toLocaleString()} pages. Large PDFs can take a few minutes.`;
      }
      return 'Checking the full PDF and confirming the parsed voter data before import.';
    case 'normalizing_pdf':
      return 'Converting the PDF into import-ready rows for the voter database.';
    case 'parsing':
      return isPdfImport
        ? 'Importing the parsed PDF data. You can safely leave this page.'
        : 'Reading the uploaded file and preparing rows for import.';
    case 'importing':
      return `${Math.max(5, Math.min(100, progressPercent))}% complete. Progress updates automatically.`;
    case 'matching':
      return 'Comparing this list against existing voters to find changes.';
    case 'detecting_changes':
      return 'Calculating adds, updates, transfers, and removals.';
    case 'saving':
      return 'Saving import results and finishing up.';
    case 'finalizing_artifact':
      return 'Finishing import transparency files so Imported Data and download are ready as soon as the import completes.';
    default:
      return `${Math.max(5, Math.min(100, progressPercent))}% complete. Progress updates automatically.`;
  }
}

interface ImportViewDataResponse {
  import: ImportRecord;
  preview: PreviewData;
}

interface ImportOriginalViewResponse {
  view_url: string;
  filename: string;
  content_type: string;
  inline_supported: boolean;
}

interface ImportChangeRecord {
  id: number | string;
  change_type: 'new' | 'updated' | 'removed' | 'transferred' | 'routed_to_unassigned';
  row_number: number | null;
  first_name: string | null;
  middle_name?: string | null;
  last_name: string | null;
  voter_registration_number: string | null;
  village_name: string | null;
  previous_village_name: string | null;
  birth_year: number | null;
  dob: string | null;
  details: {
    source_name?: string | null;
    reason?: string | null;
    changed_fields?: Record<string, { before: unknown; after: unknown }>;
    [key: string]: unknown;
  };
}

interface ImportChangesResponse {
  import: ImportRecord;
  changes: ImportChangeRecord[];
  counts: {
    all: number;
    new: number;
    changed: number;
    updated: number;
    removed: number;
    transferred: number;
    routed_to_unassigned: number;
  };
  filters: {
    type: ImportChangeFilter;
    q: string;
  };
  pagination: PreviewPagination;
}

interface SkippedRowResolvedVoter {
  id: number;
  first_name: string;
  last_name: string;
  village_name: string | null;
  voter_registration_number: string | null;
  birth_year: number | null;
  dob: string | null;
}

interface ImportSkippedRowRecord {
  id: number;
  row_number: number;
  message: string;
  source_name: string | null;
  first_name: string | null;
  last_name: string | null;
  voter_registration_number: string | null;
  village_name: string | null;
  birth_year: number | null;
  dob: string | null;
  raw_values: string[];
  resolution_status: 'pending' | 'resolved_created' | 'resolved_updated' | 'dismissed';
  resolution_action: 'create' | 'update' | 'dismiss' | null;
  corrected_values: Record<string, unknown>;
  resolution_details: Record<string, unknown>;
  resolved_at: string | null;
  resolved_by_email: string | null;
  resolved_gec_voter: SkippedRowResolvedVoter | null;
}

interface SkippedRowCandidateMatch {
  confidence: 'exact' | 'high' | 'medium' | 'low';
  match_type: string;
  match_count: number;
  gec_voter: SkippedRowResolvedVoter;
}

interface SkippedRowResolutionPreview {
  status: 'invalid' | 'conflict' | 'ambiguous' | 'ready_to_create' | 'ready_to_update' | 'already_resolved' | 'resolved_created' | 'resolved_updated' | 'dismissed';
  errors: string[];
  suggested_action?: 'create' | 'update' | 'dismiss';
  corrected_values: Record<string, unknown>;
  target_voter?: SkippedRowResolvedVoter | null;
  candidate_matches: SkippedRowCandidateMatch[];
}

interface ImportSkippedRowsResponse {
  import: ImportRecord;
  skipped_rows: ImportSkippedRowRecord[];
  counts: {
    all: number;
    pending: number;
    resolved: number;
    dismissed: number;
  };
  filters: {
    status: SkippedRowFilter;
    q: string;
  };
  pagination: PreviewPagination;
}

function useDebouncedValue<T>(value: T, delayMs: number) {
  const [debouncedValue, setDebouncedValue] = useState(value);

  useEffect(() => {
    const timeout = window.setTimeout(() => setDebouncedValue(value), delayMs);
    return () => window.clearTimeout(timeout);
  }, [value, delayMs]);

  return debouncedValue;
}

export default function TeamGecPage() {
  const queryClient = useQueryClient();
  const [file, setFile] = useState<File | null>(null);
  const [listDate, setListDate] = useState('');
  const [sheetName, setSheetName] = useState('');
  const [importType, setImportType] = useState<'full_list' | 'changes_only'>('full_list');
  const [previewData, setPreviewData] = useState<PreviewData | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [successMessage, setSuccessMessage] = useState<string | null>(null);
  const [confirmReview, setConfirmReview] = useState(false);
  const [pdfPreviewStatus, setPdfPreviewStatus] = useState<'idle' | 'pending' | 'processing' | 'completed' | 'failed'>('idle');
  const [expandedImportId, setExpandedImportId] = useState<number | null>(null);
  const [viewerState, setViewerState] = useState<{ importId: number } | null>(null);
  const [viewerTab, setViewerTab] = useState<ViewerTab>('parsed');
  const [viewerPage, setViewerPage] = useState(1);
  const [viewerSearchInput, setViewerSearchInput] = useState('');
  const [viewerVillageFilter, setViewerVillageFilter] = useState('');
  const [changeViewerPage, setChangeViewerPage] = useState(1);
  const [changeViewerSearchInput, setChangeViewerSearchInput] = useState('');
  const [changeViewerType, setChangeViewerType] = useState<ImportChangeFilter>('all');
  const [skippedViewerPage, setSkippedViewerPage] = useState(1);
  const [skippedViewerSearchInput, setSkippedViewerSearchInput] = useState('');
  const [skippedViewerFilter, setSkippedViewerFilter] = useState<SkippedRowFilter>('all');
  const viewerPerPage = 100;
  const skippedViewerPerPage = 25;
  const debouncedViewerSearch = useDebouncedValue(viewerSearchInput.trim(), 250);
  const debouncedChangeViewerSearch = useDebouncedValue(changeViewerSearchInput.trim(), 250);
  const debouncedSkippedViewerSearch = useDebouncedValue(skippedViewerSearchInput.trim(), 250);

  const { data: stats, isLoading: statsLoading } = useQuery({ queryKey: ['gec-stats'], queryFn: getGecStats });
  const { data: imports } = useQuery({
    queryKey: ['gec-imports'],
    queryFn: getGecImports,
    refetchInterval: (query) => {
      // Keep polling (at a slower rate) when errored — the progress banner
      // stays frozen otherwise with no indication that updates have paused.
      if (query.state.status === 'error') return 10_000;
      const data = query.state.data as { imports?: ImportRecord[] } | undefined;
      const rows = Array.isArray(data?.imports) ? data.imports : [];
      return shouldContinueImportPolling(rows) ? 3000 : false;
    }
  });

  const importRows = (imports?.imports || []) as ImportRecord[];
  const selectedImport = viewerState ? (importRows.find((imp) => imp.id === viewerState.importId) ?? null) : null;
  const selectedFileIsPdf = Boolean(file && (file.type.includes('pdf') || file.name.toLowerCase().endsWith('.pdf')));
  const effectiveSheetName = selectedFileIsPdf ? undefined : (sheetName.trim() || undefined);
  const [uploadRequestId, setUploadRequestId] = useState(() => createUploadRequestId());
  const activePreviewRequestRef = useRef<string | null>(null);

  const isPdfPreview = previewData?.source_type === 'pdf';
  const pdfStatus = isPdfPreview ? previewData.qa?.status : null;
  const pdfPreviewRequiresConfirmation = Boolean(isPdfPreview && (previewData.qa?.preview_mode || pdfStatus === 'review'));
  const reviewNeedsConfirmation = pdfPreviewRequiresConfirmation && !confirmReview;
  const activeImports = importRows.filter(
    (imp) => imp.status === 'processing' || imp.status === 'pending'
  );
  const hasActiveImport = activeImports.length > 0;
  const activeImport = activeImports.find((imp) => imp.status === 'processing') || activeImports[0];
  const activeProgress = Number(activeImport?.metadata?.progress_percent || 0);
  const activeProgressDisplay = Math.max(5, Math.min(100, activeProgress));
  const activeStage = String(activeImport?.metadata?.stage || 'processing');
  const activeImportCount = activeImports.length;
  const activeImportIsPdf = Boolean(activeImport?.raw_content_type?.includes('pdf') || activeImport?.metadata?.pdf_qa);
  const activeStageLabel = getImportStageLabel(activeStage, activeImportIsPdf);
  const activeStageMessage = getImportStageMessage(activeStage, activeProgress, activeImportIsPdf, activeImport?.metadata);

  const previouslyHadActiveImport = useRef(false);
  useEffect(() => {
    if (previouslyHadActiveImport.current && !hasActiveImport) {
      queryClient.invalidateQueries({ queryKey: ['gec-stats'] });
    }
    previouslyHadActiveImport.current = hasActiveImport;
  }, [hasActiveImport, queryClient]);

  const importViewerQuery = useQuery<ImportViewDataResponse>({
    queryKey: ['gec-import-view-data', viewerState?.importId, viewerPage, viewerPerPage, debouncedViewerSearch, viewerVillageFilter],
    queryFn: () => getGecImportViewData(viewerState!.importId, viewerPage, viewerPerPage, debouncedViewerSearch, viewerVillageFilter || undefined),
    enabled: Boolean(viewerState?.importId && selectedImport?.has_import_artifact),
    staleTime: 30_000,
    placeholderData: (previousData) => previousData,
  });

  const originalViewerQuery = useQuery<ImportOriginalViewResponse>({
    queryKey: ['gec-import-original-view', viewerState?.importId],
    queryFn: () => getGecImportOriginalView(viewerState!.importId),
    enabled: Boolean(viewerState?.importId && selectedImport?.has_original_file),
    staleTime: 60_000,
  });

  const importChangesQuery = useQuery<ImportChangesResponse>({
    queryKey: ['gec-import-changes', viewerState?.importId, changeViewerPage, viewerPerPage, changeViewerType, debouncedChangeViewerSearch],
    queryFn: () => getGecImportChanges(viewerState!.importId, changeViewerPage, viewerPerPage, changeViewerType, debouncedChangeViewerSearch || undefined),
    enabled: Boolean(viewerState?.importId && selectedImport?.status === 'completed'),
    staleTime: 30_000,
    placeholderData: (previousData) => previousData,
  });

  const importSkippedRowsQuery = useQuery<ImportSkippedRowsResponse>({
    queryKey: ['gec-import-skipped-rows', viewerState?.importId, skippedViewerPage, skippedViewerPerPage, skippedViewerFilter, debouncedSkippedViewerSearch],
    queryFn: () => getGecImportSkippedRows(viewerState!.importId, skippedViewerPage, skippedViewerPerPage, skippedViewerFilter, debouncedSkippedViewerSearch || undefined),
    enabled: Boolean(viewerState?.importId && selectedImport && (selectedImport.skipped_rows_count || selectedImport.metadata?.skipped)),
    staleTime: 15_000,
    placeholderData: (previousData) => previousData,
  });

  const resetUploadForm = () => {
    activePreviewRequestRef.current = null;
    setFile(null);
    setListDate('');
    setSheetName('');
    setImportType('full_list');
    setPreviewData(null);
    setConfirmReview(false);
    setPdfPreviewStatus('idle');
    setUploadRequestId(createUploadRequestId());
  };

  const clearPreviewState = () => {
    activePreviewRequestRef.current = null;
    setPreviewData(null);
    setConfirmReview(false);
    setPdfPreviewStatus('idle');
    setErrorMessage(null);
    setSuccessMessage(null);
  };

  const resetUploadAttempt = () => {
    clearPreviewState();
    setUploadRequestId(createUploadRequestId());
  };

  const pollPdfPreview = async (requestId: string) => {
    try {
      for (const delayMs of [1000, 1500, 2000, 2500, 3000, 4000, 5000, 5000, 5000, 5000, 5000, 5000]) {
        await sleep(delayMs);
        if (activePreviewRequestRef.current !== requestId) return;

        let data: PdfPreviewAsyncResponse | PdfPreviewData;
        try {
          data = await getGecPdfPreviewStatus(requestId) as PdfPreviewAsyncResponse | PdfPreviewData;
        } catch (fetchErr) {
          if (activePreviewRequestRef.current !== requestId) return;
          setPdfPreviewStatus('failed');
          setErrorMessage(`Preview failed: ${fetchErr instanceof Error ? fetchErr.message : 'Network error'}`);
          return;
        }

        if ('preview_rows' in data) {
          if (activePreviewRequestRef.current !== requestId) return;
          setPreviewData(data);
          setPdfPreviewStatus('completed');
          setSuccessMessage(null);
          return;
        }

        if (data.status === 'failed') {
          if (activePreviewRequestRef.current !== requestId) return;
          setPreviewData(null);
          setPdfPreviewStatus('failed');
          setErrorMessage(`Preview failed: ${data.error || 'PDF preview failed'}`);
          return;
        }

        if (activePreviewRequestRef.current !== requestId) return;
        setPdfPreviewStatus(data.status);
      }

      if (activePreviewRequestRef.current === requestId) {
        setPdfPreviewStatus('failed');
        setErrorMessage('PDF preview is taking too long. Please try again.');
      }
    } catch {
      if (activePreviewRequestRef.current === requestId) {
        setPdfPreviewStatus('failed');
        setErrorMessage('PDF preview encountered an unexpected error. Please try again.');
      }
    }
  };

  const recoverQueuedImport = async (requestId: string) => {
    if (!file || !listDate) return null;

    try {
      for (const delayMs of [500, 1500, 3000]) {
        if (delayMs > 0) await sleep(delayMs);
        const latest = await queryClient.fetchQuery<{ imports?: ImportRecord[] }>({
          queryKey: ['gec-imports'],
          queryFn: getGecImports,
          staleTime: 0,
        });
        const rows = Array.isArray(latest?.imports) ? latest.imports : [];
        const matched = rows.find((row) => importMatchesUploadAttempt(row, requestId, file, listDate, importType));
        if (matched) return matched;
      }
    } catch {
      return null;
    }

    return null;
  };

  const previewMutation = useMutation({
    mutationFn: ({ requestId }: { requestId: string }) => previewGecList(file!, effectiveSheetName, requestId),
    onMutate: ({ requestId }) => {
      clearPreviewState();
      activePreviewRequestRef.current = selectedFileIsPdf ? requestId : null;
      setErrorMessage(null);
      setSuccessMessage(null);
      setPdfPreviewStatus(selectedFileIsPdf ? 'pending' : 'idle');
    },
    onSuccess: (data: PreviewResponse, { requestId }) => {
      if ('preview_rows' in data) {
        setPreviewData(data);
        setPdfPreviewStatus('completed');
        return;
      }

      if (data.status === 'failed') {
        activePreviewRequestRef.current = null;
        setPreviewData(null);
        setPdfPreviewStatus('failed');
        setErrorMessage(`Preview failed: ${data.error || 'PDF preview failed'}`);
        return;
      }

      setPdfPreviewStatus(data.status);
      setSuccessMessage('PDF preview is running in the background. We will update this panel as soon as the sample is ready.');
      void pollPdfPreview(data.preview_request_id || requestId);
    },
    onError: (err: Error) => {
      activePreviewRequestRef.current = null;
      setPdfPreviewStatus('failed');
      setErrorMessage(`Preview failed: ${err.message}`);
    },
  });
  const isPreviewBusy = previewMutation.isPending || pdfPreviewStatus === 'pending' || pdfPreviewStatus === 'processing';

  const uploadMutation = useMutation({
    mutationFn: ({ requestId }: { requestId: string }) => uploadGecList(
      file!,
      listDate,
      effectiveSheetName,
      importType,
      isPdfPreview ? previewData.parse_cache_key || undefined : undefined,
      confirmReview,
      true,
      requestId,
    ),
    onSuccess: (data) => {
      resetUploadForm();
      setErrorMessage(null);
      queryClient.invalidateQueries({ queryKey: ['gec-imports'] });

      if (data?.async) {
        const importId = data?.import?.id;
        setSuccessMessage(
          data?.duplicate_request
            ? `Import already queued${importId ? ` (ID #${importId})` : ''}. We reused the existing background import instead of creating a duplicate.`
            : `Import queued in background${importId ? ` (ID #${importId})` : ''}. You can leave this page — progress will continue and update in Import History.`,
        );
        return;
      }

      queryClient.invalidateQueries({ queryKey: ['gec-stats'] });
      const s = data.stats;
      const lines = [
        `Import successful!`,
        ``,
        `Total processed: ${s.total}`,
        `New voters: ${s.new}`,
        `Updated: ${s.updated}`,
        s.removed ? `Purged (removed from list): ${s.removed}` : null,
        s.transferred ? `Village transfers detected: ${s.transferred}` : null,
        s.re_vetted ? `Supporters re-flagged for review: ${s.re_vetted}` : null,
        s.ambiguous_dob ? `Ambiguous DOBs: ${s.ambiguous_dob}` : null,
      ].filter(Boolean);
      setSuccessMessage(lines.join('\n'));
    },
    onError: async (err: Error, { requestId }) => {
      const recoveredImport = await recoverQueuedImport(requestId);
      if (recoveredImport) {
        resetUploadForm();
        setErrorMessage(null);
        queryClient.invalidateQueries({ queryKey: ['gec-imports'] });
        setSuccessMessage(
          `We lost the network response, but confirmed that import #${recoveredImport.id} was already queued${recoveredImport.status === 'completed' ? ' and completed' : ''}. No duplicate import was created.`,
        );
        return;
      }

      setErrorMessage(`Import failed: ${err.message}`);
    },
  });

  const bulkVetMutation = useMutation({
    mutationFn: () => bulkVetSupporters({ unverified_only: 'true' }),
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: ['vetting-queue'] });
      setErrorMessage(null);
      setSuccessMessage(`Bulk vetting complete!\n\nAuto-verified: ${data.results.auto_verified}\nFlagged: ${data.results.flagged}\nReferrals: ${data.results.referral}\nUnregistered: ${data.results.unregistered}`);
    },
    onError: (err: Error) => setErrorMessage(`Bulk vetting failed: ${err.message}`),
  });

  const activateElectionDayMutation = useMutation({
    mutationFn: (importId: number) => activateGecElectionDayImport(importId),
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: ['gec-stats'] });
      queryClient.invalidateQueries({ queryKey: ['gec-imports'] });
      setErrorMessage(null);
      const activatedImport = data?.import as ImportRecord | undefined;
      setSuccessMessage(
        activatedImport
          ? `Election-day GEC list set to import #${activatedImport.id} from ${formatCampaignDate(activatedImport.gec_list_date)}.`
          : 'Election-day GEC list updated.'
      );
    },
    onError: (err: Error) => setErrorMessage(`Could not set election-day list: ${err.message}`),
  });

  const openViewer = (imp: ImportRecord) => {
    const initialTab: ViewerTab = imp.has_import_artifact
      ? 'parsed'
      : (imp.pending_skipped_rows_count || imp.skipped_rows_count || imp.metadata?.skipped)
      ? 'skipped'
      : imp.status === 'completed'
      ? 'changes'
      : imp.has_original_file
      ? 'original'
      : 'parsed';
    setViewerTab(initialTab);
    setViewerPage(1);
    setViewerSearchInput('');
    setViewerVillageFilter('');
    setChangeViewerPage(1);
    setChangeViewerSearchInput('');
    setChangeViewerType('all');
    setSkippedViewerPage(1);
    setSkippedViewerSearchInput('');
    setSkippedViewerFilter('all');
    setViewerState({ importId: imp.id });
  };

  const closeViewer = () => {
    setViewerState(null);
    setViewerTab('parsed');
    setViewerPage(1);
    setViewerSearchInput('');
    setViewerVillageFilter('');
    setChangeViewerPage(1);
    setChangeViewerSearchInput('');
    setChangeViewerType('all');
    setSkippedViewerPage(1);
    setSkippedViewerSearchInput('');
    setSkippedViewerFilter('all');
  };

  return (
    <WorkspacePage width="full" className="space-y-6">
      <div>
        <h1 className="text-xl font-bold text-gray-900">GEC Voter List</h1>
        <p className="text-sm text-gray-500 mt-0.5">Manage the Guam Election Commission voter registration data</p>
      </div>

      {/* Current Status */}
      <div className="bg-white rounded-xl border border-gray-200 p-5">
        <h2 className="text-sm font-semibold text-gray-700 mb-4 flex items-center gap-2">
          <Database className="w-4 h-4 text-blue-500" />
          Current Status
        </h2>
        {statsLoading ? (
          <div className="animate-pulse h-20 bg-gray-100 rounded-lg" />
        ) : stats?.total_voters ? (
          <>
          <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-8 gap-x-6 gap-y-4">
            <div className="min-w-0">
              <div className="text-2xl font-bold text-gray-900 whitespace-nowrap">{(stats.total_voters || 0).toLocaleString()}</div>
              <div className="text-xs text-gray-400">Active Voters</div>
            </div>
            <div className="min-w-0">
              <div className="text-2xl font-bold text-gray-900 whitespace-nowrap">
                {Number(stats.official_village_count ?? (stats.villages?.filter((v: { name: string }) => v.name !== 'Unassigned').length || 0)).toLocaleString()}
              </div>
              <div className="text-xs text-gray-400">Official Villages</div>
            </div>
            <div className="min-w-0">
              <div className="text-2xl font-bold text-gray-900 whitespace-nowrap">{formatCampaignDate(stats.latest_list_date)}</div>
              <div className="text-xs text-gray-400">List Date</div>
            </div>
            <div className="min-w-0">
              <div className={`text-2xl font-bold whitespace-nowrap ${stats.active_election_day_import ? 'text-green-700' : 'text-amber-600'}`}>
                {stats.active_election_day_import ? formatCampaignDate(stats.election_day_list_date) : 'Fallback'}
              </div>
              <div className="text-xs text-gray-400">Election-Day List</div>
            </div>
            <div className="min-w-0">
              <div className={`text-2xl font-bold whitespace-nowrap ${stats.removed_voters > 0 ? 'text-red-600' : 'text-gray-900'}`}>
                {stats.removed_voters || 0}
              </div>
              <div className="text-xs text-gray-400">Current Removed GEC Voters</div>
            </div>
            <div className="min-w-0">
              <div className={`text-2xl font-bold whitespace-nowrap ${stats.transferred_voters > 0 ? 'text-blue-600' : 'text-gray-900'}`}>
                {stats.transferred_voters || 0}
              </div>
              <div className="text-xs text-gray-400">Transfers</div>
            </div>
            <div className="min-w-0">
              <div className={`text-2xl font-bold whitespace-nowrap ${stats.ambiguous_dob_count > 0 ? 'text-amber-600' : 'text-gray-900'}`}>
                {stats.ambiguous_dob_count || 0}
              </div>
              <div className="text-xs text-gray-400">Ambiguous DOBs</div>
            </div>
            <div className="min-w-0">
              <div className={`text-2xl font-bold whitespace-nowrap ${stats.unassigned_gec_voters > 0 ? 'text-amber-600' : 'text-gray-900'}`}>
                {stats.unassigned_gec_voters || 0}
              </div>
              <div className="text-xs text-gray-400">Unassigned GEC Voters</div>
            </div>
          </div>

          {/* Last import change summary */}
          <ChangeSummary summary={stats.last_change_summary} />
          {stats.active_election_day_import ? (
            <div className="mt-3 rounded-lg border border-green-200 bg-green-50 px-3 py-2 text-xs text-green-800">
              Election-day voter list is explicitly set to import #{stats.active_election_day_import.id}
              {stats.active_election_day_import.activated_for_election_at
                ? `, activated ${formatCampaignDateTime(stats.active_election_day_import.activated_for_election_at)}`
                : ''}
              .
            </div>
          ) : (
            <div className="mt-3 rounded-lg border border-amber-200 bg-amber-50 px-3 py-2 text-xs text-amber-800">
              No completed import is explicitly set for election day. Poll watcher and war room tools are using the latest active GEC list date until an import is activated.
            </div>
          )}
          <div className="mt-2 text-xs text-gray-500">
            `Current Removed GEC Voters` and `Unassigned GEC Voters` show the current live totals. `Last Import Changes` below shows what changed during the latest import only.
          </div>
          </>
        ) : (
          <div className="flex items-start gap-3 p-4 bg-amber-50 border border-amber-100 rounded-lg">
            <AlertTriangle className="w-5 h-5 text-amber-500 shrink-0 mt-0.5" />
            <div>
              <p className="text-sm font-medium text-amber-800">No GEC data loaded</p>
              <p className="text-xs text-amber-600 mt-0.5">Upload the GEC voter registration list below to enable auto-vetting.</p>
            </div>
          </div>
        )}
      </div>

      {activeImport && (
        <div className="bg-blue-50 border border-blue-200 rounded-xl p-4">
          <div className="flex items-center justify-between gap-3 mb-2">
            <div className="text-sm font-semibold text-blue-900">
              {activeImportCount > 1 ? `${activeImportCount} imports in progress` : 'Background import in progress'}
            </div>
            <div className="text-xs text-blue-700">{activeStageLabel}</div>
          </div>
          <div className="w-full h-2 bg-blue-100 rounded-full overflow-hidden">
            <div className="h-full bg-blue-600 transition-all" style={{ width: `${activeProgressDisplay}%` }} />
          </div>
          <div className="mt-2 text-xs text-blue-700">
            {activeStageMessage}
          </div>
        </div>
      )}

      {/* Upload */}
      <div className="bg-white rounded-xl border border-gray-200 p-5">
        <h2 className="text-sm font-semibold text-gray-700 mb-4 flex items-center gap-2">
          <Upload className="w-4 h-4 text-green-500" />
          Upload New GEC List
        </h2>
        <div className="space-y-4">
          <div>
            <label className="text-xs font-medium text-gray-600 block mb-1">Excel / PDF File</label>
            <input
              type="file"
              accept=".xlsx,.xls,.csv,.pdf"
              onChange={e => {
                const nextFile = e.target.files?.[0] || null;
                setFile(nextFile);
                if (nextFile && (nextFile.type.includes('pdf') || nextFile.name.toLowerCase().endsWith('.pdf'))) {
                  setSheetName('');
                }
                resetUploadAttempt();
                setErrorMessage(null);
                setSuccessMessage(null);
              }}
              className="w-full text-sm border border-gray-200 rounded-lg p-2 file:mr-3 file:py-1 file:px-3 file:rounded-lg file:border-0 file:text-xs file:font-medium file:bg-blue-50 file:text-blue-700 hover:file:bg-blue-100"
            />
          </div>
          <div>
            <label className="text-xs font-medium text-gray-600 block mb-1.5">Import Type</label>
            <div className="flex gap-3">
              <label className={`flex items-center gap-2 px-4 py-2.5 rounded-lg border cursor-pointer transition-colors ${importType === 'full_list' ? 'border-blue-500 bg-blue-50 text-blue-700' : 'border-gray-200 text-gray-600 hover:bg-gray-50'}`}>
                <input type="radio" name="importType" value="full_list" checked={importType === 'full_list'} onChange={() => { setImportType('full_list'); resetUploadAttempt(); }} className="sr-only" />
                <Database className="w-4 h-4" />
                <div>
                  <div className="text-sm font-medium">Full Voter List</div>
                  <div className="text-[10px] opacity-70">Detects purges &amp; transfers</div>
                </div>
              </label>
              <label className={`flex items-center gap-2 px-4 py-2.5 rounded-lg border cursor-pointer transition-colors ${importType === 'changes_only' ? 'border-blue-500 bg-blue-50 text-blue-700' : 'border-gray-200 text-gray-600 hover:bg-gray-50'}`}>
                <input type="radio" name="importType" value="changes_only" checked={importType === 'changes_only'} onChange={() => { setImportType('changes_only'); resetUploadAttempt(); }} className="sr-only" />
                <RefreshCw className="w-4 h-4" />
                <div>
                  <div className="text-sm font-medium">Changes Only</div>
                  <div className="text-[10px] opacity-70">Adds/updates only, no purge detection</div>
                </div>
              </label>
            </div>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="text-xs font-medium text-gray-600 block mb-1">GEC List Date</label>
              <input
                type="date"
                value={listDate}
                onChange={e => { setListDate(e.target.value); resetUploadAttempt(); }}
                className="w-full px-3 py-2 text-sm border border-gray-200 rounded-lg focus:ring-2 focus:ring-blue-500"
              />
            </div>
            <div>
              <label className="text-xs font-medium text-gray-600 block mb-1">Sheet Name (optional)</label>
              <input
                type="text"
                value={sheetName}
                onChange={e => { setSheetName(e.target.value); resetUploadAttempt(); }}
                placeholder={selectedFileIsPdf ? 'Not used for PDF imports' : 'e.g., Voter List'}
                disabled={selectedFileIsPdf}
                className={`w-full px-3 py-2 text-sm border border-gray-200 rounded-lg focus:ring-2 focus:ring-blue-500 ${
                  selectedFileIsPdf ? 'bg-gray-100 text-gray-400 cursor-not-allowed' : ''
                }`}
              />
              {selectedFileIsPdf && (
                <div className="mt-1 text-[11px] text-gray-500">
                  PDF imports do not have worksheet tabs, so sheet names are ignored.
                </div>
              )}
            </div>
          </div>
          <div className="flex flex-wrap gap-2">
            <button
              onClick={() => {
                const requestId = createPreviewRequestId();
                previewMutation.mutate({ requestId });
              }}
              disabled={!file || isPreviewBusy || uploadMutation.isPending}
              className="flex items-center gap-2 px-4 py-2 bg-white border border-gray-300 text-gray-700 text-sm font-medium rounded-lg hover:bg-gray-50 disabled:opacity-50 transition-colors"
            >
              {isPreviewBusy ? <Loader2 className="w-4 h-4 animate-spin" /> : <Database className="w-4 h-4" />}
              {isPreviewBusy ? 'Analyzing...' : 'Analyze File'}
            </button>
            <button
              onClick={() => uploadMutation.mutate({ requestId: uploadRequestId })}
              disabled={!file || !listDate || !previewData || uploadMutation.isPending || pdfStatus === 'fail' || reviewNeedsConfirmation}
              className="flex items-center gap-2 px-4 py-2 bg-green-600 text-white text-sm font-medium rounded-lg hover:bg-green-700 disabled:opacity-50 transition-colors"
              title={!previewData ? 'Analyze file first to review before importing' : undefined}
            >
              {uploadMutation.isPending ? <Loader2 className="w-4 h-4 animate-spin" /> : <Upload className="w-4 h-4" />}
              {uploadMutation.isPending ? 'Uploading...' : 'Confirm & Import'}
            </button>
          </div>

          {file && !previewData && !isPreviewBusy && (
            <div className="text-xs text-gray-500">
              Click "Analyze File" to preview the data before importing.
            </div>
          )}

          {selectedFileIsPdf && isPreviewBusy && !previewData && (
            <div className="rounded-lg border border-blue-200 bg-blue-50 px-3 py-2 text-xs text-blue-800">
              PDF preview is running in the background so the web service does not have to parse the PDF inline. This can take a little longer, but it is much safer for large files.
            </div>
          )}

          {errorMessage && (
            <div className="rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-xs text-red-700 whitespace-pre-line">
              {errorMessage}
            </div>
          )}

          {successMessage && (
            <div className="rounded-lg border border-green-200 bg-green-50 px-3 py-2 text-xs text-green-700 whitespace-pre-line">
              {successMessage}
            </div>
          )}

          {previewData && (
            <div className="rounded-lg border border-gray-200 p-3 bg-gray-50 space-y-3">
              {previewData.source_type === 'pdf' ? (
                <>
                  <div className="space-y-2 text-sm">
                    <div className="font-semibold text-gray-800">PDF Preview Summary</div>
                    <div className="text-gray-700">Rows sampled: <strong>{Number(previewData.row_count || 0).toLocaleString()}</strong></div>
                    <div className="text-gray-700">
                      Quality score: <strong>{previewData.qa?.preview_mode ? 'Calculated during full import' : (previewData.qa?.quality_score ?? 'Unavailable')}</strong>
                    </div>
                    <div className="text-gray-700">Status: <strong className={`uppercase ${
                      previewData.qa?.status === 'fail'
                        ? 'text-red-600'
                        : previewData.qa?.status === 'review'
                        ? 'text-amber-600'
                        : previewData.qa?.status === 'preview'
                        ? 'text-blue-600'
                        : 'text-green-600'
                    }`}>{previewData.qa?.status ?? 'unknown'}</strong></div>

                    {previewData.qa?.preview_mode && (
                      <div className="rounded-md border border-blue-200 bg-blue-50 px-2 py-2 text-xs text-blue-800">
                        {previewData.qa?.note ?? 'This is a fast sample preview. Full PDF validation runs during import.'}
                        {previewData.qa?.pages_sampled && previewData.qa?.page_count ? ` Sampled ${previewData.qa.pages_sampled} of ${previewData.qa.page_count} pages.` : ''}
                      </div>
                    )}

                    {pdfPreviewRequiresConfirmation && (
                      <label className="flex items-center gap-2 text-xs text-amber-800 bg-amber-50 border border-amber-200 rounded-md px-2 py-2">
                        <input
                          type="checkbox"
                          checked={confirmReview}
                          onChange={e => setConfirmReview(e.target.checked)}
                        />
                        {previewData.qa?.preview_mode
                          ? 'I understand this is a sample preview and want to proceed with the background import even if full PDF validation later needs manual review.'
                          : 'I reviewed this PDF preview and want to proceed with import.'}
                      </label>
                    )}

                    {previewData.warnings.length > 0 && (
                      <ul className="list-disc pl-5 text-amber-700 text-xs">
                        {previewData.warnings.map((w, i) => <li key={i}>{w}</li>)}
                      </ul>
                    )}
                  </div>
                  {previewData.preview_rows.length > 0 && (
                    <div>
                      <div className="text-xs font-semibold text-gray-500 uppercase mb-1">Sample Rows (first {previewData.preview_rows.length})</div>
                      <div className="overflow-x-auto">
                        <table className="w-full text-xs border-collapse">
                          <thead>
                            <tr className="bg-gray-100">
                              <th className="text-left px-2 py-1 text-gray-500 font-medium">Reg No.</th>
                              <th className="text-left px-2 py-1 text-gray-500 font-medium">Name</th>
                              <th className="text-left px-2 py-1 text-gray-500 font-medium">Address</th>
                              <th className="text-left px-2 py-1 text-gray-500 font-medium">Village</th>
                              <th className="text-left px-2 py-1 text-gray-500 font-medium">Precinct</th>
                              <th className="text-left px-2 py-1 text-gray-500 font-medium">Birth Year</th>
                            </tr>
                          </thead>
                          <tbody>
                            {previewData.preview_rows.map((row, i) => (
                              <tr key={i} className="border-t border-gray-200">
                                <td className="px-2 py-1 text-gray-600">{String(row.voter_registration_number ?? '')}</td>
                                <td className="px-2 py-1 text-gray-800">{String(row.name ?? '')}</td>
                                <td className="px-2 py-1 text-gray-600">{String(row.address ?? '')}</td>
                                <td className="px-2 py-1 text-gray-600">{String(row.village ?? '')}</td>
                                <td className="px-2 py-1 text-gray-600">{String(row.precinct_number ?? '')}</td>
                                <td className="px-2 py-1 text-gray-600">{String(row.birth_year ?? '')}</td>
                              </tr>
                            ))}
                          </tbody>
                        </table>
                      </div>
                    </div>
                  )}
                </>
              ) : (
                <div className="space-y-2">
                  <div className="text-sm font-semibold text-gray-800">Spreadsheet Preview</div>
                  <div className="text-sm text-gray-700">
                    Rows detected: <strong>{Number(previewData.row_count || 0).toLocaleString()}</strong>
                    {previewData.sheets?.length > 1 && (
                      <span className="ml-2 text-gray-500">({previewData.sheets.length} sheets)</span>
                    )}
                  </div>
                  {previewData.column_map && Object.keys(previewData.column_map).length > 0 && (
                    <div className="text-xs text-gray-600">
                      <span className="font-medium">Columns mapped:</span>{' '}
                      {Object.entries(previewData.column_map).map(([key, val]) =>
                        `${key} → ${val}`).join(', ')}
                    </div>
                  )}
                  {previewData.preview_rows?.length > 0 && (
                    <div>
                      <div className="text-xs font-semibold text-gray-500 uppercase mb-1">Sample Rows (first {previewData.preview_rows.length})</div>
                      <div className="overflow-x-auto">
                        <table className="w-full text-xs border-collapse">
                          <thead>
                            <tr className="bg-gray-100">
                              <th className="text-left px-2 py-1 text-gray-500 font-medium">First Name</th>
                              <th className="text-left px-2 py-1 text-gray-500 font-medium">Last Name</th>
                              <th className="text-left px-2 py-1 text-gray-500 font-medium">Address</th>
                              <th className="text-left px-2 py-1 text-gray-500 font-medium">Village</th>
                              <th className="text-left px-2 py-1 text-gray-500 font-medium">Precinct</th>
                              <th className="text-left px-2 py-1 text-gray-500 font-medium">DOB / Year</th>
                              <th className="text-left px-2 py-1 text-gray-500 font-medium">Reg No.</th>
                            </tr>
                          </thead>
                          <tbody>
                            {previewData.preview_rows.map((row, i) => (
                              <tr key={i} className="border-t border-gray-200">
                                <td className="px-2 py-1 text-gray-800">{String(row.first_name ?? '')}</td>
                                <td className="px-2 py-1 text-gray-800">{String(row.last_name ?? '')}</td>
                                <td className="px-2 py-1 text-gray-600">{String(row.address ?? '')}</td>
                                <td className="px-2 py-1 text-gray-600">{String(row.village_name ?? '')}</td>
                                <td className="px-2 py-1 text-gray-600">{String(row.precinct_number ?? '')}</td>
                                <td className="px-2 py-1 text-gray-600">{String(row.dob ?? row.birth_year ?? '')}</td>
                                <td className="px-2 py-1 text-gray-600">{String(row.voter_registration_number ?? '')}</td>
                              </tr>
                            ))}
                          </tbody>
                        </table>
                      </div>
                    </div>
                  )}
                </div>
              )}
            </div>
          )}
        </div>
      </div>

      {/* Bulk Vet */}
      {stats?.total_voters > 0 && (
        <div className="bg-white rounded-xl border border-gray-200 p-5">
          <h2 className="text-sm font-semibold text-gray-700 mb-2 flex items-center gap-2">
            <RefreshCw className="w-4 h-4 text-blue-500" />
            Re-vet Existing Supporters
          </h2>
          <p className="text-xs text-gray-500 mb-4">Run auto-vetting on all unverified supporters against the current GEC list. Useful after uploading a new list.</p>
          <button
            onClick={() => bulkVetMutation.mutate()}
            disabled={bulkVetMutation.isPending}
            className="flex items-center gap-2 px-4 py-2 bg-blue-600 text-white text-sm font-medium rounded-lg hover:bg-blue-700 disabled:opacity-50 transition-colors"
          >
            {bulkVetMutation.isPending ? <Loader2 className="w-4 h-4 animate-spin" /> : <RefreshCw className="w-4 h-4" />}
            {bulkVetMutation.isPending ? 'Vetting...' : 'Bulk Vet Unverified Supporters'}
          </button>
        </div>
      )}

      {/* Import History */}
      {importRows.length > 0 && (
        <div className="bg-white rounded-xl border border-gray-200 p-5">
          <h2 className="text-sm font-semibold text-gray-700 mb-4 flex items-center gap-2">
            <Calendar className="w-4 h-4 text-gray-500" />
            Import History
          </h2>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-gray-100">
                  <th className="w-6 py-2 px-1"></th>
                  <th className="text-left py-2 px-3 text-xs font-semibold text-gray-400 uppercase">Date</th>
                  <th className="text-left py-2 px-3 text-xs font-semibold text-gray-400 uppercase">File</th>
                  <th className="text-right py-2 px-3 text-xs font-semibold text-gray-400 uppercase">Total</th>
                  <th className="text-right py-2 px-3 text-xs font-semibold text-gray-400 uppercase">New</th>
                  <th className="text-right py-2 px-3 text-xs font-semibold text-gray-400 uppercase">Updated</th>
                  <th className="text-right py-2 px-3 text-xs font-semibold text-gray-400 uppercase">Removed</th>
                  <th className="text-right py-2 px-3 text-xs font-semibold text-gray-400 uppercase">Transfers</th>
                  <th className="text-left py-2 px-3 text-xs font-semibold text-gray-400 uppercase">Imported At</th>
                  <th className="text-left py-2 px-3 text-xs font-semibold text-gray-400 uppercase">Imported By</th>
                  <th className="text-left py-2 px-3 text-xs font-semibold text-gray-400 uppercase">Type</th>
                  <th className="text-left py-2 px-3 text-xs font-semibold text-gray-400 uppercase">Status</th>
                </tr>
              </thead>
              <tbody>
                {importRows.map((imp) => {
                  const isExpanded = expandedImportId === imp.id;
                  const meta = imp.metadata || {};
                  const matchedUnchanged = Number(meta.matched_unchanged || 0);
                  const errors = meta.errors as string[] | undefined;
                  const rowErrorDetails = meta.row_error_details as ImportRecord['metadata']['row_error_details'];
                  const errorMsg = meta.error as string | undefined;
                  const skipped = Number(meta.skipped || 0);
                  const unassigned = Number(meta.unassigned || 0);

                  return (
                    <React.Fragment key={imp.id}>
                    <tr
                      className={`border-b border-gray-50 cursor-pointer hover:bg-gray-50 transition-colors ${isExpanded ? 'bg-gray-50' : ''}`}
                      onClick={() => setExpandedImportId(isExpanded ? null : imp.id)}
                    >
                      <td className="py-2 px-1 text-gray-400">
                        {isExpanded ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4" />}
                      </td>
                      <td className="py-2 px-3 text-gray-600">{formatCampaignDate(imp.gec_list_date)}</td>
                      <td className="py-2 px-3 text-gray-600 text-xs">{displayImportFilename(imp)}</td>
                      <td className="py-2 px-3 text-right font-medium">{(imp.total_records || 0).toLocaleString()}</td>
                      <td className="py-2 px-3 text-right text-green-600">{imp.new_records}</td>
                      <td className="py-2 px-3 text-right text-blue-600">{imp.updated_records}</td>
                      <td className="py-2 px-3 text-right text-red-600">{imp.removed_records || 0}</td>
                      <td className="py-2 px-3 text-right text-blue-600">{imp.transferred_records || 0}</td>
                      <td className="py-2 px-3 text-gray-500 text-xs whitespace-nowrap">{formatCampaignDateTime(imp.created_at)}</td>
                      <td className="py-2 px-3 text-gray-500 text-xs">{imp.uploaded_by_email || '—'}</td>
                      <td className="py-2 px-3">
                        <span className="text-xs text-gray-500">{imp.import_type?.replace(/_/g, ' ')}</span>
                      </td>
                      <td className="py-2 px-3">
                        <span className={`text-xs font-medium px-2 py-0.5 rounded-full ${
                          imp.status === 'completed'
                            ? 'bg-green-50 text-green-700'
                            : (imp.status === 'processing' || imp.status === 'pending')
                            ? 'bg-amber-50 text-amber-700'
                            : 'bg-red-50 text-red-700'
                        }`}>
                          {imp.status}
                        </span>
                      </td>
                    </tr>
                    {isExpanded && (
                      <tr key={`${imp.id}-detail`}>
                        <td colSpan={12} className="p-0">
                          <ImportDetailPanel
                            imp={imp}
                            matchedUnchanged={matchedUnchanged}
                            skipped={skipped}
                            unassigned={unassigned}
                            errors={errors}
                            rowErrorDetails={rowErrorDetails}
                            errorMsg={errorMsg}
                            onOpenViewer={openViewer}
                            onActivateElectionDay={(importId) => activateElectionDayMutation.mutate(importId)}
                            activatingElectionDay={activateElectionDayMutation.isPending}
                          />
                        </td>
                      </tr>
                    )}
                    </React.Fragment>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}
      {viewerState && selectedImport && (
        <ImportViewerModal
          imp={selectedImport}
          viewerTab={viewerTab}
          onChangeTab={setViewerTab}
          onClose={closeViewer}
          importViewData={importViewerQuery.data}
          importViewLoading={importViewerQuery.isLoading}
          importViewError={importViewerQuery.error instanceof Error ? importViewerQuery.error.message : null}
          originalViewData={originalViewerQuery.data}
          originalViewLoading={originalViewerQuery.isLoading}
          originalViewError={originalViewerQuery.error instanceof Error ? originalViewerQuery.error.message : null}
          onPageChange={setViewerPage}
          changeViewData={importChangesQuery.data}
          changeViewLoading={importChangesQuery.isLoading}
          changeViewFetching={importChangesQuery.isFetching}
          changeViewError={importChangesQuery.error instanceof Error ? importChangesQuery.error.message : null}
          onChangePage={setChangeViewerPage}
          skippedRowsData={importSkippedRowsQuery.data}
          skippedRowsLoading={importSkippedRowsQuery.isLoading}
          skippedRowsError={importSkippedRowsQuery.error instanceof Error ? importSkippedRowsQuery.error.message : null}
          onSkippedRowsPageChange={setSkippedViewerPage}
          viewerSearchInput={viewerSearchInput}
          onViewerSearchInputChange={(value) => {
            setViewerPage(1);
            setViewerSearchInput(value);
          }}
          viewerVillageFilter={viewerVillageFilter}
          onViewerVillageFilterChange={(value) => {
            setViewerPage(1);
            setViewerVillageFilter(value);
          }}
          changeViewerSearchInput={changeViewerSearchInput}
          onChangeViewerSearchInputChange={(value) => {
            setChangeViewerPage(1);
            setChangeViewerSearchInput(value);
          }}
          changeViewerType={changeViewerType}
          onChangeViewerTypeChange={(value) => {
            setChangeViewerPage(1);
            setChangeViewerType(value);
          }}
          skippedViewerSearchInput={skippedViewerSearchInput}
          onSkippedViewerSearchInputChange={(value) => {
            setSkippedViewerPage(1);
            setSkippedViewerSearchInput(value);
          }}
          skippedViewerFilter={skippedViewerFilter}
          onSkippedViewerFilterChange={(value) => {
            setSkippedViewerPage(1);
            setSkippedViewerFilter(value);
          }}
        />
      )}
    </WorkspacePage>
  );
}

function ImportDetailPanel({
  imp,
  matchedUnchanged,
  skipped,
  unassigned,
  errors,
  rowErrorDetails,
  errorMsg,
  onOpenViewer,
  onActivateElectionDay,
  activatingElectionDay,
}: {
  imp: ImportRecord;
  matchedUnchanged: number;
  skipped: number;
  unassigned: number;
  errors?: string[];
  rowErrorDetails?: ImportRecord['metadata']['row_error_details'];
  errorMsg?: string;
  onOpenViewer: (imp: ImportRecord) => void;
  onActivateElectionDay: (importId: number) => void;
  activatingElectionDay: boolean;
}) {
  return (
    <div className="px-6 py-4 bg-gray-50 border-t border-gray-100">
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
        {/* Info */}
        <div className="space-y-1.5">
          <div className="text-[10px] font-semibold text-gray-400 uppercase tracking-wider">Import Details</div>
          <div className="text-xs text-gray-600">
            <span className="font-medium">Imported at:</span> {formatCampaignDateTime(imp.created_at)}
          </div>
          <div className="text-xs text-gray-600">
            <span className="font-medium">Imported by:</span> {imp.uploaded_by_email || '—'}
          </div>
          <div className="text-xs text-gray-600">
            <span className="font-medium">Filename:</span> {displayImportFilename(imp)}
          </div>
          <div className="text-xs text-gray-600">
            <span className="font-medium">List date:</span> {formatCampaignDate(imp.gec_list_date)}
          </div>
          <div className="text-xs text-gray-600">
            <span className="font-medium">Type:</span> {imp.import_type?.replace(/_/g, ' ')}
          </div>
        </div>

        {/* Breakdown */}
        <div className="space-y-1.5">
          <div className="text-[10px] font-semibold text-gray-400 uppercase tracking-wider">Breakdown</div>
          <div className="text-xs text-gray-600">Total processed: <strong>{(imp.total_records || 0).toLocaleString()}</strong></div>
          <div className="text-xs text-green-700">New records: <strong>{imp.new_records}</strong></div>
          <div className="text-xs text-blue-700">
            Updated records: <strong>{imp.updated_records}</strong>
            {matchedUnchanged > 0 && (
              <span className="text-gray-500 ml-1">({matchedUnchanged.toLocaleString()} matched unchanged)</span>
            )}
          </div>
          <div className="text-xs text-red-700">Removed / purged: <strong>{imp.removed_records || 0}</strong></div>
          <div className="text-xs text-indigo-700">Transferred villages: <strong>{imp.transferred_records || 0}</strong></div>
          <div className="text-xs text-gray-600">Re-vetted supporters: <strong>{imp.re_vetted_count || 0}</strong></div>
        </div>

        {/* Extra stats */}
        <div className="space-y-1.5">
          <div className="text-[10px] font-semibold text-gray-400 uppercase tracking-wider">Additional</div>
          <div className="text-xs text-amber-700">Ambiguous DOBs: <strong>{imp.ambiguous_dob_count || 0}</strong></div>
          {imp.active_election_day && (
            <div className="text-xs text-green-700">
              Active election-day list
              {imp.activated_for_election_at ? ` since ${formatCampaignDateTime(imp.activated_for_election_at)}` : ''}
            </div>
          )}
          {skipped > 0 && <div className="text-xs text-gray-600">Skipped rows: <strong>{skipped}</strong></div>}
          {(imp.pending_skipped_rows_count || 0) > 0 && <div className="text-xs text-amber-700">Pending skipped-row review: <strong>{imp.pending_skipped_rows_count}</strong></div>}
          {imp.metadata?.review_required && <div className="text-xs text-amber-700">Review required: this import has unresolved rows that need staff attention.</div>}
          {imp.metadata?.removal_detection_suppressed && <div className="text-xs text-amber-700">Removal detection was safely suppressed because unresolved rows could make purge results unreliable.</div>}
          {unassigned > 0 && <div className="text-xs text-gray-600">Routed to Unassigned in this import: <strong>{unassigned}</strong></div>}
          {(imp.has_import_artifact || imp.has_original_file) && (
            <div className="mt-2">
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  onOpenViewer(imp);
                }}
                className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-blue-700 bg-blue-50 border border-blue-200 rounded-lg hover:bg-blue-100 transition-colors"
              >
                <FileSearch className="w-3.5 h-3.5" />
                {skipped > 0 ? 'Open Import & Review Skipped Rows' : 'Open Import'}
              </button>
            </div>
          )}
          {imp.status === 'completed' && (
            <div className="mt-2">
              <button
                type="button"
                onClick={(e) => {
                  e.stopPropagation();
                  onActivateElectionDay(imp.id);
                }}
                disabled={Boolean(imp.active_election_day) || activatingElectionDay}
                className={`flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium border rounded-lg transition-colors ${
                  imp.active_election_day
                    ? 'text-green-700 bg-green-50 border-green-200'
                    : 'text-gray-700 bg-white border-gray-200 hover:bg-gray-50 disabled:opacity-60'
                }`}
              >
                {activatingElectionDay ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Calendar className="w-3.5 h-3.5" />}
                {imp.active_election_day ? 'Election-Day List' : 'Use For Election Day'}
              </button>
            </div>
          )}
        </div>
      </div>

      {/* Errors */}
      {errorMsg && (
        <div className="mt-3 rounded-md border border-red-200 bg-red-50 px-3 py-2 text-xs text-red-700">
          <span className="font-medium">Error:</span> {errorMsg}
        </div>
      )}
      {errors && errors.length > 0 && (
        <div className="mt-3 rounded-md border border-amber-200 bg-amber-50 px-3 py-2">
          <div className="text-[10px] font-semibold text-amber-600 uppercase mb-1">Row Errors ({errors.length})</div>
          <ul className="text-xs text-amber-700 space-y-0.5 max-h-32 overflow-y-auto">
            {errors.map((err, i) => <li key={i}>{err}</li>)}
          </ul>
          {rowErrorDetails && rowErrorDetails.length > 0 && (
            <div className="mt-3 space-y-2">
              {rowErrorDetails.map((detail) => (
                <div key={`${detail.row_number}-${detail.message}`} className="rounded-md border border-amber-200 bg-white/70 px-3 py-2 text-xs text-amber-900">
                  <div className="font-medium">Row {detail.row_number}</div>
                  <div className="mt-0.5">{detail.message}</div>
                  {detail.source_name && (
                    <div className="mt-1 text-amber-800">
                      Source name: <strong>{detail.source_name}</strong>
                    </div>
                  )}
                  <div className="mt-1 flex flex-wrap gap-x-3 gap-y-1 text-amber-800">
                    {detail.first_name && <span>First: <strong>{detail.first_name}</strong></span>}
                    {detail.last_name && <span>Last: <strong>{detail.last_name}</strong></span>}
                    {detail.voter_registration_number && <span>Reg No.: <strong>{detail.voter_registration_number}</strong></span>}
                    {detail.village_name && <span>Village: <strong>{detail.village_name}</strong></span>}
                    {detail.birth_year && <span>Birth year: <strong>{detail.birth_year}</strong></span>}
                  </div>
                  {detail.raw_values && detail.raw_values.length > 0 && (
                    <div className="mt-1 text-amber-800">
                      Raw row: <strong>{detail.raw_values.join(' | ')}</strong>
                    </div>
                  )}
                </div>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function ImportViewerModal({
  imp,
  viewerTab,
  onChangeTab,
  onClose,
  importViewData,
  importViewLoading,
  importViewError,
  originalViewData,
  originalViewLoading,
  originalViewError,
  onPageChange,
  changeViewData,
  changeViewLoading,
  changeViewFetching,
  changeViewError,
  onChangePage,
  skippedRowsData,
  skippedRowsLoading,
  skippedRowsError,
  onSkippedRowsPageChange,
  viewerSearchInput,
  onViewerSearchInputChange,
  viewerVillageFilter,
  onViewerVillageFilterChange,
  changeViewerSearchInput,
  onChangeViewerSearchInputChange,
  changeViewerType,
  onChangeViewerTypeChange,
  skippedViewerSearchInput,
  onSkippedViewerSearchInputChange,
  skippedViewerFilter,
  onSkippedViewerFilterChange,
}: {
  imp: ImportRecord;
  viewerTab: ViewerTab;
  onChangeTab: (tab: ViewerTab) => void;
  onClose: () => void;
  importViewData?: ImportViewDataResponse;
  importViewLoading: boolean;
  importViewError: string | null;
  originalViewData?: ImportOriginalViewResponse;
  originalViewLoading: boolean;
  originalViewError: string | null;
  onPageChange: (page: number) => void;
  changeViewData?: ImportChangesResponse;
  changeViewLoading: boolean;
  changeViewFetching: boolean;
  changeViewError: string | null;
  onChangePage: (page: number) => void;
  skippedRowsData?: ImportSkippedRowsResponse;
  skippedRowsLoading: boolean;
  skippedRowsError: string | null;
  onSkippedRowsPageChange: (page: number) => void;
  viewerSearchInput: string;
  onViewerSearchInputChange: (value: string) => void;
  viewerVillageFilter: string;
  onViewerVillageFilterChange: (value: string) => void;
  changeViewerSearchInput: string;
  onChangeViewerSearchInputChange: (value: string) => void;
  changeViewerType: ImportChangeFilter;
  onChangeViewerTypeChange: (value: ImportChangeFilter) => void;
  skippedViewerSearchInput: string;
  onSkippedViewerSearchInputChange: (value: string) => void;
  skippedViewerFilter: SkippedRowFilter;
  onSkippedViewerFilterChange: (value: SkippedRowFilter) => void;
}) {
  const [downloading, setDownloading] = useState(false);
  const [downloadError, setDownloadError] = useState<string | null>(null);
  const showParsedTab = imp.has_import_artifact;
  const showChangesTab = imp.status === 'completed';
  const showSkippedRowsTab = Number(imp.skipped_rows_count || imp.metadata?.skipped || 0) > 0;
  const showOriginalTab = imp.has_original_file;

  const handleDownload = async () => {
    setDownloading(true);
    setDownloadError(null);
    try {
      await downloadGecImportFile(imp.id);
    } catch (err) {
      setDownloadError(err instanceof Error ? err.message : 'Download failed.');
    } finally {
      setDownloading(false);
    }
  };

  const openOriginalInNewTab = () => {
    if (!originalViewData?.view_url) return;
    window.open(originalViewData.view_url, '_blank', 'noopener,noreferrer');
  };

  return (
    <div
      className="fixed inset-0 z-50 bg-black/50 backdrop-blur-sm flex items-center justify-center p-4"
      onClick={onClose}
    >
      <div
        className="bg-white rounded-2xl shadow-xl w-full max-w-6xl max-h-[90vh] overflow-hidden flex flex-col"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="px-5 py-4 border-b border-gray-200 flex items-start justify-between gap-4">
          <div className="min-w-0">
            <div className="text-xs font-semibold text-blue-600 uppercase tracking-wider">Import Transparency</div>
            <h3 className="text-lg font-semibold text-gray-900 truncate">{imp.raw_filename || imp.original_filename || imp.filename}</h3>
            <div className="mt-1 flex flex-wrap gap-x-4 gap-y-1 text-xs text-gray-500">
              <span>Imported at: {formatCampaignDateTime(imp.created_at)}</span>
              <span>Imported by: {imp.uploaded_by_email || '—'}</span>
              <span>Type: {imp.import_type?.replace(/_/g, ' ')}</span>
              <span>Status: {imp.status}</span>
            </div>
          </div>
          <button
            onClick={onClose}
            className="p-2 rounded-lg text-gray-500 hover:bg-gray-100 hover:text-gray-700 transition-colors"
            aria-label="Close import viewer"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        <div className="px-5 pt-4 flex flex-wrap items-center gap-2 border-b border-gray-200">
          {showParsedTab && (
            <button
              onClick={() => onChangeTab('parsed')}
              className={`px-3 py-2 rounded-t-lg text-sm font-medium transition-colors ${
                viewerTab === 'parsed'
                  ? 'bg-blue-50 text-blue-700 border border-blue-200 border-b-white'
                  : 'text-gray-500 hover:text-gray-700'
              }`}
            >
              Imported Data
            </button>
          )}
          {showChangesTab && (
            <button
              onClick={() => onChangeTab('changes')}
              className={`px-3 py-2 rounded-t-lg text-sm font-medium transition-colors ${
                viewerTab === 'changes'
                  ? 'bg-blue-50 text-blue-700 border border-blue-200 border-b-white'
                  : 'text-gray-500 hover:text-gray-700'
              }`}
            >
              All Changes
            </button>
          )}
          {showSkippedRowsTab && (
            <button
              onClick={() => onChangeTab('skipped')}
              className={`px-3 py-2 rounded-t-lg text-sm font-medium transition-colors ${
                viewerTab === 'skipped'
                  ? 'bg-blue-50 text-blue-700 border border-blue-200 border-b-white'
                  : 'text-gray-500 hover:text-gray-700'
              }`}
            >
              Skipped Rows
            </button>
          )}
          {showOriginalTab && (
            <button
              onClick={() => onChangeTab('original')}
              className={`px-3 py-2 rounded-t-lg text-sm font-medium transition-colors ${
                viewerTab === 'original'
                  ? 'bg-blue-50 text-blue-700 border border-blue-200 border-b-white'
                  : 'text-gray-500 hover:text-gray-700'
              }`}
            >
              Original File
            </button>
          )}
          <div className="ml-auto flex items-center gap-2 pb-3">
            {imp.has_downloadable_file && (
              <button
                onClick={handleDownload}
                disabled={downloading}
                className="inline-flex items-center gap-1.5 px-3 py-2 rounded-lg border border-gray-200 text-sm font-medium text-gray-700 hover:bg-gray-100 disabled:opacity-50 transition-colors"
              >
                {downloading ? <Loader2 className="w-4 h-4 animate-spin" /> : <Download className="w-4 h-4" />}
                Download File
              </button>
            )}
          </div>
        </div>

        <div className="flex-1 overflow-y-auto p-5 bg-gray-50">
          {viewerTab === 'parsed' && showParsedTab ? (
            <ParsedImportView
              imp={importViewData?.import || imp}
              preview={importViewData?.preview}
              loading={importViewLoading}
              error={importViewError}
              onPageChange={onPageChange}
              viewerSearchInput={viewerSearchInput}
              onViewerSearchInputChange={onViewerSearchInputChange}
              viewerVillageFilter={viewerVillageFilter}
              onViewerVillageFilterChange={onViewerVillageFilterChange}
            />
          ) : viewerTab === 'changes' && showChangesTab ? (
            <ImportChangesView
              imp={changeViewData?.import || imp}
              data={changeViewData}
              loading={changeViewLoading || changeViewFetching}
              error={changeViewError}
              onPageChange={onChangePage}
              searchInput={changeViewerSearchInput}
              onSearchInputChange={onChangeViewerSearchInputChange}
              changeType={changeViewerType}
              onChangeTypeChange={onChangeViewerTypeChange}
            />
          ) : viewerTab === 'skipped' && showSkippedRowsTab ? (
            <ImportSkippedRowsView
              imp={skippedRowsData?.import || imp}
              data={skippedRowsData}
              loading={skippedRowsLoading}
              error={skippedRowsError}
              onPageChange={onSkippedRowsPageChange}
              searchInput={skippedViewerSearchInput}
              onSearchInputChange={onSkippedViewerSearchInputChange}
              statusFilter={skippedViewerFilter}
              onStatusFilterChange={onSkippedViewerFilterChange}
            />
          ) : (
            <OriginalImportView
              data={originalViewData}
              loading={originalViewLoading}
              error={originalViewError}
              hasOriginalFile={imp.has_original_file}
              onOpenExternal={openOriginalInNewTab}
              actionLabel="Open Original File"
            />
          )}
          {downloadError && (
            <div className="mt-4 rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700">
              {downloadError}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

function ParsedImportView({
  imp,
  preview,
  loading,
  error,
  onPageChange,
  viewerSearchInput,
  onViewerSearchInputChange,
  viewerVillageFilter,
  onViewerVillageFilterChange,
}: {
  imp: ImportRecord;
  preview?: PreviewData;
  loading: boolean;
  error: string | null;
  onPageChange: (page: number) => void;
  viewerSearchInput: string;
  onViewerSearchInputChange: (value: string) => void;
  viewerVillageFilter: string;
  onViewerVillageFilterChange: (value: string) => void;
}) {
  if (loading) {
    return (
      <div className="flex items-center justify-center py-16 text-gray-500">
        <Loader2 className="w-5 h-5 animate-spin mr-2" />
        Loading parsed import data...
      </div>
    );
  }

  if (error) {
    return (
      <div className="rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
        {error}
      </div>
    );
  }

  if (!preview) {
    return (
      <div className="rounded-lg border border-gray-200 bg-white px-4 py-6 text-sm text-gray-500">
        Parsed import data is not available for this entry.
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-1 md:grid-cols-4 gap-3">
        <InfoStat label="Imported Data" value={preview.source_type === 'pdf' ? 'PDF import' : 'Spreadsheet import'} />
        <InfoStat label="Rows Detected" value={Number(preview.row_count || 0).toLocaleString()} />
        <InfoStat label="Filename" value={displayImportFilename(imp)} />
        <InfoStat label="Imported By" value={imp.uploaded_by_email || '—'} />
      </div>

      {preview.source_type === 'pdf' ? (
        <div className="space-y-4">
          <div className="bg-white rounded-xl border border-gray-200 p-4 space-y-2">
            <div className="text-sm text-gray-500">
              This view shows what the app parsed and used during the import.
            </div>
            <div className="flex flex-wrap items-center gap-4 text-sm">
              <div className="font-semibold text-gray-800">PDF QA Summary</div>
              <div className="text-gray-600">Rows parsed: <strong>{Number(preview.row_count || 0).toLocaleString()}</strong></div>
              <div className="text-gray-600">Quality score: <strong>{preview.qa?.quality_score ?? 'n/a'}</strong></div>
              <div className={`text-sm font-semibold uppercase ${
                preview.qa?.status === 'fail'
                  ? 'text-red-600'
                  : preview.qa?.status === 'review'
                  ? 'text-amber-600'
                  : 'text-green-600'
              }`}>
                {preview.qa?.status ?? 'unknown'}
              </div>
            </div>
            {preview.warnings.length > 0 && (
              <ul className="list-disc pl-5 text-sm text-amber-700 space-y-1">
                {preview.warnings.map((warning, idx) => <li key={idx}>{warning}</li>)}
              </ul>
            )}
            <div className="text-sm text-gray-500">
              Rows that were routed to <strong>Unassigned</strong> are highlighted below so staff can review exactly where the parser could not safely confirm a village.
            </div>
          </div>
          <ImportViewerFilters
            preview={preview}
            viewerSearchInput={viewerSearchInput}
            onViewerSearchInputChange={onViewerSearchInputChange}
            viewerVillageFilter={viewerVillageFilter}
            onViewerVillageFilterChange={onViewerVillageFilterChange}
          />
          <PreviewRowsTable preview={preview} onPageChange={onPageChange} />
        </div>
      ) : (
        <div className="space-y-4">
          <div className="bg-white rounded-xl border border-gray-200 p-4 space-y-2">
            <div className="text-sm font-semibold text-gray-800">Imported Spreadsheet Data</div>
            <div className="text-sm text-gray-500">
              This view shows what the app parsed and used during the import.
            </div>
            {preview.column_map && Object.keys(preview.column_map).length > 0 && (
              <div className="text-sm text-gray-600">
                <span className="font-medium">Columns mapped:</span>{' '}
                {Object.entries(preview.column_map).map(([key, val]) => `${key} → ${val}`).join(', ')}
              </div>
            )}
            {preview.sheets?.length > 1 && (
              <div className="text-sm text-gray-500">Sheets detected: {preview.sheets.join(', ')}</div>
            )}
            {imp.has_original_file && !imp.raw_content_type?.includes('pdf') && (
              <div className="text-sm text-gray-500">
                The original spreadsheet file is available through <strong>Download File</strong> in the header.
              </div>
            )}
          </div>
          <ImportViewerFilters
            preview={preview}
            viewerSearchInput={viewerSearchInput}
            onViewerSearchInputChange={onViewerSearchInputChange}
            viewerVillageFilter={viewerVillageFilter}
            onViewerVillageFilterChange={onViewerVillageFilterChange}
          />
          <PreviewRowsTable preview={preview} onPageChange={onPageChange} />
        </div>
      )}
    </div>
  );
}

function ImportViewerFilters({
  preview,
  viewerSearchInput,
  onViewerSearchInputChange,
  viewerVillageFilter,
  onViewerVillageFilterChange,
}: {
  preview: PreviewData;
  viewerSearchInput: string;
  onViewerSearchInputChange: (value: string) => void;
  viewerVillageFilter: string;
  onViewerVillageFilterChange: (value: string) => void;
}) {
  return (
    <div className="bg-white rounded-xl border border-gray-200 p-4 flex flex-col md:flex-row gap-3">
      <div className="flex-1">
        <label className="block text-xs font-semibold text-gray-500 uppercase tracking-wider mb-1">
          Search Imported Rows
        </label>
        <input
          value={viewerSearchInput}
          onChange={(e) => onViewerSearchInputChange(e.target.value)}
          placeholder={preview.source_type === 'pdf' ? 'Search name, village, precinct, reg no., birth year' : 'Search name, village, precinct, reg no., DOB'}
          className="w-full px-3 py-2 rounded-lg border border-gray-200 text-sm text-gray-700 focus:outline-none focus:ring-2 focus:ring-blue-200"
        />
      </div>
      <div className="md:w-56">
        <label className="block text-xs font-semibold text-gray-500 uppercase tracking-wider mb-1">
          Filter by Village
        </label>
        <select
          value={viewerVillageFilter}
          onChange={(e) => onViewerVillageFilterChange(e.target.value)}
          className="w-full px-3 py-2 rounded-lg border border-gray-200 text-sm text-gray-700 bg-white focus:outline-none focus:ring-2 focus:ring-blue-200"
        >
          <option value="">All villages</option>
          {preview.available_villages?.map((village) => (
            <option key={village} value={village}>{village}</option>
          ))}
        </select>
      </div>
    </div>
  );
}

function ImportChangesView({
  imp,
  data,
  loading,
  error,
  onPageChange,
  searchInput,
  onSearchInputChange,
  changeType,
  onChangeTypeChange,
}: {
  imp: ImportRecord;
  data?: ImportChangesResponse;
  loading: boolean;
  error: string | null;
  onPageChange: (page: number) => void;
  searchInput: string;
  onSearchInputChange: (value: string) => void;
  changeType: ImportChangeFilter;
  onChangeTypeChange: (value: ImportChangeFilter) => void;
}) {
  const counts = data?.counts ?? {
    all: imp.new_records + imp.updated_records + imp.removed_records + imp.transferred_records,
    new: imp.new_records,
    changed: imp.updated_records + imp.transferred_records,
    updated: imp.updated_records,
    removed: imp.removed_records,
    transferred: imp.transferred_records,
    routed_to_unassigned: Number(imp.metadata?.unassigned || 0),
  };

  const filters: Array<{ key: ImportChangeFilter; label: string; count: number }> = [
    { key: 'all', label: 'All Changes', count: counts.all },
    { key: 'new', label: 'New', count: counts.new },
    { key: 'updated', label: 'Updated', count: counts.updated },
    { key: 'removed', label: 'Removed', count: counts.removed },
    { key: 'transferred', label: 'Transferred', count: counts.transferred },
    { key: 'routed_to_unassigned', label: 'Routed to Unassigned', count: counts.routed_to_unassigned },
  ];

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
        <InfoStat label="New" value={Number(counts.new || 0).toLocaleString()} />
        <InfoStat label="Updated" value={Number(counts.updated || 0).toLocaleString()} />
        <InfoStat label="Removed" value={Number(counts.removed || 0).toLocaleString()} />
        <InfoStat label="Transferred" value={Number(counts.transferred || 0).toLocaleString()} />
        <InfoStat label="Routed to Unassigned" value={Number(counts.routed_to_unassigned || 0).toLocaleString()} />
      </div>

      <div className="bg-white rounded-xl border border-gray-200 p-4 space-y-3">
        <div className="text-sm text-gray-500">
          This view shows the actual voters this import added, updated, transferred, or removed. Rows routed to <strong>Unassigned</strong> are shown separately for import transparency.
        </div>
        <div className="flex flex-wrap gap-2">
          {filters.map((filter) => (
            <button
              key={filter.key}
              onClick={() => onChangeTypeChange(filter.key)}
              className={`px-3 py-2 rounded-lg text-sm font-medium transition-colors ${
                changeType === filter.key
                  ? 'bg-blue-50 text-blue-700 border border-blue-200'
                  : 'bg-gray-50 text-gray-600 border border-gray-200 hover:bg-gray-100'
              }`}
            >
              {filter.label} ({Number(filter.count || 0).toLocaleString()})
            </button>
          ))}
        </div>
        <div>
          <label className="block text-xs font-semibold text-gray-500 uppercase tracking-wider mb-1">
            Search Changes
          </label>
          <input
            value={searchInput}
            onChange={(e) => onSearchInputChange(e.target.value)}
            placeholder="Search name, village, or registration number"
            className="w-full px-3 py-2 rounded-lg border border-gray-200 text-sm text-gray-700 focus:outline-none focus:ring-2 focus:ring-blue-200"
          />
        </div>
      </div>

      {loading ? (
        <div className="flex items-center justify-center py-16 text-gray-500">
          <Loader2 className="w-5 h-5 animate-spin mr-2" />
          Loading import changes...
        </div>
      ) : error ? (
        <div className="rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
          {error}
        </div>
      ) : !data || data.changes.length === 0 ? (
        <div className="rounded-xl border border-gray-200 bg-white px-4 py-6 text-sm text-gray-500">
          {changeType === 'routed_to_unassigned'
            ? 'No routed-to-Unassigned rows were found for this filter.'
            : 'No matching change rows were found for this filter.'}
        </div>
      ) : (
        <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
          <div className="overflow-x-auto">
            <table className="min-w-full text-sm">
              <thead className="bg-gray-50 text-gray-500 uppercase text-[11px] tracking-wider">
                <tr>
                  <th className="px-4 py-3 text-left font-semibold">Type</th>
                  <th className="px-4 py-3 text-left font-semibold">Voter</th>
                  <th className="px-4 py-3 text-left font-semibold">Reg No.</th>
                  <th className="px-4 py-3 text-left font-semibold">Village</th>
                  <th className="px-4 py-3 text-left font-semibold">Details</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {data.changes.map((change) => (
                  <tr key={change.id} className="align-top">
                    <td className="px-4 py-3">
                      <span className={getChangeTypeBadgeClass(change.change_type)}>
                        {formatChangeTypeLabel(change.change_type)}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-gray-900">
                      <div className="font-medium">{[change.first_name, change.middle_name, change.last_name].filter(Boolean).join(' ') || '—'}</div>
                      <div className="text-xs text-gray-500">
                        {change.dob ? formatCampaignDate(change.dob) : (change.birth_year ?? '—')}
                        {change.row_number ? ` • Row ${change.row_number}` : ''}
                      </div>
                    </td>
                    <td className="px-4 py-3 text-gray-700">{change.voter_registration_number || '—'}</td>
                    <td className="px-4 py-3 text-gray-700">
                      <div>{change.village_name || '—'}</div>
                      {change.previous_village_name && change.previous_village_name !== change.village_name && (
                        <div className="text-xs text-gray-500">From {change.previous_village_name}</div>
                      )}
                    </td>
                    <td className="px-4 py-3 text-gray-600">
                      <ChangeDetailsSummary change={change} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div className="flex items-center justify-between gap-3 px-4 py-3 border-t border-gray-200 bg-gray-50 text-sm text-gray-600">
            <div>
              Page {data.pagination.page} of {Math.max(1, data.pagination.total_pages)} • {Number(data.pagination.total_rows || 0).toLocaleString()} rows
            </div>
            <div className="flex items-center gap-2">
              <button
                onClick={() => onPageChange(Math.max(1, data.pagination.page - 1))}
                disabled={data.pagination.page <= 1}
                className="inline-flex items-center gap-1 rounded-lg border border-gray-200 bg-white px-3 py-2 disabled:opacity-50"
              >
                <ChevronLeft className="w-4 h-4" />
                Previous
              </button>
              <button
                onClick={() => onPageChange(Math.min(data.pagination.total_pages || data.pagination.page, data.pagination.page + 1))}
                disabled={data.pagination.page >= data.pagination.total_pages}
                className="inline-flex items-center gap-1 rounded-lg border border-gray-200 bg-white px-3 py-2 disabled:opacity-50"
              >
                Next
                <ChevronRight className="w-4 h-4" />
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function ChangeDetailsSummary({ change }: { change: ImportChangeRecord }) {
  const changedFields = change.details?.changed_fields ? Object.entries(change.details.changed_fields) : [];

  if (change.change_type === 'removed') {
    return <div>Missing from this full-list import, so this voter was marked removed.</div>;
  }

  if (change.change_type === 'new') {
    return <div>New voter added from this import.</div>;
  }

  if (change.change_type === 'routed_to_unassigned') {
    const sourceName = typeof change.details?.source_name === 'string' ? change.details.source_name : '';
    const sourceVillageName = typeof change.details?.source_village_name === 'string' ? change.details.source_village_name : '';

    return (
      <div className="space-y-1">
        <div>
          <span className="font-medium text-gray-700">Village:</span>{' '}
          <span>{sourceVillageName || 'No usable village text'} {'->'} Unassigned</span>
        </div>
        {sourceName && (
          <div>
            <span className="font-medium text-gray-700">Source row:</span>{' '}
            <span>{sourceName}</span>
          </div>
        )}
        <div>
          {change.details?.reason || 'No usable village could be safely parsed from this import row, so it was routed to Unassigned.'}
        </div>
      </div>
    );
  }

  if (changedFields.length === 0) {
    return <div>Updated during this import.</div>;
  }

  return (
    <div className="space-y-1">
      {changedFields.map(([field, values]) => (
        <div key={field}>
          <span className="font-medium text-gray-700">{formatChangeFieldLabel(field)}:</span>{' '}
          <span>{formatChangeFieldValue(values.before)} {'->'} {formatChangeFieldValue(values.after)}</span>
        </div>
      ))}
    </div>
  );
}

function ImportSkippedRowsView({
  imp,
  data,
  loading,
  error,
  onPageChange,
  searchInput,
  onSearchInputChange,
  statusFilter,
  onStatusFilterChange,
}: {
  imp: ImportRecord;
  data?: ImportSkippedRowsResponse;
  loading: boolean;
  error: string | null;
  onPageChange: (page: number) => void;
  searchInput: string;
  onSearchInputChange: (value: string) => void;
  statusFilter: SkippedRowFilter;
  onStatusFilterChange: (value: SkippedRowFilter) => void;
}) {
  const queryClient = useQueryClient();
  const [expandedRowId, setExpandedRowId] = useState<number | null>(null);
  const [drafts, setDrafts] = useState<Record<number, Record<string, string>>>({});
  const [previews, setPreviews] = useState<Record<number, SkippedRowResolutionPreview>>({});
  const [selectedCandidateIds, setSelectedCandidateIds] = useState<Record<number, number | null>>({});
  const [rowFeedback, setRowFeedback] = useState<Record<number, string | null>>({});

  const previewMutation = useMutation({
    mutationFn: ({ skippedRowId, correctedValues, selectedGecVoterId }: { skippedRowId: number; correctedValues: Record<string, unknown>; selectedGecVoterId?: number | null }) =>
      previewGecImportSkippedRowResolution(imp.id, skippedRowId, correctedValues, selectedGecVoterId),
    onSuccess: (response, variables) => {
      setPreviews((current) => ({ ...current, [variables.skippedRowId]: response.preview }));
      setRowFeedback((current) => ({ ...current, [variables.skippedRowId]: null }));
    },
    onError: (mutationError, variables) => {
      const message = mutationError instanceof Error ? mutationError.message : 'Could not preview this skipped-row fix.';
      setRowFeedback((current) => ({ ...current, [variables.skippedRowId]: message }));
    },
  });

  const applyMutation = useMutation({
    mutationFn: ({ skippedRowId, correctedValues, selectedGecVoterId }: { skippedRowId: number; correctedValues: Record<string, unknown>; selectedGecVoterId?: number | null }) =>
      resolveGecImportSkippedRow(imp.id, skippedRowId, correctedValues, selectedGecVoterId),
    onSuccess: (_, variables) => {
      setRowFeedback((current) => ({ ...current, [variables.skippedRowId]: 'Fix applied successfully.' }));
      setPreviews((current) => {
        const next = { ...current };
        delete next[variables.skippedRowId];
        return next;
      });
      queryClient.invalidateQueries({ queryKey: ['gec-import-skipped-rows', imp.id] });
      queryClient.invalidateQueries({ queryKey: ['gec-imports'] });
      queryClient.invalidateQueries({ queryKey: ['gec-stats'] });
    },
    onError: (mutationError, variables) => {
      const message = mutationError instanceof Error ? mutationError.message : 'Could not apply this skipped-row fix.';
      setRowFeedback((current) => ({ ...current, [variables.skippedRowId]: message }));
    },
  });

  const dismissMutation = useMutation({
    mutationFn: (skippedRowId: number) => dismissGecImportSkippedRow(imp.id, skippedRowId),
    onSuccess: (_, skippedRowId) => {
      setRowFeedback((current) => ({ ...current, [skippedRowId]: 'Skipped row dismissed.' }));
      queryClient.invalidateQueries({ queryKey: ['gec-import-skipped-rows', imp.id] });
      queryClient.invalidateQueries({ queryKey: ['gec-imports'] });
    },
    onError: (mutationError, skippedRowId) => {
      const message = mutationError instanceof Error ? mutationError.message : 'Could not dismiss this skipped row.';
      setRowFeedback((current) => ({ ...current, [skippedRowId]: message }));
    },
  });

  const counts = data?.counts ?? {
    all: imp.skipped_rows_count || Number(imp.metadata?.skipped || 0),
    pending: imp.pending_skipped_rows_count || Number(imp.metadata?.skipped || 0),
    resolved: 0,
    dismissed: 0,
  };

  const filters: Array<{ key: SkippedRowFilter; label: string; count: number }> = [
    { key: 'all', label: 'All', count: counts.all },
    { key: 'pending', label: 'Pending Review', count: counts.pending },
    { key: 'resolved', label: 'Resolved', count: counts.resolved },
    { key: 'dismissed', label: 'Dismissed', count: counts.dismissed },
  ];

  const rows = data?.skipped_rows || [];

  const buildDraft = (row: ImportSkippedRowRecord) => {
    const existing = drafts[row.id];
    if (existing) return existing;
    return {
      first_name: String(row.corrected_values.first_name ?? row.first_name ?? ''),
      last_name: String(row.corrected_values.last_name ?? row.last_name ?? ''),
      village_name: String(row.corrected_values.village_name ?? row.village_name ?? ''),
      voter_registration_number: String(row.corrected_values.voter_registration_number ?? row.voter_registration_number ?? ''),
      birth_year: String(row.corrected_values.birth_year ?? row.birth_year ?? ''),
      dob: String(row.corrected_values.dob ?? row.dob ?? ''),
    };
  };

  const updateDraft = (rowId: number, field: string, value: string) => {
    setDrafts((current) => ({
      ...current,
      [rowId]: {
        ...(current[rowId] || {}),
        [field]: value,
      }
    }));
  };

  const handlePreview = (row: ImportSkippedRowRecord, selectedGecVoterId?: number | null) => {
    const draft = buildDraft(row);
    previewMutation.mutate({
      skippedRowId: row.id,
      correctedValues: draft,
      selectedGecVoterId,
    });
  };

  const handleApply = (row: ImportSkippedRowRecord) => {
    const draft = buildDraft(row);
    applyMutation.mutate({
      skippedRowId: row.id,
      correctedValues: draft,
      selectedGecVoterId: selectedCandidateIds[row.id],
    });
  };

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        <InfoStat label="Pending Review" value={Number(counts.pending || 0).toLocaleString()} />
        <InfoStat label="Resolved" value={Number(counts.resolved || 0).toLocaleString()} />
        <InfoStat label="Dismissed" value={Number(counts.dismissed || 0).toLocaleString()} />
        <InfoStat label="Total Skipped" value={Number(counts.all || 0).toLocaleString()} />
      </div>

      <div className="bg-white rounded-xl border border-gray-200 p-4 space-y-3">
        <div className="space-y-1">
          <div className="text-sm font-semibold text-gray-800">Review skipped rows</div>
          <div className="text-sm text-gray-500">
            Use this to manually fix rows the importer could not safely apply. The original skipped row stays unchanged, and every fix is saved with an audit trail.
          </div>
        </div>
        <div className="flex flex-wrap gap-2">
          {filters.map((filter) => (
            <button
              key={filter.key}
              onClick={() => onStatusFilterChange(filter.key)}
              className={`px-3 py-2 rounded-lg text-sm font-medium transition-colors ${
                statusFilter === filter.key
                  ? 'bg-blue-50 text-blue-700 border border-blue-200'
                  : 'bg-gray-50 text-gray-600 border border-gray-200 hover:bg-gray-100'
              }`}
            >
              {filter.label} ({Number(filter.count || 0).toLocaleString()})
            </button>
          ))}
        </div>
        <div>
          <label className="block text-xs font-semibold text-gray-500 uppercase tracking-wider mb-1">
            Search Skipped Rows
          </label>
          <input
            value={searchInput}
            onChange={(e) => onSearchInputChange(e.target.value)}
            placeholder="Search name, village, or registration number"
            className="w-full px-3 py-2 rounded-lg border border-gray-200 text-sm text-gray-700 focus:outline-none focus:ring-2 focus:ring-blue-200"
          />
        </div>
      </div>

      {loading ? (
        <div className="flex items-center justify-center py-16 text-gray-500">
          <Loader2 className="w-5 h-5 animate-spin mr-2" />
          Loading skipped rows...
        </div>
      ) : error ? (
        <div className="rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
          {error}
        </div>
      ) : rows.length === 0 ? (
        <div className="rounded-xl border border-gray-200 bg-white px-4 py-6 text-sm text-gray-500">
          No skipped rows were found for this filter.
        </div>
      ) : (
        <div className="space-y-3">
          {rows.map((row) => {
            const isExpanded = expandedRowId === row.id;
            const draft = buildDraft(row);
            const preview = previews[row.id];
            const pending = row.resolution_status === 'pending';
            const selectedCandidateId = selectedCandidateIds[row.id];
            const rowBusy = previewMutation.isPending || applyMutation.isPending || dismissMutation.isPending;

            return (
              <div key={row.id} className="bg-white rounded-xl border border-gray-200 overflow-hidden">
                <button
                  onClick={() => setExpandedRowId(isExpanded ? null : row.id)}
                  className="w-full px-4 py-4 flex items-start justify-between gap-4 text-left hover:bg-gray-50 transition-colors"
                >
                  <div className="min-w-0 space-y-1">
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="text-sm font-semibold text-gray-900">Row {row.row_number}</span>
                      <span className={getSkippedRowStatusBadgeClass(row.resolution_status)}>
                        {formatSkippedRowStatus(row.resolution_status)}
                      </span>
                    </div>
                    <div className="text-sm text-gray-700">{row.message}</div>
                    <div className="text-xs text-gray-500">
                      {[row.first_name, row.last_name].filter(Boolean).join(' ') || row.source_name || 'Unnamed row'}
                      {row.village_name ? ` • ${row.village_name}` : ''}
                      {row.birth_year ? ` • ${row.birth_year}` : row.dob ? ` • ${formatCampaignDate(row.dob)}` : ''}
                    </div>
                  </div>
                  {isExpanded ? <ChevronDown className="w-4 h-4 text-gray-400 shrink-0" /> : <ChevronRight className="w-4 h-4 text-gray-400 shrink-0" />}
                </button>

                {isExpanded && (
                  <div className="border-t border-gray-200 px-4 py-4 bg-gray-50 space-y-4">
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                      <div className="rounded-lg border border-gray-200 bg-white p-4 space-y-2">
                        <div className="text-xs font-semibold text-gray-500 uppercase tracking-wider">Original skipped row</div>
                        <div className="text-sm text-gray-700">Reason: <strong>{row.message}</strong></div>
                        {row.source_name && <div className="text-sm text-gray-700">Source name: <strong>{row.source_name}</strong></div>}
                        <div className="flex flex-wrap gap-x-3 gap-y-1 text-sm text-gray-700">
                          {row.first_name && <span>First: <strong>{row.first_name}</strong></span>}
                          {row.last_name && <span>Last: <strong>{row.last_name}</strong></span>}
                          {row.village_name && <span>Village: <strong>{row.village_name}</strong></span>}
                          {row.voter_registration_number && <span>Reg No.: <strong>{row.voter_registration_number}</strong></span>}
                          {row.birth_year && <span>Birth year: <strong>{row.birth_year}</strong></span>}
                          {row.dob && <span>DOB: <strong>{formatCampaignDate(row.dob)}</strong></span>}
                        </div>
                        {row.raw_values.length > 0 && (
                          <div className="text-sm text-gray-600">
                            Raw row: <strong>{row.raw_values.join(' | ')}</strong>
                          </div>
                        )}
                      </div>

                      <div className="rounded-lg border border-gray-200 bg-white p-4 space-y-3">
                        <div className="text-xs font-semibold text-gray-500 uppercase tracking-wider">Resolution</div>
                        {pending ? (
                          <>
                            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                              <label className="text-sm text-gray-700">
                                <div className="mb-1 font-medium">First name</div>
                                <input value={draft.first_name} onChange={(e) => updateDraft(row.id, 'first_name', e.target.value)} className="w-full px-3 py-2 rounded-lg border border-gray-200 text-sm focus:outline-none focus:ring-2 focus:ring-blue-200" />
                              </label>
                              <label className="text-sm text-gray-700">
                                <div className="mb-1 font-medium">Last name</div>
                                <input value={draft.last_name} onChange={(e) => updateDraft(row.id, 'last_name', e.target.value)} className="w-full px-3 py-2 rounded-lg border border-gray-200 text-sm focus:outline-none focus:ring-2 focus:ring-blue-200" />
                              </label>
                              <label className="text-sm text-gray-700">
                                <div className="mb-1 font-medium">Village</div>
                                <input value={draft.village_name} onChange={(e) => updateDraft(row.id, 'village_name', e.target.value)} className="w-full px-3 py-2 rounded-lg border border-gray-200 text-sm focus:outline-none focus:ring-2 focus:ring-blue-200" />
                              </label>
                              <label className="text-sm text-gray-700">
                                <div className="mb-1 font-medium">Reg No.</div>
                                <input value={draft.voter_registration_number} onChange={(e) => updateDraft(row.id, 'voter_registration_number', e.target.value)} className="w-full px-3 py-2 rounded-lg border border-gray-200 text-sm focus:outline-none focus:ring-2 focus:ring-blue-200" />
                              </label>
                              <label className="text-sm text-gray-700">
                                <div className="mb-1 font-medium">Birth year</div>
                                <input value={draft.birth_year} onChange={(e) => updateDraft(row.id, 'birth_year', e.target.value)} className="w-full px-3 py-2 rounded-lg border border-gray-200 text-sm focus:outline-none focus:ring-2 focus:ring-blue-200" />
                              </label>
                              <label className="text-sm text-gray-700">
                                <div className="mb-1 font-medium">DOB</div>
                                <input type="date" value={draft.dob} onChange={(e) => updateDraft(row.id, 'dob', e.target.value)} className="w-full px-3 py-2 rounded-lg border border-gray-200 text-sm focus:outline-none focus:ring-2 focus:ring-blue-200" />
                              </label>
                            </div>

                            <div className="flex flex-wrap gap-2">
                              <button
                                onClick={() => handlePreview(row)}
                                disabled={rowBusy}
                                className="inline-flex items-center gap-1.5 px-3 py-2 rounded-lg border border-blue-200 bg-blue-50 text-sm font-medium text-blue-700 hover:bg-blue-100 disabled:opacity-50"
                              >
                                {previewMutation.isPending ? <Loader2 className="w-4 h-4 animate-spin" /> : null}
                                Check Fix
                              </button>
                              <button
                                onClick={() => dismissMutation.mutate(row.id)}
                                disabled={rowBusy}
                                className="inline-flex items-center gap-1.5 px-3 py-2 rounded-lg border border-gray-200 bg-white text-sm font-medium text-gray-700 hover:bg-gray-100 disabled:opacity-50"
                              >
                                Dismiss Row
                              </button>
                            </div>

                            {preview && (
                              <div className={`rounded-lg border px-3 py-3 text-sm ${
                                preview.status === 'ready_to_create' || preview.status === 'ready_to_update'
                                  ? 'border-green-200 bg-green-50 text-green-800'
                                  : preview.status === 'ambiguous'
                                  ? 'border-amber-200 bg-amber-50 text-amber-800'
                                  : 'border-red-200 bg-red-50 text-red-700'
                              }`}>
                                {preview.status === 'ready_to_create' && <div>This fix will create a new voter record for this import date.</div>}
                                {preview.status === 'ready_to_update' && (
                                  <div>
                                    This fix will update <strong>{[preview.target_voter?.first_name, preview.target_voter?.last_name].filter(Boolean).join(' ') || 'the selected voter'}</strong>
                                    {preview.target_voter?.village_name ? ` in ${preview.target_voter.village_name}` : ''}.
                                  </div>
                                )}
                                {preview.errors?.length > 0 && (
                                  <div className="space-y-1">
                                    {preview.errors.map((previewError, index) => <div key={index}>{previewError}</div>)}
                                  </div>
                                )}

                                {preview.status === 'ambiguous' && preview.candidate_matches.length > 0 && (
                                  <div className="mt-3 space-y-2">
                                    <div className="font-medium">Select the voter this skipped row should update:</div>
                                    {preview.candidate_matches.map((candidate) => (
                                      <label key={candidate.gec_voter.id} className="flex items-start gap-2 rounded-lg border border-amber-200 bg-white px-3 py-2">
                                        <input
                                          type="radio"
                                          checked={selectedCandidateId === candidate.gec_voter.id}
                                          onChange={() => setSelectedCandidateIds((current) => ({ ...current, [row.id]: candidate.gec_voter.id }))}
                                        />
                                        <div>
                                          <div className="font-medium text-gray-900">
                                            {candidate.gec_voter.first_name} {candidate.gec_voter.last_name}
                                          </div>
                                          <div className="text-xs text-gray-600">
                                            {candidate.gec_voter.village_name || '—'}
                                            {candidate.gec_voter.birth_year ? ` • ${candidate.gec_voter.birth_year}` : candidate.gec_voter.dob ? ` • ${formatCampaignDate(candidate.gec_voter.dob)}` : ''}
                                            {candidate.gec_voter.voter_registration_number ? ` • ${candidate.gec_voter.voter_registration_number}` : ''}
                                          </div>
                                          <div className="text-xs text-amber-700 mt-1">
                                            Confidence: {candidate.confidence} • Match type: {candidate.match_type.replace(/_/g, ' ')}
                                          </div>
                                        </div>
                                      </label>
                                    ))}
                                    <button
                                      onClick={() => handlePreview(row, selectedCandidateId)}
                                      disabled={!selectedCandidateId || rowBusy}
                                      className="inline-flex items-center gap-1.5 px-3 py-2 rounded-lg border border-amber-200 bg-white text-sm font-medium text-amber-800 hover:bg-amber-100 disabled:opacity-50"
                                    >
                                      Use Selected Voter
                                    </button>
                                  </div>
                                )}

                                {(preview.status === 'ready_to_create' || preview.status === 'ready_to_update') && (
                                  <div className="mt-3">
                                    <button
                                      onClick={() => handleApply(row)}
                                      disabled={rowBusy}
                                      className="inline-flex items-center gap-1.5 px-3 py-2 rounded-lg border border-green-200 bg-white text-sm font-medium text-green-800 hover:bg-green-100 disabled:opacity-50"
                                    >
                                      {applyMutation.isPending ? <Loader2 className="w-4 h-4 animate-spin" /> : null}
                                      Apply Fix
                                    </button>
                                  </div>
                                )}
                              </div>
                            )}
                          </>
                        ) : (
                          <div className="space-y-2 text-sm text-gray-700">
                            <div>
                              <strong>{formatSkippedRowStatus(row.resolution_status)}</strong>
                              {row.resolved_at ? ` on ${formatCampaignDateTime(row.resolved_at)}` : ''}
                              {row.resolved_by_email ? ` by ${row.resolved_by_email}` : ''}
                            </div>
                            {row.resolution_action && (
                              <div>Action: <strong>{row.resolution_action}</strong></div>
                            )}
                            {row.resolved_gec_voter && (
                              <div>
                                Result voter: <strong>{row.resolved_gec_voter.first_name} {row.resolved_gec_voter.last_name}</strong>
                                {row.resolved_gec_voter.village_name ? ` • ${row.resolved_gec_voter.village_name}` : ''}
                              </div>
                            )}
                          </div>
                        )}

                        {rowFeedback[row.id] && (
                          <div className="rounded-lg border border-gray-200 bg-gray-50 px-3 py-2 text-sm text-gray-700">
                            {rowFeedback[row.id]}
                          </div>
                        )}
                      </div>
                    </div>
                  </div>
                )}
              </div>
            );
          })}

          {data && (
            <div className="flex items-center justify-between gap-3 px-1 py-1 text-sm text-gray-600">
              <div>
                Page {data.pagination.page} of {Math.max(1, data.pagination.total_pages)} • {Number(data.pagination.total_rows || 0).toLocaleString()} rows
              </div>
              <div className="flex items-center gap-2">
                <button
                  onClick={() => onPageChange(Math.max(1, data.pagination.page - 1))}
                  disabled={data.pagination.page <= 1}
                  className="inline-flex items-center gap-1 rounded-lg border border-gray-200 bg-white px-3 py-2 disabled:opacity-50"
                >
                  <ChevronLeft className="w-4 h-4" />
                  Previous
                </button>
                <button
                  onClick={() => onPageChange(Math.min(data.pagination.total_pages || data.pagination.page, data.pagination.page + 1))}
                  disabled={data.pagination.page >= data.pagination.total_pages}
                  className="inline-flex items-center gap-1 rounded-lg border border-gray-200 bg-white px-3 py-2 disabled:opacity-50"
                >
                  Next
                  <ChevronRight className="w-4 h-4" />
                </button>
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function formatSkippedRowStatus(status: ImportSkippedRowRecord['resolution_status']): string {
  switch (status) {
    case 'pending':
      return 'Pending Review';
    case 'resolved_created':
      return 'Resolved: Created';
    case 'resolved_updated':
      return 'Resolved: Updated';
    case 'dismissed':
      return 'Dismissed';
    default:
      return status;
  }
}

function getSkippedRowStatusBadgeClass(status: ImportSkippedRowRecord['resolution_status']): string {
  const base = 'inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold';
  switch (status) {
    case 'pending':
      return `${base} bg-amber-50 text-amber-700`;
    case 'resolved_created':
      return `${base} bg-green-50 text-green-700`;
    case 'resolved_updated':
      return `${base} bg-blue-50 text-blue-700`;
    case 'dismissed':
      return `${base} bg-gray-100 text-gray-700`;
    default:
      return `${base} bg-gray-100 text-gray-700`;
  }
}

function formatChangeTypeLabel(changeType: ImportChangeRecord['change_type']): string {
  switch (changeType) {
    case 'new':
      return 'New';
    case 'updated':
      return 'Updated';
    case 'removed':
      return 'Removed';
    case 'transferred':
      return 'Transferred';
    case 'routed_to_unassigned':
      return 'Routed to Unassigned';
    default:
      return changeType;
  }
}

function getChangeTypeBadgeClass(changeType: ImportChangeRecord['change_type']): string {
  const base = 'inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold';
  switch (changeType) {
    case 'new':
      return `${base} bg-green-50 text-green-700`;
    case 'updated':
      return `${base} bg-blue-50 text-blue-700`;
    case 'removed':
      return `${base} bg-red-50 text-red-700`;
    case 'transferred':
      return `${base} bg-indigo-50 text-indigo-700`;
    case 'routed_to_unassigned':
      return `${base} bg-amber-50 text-amber-800`;
    default:
      return `${base} bg-gray-100 text-gray-700`;
  }
}

function formatChangeFieldLabel(field: string): string {
  switch (field) {
    case 'village_name':
      return 'Village';
    case 'voter_registration_number':
      return 'Reg No.';
    case 'birth_year':
      return 'Birth year';
    case 'dob':
      return 'DOB';
    default:
      return field.replace(/_/g, ' ');
  }
}

function formatChangeFieldValue(value: unknown): string {
  if (value == null || value === '') return '—';
  if (typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value)) return formatCampaignDate(value);
  return String(value);
}

function OriginalImportView({
  data,
  loading,
  error,
  hasOriginalFile,
  onOpenExternal,
  actionLabel,
}: {
  data?: ImportOriginalViewResponse;
  loading: boolean;
  error: string | null;
  hasOriginalFile: boolean;
  onOpenExternal: () => void;
  actionLabel: string;
}) {
  if (!hasOriginalFile) {
    return (
      <div className="rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-800">
        This import does not have a preserved raw source file. Parsed import data and download remain available when the import artifact exists.
      </div>
    );
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center py-16 text-gray-500">
        <Loader2 className="w-5 h-5 animate-spin mr-2" />
        Loading original file...
      </div>
    );
  }

  if (error) {
    return (
      <div className="rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
        {error}
      </div>
    );
  }

  if (!data) {
    return null;
  }

  return (
    <div className="space-y-4">
      <div className="bg-white rounded-xl border border-gray-200 p-4 flex flex-wrap items-center justify-between gap-3">
        <div>
          <div className="text-sm font-semibold text-gray-800">{data.filename}</div>
          <div className="text-sm text-gray-500">{data.content_type}</div>
          <div className="text-sm text-gray-500 mt-1">This is the original file that was uploaded.</div>
        </div>
        <button
          onClick={onOpenExternal}
          className="inline-flex items-center gap-1.5 px-3 py-2 rounded-lg border border-gray-200 text-sm font-medium text-gray-700 hover:bg-gray-100 transition-colors"
        >
          <ExternalLink className="w-4 h-4" />
          {actionLabel}
        </button>
      </div>

      {data.inline_supported ? (
        <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
          <iframe
            title={`Original file preview for ${data.filename}`}
            src={data.view_url}
            className="w-full h-[68vh] bg-white"
          />
        </div>
      ) : (
        <div className="rounded-xl border border-gray-200 bg-white p-5 space-y-3">
          <div className="text-sm text-gray-700">
            The original file is preserved and ready to open, but this file type is better handled by your browser or local spreadsheet app than an embedded in-app viewer.
          </div>
          <div className="text-sm text-gray-500">
            Use <strong>{actionLabel}</strong> to inspect it directly, or use <strong>Download File</strong> from the header if you want a local copy.
          </div>
        </div>
      )}
    </div>
  );
}

function PreviewRowsTable({ preview, onPageChange }: { preview: PreviewData; onPageChange: (page: number) => void }) {
  if (!preview.preview_rows?.length) {
    return (
      <div className="rounded-xl border border-gray-200 bg-white px-4 py-6 text-sm text-gray-500">
        No preview rows available.
      </div>
    );
  }

  const pagination = preview.pagination;
  const startRow = pagination ? ((pagination.page - 1) * pagination.per_page) + 1 : 1;
  const endRow = pagination ? Math.min(pagination.page * pagination.per_page, pagination.total_rows) : preview.preview_rows.length;

  return preview.source_type === 'pdf' ? (
    <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
      <div className="px-4 py-3 flex flex-wrap items-center justify-between gap-2 text-xs border-b border-gray-200">
        <div className="font-semibold text-gray-500 uppercase tracking-wider">
          Imported Rows {pagination ? `(${startRow}-${endRow} of ${pagination.total_rows.toLocaleString()})` : ''}
        </div>
        {pagination && (
          <PaginationControls pagination={pagination} onPageChange={onPageChange} />
        )}
      </div>
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="bg-gray-50">
            <tr>
              <th className="text-left px-4 py-2 text-gray-500 font-medium">Reg No.</th>
              <th className="text-left px-4 py-2 text-gray-500 font-medium">Name</th>
              <th className="text-left px-4 py-2 text-gray-500 font-medium">Address</th>
              <th className="text-left px-4 py-2 text-gray-500 font-medium">Village</th>
              <th className="text-left px-4 py-2 text-gray-500 font-medium">Precinct</th>
              <th className="text-left px-4 py-2 text-gray-500 font-medium">Birth Year</th>
            </tr>
          </thead>
          <tbody>
            {preview.preview_rows.map((row, idx) => {
              const routedToUnassigned = Boolean(row.routed_to_unassigned);
              const sourceVillage = String(row.source_village ?? row.source_village_name ?? '');
              return (
              <tr key={idx} className={`border-t ${routedToUnassigned ? 'border-amber-100 bg-amber-50/40' : 'border-gray-100'}`}>
                <td className="px-4 py-2 text-gray-600">{String(row.voter_registration_number ?? '')}</td>
                <td className="px-4 py-2 text-gray-800">{String(row.name ?? '')}</td>
                <td className="px-4 py-2 text-gray-600">{String(row.address ?? '')}</td>
                <td className="px-4 py-2 text-gray-600">
                  <div>{String(row.village ?? '')}</div>
                  {routedToUnassigned && (
                    <div className="mt-1 space-y-1">
                      <span className="inline-flex items-center rounded-full bg-amber-100 px-2 py-0.5 text-[11px] font-medium text-amber-800">
                        Routed to Unassigned
                      </span>
                      <div className="text-[11px] text-amber-700">
                        {sourceVillage ? `Source village text: ${sourceVillage}` : 'No usable village was parsed from this row.'}
                      </div>
                    </div>
                  )}
                </td>
                <td className="px-4 py-2 text-gray-600">{String(row.precinct_number ?? '')}</td>
                <td className="px-4 py-2 text-gray-600">{String(row.birth_year ?? '')}</td>
              </tr>
            )})}
          </tbody>
        </table>
      </div>
    </div>
  ) : (
    <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
      <div className="px-4 py-3 flex flex-wrap items-center justify-between gap-2 text-xs border-b border-gray-200">
        <div className="font-semibold text-gray-500 uppercase tracking-wider">
          Imported Rows {pagination ? `(${startRow}-${endRow} of ${pagination.total_rows.toLocaleString()})` : ''}
        </div>
        {pagination && (
          <PaginationControls pagination={pagination} onPageChange={onPageChange} />
        )}
      </div>
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="bg-gray-50">
            <tr>
              <th className="text-left px-4 py-2 text-gray-500 font-medium">First Name</th>
              <th className="text-left px-4 py-2 text-gray-500 font-medium">Last Name</th>
              <th className="text-left px-4 py-2 text-gray-500 font-medium">Address</th>
              <th className="text-left px-4 py-2 text-gray-500 font-medium">Village</th>
              <th className="text-left px-4 py-2 text-gray-500 font-medium">Precinct</th>
              <th className="text-left px-4 py-2 text-gray-500 font-medium">DOB / Year</th>
              <th className="text-left px-4 py-2 text-gray-500 font-medium">Reg No.</th>
            </tr>
          </thead>
          <tbody>
            {preview.preview_rows.map((row, idx) => {
              const routedToUnassigned = Boolean(row.routed_to_unassigned);
              const sourceVillage = String(row.source_village_name ?? row.source_village ?? '');
              return (
              <tr key={idx} className={`border-t ${routedToUnassigned ? 'border-amber-100 bg-amber-50/40' : 'border-gray-100'}`}>
                <td className="px-4 py-2 text-gray-800">{String(row.first_name ?? '')}</td>
                <td className="px-4 py-2 text-gray-800">{String(row.last_name ?? '')}</td>
                <td className="px-4 py-2 text-gray-600">{String(row.address ?? '')}</td>
                <td className="px-4 py-2 text-gray-600">
                  <div>{String(row.village_name ?? row.village ?? '')}</div>
                  {routedToUnassigned && (
                    <div className="mt-1 space-y-1">
                      <span className="inline-flex items-center rounded-full bg-amber-100 px-2 py-0.5 text-[11px] font-medium text-amber-800">
                        Routed to Unassigned
                      </span>
                      <div className="text-[11px] text-amber-700">
                        {sourceVillage ? `Source village text: ${sourceVillage}` : 'No usable village was parsed from this row.'}
                      </div>
                    </div>
                  )}
                </td>
                <td className="px-4 py-2 text-gray-600">{String(row.precinct_number ?? '')}</td>
                <td className="px-4 py-2 text-gray-600">{String(row.dob ?? row.birth_year ?? '')}</td>
                <td className="px-4 py-2 text-gray-600">{String(row.voter_registration_number ?? '')}</td>
              </tr>
            )})}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function PaginationControls({ pagination, onPageChange }: { pagination: PreviewPagination; onPageChange: (page: number) => void }) {
  return (
    <div className="flex items-center gap-2 text-xs text-gray-500">
      <button
        onClick={() => onPageChange(pagination.page - 1)}
        disabled={pagination.page <= 1}
        className="inline-flex items-center gap-1 px-2 py-1 rounded border border-gray-200 text-gray-600 hover:bg-gray-100 disabled:opacity-40 transition-colors"
      >
        <ChevronLeft className="w-3.5 h-3.5" />
        Prev
      </button>
      <span>Page {pagination.page} of {pagination.total_pages}</span>
      <button
        onClick={() => onPageChange(pagination.page + 1)}
        disabled={pagination.page >= pagination.total_pages}
        className="inline-flex items-center gap-1 px-2 py-1 rounded border border-gray-200 text-gray-600 hover:bg-gray-100 disabled:opacity-40 transition-colors"
      >
        Next
        <ChevronRight className="w-3.5 h-3.5" />
      </button>
    </div>
  );
}

function InfoStat({ label, value }: { label: string; value: string }) {
  return (
    <div className="bg-white rounded-xl border border-gray-200 px-4 py-3">
      <div className="text-[10px] font-semibold text-gray-400 uppercase tracking-wider">{label}</div>
      <div className="mt-1 text-sm text-gray-800 wrap-break-word">{value}</div>
    </div>
  );
}

function ChangeSummary({ summary }: { summary?: Record<string, number> }) {
  if (!summary) return null;
  const removed = summary.removed_records || 0;
  const transferred = summary.transferred_records || 0;
  const reVetted = summary.re_vetted_count || 0;
  if (removed + transferred + reVetted === 0) return null;

  return (
    <div className="mt-4 p-3 bg-blue-50 border border-blue-100 rounded-lg">
      <div className="text-[10px] font-semibold text-blue-600 uppercase tracking-wider mb-1">Last Import Changes</div>
      <div className="flex flex-wrap gap-4 text-xs text-blue-800">
        {removed > 0 && <span>Purged: <strong>{removed}</strong></span>}
        {transferred > 0 && <span>Transfers: <strong>{transferred}</strong></span>}
        {reVetted > 0 && <span>Supporters re-flagged: <strong>{reVetted}</strong></span>}
      </div>
    </div>
  );
}
