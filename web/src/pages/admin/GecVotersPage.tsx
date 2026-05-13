import { Fragment, useEffect, useMemo, useRef, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import {
  AlertTriangle,
  ChevronDown,
  CheckCircle2,
  Database,
  Download,
  Eye,
  FileText,
  Home,
  Link as LinkIcon,
  Loader2,
  RefreshCw,
  Search,
  Upload,
  Users,
  X,
} from 'lucide-react';
import {
  activateGecImport,
  createContactFromGecVoter,
  dismissGecImportSkippedRow,
  downloadGecImportFile,
  getGecImportChanges,
  getGecImportData,
  getGecImportSkippedRows,
  getGecHouseholds,
  getGecImports,
  getGecPdfPreviewStatus,
  getGecStats,
  getGecVoters,
  getSupporters,
  openGecImportOriginal,
  linkContactToGecVoter,
  previewGecList,
  previewGecImportSkippedRowResolution,
  resolveGecImportSkippedRow,
  uploadGecList,
} from '../../lib/api';
import { useSession } from '../../hooks/useSession';
import WorkspacePage from '../../components/WorkspacePage';

type GecVoter = {
  id: number;
  first_name: string;
  middle_name?: string | null;
  last_name: string;
  birth_year?: number | null;
  address?: string | null;
  village_name: string;
  precinct_number?: string | null;
  voter_registration_number?: string | null;
  gec_list_date: string;
  linked_contact_count?: number;
};

type Household = {
  address: string;
  village_name: string;
  gec_voters: GecVoter[];
  contacts: Array<{
    id: number;
    print_name?: string | null;
    first_name: string;
    last_name: string;
    contact_classification: string;
    current_gec_match: boolean;
  }>;
};

type GecImport = {
  id: number;
  gec_list_date: string;
  filename: string;
  import_type?: string;
  total_records: number;
  new_records: number;
  updated_records: number;
  removed_records: number;
  transferred_records: number;
  skipped_rows_count?: number;
  pending_skipped_rows_count?: number;
  status: string;
  created_at: string;
  uploaded_by_email?: string | null;
  active_election_day?: boolean;
  has_import_artifact?: boolean;
  has_original_file?: boolean;
  has_downloadable_file?: boolean;
  raw_content_type?: string | null;
  metadata?: {
    stage?: string;
    progress_percent?: number;
    pages_processed?: number;
    page_count?: number;
    error?: string;
    pdf_qa?: Record<string, unknown>;
    active_job_id?: string;
    enqueued_at?: string;
    [key: string]: unknown;
  };
};

type ImportViewerTab = 'data' | 'changes' | 'skipped';
type GecImportType = 'full_list' | 'changes_only';

type ImportPreviewRow = Record<string, unknown>;

type ImportChange = {
  id: number | string;
  change_type: string;
  row_number?: number | null;
  first_name?: string | null;
  middle_name?: string | null;
  last_name?: string | null;
  village_name?: string | null;
  previous_village_name?: string | null;
  voter_registration_number?: string | null;
  birth_year?: number | string | null;
  dob?: string | null;
  details?: Record<string, unknown>;
};

type ImportSkippedRow = {
  id: number;
  row_number: number;
  message: string;
  raw_values?: string[];
  corrected_values?: Record<string, unknown>;
  source_name?: string | null;
  first_name?: string | null;
  middle_name?: string | null;
  last_name?: string | null;
  village_name?: string | null;
  voter_registration_number?: string | null;
  birth_year?: number | string | null;
  dob?: string | null;
  resolution_status: string;
  resolved_at?: string | null;
  resolved_by_email?: string | null;
  resolved_gec_voter?: {
    id: number;
    first_name?: string | null;
    last_name?: string | null;
    village_name?: string | null;
    voter_registration_number?: string | null;
    birth_year?: number | string | null;
    dob?: string | null;
  } | null;
};

type SkippedRowResolutionPreview = {
  status: string;
  errors?: string[];
  target_voter?: ImportSkippedRow['resolved_gec_voter'];
  candidate_matches?: Array<{
    confidence: string;
    match_type: string;
    gec_voter: NonNullable<ImportSkippedRow['resolved_gec_voter']>;
  }>;
};

type ImportDataResponse = {
  preview?: {
    preview_rows?: ImportPreviewRow[];
    available_villages?: string[];
    pagination?: Pagination;
  };
};

type ImportChangesResponse = {
  changes?: ImportChange[];
  pagination?: Pagination;
};

type ImportSkippedRowsResponse = {
  skipped_rows?: ImportSkippedRow[];
  pagination?: Pagination;
};

type Pagination = {
  page?: number;
  per_page?: number;
  total?: number;
  total_pages?: number;
  total_rows?: number;
};

type ContactResult = {
  id: number;
  print_name?: string | null;
  first_name: string;
  last_name: string;
  contact_number?: string | null;
  email?: string | null;
  street_address?: string | null;
  village_name?: string | null;
  contact_classification?: string | null;
  current_gec_match?: boolean | null;
};

const today = new Date().toISOString().slice(0, 10);

type PreviewResponse = {
  async?: boolean;
  source_type?: 'pdf' | 'spreadsheet';
  preview_request_id?: string;
  status?: 'pending' | 'processing' | 'completed' | 'failed';
  error?: string;
  qa?: { status?: string; quality_score?: number | null; row_count?: number; preview_mode?: boolean };
  warnings?: string[];
  row_count?: number;
  column_map?: Record<string, number>;
  preview_rows?: Array<Record<string, unknown>>;
};

function getErrorMessage(error: unknown) {
  if (error instanceof Error) return error.message;
  if (typeof error === 'object' && error && 'response' in error) {
    const response = (error as { response?: { data?: { message?: string; error?: string } } }).response;
    return response?.data?.message || response?.data?.error || 'The request failed.';
  }
  return 'The request failed.';
}

function fullName(voter: Pick<GecVoter, 'first_name' | 'middle_name' | 'last_name'>) {
  return [voter.first_name, voter.middle_name, voter.last_name].filter(Boolean).join(' ');
}

function formatDate(value?: string | null) {
  if (!value) return '—';
  return new Date(`${value}T00:00:00Z`).toLocaleDateString('en-US', { timeZone: 'Pacific/Guam' });
}

function formatDateTime(value?: string | null) {
  if (!value) return '—';
  return new Date(value).toLocaleString('en-US', {
    timeZone: 'Pacific/Guam',
    dateStyle: 'short',
    timeStyle: 'short',
  });
}

function displayValue(value: unknown) {
  if (value === null || value === undefined || value === '') return '—';
  if (typeof value === 'object') return JSON.stringify(value);
  return String(value);
}

function createPreviewRequestId() {
  return globalThis.crypto?.randomUUID?.() ?? `gec-preview-${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

function sleep(ms: number) {
  return new Promise((resolve) => window.setTimeout(resolve, ms));
}

function shouldContinueImportPolling(rows: GecImport[]) {
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
      return 'Re-vetting Contacts';
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
  metadata?: GecImport['metadata']
) {
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
    case 're_vetting':
      return 'Refreshing contact matches against the updated voter file.';
    case 'saving':
      return 'Saving import results and finishing up.';
    case 'finalizing_artifact':
      return 'Finishing import transparency files so imported data and downloads are ready as soon as the import completes.';
    default:
      return `${Math.max(5, Math.min(100, progressPercent))}% complete. Progress updates automatically.`;
  }
}

export default function GecVotersPage() {
  const queryClient = useQueryClient();
  const { data: session } = useSession();
  const canUploadGec = Boolean(session?.permissions?.can_upload_gec);
  const [search, setSearch] = useState('');
  const [submittedSearch, setSubmittedSearch] = useState('');
  const [voterVillage, setVoterVillage] = useState('');
  const [voterPrecinct, setVoterPrecinct] = useState('');
  const [voterLinkedStatus, setVoterLinkedStatus] = useState('');
  const [voterSort, setVoterSort] = useState('default');
  const [voterDirection, setVoterDirection] = useState<'asc' | 'desc'>('asc');
  const [voterPage, setVoterPage] = useState(1);
  const [householdSearch, setHouseholdSearch] = useState('');
  const [submittedHouseholdSearch, setSubmittedHouseholdSearch] = useState('');
  const [expandedHouseholds, setExpandedHouseholds] = useState<Record<string, boolean>>({});
  const [showImportPanel, setShowImportPanel] = useState(false);
  const [file, setFile] = useState<File | null>(null);
  const [listDate, setListDate] = useState(today);
  const [importType, setImportType] = useState<GecImportType>('full_list');
  const [uploadMessage, setUploadMessage] = useState<string | null>(null);
  const [uploadError, setUploadError] = useState<string | null>(null);
  const [actionMessage, setActionMessage] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [linkVoterId, setLinkVoterId] = useState<number | null>(null);
  const [contactSearch, setContactSearch] = useState('');
  const [submittedContactSearch, setSubmittedContactSearch] = useState('');
  const [previewData, setPreviewData] = useState<PreviewResponse | null>(null);
  const [confirmReview, setConfirmReview] = useState(false);
  const [pdfPreviewStatus, setPdfPreviewStatus] = useState<'idle' | 'pending' | 'processing' | 'completed' | 'failed'>('idle');
  const [expandedImportId, setExpandedImportId] = useState<number | null>(null);
  const [selectedImportId, setSelectedImportId] = useState<number | null>(null);
  const [viewerTab, setViewerTab] = useState<ImportViewerTab>('data');
  const [viewerSearch, setViewerSearch] = useState('');
  const [submittedViewerSearch, setSubmittedViewerSearch] = useState('');
  const [viewerVillage, setViewerVillage] = useState('');
  const [changeType, setChangeType] = useState('all');
  const [skippedStatus, setSkippedStatus] = useState('all');
  const [viewerPage, setViewerPage] = useState(1);
  const activePreviewRequestRef = useRef<string | null>(null);

  const statsQuery = useQuery({ queryKey: ['gec-stats'], queryFn: getGecStats });
  const importsQuery = useQuery({
    queryKey: ['gec-imports'],
    queryFn: getGecImports,
    enabled: canUploadGec,
    refetchInterval: (query) => {
      const rows = (query.state.data?.imports ?? []) as GecImport[];
      return shouldContinueImportPolling(rows) ? 3000 : false;
    },
  });
  const votersQuery = useQuery({
    queryKey: ['gec-voters', submittedSearch, voterVillage, voterPrecinct, voterLinkedStatus, voterSort, voterDirection, voterPage],
    queryFn: () => getGecVoters({
      q: submittedSearch,
      village: voterVillage || undefined,
      precinct_number: voterPrecinct || undefined,
      linked_status: voterLinkedStatus || undefined,
      sort: voterSort === 'default' ? undefined : voterSort,
      direction: voterDirection,
      page: voterPage,
      per_page: 50,
    }),
  });
  const householdsQuery = useQuery({
    queryKey: ['gec-households', submittedHouseholdSearch],
    queryFn: () => getGecHouseholds({ q: submittedHouseholdSearch }),
    enabled: submittedHouseholdSearch.trim().length >= 3,
  });
  const contactResultsQuery = useQuery({
    queryKey: ['gec-link-contact-candidates', linkVoterId, submittedContactSearch],
    queryFn: () => getSupporters({ search: submittedContactSearch, per_page: 10 }),
    enabled: Boolean(linkVoterId) && submittedContactSearch.trim().length >= 2,
  });
  const selectedFileIsPdf = Boolean(file && (file.type.includes('pdf') || file.name.toLowerCase().endsWith('.pdf')));
  const hasCompletedPreview = Boolean(previewData?.preview_rows && (previewData.row_count ?? previewData.preview_rows.length) > 0);

  async function pollPdfPreview(previewRequestId?: string) {
    if (!previewRequestId) return;

    for (const delayMs of [1000, 1500, 2000, 2500, 3000, 4000, 5000, 5000]) {
      await sleep(delayMs);
      if (activePreviewRequestRef.current !== previewRequestId) return;

      try {
        const data = await getGecPdfPreviewStatus(previewRequestId);
        if (activePreviewRequestRef.current !== previewRequestId) return;

        if (data.status === 'completed') {
          setPreviewData(data);
          setPdfPreviewStatus('completed');
          setUploadError(null);
          setUploadMessage(`PDF preview found ${data.row_count ?? 0} sample rows. Review the sample before importing.`);
          return;
        }

        if (data.status === 'failed') {
          setPreviewData(null);
          setPdfPreviewStatus('failed');
          setUploadMessage(null);
          setUploadError(`Preview failed: ${data.error || 'PDF preview failed'}`);
          return;
        }

        setPdfPreviewStatus(data.status || 'processing');
      } catch (error) {
        setPreviewData(null);
        setPdfPreviewStatus('failed');
        setUploadMessage(null);
        setUploadError(getErrorMessage(error));
        return;
      }
    }

    setPdfPreviewStatus('failed');
    setUploadMessage(null);
    setUploadError('PDF preview is taking longer than expected. Please try again.');
  }

  const previewMutation = useMutation({
    mutationFn: async () => {
      if (!file) throw new Error('Choose a file first.');
      const requestId = selectedFileIsPdf ? createPreviewRequestId() : undefined;
      if (requestId) activePreviewRequestRef.current = requestId;
      return previewGecList(file, listDate, 20, requestId);
    },
    onSuccess: (data) => {
      setUploadError(null);
      if (data.async && data.source_type === 'pdf') {
        setPdfPreviewStatus(data.status || 'pending');
        setUploadMessage('PDF preview is running in the background. This usually takes a few seconds.');
        void pollPdfPreview(data.preview_request_id);
        return;
      }

      setPreviewData(data);
      setPdfPreviewStatus('completed');
      setUploadMessage(`Preview found ${data.row_count ?? 0} rows and mapped ${Object.keys(data.column_map ?? {}).length} columns.`);
    },
    onError: (error: unknown) => {
      activePreviewRequestRef.current = null;
      setPreviewData(null);
      setPdfPreviewStatus('failed');
      setUploadMessage(null);
      setUploadError(getErrorMessage(error));
    },
  });

  const uploadMutation = useMutation({
    mutationFn: async () => {
      if (!file) throw new Error('Choose a file first.');
      return uploadGecList(file, listDate, importType, selectedFileIsPdf ? confirmReview : false);
    },
    onSuccess: (data) => {
      setUploadError(null);
      setPreviewData(null);
      setConfirmReview(false);
      setPdfPreviewStatus('idle');
      activePreviewRequestRef.current = null;
      if (data.async) {
        setUploadMessage(`Import queued in background${data.import?.id ? ` (#${data.import.id})` : ''}. You can leave this page — progress will continue and update in Import History.`);
      } else {
        setUploadMessage(`Imported ${data.stats?.total ?? 0} GEC rows. New: ${data.stats?.new ?? 0}, updated: ${data.stats?.updated ?? 0}, removed: ${data.stats?.removed ?? 0}.`);
      }
      void queryClient.invalidateQueries({ queryKey: ['gec-stats'] });
      void queryClient.invalidateQueries({ queryKey: ['gec-imports'] });
      void queryClient.invalidateQueries({ queryKey: ['gec-voters'] });
    },
    onError: (error: unknown) => {
      setUploadMessage(null);
      setUploadError(getErrorMessage(error));
    },
  });

  const createContactMutation = useMutation({
    mutationFn: (voterId: number) => createContactFromGecVoter(voterId),
    onSuccess: () => {
      setActionError(null);
      setActionMessage('Created and linked the DPG contact.');
      void queryClient.invalidateQueries({ queryKey: ['gec-voters'] });
      void queryClient.invalidateQueries({ queryKey: ['gec-households'] });
      void queryClient.invalidateQueries({ queryKey: ['session'] });
    },
    onError: (error: unknown) => {
      setActionMessage(null);
      setActionError(getErrorMessage(error));
    },
  });

  const activateImportMutation = useMutation({
    mutationFn: (importId: number) => activateGecImport(importId),
    onSuccess: () => {
      setActionError(null);
      setActionMessage('Activated the selected GEC import.');
      void queryClient.invalidateQueries({ queryKey: ['gec-stats'] });
      void queryClient.invalidateQueries({ queryKey: ['gec-imports'] });
    },
    onError: (error: unknown) => {
      setActionMessage(null);
      setActionError(getErrorMessage(error));
    },
  });

  const openOriginalMutation = useMutation({
    mutationFn: (importId: number) => openGecImportOriginal(importId),
    onError: (error: unknown) => {
      setActionMessage(null);
      setActionError(getErrorMessage(error));
    },
  });

  const downloadImportMutation = useMutation({
    mutationFn: (importId: number) => downloadGecImportFile(importId),
    onError: (error: unknown) => {
      setActionMessage(null);
      setActionError(getErrorMessage(error));
    },
  });

  const linkContactMutation = useMutation({
    mutationFn: ({ voterId, supporterId }: { voterId: number; supporterId: number }) => linkContactToGecVoter(voterId, supporterId),
    onSuccess: () => {
      setActionError(null);
      setActionMessage('Linked the existing DPG contact to the GEC voter.');
      setLinkVoterId(null);
      setContactSearch('');
      setSubmittedContactSearch('');
      void queryClient.invalidateQueries({ queryKey: ['gec-voters'] });
      void queryClient.invalidateQueries({ queryKey: ['gec-households'] });
      void queryClient.invalidateQueries({ queryKey: ['gec-link-contact-candidates'] });
    },
    onError: (error: unknown) => {
      setActionMessage(null);
      setActionError(getErrorMessage(error));
    },
  });

  const voters = useMemo<GecVoter[]>(() => votersQuery.data?.gec_voters ?? [], [votersQuery.data]);
  const voterPagination = votersQuery.data?.pagination as Pagination | undefined;
  const voterVillages = useMemo(
    () => ((statsQuery.data?.villages ?? []) as Array<{ name?: string; count?: number }>)
      .map((row) => row.name)
      .filter((name): name is string => Boolean(name)),
    [statsQuery.data]
  );
  const voterPrecincts = useMemo(
    () => Array.from(new Set(voters.map((voter) => voter.precinct_number).filter((value): value is string => Boolean(value)))).sort(),
    [voters]
  );
  const households = useMemo<Household[]>(() => householdsQuery.data?.households ?? [], [householdsQuery.data]);
  const householdAddressSuggestions = useMemo(
    () => Array.from(new Set([
      ...voters.map((voter) => voter.address),
      ...households.map((household) => household.address),
    ].filter((value): value is string => Boolean(value)))).slice(0, 30),
    [households, voters]
  );
  const imports = useMemo<GecImport[]>(() => importsQuery.data?.imports ?? [], [importsQuery.data]);
  const activeImports = imports.filter((row) => row.status === 'processing' || row.status === 'pending');
  const activeImport = activeImports.find((row) => row.status === 'processing') || activeImports[0];
  const activeProgress = Number(activeImport?.metadata?.progress_percent || 0);
  const activeProgressDisplay = Math.max(5, Math.min(100, activeProgress));
  const activeStage = String(activeImport?.metadata?.stage || 'queued');
  const activeImportIsPdf = Boolean(activeImport?.metadata?.source_type === 'pdf' || activeImport?.metadata?.pdf_qa || activeImport?.raw_content_type?.includes('pdf'));
  const activeStageLabel = getImportStageLabel(activeStage, activeImportIsPdf);
  const activeStageMessage = getImportStageMessage(activeStage, activeProgress, activeImportIsPdf, activeImport?.metadata);
  const previouslyHadActiveImport = useRef(false);
  const contactResults = useMemo<ContactResult[]>(() => contactResultsQuery.data?.supporters ?? [], [contactResultsQuery.data]);
  const selectedImport = useMemo(
    () => imports.find((row) => row.id === selectedImportId) ?? null,
    [imports, selectedImportId]
  );

  useEffect(() => {
    if (previouslyHadActiveImport.current && !activeImport) {
      void queryClient.invalidateQueries({ queryKey: ['gec-stats'] });
      void queryClient.invalidateQueries({ queryKey: ['gec-voters'] });
    }
    previouslyHadActiveImport.current = Boolean(activeImport);
  }, [activeImport, queryClient]);
  const importDataQuery = useQuery({
    queryKey: ['gec-import-data', selectedImportId, viewerPage, submittedViewerSearch, viewerVillage],
    queryFn: () => getGecImportData(selectedImportId!, {
      page: viewerPage,
      per_page: 50,
      q: submittedViewerSearch,
      village: viewerVillage,
    }),
    enabled: canUploadGec && viewerTab === 'data' && Boolean(selectedImportId),
  });
  const importChangesQuery = useQuery({
    queryKey: ['gec-import-changes', selectedImportId, viewerPage, submittedViewerSearch, changeType],
    queryFn: () => getGecImportChanges(selectedImportId!, {
      page: viewerPage,
      per_page: 50,
      q: submittedViewerSearch,
      type: changeType,
    }),
    enabled: canUploadGec && viewerTab === 'changes' && Boolean(selectedImportId),
  });
  const importSkippedRowsQuery = useQuery({
    queryKey: ['gec-import-skipped-rows', selectedImportId, viewerPage, submittedViewerSearch, skippedStatus],
    queryFn: () => getGecImportSkippedRows(selectedImportId!, {
      page: viewerPage,
      per_page: 25,
      q: submittedViewerSearch,
      status: skippedStatus,
    }),
    enabled: canUploadGec && viewerTab === 'skipped' && Boolean(selectedImportId),
  });
  const isPreviewBusy = previewMutation.isPending || pdfPreviewStatus === 'pending' || pdfPreviewStatus === 'processing';
  const canAnalyze = Boolean(file && listDate && !isPreviewBusy);
  const canImport = Boolean(
    file &&
    listDate &&
    hasCompletedPreview &&
    !isPreviewBusy &&
    !uploadMutation.isPending &&
    (!selectedFileIsPdf || (previewData?.source_type === 'pdf' && confirmReview))
  );
  const openImportViewer = (row: GecImport, tab: ImportViewerTab = 'data') => {
    setSelectedImportId(row.id);
    setViewerTab(tab);
    setViewerPage(1);
    setSubmittedViewerSearch('');
    setViewerSearch('');
    setViewerVillage('');
    setChangeType('all');
    setSkippedStatus('all');
  };

  const closeImportViewer = () => {
    setSelectedImportId(null);
    setSubmittedViewerSearch('');
    setViewerSearch('');
    setViewerVillage('');
    setChangeType('all');
    setSkippedStatus('all');
    setViewerPage(1);
  };

  const renderImportHistory = () => (
    <section className="overflow-hidden rounded-2xl border border-slate-200 bg-white">
      <div className="flex flex-col gap-3 border-b border-slate-100 p-4 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <div className="flex items-center gap-2">
            <FileText className="h-5 w-5 text-slate-500" />
            <h2 className="text-lg font-semibold text-slate-950">Import History</h2>
          </div>
          <p className="mt-1 max-w-3xl text-sm text-slate-500">
            Review every GEC list upload, inspect what changed from prior lists, and open the original file for transparency.
          </p>
        </div>
      </div>

      {imports.length === 0 ? (
        <div className="p-4 sm:p-5">
          <div className="rounded-xl bg-slate-50 p-4 text-sm text-slate-500">No GEC imports yet.</div>
        </div>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full min-w-[1100px] text-sm">
            <thead className="bg-slate-50 text-left text-xs uppercase tracking-[0.08em] text-slate-500">
              <tr>
                <th className="w-10 px-3 py-3" aria-label="Expand import details" />
                <th className="px-4 py-3">Date</th>
                <th className="px-4 py-3">File</th>
                <th className="px-4 py-3 text-right">Total</th>
                <th className="px-4 py-3 text-right">New</th>
                <th className="px-4 py-3 text-right">Updated</th>
                <th className="px-4 py-3 text-right">Removed</th>
                <th className="px-4 py-3 text-right">Transfers</th>
                <th className="px-4 py-3">Imported at</th>
                <th className="px-4 py-3">Imported by</th>
                <th className="px-4 py-3">Status</th>
                <th className="px-4 py-3 text-right">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {imports.map((row) => (
                <Fragment key={row.id}>
                  <tr className={expandedImportId === row.id ? 'bg-blue-50/40' : undefined}>
                    <td className="px-3 py-3">
                      <button
                        type="button"
                        onClick={() => setExpandedImportId((current) => (current === row.id ? null : row.id))}
                        className="inline-flex h-8 w-8 items-center justify-center rounded-lg text-slate-500 hover:bg-white hover:text-slate-900"
                        aria-label={expandedImportId === row.id ? 'Collapse import details' : 'Expand import details'}
                      >
                        <ChevronDown className={`h-4 w-4 transition-transform ${expandedImportId === row.id ? 'rotate-180' : '-rotate-90'}`} />
                      </button>
                    </td>
                    <td className="px-4 py-3 font-medium text-slate-700">{formatDate(row.gec_list_date)}</td>
                    <td className="max-w-[260px] px-4 py-3">
                      <div className="truncate font-semibold text-slate-900">{row.filename}</div>
                      <div className="mt-1 text-xs text-slate-500">
                        {row.import_type ? row.import_type.replace(/_/g, ' ') : 'full list'}
                        {row.pending_skipped_rows_count ? ` · ${row.pending_skipped_rows_count} skipped pending` : ''}
                        {row.active_election_day ? ' · Active election list' : ''}
                      </div>
                    </td>
                    <td className="px-4 py-3 text-right font-semibold text-slate-950">{row.total_records || 0}</td>
                    <td className="px-4 py-3 text-right font-semibold text-green-700">{row.new_records || 0}</td>
                    <td className="px-4 py-3 text-right font-semibold text-blue-700">{row.updated_records || 0}</td>
                    <td className="px-4 py-3 text-right font-semibold text-red-700">{row.removed_records || 0}</td>
                    <td className="px-4 py-3 text-right font-semibold text-blue-700">{row.transferred_records || 0}</td>
                    <td className="px-4 py-3 text-slate-600">{formatDateTime(row.created_at)}</td>
                    <td className="max-w-[180px] truncate px-4 py-3 text-slate-600">{row.uploaded_by_email || '—'}</td>
                    <td className="px-4 py-3">
                      <span className={`rounded-full px-2 py-1 text-xs font-semibold ${
                        row.status === 'completed'
                          ? 'bg-green-50 text-green-700'
                          : row.status === 'failed'
                            ? 'bg-red-50 text-red-700'
                            : 'bg-amber-50 text-amber-700'
                      }`}
                      >
                        {row.status}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-right">
                      <button
                        type="button"
                        disabled={row.status !== 'completed'}
                        onClick={() => openImportViewer(row)}
                        title={row.status === 'completed' ? undefined : 'Import review is available after the import completes'}
                        className="inline-flex min-h-8 items-center gap-1 rounded-lg border border-blue-200 bg-white px-2 text-xs font-semibold text-blue-700 hover:bg-blue-50 disabled:border-slate-200 disabled:text-slate-400 disabled:opacity-60"
                      >
                        <Eye className="h-3.5 w-3.5" />
                        Open
                      </button>
                    </td>
                  </tr>
                  {expandedImportId === row.id && (
                    <tr className="bg-slate-50/60">
                      <td colSpan={12} className="px-4 py-4">
                        <div className="grid gap-4 rounded-xl bg-white p-4 shadow-sm ring-1 ring-slate-100 lg:grid-cols-3">
                          <div className="space-y-2">
                            <div className="text-xs font-semibold uppercase tracking-[0.08em] text-slate-400">Import details</div>
                            <div className="text-sm text-slate-700">Imported at: <span className="font-semibold text-slate-900">{formatDateTime(row.created_at)}</span></div>
                            <div className="text-sm text-slate-700">Imported by: <span className="font-semibold text-slate-900">{row.uploaded_by_email || '—'}</span></div>
                            <div className="text-sm text-slate-700">Filename: <span className="font-semibold text-slate-900">{row.filename}</span></div>
                            <div className="text-sm text-slate-700">List date: <span className="font-semibold text-slate-900">{formatDate(row.gec_list_date)}</span></div>
                            <div className="text-sm text-slate-700">Type: <span className="font-semibold text-slate-900">{row.import_type?.replace(/_/g, ' ') || 'full list'}</span></div>
                          </div>
                          <div className="space-y-2">
                            <div className="text-xs font-semibold uppercase tracking-[0.08em] text-slate-400">Breakdown</div>
                            <div className="text-sm text-slate-700">Total processed: <span className="font-semibold text-slate-900">{row.total_records || 0}</span></div>
                            <div className="text-sm text-green-700">New records: <span className="font-semibold">{row.new_records || 0}</span></div>
                            <div className="text-sm text-blue-700">Updated records: <span className="font-semibold">{row.updated_records || 0}</span></div>
                            <div className="text-sm text-red-700">Removed / purged: <span className="font-semibold">{row.removed_records || 0}</span></div>
                            <div className="text-sm text-blue-700">Transferred villages: <span className="font-semibold">{row.transferred_records || 0}</span></div>
                          </div>
                          <div className="space-y-3">
                            <div className="text-xs font-semibold uppercase tracking-[0.08em] text-slate-400">Additional</div>
                            <div className="text-sm text-slate-700">Skipped rows: <span className="font-semibold text-slate-900">{row.skipped_rows_count || 0}</span></div>
                            <div className="text-sm text-slate-700">Pending fixes: <span className="font-semibold text-slate-900">{row.pending_skipped_rows_count || 0}</span></div>
                            <div className="flex flex-wrap gap-2 pt-1">
                              <button type="button" disabled={row.status !== 'completed'} onClick={() => openImportViewer(row)} className="app-btn-secondary min-h-10">
                                <Eye className="h-4 w-4" />
                                Open Import
                              </button>
                              {row.has_original_file ? (
                                <button type="button" disabled={openOriginalMutation.isPending} onClick={() => openOriginalMutation.mutate(row.id)} className="app-btn-secondary min-h-10">
                                  <FileText className="h-4 w-4" />
                                  Original
                                </button>
                              ) : null}
                              {row.has_downloadable_file ? (
                                <button type="button" disabled={downloadImportMutation.isPending} onClick={() => downloadImportMutation.mutate(row.id)} className="app-btn-secondary min-h-10">
                                  <Download className="h-4 w-4" />
                                  Download
                                </button>
                              ) : null}
                              {row.status === 'completed' && !row.active_election_day ? (
                                <button type="button" disabled={activateImportMutation.isPending} onClick={() => activateImportMutation.mutate(row.id)} className="app-btn-secondary min-h-10">
                                  Activate
                                </button>
                              ) : null}
                            </div>
                          </div>
                        </div>
                      </td>
                    </tr>
                  )}
                </Fragment>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );

  return (
    <WorkspacePage width="full" className="space-y-6">
      <div className="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
        <div>
          <div className="mb-2 inline-flex items-center gap-2 rounded-full bg-blue-50 px-3 py-1 text-xs font-semibold uppercase tracking-[0.12em] text-blue-700">
            <Database className="h-3.5 w-3.5" />
            Public voter file
          </div>
          <h1 className="text-2xl font-bold tracking-tight text-slate-950">GEC Voter List</h1>
          <p className="mt-1 max-w-3xl text-sm text-slate-500">
            Search official voter records by name, address, village, precinct, or registration number, then link voters into DPG contacts for follow-up.
          </p>
        </div>
      </div>

      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard label="Active GEC voters" value={statsQuery.data?.total_voters ?? 0} />
        <StatCard label="Linked DPG contacts" value={statsQuery.data?.linked_contacts ?? 0} />
        <StatCard label="Latest list" value={formatDate(statsQuery.data?.latest_list_date)} />
        <StatCard label="Removed records" value={statsQuery.data?.removed_voters ?? 0} />
      </div>

      {actionMessage && (
        <div className="flex items-start gap-2 rounded-xl bg-green-50 px-3 py-2 text-sm text-green-800">
          <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0" />
          {actionMessage}
        </div>
      )}
      {actionError && (
        <div className="flex items-start gap-2 rounded-xl bg-red-50 px-3 py-2 text-sm text-red-800">
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
          {actionError}
        </div>
      )}

      {activeImport && (
        <div className="rounded-xl border border-blue-200 bg-blue-50 p-4">
          <div className="mb-2 flex items-center justify-between gap-3">
            <div className="text-sm font-semibold text-blue-900">
              {activeImports.length > 1 ? `${activeImports.length} imports in progress` : 'Background import in progress'}
            </div>
            <div className="text-xs font-semibold text-blue-700">{activeStageLabel}</div>
          </div>
          <div className="h-2 w-full overflow-hidden rounded-full bg-blue-100">
            <div className="h-full bg-blue-600 transition-all" style={{ width: `${activeProgressDisplay}%` }} />
          </div>
          <div className="mt-2 text-xs text-blue-700">{activeStageMessage}</div>
          {activeImport.metadata?.error && (
            <div className="mt-2 text-xs font-medium text-red-700">{String(activeImport.metadata.error)}</div>
          )}
        </div>
      )}

      {canUploadGec && (
        <section className="app-card p-4 sm:p-5">
          <button
            type="button"
            onClick={() => setShowImportPanel((current) => !current)}
            className="flex w-full items-center justify-between gap-4 text-left"
          >
            <span className="flex min-w-0 items-center gap-3">
              <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-blue-50 text-blue-700">
                <Upload className="h-5 w-5" />
              </span>
              <span className="min-w-0">
                <span className="block text-lg font-semibold text-slate-950">Upload New GEC List</span>
                <span className="block text-sm text-slate-500">
                  Analyze the public voter file, review a sample, then queue the full background import.
                </span>
              </span>
            </span>
            <ChevronDown className={`h-5 w-5 shrink-0 text-slate-500 transition-transform ${showImportPanel ? 'rotate-180' : ''}`} />
          </button>

          {showImportPanel && (
            <div className="mt-5 space-y-4 border-t border-slate-100 pt-5">
              <label className="block">
                <span className="mb-1 block text-xs font-semibold uppercase tracking-[0.08em] text-slate-500">Excel / PDF file</span>
                <span className="flex min-h-11 w-full items-center gap-3 rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm">
                  <span className="inline-flex shrink-0 cursor-pointer items-center rounded-lg bg-blue-50 px-3 py-1.5 font-semibold text-blue-700 hover:bg-blue-100">
                    Choose File
                    <input
                      type="file"
                      accept=".csv,.xlsx,.xls,.pdf"
                      onChange={(event) => {
                        setFile(event.target.files?.[0] ?? null);
                        setPreviewData(null);
                        setUploadMessage(null);
                        setUploadError(null);
                        setConfirmReview(false);
                        setPdfPreviewStatus('idle');
                        activePreviewRequestRef.current = null;
                      }}
                      className="sr-only"
                    />
                  </span>
                  <span className="min-w-0 truncate text-slate-950">{file?.name || 'No file chosen'}</span>
                </span>
              </label>

              <div className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_minmax(220px,320px)]">
                <div>
                  <span className="mb-2 block text-xs font-semibold uppercase tracking-[0.08em] text-slate-500">Import type</span>
                  <div className="grid gap-3 sm:grid-cols-2">
                    <label className={`flex cursor-pointer items-center gap-3 rounded-xl border p-4 transition-colors ${
                      importType === 'full_list'
                        ? 'border-blue-300 bg-blue-50 text-blue-900'
                        : 'border-slate-200 bg-white text-slate-600 hover:bg-slate-50'
                    }`}>
                      <input
                        type="radio"
                        name="gecImportType"
                        value="full_list"
                        checked={importType === 'full_list'}
                        onChange={() => {
                          setImportType('full_list');
                          setPreviewData(null);
                          setUploadMessage(null);
                          setUploadError(null);
                          setConfirmReview(false);
                          setPdfPreviewStatus('idle');
                          activePreviewRequestRef.current = null;
                        }}
                        className="sr-only"
                      />
                      <Database className="h-4 w-4 shrink-0" />
                      <span>
                        <span className="block font-semibold">Full voter list</span>
                        <span className={`mt-1 block text-xs ${importType === 'full_list' ? 'text-blue-700' : 'text-slate-500'}`}>
                          Detects new voters, updates, purges, transfers, and address changes.
                        </span>
                      </span>
                    </label>
                    <label className={`flex cursor-pointer items-center gap-3 rounded-xl border p-4 transition-colors ${
                      importType === 'changes_only'
                        ? 'border-blue-300 bg-blue-50 text-blue-900'
                        : 'border-slate-200 bg-white text-slate-600 hover:bg-slate-50'
                    }`}>
                      <input
                        type="radio"
                        name="gecImportType"
                        value="changes_only"
                        checked={importType === 'changes_only'}
                        onChange={() => {
                          setImportType('changes_only');
                          setPreviewData(null);
                          setUploadMessage(null);
                          setUploadError(null);
                          setConfirmReview(false);
                          setPdfPreviewStatus('idle');
                          activePreviewRequestRef.current = null;
                        }}
                        className="sr-only"
                      />
                      <RefreshCw className="h-4 w-4 shrink-0" />
                      <span>
                        <span className="block font-semibold">Changes only</span>
                        <span className={`mt-1 block text-xs ${importType === 'changes_only' ? 'text-blue-700' : 'text-slate-500'}`}>
                          Adds and updates only, with no purge detection.
                        </span>
                      </span>
                    </label>
                  </div>
                </div>
                <label className="block">
                  <span className="mb-2 block text-xs font-semibold uppercase tracking-[0.08em] text-slate-500">GEC list date</span>
                  <input
                    type="date"
                    value={listDate}
                    onChange={(event) => {
                      setListDate(event.target.value);
                      setPreviewData(null);
                      setUploadMessage(null);
                      setUploadError(null);
                      setConfirmReview(false);
                      setPdfPreviewStatus('idle');
                      activePreviewRequestRef.current = null;
                    }}
                    className="block w-full rounded-xl border border-slate-200 bg-white px-3 py-3 text-sm"
                  />
                </label>
              </div>

              <div className="flex flex-col gap-3 sm:flex-row">
                <button
                  type="button"
                  disabled={!canAnalyze}
                  onClick={() => previewMutation.mutate()}
                  className="app-btn-secondary min-h-11 justify-center"
                >
                  {isPreviewBusy ? <Loader2 className="h-4 w-4 animate-spin" /> : <Database className="h-4 w-4" />}
                  Analyze File
                </button>
                <button
                  type="button"
                  disabled={!canImport}
                  onClick={() => uploadMutation.mutate()}
                  className="app-btn-primary min-h-11 justify-center"
                  title={!hasCompletedPreview ? 'Analyze file first to review before importing' : undefined}
                >
                  {uploadMutation.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Upload className="h-4 w-4" />}
                  Confirm & Import
                </button>
              </div>

              {previewData && (
                <div className="rounded-xl border border-blue-100 bg-blue-50 p-3 text-sm text-blue-900">
                  <div className="font-semibold">
                    {previewData.source_type === 'pdf' ? 'PDF Preview Summary' : 'Spreadsheet Preview Summary'}
                  </div>
                  <div className="mt-2 grid gap-1 text-blue-800 sm:grid-cols-3">
                    <div>Rows sampled: <span className="font-semibold">{previewData.row_count ?? 0}</span></div>
                    <div>Quality: <span className="font-semibold">{previewData.qa?.status || 'preview'}</span></div>
                    <div>Status: <span className="font-semibold uppercase">{previewData.status || 'preview'}</span></div>
                  </div>
                  {previewData.preview_rows?.length ? (
                    <div className="mt-3 max-h-80 overflow-auto rounded-xl border border-blue-100 bg-white">
                      <table className="w-full min-w-[720px] text-left text-xs">
                        <thead className="bg-slate-50 uppercase tracking-[0.08em] text-slate-500">
                          <tr>
                            <th className="px-3 py-2">Reg No.</th>
                            <th className="px-3 py-2">Name</th>
                            <th className="px-3 py-2">Address</th>
                            <th className="px-3 py-2">Village</th>
                            <th className="px-3 py-2">Precinct</th>
                            <th className="px-3 py-2">Birth Year</th>
                          </tr>
                        </thead>
                        <tbody className="divide-y divide-slate-100">
                          {previewData.preview_rows.slice(0, 20).map((row, index) => (
                            <tr key={index}>
                              <td className="px-3 py-2">{displayValue(row.voter_registration_number || row.registration_number || row.reg_no)}</td>
                              <td className="px-3 py-2 font-medium text-slate-900">{displayValue(row.name) !== '—' ? displayValue(row.name) : [row.first_name, row.middle_name, row.last_name].map(displayValue).filter((value) => value !== '—').join(' ')}</td>
                              <td className="px-3 py-2">{displayValue(row.address)}</td>
                              <td className="px-3 py-2">{displayValue(row.village_name || row.village)}</td>
                              <td className="px-3 py-2">{displayValue(row.precinct_number || row.precinct)}</td>
                              <td className="px-3 py-2">{displayValue(row.birth_year || row.year_of_birth)}</td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  ) : null}
                  {selectedFileIsPdf && (
                    <label className="mt-3 flex items-start gap-2 rounded-lg border border-amber-200 bg-amber-50 px-3 py-2 text-sm font-medium text-amber-900">
                      <input
                        type="checkbox"
                        checked={confirmReview}
                        onChange={(event) => setConfirmReview(event.target.checked)}
                        className="mt-0.5 h-4 w-4 rounded border-amber-300"
                      />
                      I reviewed the sample and want to proceed with the background import.
                    </label>
                  )}
                </div>
              )}

              {renderImportHistory()}
            </div>
          )}
          {uploadMessage && (
            <div className="mt-3 flex items-start gap-2 rounded-xl bg-green-50 px-3 py-2 text-sm text-green-800">
              <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0" />
              {uploadMessage}
            </div>
          )}
          {uploadError && (
            <div className="mt-3 flex items-start gap-2 rounded-xl bg-red-50 px-3 py-2 text-sm text-red-800">
              <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
              {uploadError}
            </div>
          )}
        </section>
      )}

      <section className="grid gap-6 xl:grid-cols-[minmax(0,1fr)_420px]">
        <div className="app-card overflow-hidden">
          <div className="border-b border-slate-200 p-4 sm:p-5">
            <form
              className="flex flex-col gap-3 sm:flex-row"
              onSubmit={(event) => {
                event.preventDefault();
                setSubmittedSearch(search.trim());
                setVoterPage(1);
              }}
            >
              <div className="relative flex-1">
                <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" />
                <input
                  value={search}
                  onChange={(event) => setSearch(event.target.value)}
                  placeholder="Search name, address, precinct, village, or voter number"
                  className="w-full rounded-xl border border-slate-200 bg-white py-3 pl-10 pr-3 text-sm"
                />
              </div>
              <button type="submit" className="app-btn-primary min-h-11 justify-center">
                <Search className="h-4 w-4" />
                Search
              </button>
            </form>
            <div className="mt-3 grid gap-2 md:grid-cols-5">
              <select
                value={voterVillage}
                onChange={(event) => {
                  setVoterVillage(event.target.value);
                  setVoterPage(1);
                }}
                className="rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm text-slate-700"
              >
                <option value="">All villages</option>
                {voterVillages.map((village) => (
                  <option key={village} value={village}>{village}</option>
                ))}
              </select>
              <input
                value={voterPrecinct}
                onChange={(event) => {
                  setVoterPrecinct(event.target.value);
                  setVoterPage(1);
                }}
                list="gec-precinct-options"
                placeholder="Precinct"
                className="rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm text-slate-700"
              />
              <datalist id="gec-precinct-options">
                {voterPrecincts.map((precinct) => (
                  <option key={precinct} value={precinct} />
                ))}
              </datalist>
              <select
                value={voterLinkedStatus}
                onChange={(event) => {
                  setVoterLinkedStatus(event.target.value);
                  setVoterPage(1);
                }}
                className="rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm text-slate-700"
              >
                <option value="">All link statuses</option>
                <option value="linked">Linked to DPG contact</option>
                <option value="unlinked">Not linked</option>
              </select>
              <select
                value={voterSort}
                onChange={(event) => {
                  setVoterSort(event.target.value);
                  setVoterPage(1);
                }}
                className="rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm text-slate-700"
              >
                <option value="default">Default order</option>
                <option value="name">Name</option>
                <option value="village">Village</option>
                <option value="precinct">Precinct</option>
                <option value="birth_year">Birth year</option>
              </select>
              <select
                value={voterDirection}
                onChange={(event) => {
                  setVoterDirection(event.target.value as 'asc' | 'desc');
                  setVoterPage(1);
                }}
                className="rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm text-slate-700"
              >
                <option value="asc">Ascending</option>
                <option value="desc">Descending</option>
              </select>
            </div>
          </div>

          <div className="overflow-x-auto">
            <table className="w-full min-w-[760px] text-sm">
              <thead className="bg-slate-50 text-left text-xs uppercase tracking-[0.08em] text-slate-500">
                <tr>
                  <th className="px-4 py-3">Voter</th>
                  <th className="px-4 py-3">Address</th>
                  <th className="px-4 py-3">Village</th>
                  <th className="px-4 py-3">Precinct</th>
                  <th className="px-4 py-3">DPG Contact</th>
                  <th className="px-4 py-3 text-right">Action</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {votersQuery.isLoading ? (
                  <tr><td colSpan={6} className="px-4 py-12 text-center text-slate-500">Loading voters...</td></tr>
                ) : voters.length === 0 ? (
                  <tr><td colSpan={6} className="px-4 py-12 text-center text-slate-500">No GEC voters found</td></tr>
                ) : voters.map((voter) => (
                  <Fragment key={voter.id}>
                    <tr className="align-top">
                      <td className="px-4 py-3">
                        <div className="font-semibold text-slate-950">{fullName(voter)}</div>
                        <div className="text-xs text-slate-500">{voter.voter_registration_number || 'No voter number'}{voter.birth_year ? ` · Born ${voter.birth_year}` : ''}</div>
                      </td>
                      <td className="px-4 py-3 text-slate-600">{voter.address || '—'}</td>
                      <td className="px-4 py-3 text-slate-600">{voter.village_name}</td>
                      <td className="px-4 py-3 text-slate-600">{voter.precinct_number || '—'}</td>
                      <td className="px-4 py-3 text-slate-600">
                        {voter.linked_contact_count ? `${voter.linked_contact_count} linked` : 'Not linked'}
                      </td>
                      <td className="px-4 py-3 text-right">
                        <div className="flex flex-col items-end gap-2">
                          <button
                            type="button"
                            disabled={createContactMutation.isPending}
                            onClick={() => createContactMutation.mutate(voter.id)}
                            className="inline-flex min-h-10 items-center justify-center gap-2 rounded-xl border border-slate-200 px-3 text-xs font-semibold text-slate-700 hover:bg-slate-50 disabled:opacity-50"
                          >
                            <LinkIcon className="h-4 w-4" />
                            Create Contact
                          </button>
                          <button
                            type="button"
                            onClick={() => {
                              const nextId = linkVoterId === voter.id ? null : voter.id;
                              setLinkVoterId(nextId);
                              setContactSearch('');
                              setSubmittedContactSearch('');
                            }}
                            className="inline-flex min-h-10 items-center justify-center gap-2 rounded-xl border border-slate-200 px-3 text-xs font-semibold text-slate-700 hover:bg-slate-50"
                          >
                            <Users className="h-4 w-4" />
                            Link Existing
                          </button>
                        </div>
                      </td>
                    </tr>
                    {linkVoterId === voter.id && (
                      <tr>
                        <td colSpan={6} className="bg-slate-50 px-4 py-4">
                          <form
                            className="flex flex-col gap-2 sm:flex-row"
                            onSubmit={(event) => {
                              event.preventDefault();
                              setSubmittedContactSearch(contactSearch.trim());
                            }}
                          >
                            <input
                              value={contactSearch}
                              onChange={(event) => setContactSearch(event.target.value)}
                              placeholder="Search existing DPG contacts by name, phone, email, or address"
                              className="min-w-0 flex-1 rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm"
                            />
                            <button type="submit" className="app-btn-secondary min-h-10 justify-center">
                              <Search className="h-4 w-4" />
                              Find Contact
                            </button>
                          </form>
                          <div className="mt-3 space-y-2">
                            {contactResultsQuery.isFetching ? (
                              <div className="text-sm text-slate-500">Searching contacts...</div>
                            ) : submittedContactSearch && contactResults.length === 0 ? (
                              <div className="text-sm text-slate-500">No matching contacts found.</div>
                            ) : contactResults.map((contact) => (
                              <div key={contact.id} className="flex flex-col gap-2 rounded-xl border border-slate-200 bg-white p-3 sm:flex-row sm:items-center sm:justify-between">
                                <div className="min-w-0">
                                  <div className="font-semibold text-slate-900">{contact.print_name || `${contact.first_name} ${contact.last_name}`}</div>
                                  <div className="text-xs text-slate-500">
                                    {[contact.contact_number, contact.email, contact.village_name, contact.street_address].filter(Boolean).join(' · ') || 'No contact details'}
                                  </div>
                                </div>
                                <button
                                  type="button"
                                  disabled={linkContactMutation.isPending}
                                  onClick={() => linkContactMutation.mutate({ voterId: voter.id, supporterId: contact.id })}
                                  className="inline-flex min-h-10 items-center justify-center gap-2 rounded-xl bg-primary px-3 text-xs font-semibold text-white disabled:opacity-50"
                                >
                                  <LinkIcon className="h-4 w-4" />
                                  Link
                                </button>
                              </div>
                            ))}
                          </div>
                        </td>
                      </tr>
                    )}
                  </Fragment>
                ))}
              </tbody>
            </table>
          </div>
          {voterPagination && (
            <div className="flex flex-col gap-3 border-t border-slate-100 px-4 py-3 text-sm text-slate-500 sm:flex-row sm:items-center sm:justify-between">
              <span>
                Page {voterPagination.page ?? voterPage} of {voterPagination.total_pages ?? 1} · {voterPagination.total ?? 0} voters
              </span>
              <div className="flex gap-2">
                <button
                  type="button"
                  disabled={voterPage <= 1}
                  onClick={() => setVoterPage((page) => Math.max(1, page - 1))}
                  className="rounded-lg border border-slate-200 px-3 py-2 font-semibold text-slate-700 disabled:opacity-40"
                >
                  Prev
                </button>
                <button
                  type="button"
                  disabled={voterPage >= (voterPagination.total_pages ?? 1)}
                  onClick={() => setVoterPage((page) => page + 1)}
                  className="rounded-lg border border-slate-200 px-3 py-2 font-semibold text-slate-700 disabled:opacity-40"
                >
                  Next
                </button>
              </div>
            </div>
          )}
        </div>

        <div className="space-y-6">
          <section className="app-card p-4 sm:p-5">
            <div className="mb-4 flex items-center gap-2">
              <Home className="h-5 w-5 text-blue-600" />
              <h2 className="text-lg font-semibold text-slate-950">Household Lookup</h2>
            </div>
            <form
              className="flex gap-2"
              onSubmit={(event) => {
                event.preventDefault();
                setSubmittedHouseholdSearch(householdSearch.trim());
              }}
            >
              <input
                list="household-address-suggestions"
                value={householdSearch}
                onChange={(event) => setHouseholdSearch(event.target.value)}
                placeholder="Street address or house number"
                className="min-w-0 flex-1 rounded-xl border border-slate-200 bg-white px-3 py-3 text-sm"
              />
              <datalist id="household-address-suggestions">
                {householdAddressSuggestions.map((address) => (
                  <option key={address} value={address} />
                ))}
              </datalist>
              <button type="submit" className="app-btn-primary min-h-11 justify-center px-3">
                <Search className="h-4 w-4" />
              </button>
            </form>
            <div className="mt-4 space-y-3">
              {householdsQuery.isFetching ? (
                <div className="rounded-xl bg-slate-50 p-4 text-sm text-slate-500">Searching addresses...</div>
              ) : households.map((household) => {
                const householdKey = `${household.village_name}-${household.address}`;
                const isExpanded = Boolean(expandedHouseholds[householdKey]);
                const visibleVoters = isExpanded ? household.gec_voters : household.gec_voters.slice(0, 8);

                return (
                  <div key={householdKey} className="rounded-xl border border-slate-200 p-3">
                    <div className="font-semibold text-slate-950">{household.address}</div>
                    <div className="text-xs text-slate-500">{household.village_name}</div>
                    <div className="mt-3 grid gap-2 text-sm sm:grid-cols-2 xl:grid-cols-1">
                      <div className="rounded-lg bg-blue-50 p-2 text-blue-900">
                        <div className="mb-1 flex items-center gap-1 text-xs font-semibold uppercase tracking-[0.08em]">
                          <Database className="h-3.5 w-3.5" />
                          GEC voters
                        </div>
                        {household.gec_voters.length || 0} found
                      </div>
                      <div className="rounded-lg bg-green-50 p-2 text-green-900">
                        <div className="mb-1 flex items-center gap-1 text-xs font-semibold uppercase tracking-[0.08em]">
                          <Users className="h-3.5 w-3.5" />
                          DPG contacts
                        </div>
                        {household.contacts.length || 0} found
                      </div>
                    </div>
                    {household.contacts.length > 0 && (
                      <div className="mt-3 rounded-lg bg-green-50/70 p-2">
                        <div className="mb-1 text-xs font-semibold uppercase tracking-[0.08em] text-green-900">DPG contacts at this address</div>
                        <div className="space-y-1">
                          {household.contacts.map((contact) => (
                            <div key={contact.id} className="text-sm text-slate-700">
                              {contact.print_name || `${contact.first_name} ${contact.last_name}`}
                              {contact.current_gec_match ? <span className="ml-2 rounded-full bg-white px-2 py-0.5 text-xs font-semibold text-green-700">matched</span> : null}
                            </div>
                          ))}
                        </div>
                      </div>
                    )}
                    <div className="mt-3 space-y-2">
                      {visibleVoters.map((voter) => (
                        <div key={voter.id} className="rounded-lg border border-slate-100 bg-white p-2">
                          <div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
                            <div className="min-w-0">
                              <div className="font-semibold text-slate-800">{fullName(voter)}</div>
                              <div className="text-xs text-slate-500">
                                {[voter.voter_registration_number, voter.birth_year ? `Born ${voter.birth_year}` : null, voter.precinct_number ? `Pct ${voter.precinct_number}` : null].filter(Boolean).join(' · ')}
                              </div>
                            </div>
                            <div className="flex shrink-0 flex-wrap gap-2">
                              <button
                                type="button"
                                onClick={() => createContactMutation.mutate(voter.id)}
                                disabled={createContactMutation.isPending || Boolean(voter.linked_contact_count)}
                                className="inline-flex min-h-9 items-center justify-center gap-2 rounded-lg border border-slate-200 px-2.5 text-xs font-semibold text-slate-700 disabled:cursor-not-allowed disabled:opacity-45"
                              >
                                <Users className="h-3.5 w-3.5" />
                                {voter.linked_contact_count ? 'Linked' : 'Create'}
                              </button>
                              <button
                                type="button"
                                onClick={() => {
                                  const nextVoterId = linkVoterId === voter.id ? null : voter.id;
                                  setLinkVoterId(nextVoterId);
                                  setContactSearch(nextVoterId ? fullName(voter) : '');
                                  setSubmittedContactSearch('');
                                }}
                                disabled={linkContactMutation.isPending || Boolean(voter.linked_contact_count)}
                                className="inline-flex min-h-9 items-center justify-center gap-2 rounded-lg border border-slate-200 px-2.5 text-xs font-semibold text-slate-700 disabled:cursor-not-allowed disabled:opacity-45"
                              >
                                <LinkIcon className="h-3.5 w-3.5" />
                                Link
                              </button>
                            </div>
                          </div>
                          {linkVoterId === voter.id && (
                            <div className="mt-3 rounded-lg bg-slate-50 p-2">
                              <form
                                className="flex gap-2"
                                onSubmit={(event) => {
                                  event.preventDefault();
                                  setSubmittedContactSearch(contactSearch.trim());
                                }}
                              >
                                <input
                                  value={contactSearch}
                                  onChange={(event) => setContactSearch(event.target.value)}
                                  placeholder="Search DPG contacts"
                                  className="min-w-0 flex-1 rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm"
                                />
                                <button type="submit" className="rounded-lg bg-primary px-3 text-sm font-semibold text-white">Search</button>
                              </form>
                              <div className="mt-2 space-y-2">
                                {contactResultsQuery.isFetching ? (
                                  <div className="text-sm text-slate-500">Searching contacts...</div>
                                ) : submittedContactSearch && contactResults.length === 0 ? (
                                  <div className="text-sm text-slate-500">No matching DPG contacts found.</div>
                                ) : contactResults.map((contact) => (
                                  <div key={contact.id} className="flex flex-col gap-2 rounded-lg border border-slate-200 bg-white p-2 sm:flex-row sm:items-center sm:justify-between">
                                    <div className="min-w-0">
                                      <div className="font-semibold text-slate-900">{contact.print_name || `${contact.first_name} ${contact.last_name}`}</div>
                                      <div className="text-xs text-slate-500">
                                        {[contact.contact_number, contact.email, contact.village_name, contact.street_address].filter(Boolean).join(' · ') || 'No contact details'}
                                      </div>
                                    </div>
                                    <button
                                      type="button"
                                      disabled={linkContactMutation.isPending}
                                      onClick={() => linkContactMutation.mutate({ voterId: voter.id, supporterId: contact.id })}
                                      className="inline-flex min-h-9 items-center justify-center gap-2 rounded-lg bg-primary px-3 text-xs font-semibold text-white disabled:opacity-50"
                                    >
                                      <LinkIcon className="h-3.5 w-3.5" />
                                      Link
                                    </button>
                                  </div>
                                ))}
                              </div>
                            </div>
                          )}
                        </div>
                      ))}
                      {household.gec_voters.length > 8 && (
                        <button
                          type="button"
                          onClick={() => setExpandedHouseholds((current) => ({ ...current, [householdKey]: !isExpanded }))}
                          className="w-full rounded-lg border border-slate-200 px-3 py-2 text-sm font-semibold text-blue-700 hover:bg-blue-50"
                        >
                          {isExpanded ? 'Show fewer voters' : `Show all ${household.gec_voters.length} voters`}
                        </button>
                      )}
                    </div>
                  </div>
                );
              })}
              {submittedHouseholdSearch && !householdsQuery.isFetching && households.length === 0 && (
                <div className="rounded-xl bg-slate-50 p-4 text-sm text-slate-500">No households found for that address.</div>
              )}
            </div>
          </section>
        </div>
      </section>

      {selectedImport && (
        <div className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-slate-950/55 px-3 py-6 backdrop-blur-sm sm:px-6">
          <div className="my-auto flex h-[86vh] w-full max-w-6xl flex-col overflow-hidden rounded-2xl bg-white shadow-2xl">
            <div className="flex items-start justify-between gap-4 border-b border-slate-100 px-5 py-4">
              <div className="min-w-0">
                <div className="text-xs font-semibold uppercase tracking-[0.08em] text-blue-700">Import transparency</div>
                <h2 className="mt-1 truncate text-xl font-semibold text-slate-950">{selectedImport.filename}</h2>
                <div className="mt-1 text-sm text-slate-500">
                  Imported at: {formatDateTime(selectedImport.created_at)} · Imported by: {selectedImport.uploaded_by_email || '—'} · Type: {selectedImport.import_type?.replace(/_/g, ' ') || 'full list'} · Status: {selectedImport.status}
                </div>
              </div>
              <button
                type="button"
                onClick={closeImportViewer}
                className="inline-flex h-10 w-10 shrink-0 items-center justify-center rounded-xl text-slate-500 hover:bg-slate-100 hover:text-slate-950"
                aria-label="Close import transparency"
              >
                <X className="h-5 w-5" />
              </button>
            </div>
            <div className="min-h-0 flex-1 overflow-y-auto p-4 sm:p-5">
              <ImportReviewPanel
                selectedImport={selectedImport}
                viewerTab={viewerTab}
                setViewerTab={(tab) => {
                  setViewerTab(tab);
                  setViewerPage(1);
                }}
                viewerSearch={viewerSearch}
                setViewerSearch={setViewerSearch}
                submitSearch={() => {
                  setSubmittedViewerSearch(viewerSearch.trim());
                  setViewerPage(1);
                }}
                viewerVillage={viewerVillage}
                setViewerVillage={(value) => {
                  setViewerVillage(value);
                  setViewerPage(1);
                }}
                changeType={changeType}
                setChangeType={(value) => {
                  setChangeType(value);
                  setViewerPage(1);
                }}
                skippedStatus={skippedStatus}
                setSkippedStatus={(value) => {
                  setSkippedStatus(value);
                  setViewerPage(1);
                }}
                viewerPage={viewerPage}
                setViewerPage={setViewerPage}
                dataQuery={importDataQuery}
                changesQuery={importChangesQuery}
                skippedRowsQuery={importSkippedRowsQuery}
              />
            </div>
          </div>
        </div>
      )}
    </WorkspacePage>
  );
}

type ImportReviewPanelProps = {
  selectedImport: GecImport;
  viewerTab: ImportViewerTab;
  setViewerTab: (tab: ImportViewerTab) => void;
  viewerSearch: string;
  setViewerSearch: (value: string) => void;
  submitSearch: () => void;
  viewerVillage: string;
  setViewerVillage: (value: string) => void;
  changeType: string;
  setChangeType: (value: string) => void;
  skippedStatus: string;
  setSkippedStatus: (value: string) => void;
  viewerPage: number;
  setViewerPage: (page: number) => void;
  dataQuery: { data?: ImportDataResponse; isFetching: boolean; isError: boolean; error: unknown };
  changesQuery: { data?: ImportChangesResponse; isFetching: boolean; isError: boolean; error: unknown };
  skippedRowsQuery: { data?: ImportSkippedRowsResponse; isFetching: boolean; isError: boolean; error: unknown };
};

function ImportReviewPanel({
  selectedImport,
  viewerTab,
  setViewerTab,
  viewerSearch,
  setViewerSearch,
  submitSearch,
  viewerVillage,
  setViewerVillage,
  changeType,
  setChangeType,
  skippedStatus,
  setSkippedStatus,
  viewerPage,
  setViewerPage,
  dataQuery,
  changesQuery,
  skippedRowsQuery,
}: ImportReviewPanelProps) {
  const dataPreview = dataQuery.data?.preview;
  const dataRows = (dataPreview?.preview_rows ?? []) as ImportPreviewRow[];
  const dataVillages = (dataPreview?.available_villages ?? []) as string[];
  const dataPagination = dataPreview?.pagination;
  const changeRows = (changesQuery.data?.changes ?? []) as ImportChange[];
  const changePagination = changesQuery.data?.pagination;
  const skippedRows = (skippedRowsQuery.data?.skipped_rows ?? []) as ImportSkippedRow[];
  const skippedPagination = skippedRowsQuery.data?.pagination;
  const activeQuery = viewerTab === 'data' ? dataQuery : viewerTab === 'changes' ? changesQuery : skippedRowsQuery;
  const activePagination = viewerTab === 'data' ? dataPagination : viewerTab === 'changes' ? changePagination : skippedPagination;

  return (
    <div className="rounded-2xl border border-slate-200 bg-white p-3">
      <div className="flex flex-col gap-3 border-b border-slate-100 pb-3">
        <div>
          <div className="text-sm font-semibold text-slate-950">Import transparency</div>
          <div className="mt-1 text-xs text-slate-500">
            {selectedImport.filename} · {formatDate(selectedImport.gec_list_date)} · {selectedImport.status}
          </div>
        </div>
        <div className="grid grid-cols-3 gap-1 rounded-xl bg-slate-100 p-1 text-xs font-semibold">
          {(['data', 'changes', 'skipped'] as ImportViewerTab[]).map((tab) => (
            <button
              key={tab}
              type="button"
              onClick={() => setViewerTab(tab)}
              className={`rounded-lg px-2 py-2 capitalize ${viewerTab === tab ? 'bg-white text-blue-700 shadow-sm' : 'text-slate-600 hover:text-slate-950'}`}
            >
              {tab === 'data' ? 'Imported data' : tab === 'changes' ? 'All changes' : 'Skipped'}
            </button>
          ))}
        </div>
        <form
          className="flex flex-col gap-2"
          onSubmit={(event) => {
            event.preventDefault();
            submitSearch();
          }}
        >
          <input
            value={viewerSearch}
            onChange={(event) => setViewerSearch(event.target.value)}
            placeholder="Search this import"
            className="rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm"
          />
          <div className="grid gap-2 sm:grid-cols-2 xl:grid-cols-1">
            {viewerTab === 'data' && (
              <select
                value={viewerVillage}
                onChange={(event) => setViewerVillage(event.target.value)}
                className="rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm"
              >
                <option value="">All villages</option>
                {dataVillages.map((village) => (
                  <option key={village} value={village}>{village}</option>
                ))}
              </select>
            )}
            {viewerTab === 'changes' && (
              <select
                value={changeType}
                onChange={(event) => setChangeType(event.target.value)}
                className="rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm"
              >
                <option value="all">All changes</option>
                <option value="new">New</option>
                <option value="changed">Changed</option>
                <option value="updated">Updated</option>
                <option value="removed">Removed</option>
                <option value="transferred">Transferred</option>
                <option value="routed_to_unassigned">Routed to Unassigned</option>
              </select>
            )}
            {viewerTab === 'skipped' && (
              <select
                value={skippedStatus}
                onChange={(event) => setSkippedStatus(event.target.value)}
                className="rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm"
              >
                <option value="all">All skipped rows</option>
                <option value="pending">Pending</option>
                <option value="resolved">Resolved</option>
                <option value="dismissed">Dismissed</option>
              </select>
            )}
            <button type="submit" className="app-btn-secondary min-h-10 justify-center">
              <Search className="h-4 w-4" />
              Search
            </button>
          </div>
        </form>
      </div>

      <div className="mt-3">
        {activeQuery.isFetching ? (
          <div className="flex items-center gap-2 rounded-xl bg-slate-50 p-4 text-sm text-slate-500">
            <Loader2 className="h-4 w-4 animate-spin" />
            Loading import review...
          </div>
        ) : activeQuery.isError ? (
          <div className="rounded-xl bg-amber-50 p-4 text-sm text-amber-800">{getErrorMessage(activeQuery.error)}</div>
        ) : viewerTab === 'data' ? (
          <ImportDataRows rows={dataRows} />
        ) : viewerTab === 'changes' ? (
          <ImportChangeRows rows={changeRows} />
        ) : (
          <ImportSkippedRows importId={selectedImport.id} rows={skippedRows} />
        )}
      </div>

      {activePagination && (
        <div className="mt-3 flex items-center justify-between gap-2 border-t border-slate-100 pt-3 text-xs text-slate-500">
          <span>
            Page {activePagination.page ?? viewerPage} of {activePagination.total_pages ?? 1} · {activePagination.total_rows ?? 0} rows
          </span>
          <div className="flex gap-2">
            <button
              type="button"
              disabled={viewerPage <= 1}
              onClick={() => setViewerPage(Math.max(1, viewerPage - 1))}
              className="rounded-lg border border-slate-200 px-2 py-1 font-semibold text-slate-700 disabled:opacity-40"
            >
              Prev
            </button>
            <button
              type="button"
              disabled={viewerPage >= (activePagination.total_pages ?? 1)}
              onClick={() => setViewerPage(viewerPage + 1)}
              className="rounded-lg border border-slate-200 px-2 py-1 font-semibold text-slate-700 disabled:opacity-40"
            >
              Next
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

function ImportDataRows({ rows }: { rows: ImportPreviewRow[] }) {
  if (rows.length === 0) return <div className="rounded-xl bg-slate-50 p-4 text-sm text-slate-500">No rows to show for this import.</div>;

  return (
    <div className="space-y-2">
      {rows.map((row, index) => (
        <div key={index} className="rounded-xl border border-slate-200 p-3 text-sm">
          <div className="font-semibold text-slate-900">
            {displayValue(row.name) !== '—'
              ? displayValue(row.name)
              : [row.first_name, row.middle_name, row.last_name].map(displayValue).filter((value) => value !== '—').join(' ') || 'Unnamed voter'}
          </div>
          <div className="mt-1 text-xs text-slate-500">
            {[row.address, row.village_name || row.village, row.precinct_number, row.voter_registration_number || row.registration_number]
              .map(displayValue)
              .filter((value) => value !== '—')
              .join(' · ') || 'No extra details'}
          </div>
        </div>
      ))}
    </div>
  );
}

function ImportChangeRows({ rows }: { rows: ImportChange[] }) {
  if (rows.length === 0) return <div className="rounded-xl bg-slate-50 p-4 text-sm text-slate-500">No change rows match the current filters.</div>;

  return (
    <div className="space-y-2">
      {rows.map((row) => (
        <div key={row.id} className="rounded-xl border border-slate-200 p-3 text-sm">
          <div className="flex items-start justify-between gap-2">
            <div className="font-semibold text-slate-900">
              {[row.first_name, row.middle_name, row.last_name].filter(Boolean).join(' ') || displayValue(row.details?.source_name) || 'GEC row'}
            </div>
            <span className="rounded-full bg-blue-50 px-2 py-1 text-xs font-semibold text-blue-700">{row.change_type}</span>
          </div>
          <div className="mt-1 text-xs text-slate-500">
            {[row.previous_village_name && `From ${row.previous_village_name}`, row.village_name && `To ${row.village_name}`, row.voter_registration_number, row.birth_year || row.dob]
              .filter(Boolean)
              .join(' · ') || `Row ${row.row_number ?? 'unknown'}`}
          </div>
        </div>
      ))}
    </div>
  );
}

function ImportSkippedRows({
  importId,
  rows,
}: {
  importId: number;
  rows: ImportSkippedRow[];
}) {
  const queryClient = useQueryClient();
  const [expandedRowId, setExpandedRowId] = useState<number | null>(null);
  const [drafts, setDrafts] = useState<Record<number, Record<string, string>>>({});
  const [previews, setPreviews] = useState<Record<number, SkippedRowResolutionPreview>>({});
  const [selectedCandidateIds, setSelectedCandidateIds] = useState<Record<number, number | null>>({});
  const [rowFeedback, setRowFeedback] = useState<Record<number, string | null>>({});

  const previewMutation = useMutation({
    mutationFn: ({ skippedRowId, correctedValues, selectedGecVoterId }: { skippedRowId: number; correctedValues: Record<string, unknown>; selectedGecVoterId?: number | null }) =>
      previewGecImportSkippedRowResolution(importId, skippedRowId, correctedValues, selectedGecVoterId),
    onSuccess: (response, variables) => {
      setPreviews((current) => ({ ...current, [variables.skippedRowId]: response.preview }));
      setRowFeedback((current) => ({ ...current, [variables.skippedRowId]: null }));
    },
    onError: (error, variables) => {
      setRowFeedback((current) => ({ ...current, [variables.skippedRowId]: getErrorMessage(error) }));
    },
  });

  const resolveMutation = useMutation({
    mutationFn: ({ skippedRowId, correctedValues, selectedGecVoterId }: { skippedRowId: number; correctedValues: Record<string, unknown>; selectedGecVoterId?: number | null }) =>
      resolveGecImportSkippedRow(importId, skippedRowId, correctedValues, selectedGecVoterId),
    onSuccess: (_, variables) => {
      setRowFeedback((current) => ({ ...current, [variables.skippedRowId]: 'Skipped row fixed.' }));
      setPreviews((current) => {
        const next = { ...current };
        delete next[variables.skippedRowId];
        return next;
      });
      void queryClient.invalidateQueries({ queryKey: ['gec-import-skipped-rows'] });
      void queryClient.invalidateQueries({ queryKey: ['gec-imports'] });
      void queryClient.invalidateQueries({ queryKey: ['gec-stats'] });
    },
    onError: (error, variables) => {
      setRowFeedback((current) => ({ ...current, [variables.skippedRowId]: getErrorMessage(error) }));
    },
  });

  const dismissMutation = useMutation({
    mutationFn: (skippedRowId: number) => dismissGecImportSkippedRow(importId, skippedRowId),
    onSuccess: (_, skippedRowId) => {
      setRowFeedback((current) => ({ ...current, [skippedRowId]: 'Skipped row dismissed.' }));
      void queryClient.invalidateQueries({ queryKey: ['gec-import-skipped-rows'] });
      void queryClient.invalidateQueries({ queryKey: ['gec-imports'] });
    },
    onError: (error, skippedRowId) => {
      setRowFeedback((current) => ({ ...current, [skippedRowId]: getErrorMessage(error) }));
    },
  });

  const buildDraft = (row: ImportSkippedRow) => {
    const existing = drafts[row.id];
    if (existing) return existing;

    return {
      first_name: String(row.corrected_values?.first_name ?? row.first_name ?? ''),
      middle_name: String(row.corrected_values?.middle_name ?? row.middle_name ?? ''),
      last_name: String(row.corrected_values?.last_name ?? row.last_name ?? ''),
      village_name: String(row.corrected_values?.village_name ?? row.village_name ?? ''),
      voter_registration_number: String(row.corrected_values?.voter_registration_number ?? row.voter_registration_number ?? ''),
      birth_year: String(row.corrected_values?.birth_year ?? row.birth_year ?? ''),
      dob: String(row.corrected_values?.dob ?? row.dob ?? ''),
    };
  };

  const updateDraft = (rowId: number, field: string, value: string) => {
    setDrafts((current) => ({
      ...current,
      [rowId]: {
        ...(current[rowId] || {}),
        [field]: value,
      },
    }));
  };

  const handlePreview = (row: ImportSkippedRow, selectedGecVoterId?: number | null) => {
    previewMutation.mutate({
      skippedRowId: row.id,
      correctedValues: buildDraft(row),
      selectedGecVoterId,
    });
  };

  const handleResolve = (row: ImportSkippedRow) => {
    resolveMutation.mutate({
      skippedRowId: row.id,
      correctedValues: buildDraft(row),
      selectedGecVoterId: selectedCandidateIds[row.id],
    });
  };

  if (rows.length === 0) return <div className="rounded-xl bg-slate-50 p-4 text-sm text-slate-500">No skipped rows match the current filters.</div>;

  return (
    <div className="space-y-2">
      {rows.map((row) => {
        const draft = buildDraft(row);
        const preview = previews[row.id];
        const isExpanded = expandedRowId === row.id;
        const isPending = row.resolution_status === 'pending';
        const isBusy = previewMutation.isPending || resolveMutation.isPending || dismissMutation.isPending;

        return (
          <div key={row.id} className="rounded-xl border border-slate-200 text-sm">
            <button
              type="button"
              onClick={() => setExpandedRowId(isExpanded ? null : row.id)}
              className="flex w-full items-start justify-between gap-3 p-3 text-left hover:bg-slate-50"
            >
              <div>
                <div className="font-semibold text-slate-900">
                  {[row.first_name, row.middle_name, row.last_name].filter(Boolean).join(' ') || row.source_name || `Row ${row.row_number}`}
                </div>
                <div className="mt-1 text-xs text-slate-500">{row.message}</div>
                <div className="mt-1 text-xs text-slate-500">
                  {[row.village_name, row.voter_registration_number, row.birth_year || row.dob, row.resolution_status].filter(Boolean).join(' · ')}
                </div>
              </div>
              <span className="shrink-0 rounded-full bg-slate-100 px-2 py-1 text-xs font-semibold text-slate-600">
                {isExpanded ? 'Hide' : 'Review'}
              </span>
            </button>

            {isExpanded && (
              <div className="space-y-3 border-t border-slate-100 bg-slate-50 p-3">
                <div className="rounded-xl bg-white p-3 text-xs text-slate-600">
                  <div className="font-semibold uppercase tracking-[0.1em] text-slate-400">Original skipped row</div>
                  <div className="mt-2">{row.raw_values?.length ? row.raw_values.join(' | ') : row.message}</div>
                </div>

                {isPending ? (
                  <>
                    <div className="grid gap-2 sm:grid-cols-2">
                      {[
                        ['first_name', 'First name'],
                        ['middle_name', 'Middle name'],
                        ['last_name', 'Last name'],
                        ['village_name', 'Village'],
                        ['voter_registration_number', 'Registration #'],
                        ['birth_year', 'Birth year'],
                        ['dob', 'DOB'],
                      ].map(([field, label]) => (
                        <label key={field} className="text-xs font-semibold uppercase tracking-[0.08em] text-slate-500">
                          {label}
                          <input
                            type={field === 'dob' ? 'date' : 'text'}
                            value={draft[field] ?? ''}
                            onChange={(event) => updateDraft(row.id, field, event.target.value)}
                            className="mt-1 w-full rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm font-normal normal-case tracking-normal text-slate-900"
                          />
                        </label>
                      ))}
                    </div>

                    <div className="flex flex-wrap gap-2">
                      <button
                        type="button"
                        disabled={isBusy}
                        onClick={() => handlePreview(row)}
                        className="rounded-lg border border-blue-200 bg-blue-50 px-3 py-2 text-xs font-semibold text-blue-700 disabled:opacity-50"
                      >
                        Check Fix
                      </button>
                      <button
                        type="button"
                        disabled={isBusy}
                        onClick={() => dismissMutation.mutate(row.id)}
                        className="rounded-lg border border-slate-200 bg-white px-3 py-2 text-xs font-semibold text-slate-700 disabled:opacity-50"
                      >
                        Dismiss Row
                      </button>
                    </div>

                    {preview && (
                      <div className={`rounded-xl border p-3 text-xs ${
                        ['ready_to_create', 'ready_to_update'].includes(preview.status)
                          ? 'border-green-200 bg-green-50 text-green-800'
                          : preview.status === 'ambiguous'
                          ? 'border-amber-200 bg-amber-50 text-amber-800'
                          : 'border-red-200 bg-red-50 text-red-700'
                      }`}>
                        <div className="font-semibold">{preview.status.replace(/_/g, ' ')}</div>
                        {preview.errors?.map((error, index) => (
                          <div key={index} className="mt-1">{error}</div>
                        ))}

                        {preview.status === 'ambiguous' && preview.candidate_matches && preview.candidate_matches.length > 0 && (
                          <div className="mt-3 space-y-2">
                            {preview.candidate_matches.map((candidate) => (
                              <label key={candidate.gec_voter.id} className="flex gap-2 rounded-lg border border-amber-200 bg-white p-2 text-slate-700">
                                <input
                                  type="radio"
                                  checked={selectedCandidateIds[row.id] === candidate.gec_voter.id}
                                  onChange={() => setSelectedCandidateIds((current) => ({ ...current, [row.id]: candidate.gec_voter.id }))}
                                />
                                <span>
                                  <strong>{candidate.gec_voter.first_name} {candidate.gec_voter.last_name}</strong>
                                  {candidate.gec_voter.village_name ? ` · ${candidate.gec_voter.village_name}` : ''}
                                  <span className="block text-amber-700">{candidate.match_type.replace(/_/g, ' ')} · {candidate.confidence}</span>
                                </span>
                              </label>
                            ))}
                            <button
                              type="button"
                              disabled={!selectedCandidateIds[row.id] || isBusy}
                              onClick={() => handlePreview(row, selectedCandidateIds[row.id])}
                              className="rounded-lg border border-amber-200 bg-white px-3 py-2 text-xs font-semibold text-amber-800 disabled:opacity-50"
                            >
                              Use Selected Voter
                            </button>
                          </div>
                        )}

                        {['ready_to_create', 'ready_to_update'].includes(preview.status) && (
                          <button
                            type="button"
                            disabled={isBusy}
                            onClick={() => handleResolve(row)}
                            className="mt-3 rounded-lg border border-green-200 bg-white px-3 py-2 text-xs font-semibold text-green-800 disabled:opacity-50"
                          >
                            Apply Fix
                          </button>
                        )}
                      </div>
                    )}
                  </>
                ) : (
                  <div className="rounded-xl bg-white p-3 text-xs text-slate-600">
                    <strong>{row.resolution_status.replace(/_/g, ' ')}</strong>
                    {row.resolved_at ? ` on ${formatDate(row.resolved_at.slice(0, 10))}` : ''}
                    {row.resolved_by_email ? ` by ${row.resolved_by_email}` : ''}
                    {row.resolved_gec_voter && (
                      <div className="mt-1">
                        Result voter: {row.resolved_gec_voter.first_name} {row.resolved_gec_voter.last_name}
                      </div>
                    )}
                  </div>
                )}

                {rowFeedback[row.id] && (
                  <div className="rounded-xl border border-slate-200 bg-white p-3 text-xs text-slate-700">
                    {rowFeedback[row.id]}
                  </div>
                )}
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}

function StatCard({ label, value }: { label: string; value: string | number }) {
  return (
    <div className="app-card p-4">
      <div className="text-xs font-semibold uppercase tracking-[0.1em] text-slate-500">{label}</div>
      <div className="mt-2 text-2xl font-bold text-slate-950">{value}</div>
    </div>
  );
}
