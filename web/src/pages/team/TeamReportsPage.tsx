import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { getReportsList, getVillages, getDistricts, getPrecincts, getReportPreview, downloadReport } from '../../lib/api';
import { captureAnalyticsEvent } from '../../lib/analytics';
import {
  FileSpreadsheet,
  Download,
  Database,
  Users,
  UserX,
  ArrowRightLeft,
  GitBranch,
  BarChart3,
  AlertTriangle,
  CheckCircle,
  Loader2,
  Link2,
  SearchCheck,
  MapPinned,
  SlidersHorizontal,
  X,
} from 'lucide-react';
import WorkspacePage from '../../components/WorkspacePage';
import {
  SUPPORT_STATUS_OPTIONS,
  VOLUNTEER_STATUS_OPTIONS,
} from '../../lib/relationshipStatus';

type ReportInfo = {
  type: string;
  name: string;
  description?: string;
};

type ReportCategory = {
  label: string;
  description: string;
  reportTypes: string[];
};

type OptionRecord = Record<string, unknown>;

const reportIcons: Record<string, React.ComponentType<{ className?: string }>> = {
  support_list: Users,
  purge_list: UserX,
  transfer_list: ArrowRightLeft,
  referral_list: GitBranch,
  mapping_issues_list: AlertTriangle,
  supporter_summary: BarChart3,
  dpg_contacts_linked_to_gec: Link2,
  dpg_contacts_unlinked_from_gec: UserX,
  gec_voters_not_in_dpg: Database,
  possible_gec_matches: SearchCheck,
  dpg_gec_mismatches: MapPinned,
};

const reportDescriptions: Record<string, string> = {
  support_list: 'Approved DPG supporters, active volunteers, and future official member-roster matches by village. Use this for the current relationship list, not raw intake.',
  purge_list: 'Voters who were removed from the GEC list. Includes last known village and last list date.',
  transfer_list: 'GEC voters whose official village changed between list versions. Shows previous village, current village, and latest list date.',
  referral_list: 'Supporter records submitted under one village but currently assigned to another. Use this for village handoff cleanup.',
  mapping_issues_list: 'GEC voters whose latest village could not be mapped cleanly to an official village. Shows previous village, current mapping, and latest list date.',
  supporter_summary: 'Per-village summary with approved supporter/contact counts, GEC matches, public signups, and review status.',
  dpg_contacts_linked_to_gec: 'DPG contacts connected to official public GEC voter records. Use this to understand how much of DPG’s contact file is voter-file matched.',
  dpg_contacts_unlinked_from_gec: 'DPG contacts without a confirmed GEC voter link. Use this for registration follow-up, cleanup, and manual matching work.',
  gec_voters_not_in_dpg: 'Current public GEC voters with no linked DPG contact. Use this to find outreach gaps by village or precinct.',
  possible_gec_matches: 'DPG contacts with likely GEC candidates that staff should review before confirming a voter-file link.',
  dpg_gec_mismatches: 'Linked DPG contacts where the DPG-entered address, village, or precinct differs from the official GEC voter-file record.',
};

const reportUseCases: Record<string, string> = {
  support_list: 'Use before outreach, events, and field planning when DPG needs the current working supporter/volunteer universe.',
  supporter_summary: 'Use for a fast village-by-village readout during leadership check-ins.',
  dpg_contacts_linked_to_gec: 'Use to validate which DPG records are already connected to official public voter-file records.',
  dpg_contacts_unlinked_from_gec: 'Use for cleanup, manual matching, and registration-help follow-up.',
  gec_voters_not_in_dpg: 'Use to identify voter-file outreach gaps where DPG does not yet have a contact relationship.',
  possible_gec_matches: 'Use as a review queue before confirming a voter-file link on a contact record.',
  dpg_gec_mismatches: 'Use to spot contacts whose current DPG information may differ from official GEC voter-file information.',
  transfer_list: 'Use after new GEC imports to understand village changes in the voter file.',
  purge_list: 'Use after new GEC imports to inspect voters removed from the current file.',
  mapping_issues_list: 'Use when imported GEC rows need village mapping cleanup.',
  referral_list: 'Use to clean up village handoffs and contacts submitted under the wrong village.',
};

const reportCategories: ReportCategory[] = [
  {
    label: 'Core DPG Lists',
    description: 'Working contact/supporter outputs for daily DPG operations.',
    reportTypes: ['support_list', 'supporter_summary'],
  },
  {
    label: 'DPG/GEC Cross-Reference',
    description: 'Compare DPG contact records against the public voter file.',
    reportTypes: ['dpg_contacts_linked_to_gec', 'dpg_contacts_unlinked_from_gec', 'gec_voters_not_in_dpg', 'possible_gec_matches', 'dpg_gec_mismatches'],
  },
  {
    label: 'GEC List Maintenance',
    description: 'Import intelligence and voter-file cleanup reports.',
    reportTypes: ['transfer_list', 'purge_list', 'mapping_issues_list'],
  },
  {
    label: 'Village Cleanup',
    description: 'Village handoff and referral cleanup reports.',
    reportTypes: ['referral_list'],
  },
];

const SUPPORTER_REPORT_TYPES = new Set([
  'support_list',
  'referral_list',
  'dpg_contacts_linked_to_gec',
  'dpg_contacts_unlinked_from_gec',
  'possible_gec_matches',
  'dpg_gec_mismatches',
]);

export default function TeamReportsPage() {
  const [selectedReport, setSelectedReport] = useState<string>('support_list');
  const [selectedDistrict, setSelectedDistrict] = useState('');
  const [selectedVillage, setSelectedVillage] = useState('');
  const [selectedPrecinct, setSelectedPrecinct] = useState('');
  const [registeredStatusFilter, setRegisteredStatusFilter] = useState('');
  const [supportStatusFilter, setSupportStatusFilter] = useState('');
  const [volunteerStatusFilter, setVolunteerStatusFilter] = useState('');
  const [supportNeedFilter, setSupportNeedFilter] = useState('');
  const [registrationFollowUpFilter, setRegistrationFollowUpFilter] = useState('');
  const [supportFollowUpFilter, setSupportFollowUpFilter] = useState('');
  const [downloadingReport, setDownloadingReport] = useState<string | null>(null);
  const supportsSupporterFilters = SUPPORTER_REPORT_TYPES.has(selectedReport);

  const buildReportParams = (reportType: string, includePreviewLimit = false) => {
    const params: Record<string, string | number> = {};
    if (selectedDistrict) params.district_id = selectedDistrict;
    if (selectedVillage) params.village_id = selectedVillage;
    if (selectedPrecinct) params.precinct_id = selectedPrecinct;

    if (SUPPORTER_REPORT_TYPES.has(reportType)) {
      if (registeredStatusFilter) params.registered_voter_status = registeredStatusFilter;
      if (supportStatusFilter) params.support_status = supportStatusFilter;
      if (volunteerStatusFilter) params.volunteer_status = volunteerStatusFilter;
      if (supportNeedFilter) params.support_need = supportNeedFilter;
      if (registrationFollowUpFilter) params.registration_outreach_status = registrationFollowUpFilter;
      if (supportFollowUpFilter) params.support_follow_up_status = supportFollowUpFilter;
    }

    if (includePreviewLimit) params.limit = 100;
    return params;
  };

  const { data: reportsList } = useQuery({ queryKey: ['reports-list'], queryFn: getReportsList });
  const { data: villages } = useQuery({ queryKey: ['villages'], queryFn: getVillages });
  const { data: districts } = useQuery({ queryKey: ['districts'], queryFn: getDistricts });
  const { data: precincts } = useQuery({
    queryKey: ['precincts', selectedVillage],
    queryFn: () => getPrecincts(selectedVillage ? { village_id: selectedVillage } : undefined),
  });
  const { data: preview, isLoading: previewLoading } = useQuery({
    queryKey: ['report-preview', selectedReport, selectedDistrict, selectedVillage, selectedPrecinct, registeredStatusFilter, supportStatusFilter, volunteerStatusFilter, supportNeedFilter, registrationFollowUpFilter, supportFollowUpFilter],
    queryFn: () => getReportPreview(selectedReport, buildReportParams(selectedReport, true)),
    enabled: Boolean(selectedReport),
  });

  const handleDownload = async (reportType: string) => {
    if (!reportType) return;

    setDownloadingReport(reportType);
    try {
      await downloadReport(reportType, buildReportParams(reportType));
      captureAnalyticsEvent('report_downloaded', {
        report_type: reportType,
        district_id: selectedDistrict ? Number(selectedDistrict) : undefined,
        village_id: selectedVillage ? Number(selectedVillage) : undefined,
        precinct_id: selectedPrecinct ? Number(selectedPrecinct) : undefined,
        registered_voter_status: SUPPORTER_REPORT_TYPES.has(reportType) ? registeredStatusFilter || undefined : undefined,
        support_status: SUPPORTER_REPORT_TYPES.has(reportType) ? supportStatusFilter || undefined : undefined,
        volunteer_status: SUPPORTER_REPORT_TYPES.has(reportType) ? volunteerStatusFilter || undefined : undefined,
        support_need: SUPPORTER_REPORT_TYPES.has(reportType) ? supportNeedFilter || undefined : undefined,
        registration_outreach_status: SUPPORTER_REPORT_TYPES.has(reportType) ? registrationFollowUpFilter || undefined : undefined,
        support_follow_up_status: SUPPORTER_REPORT_TYPES.has(reportType) ? supportFollowUpFilter || undefined : undefined,
      });
    } catch (err) {
      console.error('Download failed:', err);
    } finally {
      setDownloadingReport(null);
    }
  };

  const clearFilters = () => {
    setSelectedDistrict('');
    setSelectedVillage('');
    setSelectedPrecinct('');
    setRegisteredStatusFilter('');
    setSupportStatusFilter('');
    setVolunteerStatusFilter('');
    setSupportNeedFilter('');
    setRegistrationFollowUpFilter('');
    setSupportFollowUpFilter('');
  };

  const quickStats = reportsList?.quick_stats;
  const reports = normalizeReports(reportsList?.available_reports);
  const selectedReportInfo = reports.find((report) => report.type === selectedReport);
  const selectedReportName = selectedReportInfo?.name || selectedReport.replace(/_/g, ' ');
  const selectedReportDescription = reportDescriptions[selectedReport] || selectedReportInfo?.description;
  const selectedReportUseCase = reportUseCases[selectedReport];
  const selectedIcon = reportIcons[selectedReport] || FileSpreadsheet;
  const isDownloadingSelected = downloadingReport === selectedReport;
  const activeFilterCount = [selectedDistrict, selectedVillage, selectedPrecinct, registeredStatusFilter, supportStatusFilter, volunteerStatusFilter, supportNeedFilter, registrationFollowUpFilter, supportFollowUpFilter].filter(Boolean).length;

  return (
    <WorkspacePage width="full" className="space-y-6">
      <div className="flex flex-col gap-4 xl:flex-row xl:items-end xl:justify-between">
        <div>
          <div className="inline-flex items-center gap-2 rounded-full border border-blue-100 bg-blue-50 px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.16em] text-blue-700">
            Report Workspace
          </div>
          <h1 className="mt-3 text-2xl font-bold tracking-tight text-gray-950">Reports</h1>
          <p className="mt-1 max-w-3xl text-sm text-gray-500">Choose a report, narrow the filters that matter, preview the rows, then download the final export.</p>
        </div>
        {reportsList && (
          <div className="rounded-2xl border border-gray-200 bg-white px-4 py-3 text-sm text-gray-600 shadow-sm">
            <div className="flex items-center gap-2">
              {reportsList.gec_data_loaded ? (
                <>
                  <CheckCircle className="h-4 w-4 text-green-500" />
                  <span>Voter-list data loaded{reportsList.latest_gec_list_date ? ` · latest ${new Date(reportsList.latest_gec_list_date).toLocaleDateString()}` : ''}</span>
                </>
              ) : (
                <>
                  <FileSpreadsheet className="h-4 w-4 text-amber-500" />
                  <span>No voter-list data loaded yet</span>
                </>
              )}
            </div>
          </div>
        )}
      </div>

      {quickStats && (
        <section className="rounded-3xl border border-gray-200 bg-white p-4 shadow-sm">
          <div className="mb-3 flex items-center justify-between gap-3">
            <div>
              <h2 className="text-sm font-semibold text-gray-950">At-a-glance</h2>
              <p className="text-xs text-gray-500">Summary counts to orient the reporting workspace.</p>
            </div>
            <span className="hidden rounded-full bg-gray-50 px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.12em] text-gray-400 sm:inline-flex">Live counts</span>
          </div>
          <div className="grid grid-cols-2 gap-2 md:grid-cols-4 xl:grid-cols-5">
            <MiniStat label="Official Supporters" value={quickStats.official_supporters ?? quickStats.total_active} />
            <MiniStat label="Matched To Voter List" value={quickStats.matched_to_gec ?? quickStats.total_verified} />
            <MiniStat label="Unlinked Contacts" value={quickStats.dpg_contacts_unlinked_from_gec ?? 0} />
            <MiniStat label="GEC Outreach Gaps" value={quickStats.gec_voters_not_in_dpg ?? 0} />
            <MiniStat label="Possible Matches" value={quickStats.possible_gec_matches ?? 0} />
          </div>
          <p className="mt-3 text-xs leading-relaxed text-gray-500">
            Detailed maintenance counts are still available through the Village Change, Referral, Mapping Issues, and Purge reports below.
          </p>
        </section>
      )}

      <div className="grid gap-6 xl:grid-cols-[390px_minmax(0,1fr)]">
        <aside className="space-y-4 xl:sticky xl:top-4 xl:self-start">
          <div className="rounded-3xl border border-gray-200 bg-white shadow-sm">
            <div className="border-b border-gray-100 px-4 py-4">
              <h2 className="text-sm font-semibold text-gray-950">Report Library</h2>
              <p className="mt-1 text-xs leading-relaxed text-gray-500">Grouped by the question DPG is trying to answer.</p>
            </div>
            <div className="max-h-[calc(100vh-240px)] space-y-4 overflow-y-auto p-3">
              {reportCategories.map((category) => {
                const categoryReports = category.reportTypes
                  .map((type) => reports.find((report) => report.type === type))
                  .filter((report): report is ReportInfo => Boolean(report));
                if (!categoryReports.length) return null;

                return (
                  <div key={category.label}>
                    <div className="mb-2 px-2">
                      <h3 className="text-[11px] font-semibold uppercase tracking-[0.14em] text-gray-400">{category.label}</h3>
                      <p className="mt-0.5 text-[11px] leading-snug text-gray-400">{category.description}</p>
                    </div>
                    <div className="space-y-1">
                      {categoryReports.map((report) => (
                        <ReportLibraryItem
                          key={report.type}
                          report={report}
                          selected={selectedReport === report.type}
                          onSelect={() => setSelectedReport(report.type)}
                          count={reportCountForType(report.type, quickStats)}
                        />
                      ))}
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        </aside>

        <section className="min-w-0 space-y-4">
          <div className="rounded-3xl border border-gray-200 bg-white shadow-sm">
            <div className="flex flex-col gap-4 border-b border-gray-100 p-5 lg:flex-row lg:items-start lg:justify-between">
              <div className="flex min-w-0 gap-4">
                <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-2xl bg-blue-50 text-blue-600">
                  {(() => {
                    const Icon = selectedIcon;
                    return <Icon className="h-5 w-5" />;
                  })()}
                </div>
                <div className="min-w-0">
                  <h2 className="text-xl font-bold tracking-tight text-gray-950">{selectedReportName}</h2>
                  {selectedReportDescription && <p className="mt-1 max-w-4xl text-sm leading-relaxed text-gray-500">{selectedReportDescription}</p>}
                  {selectedReportUseCase && (
                    <p className="mt-2 max-w-4xl rounded-2xl bg-slate-50 px-3 py-2 text-xs leading-relaxed text-slate-600">
                      <span className="font-semibold text-slate-800">Best used for: </span>{selectedReportUseCase}
                    </p>
                  )}
                </div>
              </div>
              <div className="flex shrink-0 flex-wrap gap-2">
                <button
                  type="button"
                  onClick={() => void handleDownload(selectedReport)}
                  disabled={!selectedReport || isDownloadingSelected}
                  className="inline-flex min-h-11 items-center justify-center gap-2 rounded-xl bg-green-600 px-4 text-sm font-semibold text-white transition hover:bg-green-700 disabled:opacity-50"
                >
                  {isDownloadingSelected ? <Loader2 className="h-4 w-4 animate-spin" /> : <Download className="h-4 w-4" />}
                  {isDownloadingSelected ? 'Generating...' : 'Download'}
                </button>
              </div>
            </div>

            <div className="space-y-4 p-5">
              <div className="flex items-center justify-between gap-3">
                <div className="flex items-center gap-2 text-sm font-semibold text-gray-900">
                  <SlidersHorizontal className="h-4 w-4 text-gray-400" />
                  Filters
                  {activeFilterCount > 0 && <span className="rounded-full bg-blue-50 px-2 py-0.5 text-xs font-semibold text-blue-700">{activeFilterCount} active</span>}
                </div>
                {activeFilterCount > 0 && (
                  <button type="button" onClick={clearFilters} className="inline-flex min-h-9 items-center gap-1.5 rounded-lg border border-gray-200 px-3 text-xs font-semibold text-gray-500 transition hover:bg-gray-50 hover:text-gray-900">
                    <X className="h-3.5 w-3.5" />
                    Clear filters
                  </button>
                )}
              </div>

              <div className="grid gap-3 md:grid-cols-3">
                <FilterSelect label="District" value={selectedDistrict} onChange={(value) => { setSelectedDistrict(value); setSelectedVillage(''); setSelectedPrecinct(''); }}>
                  <option value="">All Districts</option>
                  {(districts?.districts || []).map((d: OptionRecord) => (
                    <option key={d.id as number} value={d.id as number}>{d.name as string}</option>
                  ))}
                </FilterSelect>
                <FilterSelect label="Village" value={selectedVillage} onChange={(value) => { setSelectedVillage(value); setSelectedPrecinct(''); }}>
                  <option value="">All Villages</option>
                  {(villages?.villages || [])
                    .filter((v: OptionRecord) => !selectedDistrict || String(v.district_id || '') === selectedDistrict)
                    .map((v: OptionRecord) => (
                      <option key={v.id as number} value={v.id as number}>{v.name as string}</option>
                    ))}
                </FilterSelect>
                <FilterSelect label="Precinct" value={selectedPrecinct} onChange={setSelectedPrecinct}>
                  <option value="">All Precincts</option>
                  {(precincts?.precincts || []).map((p: OptionRecord) => (
                    <option key={p.id as number} value={p.id as number}>
                      {(p.village_name as string) ? `${p.village_name as string} · ${p.number as string}` : (p.number as string)}
                    </option>
                  ))}
                </FilterSelect>
              </div>

              {supportsSupporterFilters ? (
                <div className="rounded-2xl border border-blue-100 bg-blue-50/40 p-3">
                  <div className="mb-3 text-xs font-semibold uppercase tracking-[0.12em] text-blue-700">Contact/supporter filters</div>
                  <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
                    <FilterSelect label="Self-reported voter status" value={registeredStatusFilter} onChange={setRegisteredStatusFilter}>
                      <option value="">All self-reported voter status</option>
                      <option value="yes">Self-reported yes</option>
                      <option value="no">Self-reported no</option>
                      <option value="not_sure">Self-reported not sure</option>
                    </FilterSelect>
                    <FilterSelect label="Support status" value={supportStatusFilter} onChange={setSupportStatusFilter}>
                      <option value="">All support statuses</option>
                      {SUPPORT_STATUS_OPTIONS.map((option) => (
                        <option key={option.value} value={option.value}>{option.label}</option>
                      ))}
                    </FilterSelect>
                    <FilterSelect label="Volunteer status" value={volunteerStatusFilter} onChange={setVolunteerStatusFilter}>
                      <option value="">All volunteer statuses</option>
                      {VOLUNTEER_STATUS_OPTIONS.map((option) => (
                        <option key={option.value} value={option.value}>{option.label}</option>
                      ))}
                    </FilterSelect>
                    <FilterSelect label="Support requests" value={supportNeedFilter} onChange={setSupportNeedFilter}>
                      <option value="">All support requests</option>
                      <option value="registration">Registration help</option>
                      <option value="absentee">Absentee help</option>
                      <option value="homebound">Homebound help</option>
                      <option value="ride">Ride to polls</option>
                      <option value="volunteer">Volunteer</option>
                      <option value="any">Any help request</option>
                    </FilterSelect>
                    <FilterSelect label="Registration follow-up" value={registrationFollowUpFilter} onChange={setRegistrationFollowUpFilter}>
                      <option value="">All registration follow-up results</option>
                      <option value="contacted">Contacted</option>
                      <option value="registered">Registered via follow-up</option>
                      <option value="declined">Declined</option>
                    </FilterSelect>
                    <FilterSelect label="Support follow-up" value={supportFollowUpFilter} onChange={setSupportFollowUpFilter}>
                      <option value="">All support follow-up progress</option>
                      <option value="in_progress">In progress</option>
                      <option value="completed">Completed</option>
                      <option value="declined">Declined</option>
                    </FilterSelect>
                  </div>
                  <p className="mt-3 text-xs leading-relaxed text-blue-900/70">
                    Membership roster reporting is intentionally reserved until DPG provides actual official roster files.
                  </p>
                </div>
              ) : (
                <div className="rounded-2xl border border-gray-200 bg-gray-50 px-3 py-2 text-xs leading-relaxed text-gray-500">
                  This report uses geography filters only. Contact/supporter relationship filters are hidden because they do not apply to this voter-file report.
                </div>
              )}
            </div>
          </div>

          <div className="overflow-hidden rounded-3xl border border-gray-200 bg-white shadow-sm">
            <div className="flex flex-col gap-3 border-b border-gray-100 px-5 py-4 lg:flex-row lg:items-center lg:justify-between">
              <div>
                <h2 className="text-sm font-semibold text-gray-950">Preview</h2>
                <p className="mt-1 text-xs text-gray-500">Showing up to 100 rows before export.</p>
              </div>
              <div className="flex items-center gap-3">
                {preview?.total_count !== undefined && (
                  <span className="text-xs font-medium text-gray-500">
                    {preview.total_count.toLocaleString()} matching rows
                  </span>
                )}
                <button
                  type="button"
                  onClick={() => void handleDownload(selectedReport)}
                  disabled={!selectedReport || isDownloadingSelected}
                  className="inline-flex min-h-10 items-center gap-2 rounded-xl border border-gray-200 bg-white px-3 text-xs font-semibold text-gray-700 transition hover:bg-gray-50 disabled:opacity-50"
                >
                  {isDownloadingSelected ? <Loader2 className="h-4 w-4 animate-spin" /> : <Download className="h-4 w-4" />}
                  Export
                </button>
              </div>
            </div>

            {previewLoading ? (
              <div className="flex items-center gap-3 p-8 text-sm text-gray-500">
                <Loader2 className="h-4 w-4 animate-spin" />
                Loading preview...
              </div>
            ) : preview?.rows?.length ? (
              <div className="overflow-x-auto">
                <table className="min-w-full text-sm">
                  <thead className="border-b border-gray-100 bg-gray-50">
                    <tr>
                      {(preview.columns || []).map((column: string) => (
                        <th key={column} className="whitespace-nowrap px-4 py-3 text-left text-xs font-semibold uppercase text-gray-400">
                          {column}
                        </th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {(preview.rows || []).map((row: unknown[], index: number) => (
                      <tr key={index} className="border-b border-gray-50 last:border-b-0">
                        {row.map((cell: unknown, cellIndex: number) => {
                          const column = String((preview.columns || [])[cellIndex] || '');
                          return (
                            <td key={`${index}-${cellIndex}`} className="whitespace-nowrap px-4 py-3 text-gray-700">
                              {renderPreviewCell(column, cell)}
                            </td>
                          );
                        })}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            ) : (
              <div className="p-8 text-sm text-gray-500">No rows match the current filters for this report.</div>
            )}
          </div>
        </section>
      </div>
    </WorkspacePage>
  );
}

function normalizeReports(rawReports: unknown): ReportInfo[] {
  if (!Array.isArray(rawReports)) return [];
  return rawReports.map((report) => {
    const row = report as Record<string, unknown>;
    return {
      type: String(row.type || ''),
      name: String(row.name || row.type || 'Report'),
      description: typeof row.description === 'string' ? row.description : undefined,
    };
  }).filter((report) => report.type);
}

function reportCountForType(type: string, quickStats: Record<string, number> | undefined) {
  if (!quickStats) return undefined;
  const countMap: Record<string, number | undefined> = {
    support_list: quickStats.official_supporters ?? quickStats.total_active,
    supporter_summary: quickStats.official_supporters ?? quickStats.total_active,
    dpg_contacts_linked_to_gec: quickStats.dpg_contacts_linked_to_gec,
    dpg_contacts_unlinked_from_gec: quickStats.dpg_contacts_unlinked_from_gec,
    gec_voters_not_in_dpg: quickStats.gec_voters_not_in_dpg,
    possible_gec_matches: quickStats.possible_gec_matches,
    transfer_list: quickStats.transfer_list_size ?? quickStats.transfers,
    referral_list: quickStats.referral_list_size,
    mapping_issues_list: quickStats.mapping_issues_list_size,
    purge_list: quickStats.purge_list_size ?? quickStats.purged_voters,
  };
  return countMap[type];
}

function ReportLibraryItem({ report, selected, onSelect, count }: { report: ReportInfo; selected: boolean; onSelect: () => void; count?: number }) {
  const Icon = reportIcons[report.type] || FileSpreadsheet;
  return (
    <button
      type="button"
      onClick={onSelect}
      className={`group flex w-full items-start gap-3 rounded-2xl border px-3 py-3 text-left transition ${
        selected
          ? 'border-blue-200 bg-blue-50 text-blue-950 shadow-sm'
          : 'border-transparent bg-white text-gray-700 hover:border-gray-200 hover:bg-gray-50'
      }`}
    >
      <span className={`mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-xl ${selected ? 'bg-white text-blue-700' : 'bg-blue-50 text-blue-600'}`}>
        <Icon className="h-4 w-4" />
      </span>
      <span className="min-w-0 flex-1">
        <span className="flex items-start justify-between gap-2">
          <span className="text-sm font-semibold leading-snug">{report.name}</span>
          {count !== undefined && <span className="shrink-0 rounded-full bg-white px-2 py-0.5 text-[11px] font-semibold text-gray-500 shadow-sm">{count.toLocaleString()}</span>}
        </span>
        <span className="mt-1 line-clamp-2 text-xs leading-relaxed text-gray-500">{reportDescriptions[report.type] || report.description}</span>
      </span>
    </button>
  );
}

function FilterSelect({ label, value, onChange, children }: { label: string; value: string; onChange: (value: string) => void; children: React.ReactNode }) {
  return (
    <label className="block">
      <span className="mb-1.5 block text-[11px] font-semibold uppercase tracking-[0.12em] text-gray-400">{label}</span>
      <select
        value={value}
        onChange={(event) => onChange(event.target.value)}
        className="min-h-11 w-full rounded-xl border border-gray-200 bg-white px-3 text-sm text-gray-900 outline-none transition focus:border-blue-300 focus:ring-4 focus:ring-blue-100"
      >
        {children}
      </select>
    </label>
  );
}

function renderPreviewCell(column: string, cell: unknown) {
  if (cell === null || cell === undefined || cell === '') return '-';

  const value = String(cell);
  if (column === 'Contact ID') {
    return <Link to={`/admin/supporters/${value}`} className="font-semibold text-blue-700 hover:underline">{value}</Link>;
  }
  if (column === 'GEC Voter ID') {
    return <Link to={`/admin/gec-voters?q=${encodeURIComponent(value)}`} className="font-semibold text-blue-700 hover:underline">{value}</Link>;
  }

  return value;
}

function MiniStat({ label, value }: { label: string; value: number }) {
  return (
    <div className="rounded-2xl border border-gray-100 bg-gray-50/80 p-3">
      <div className="text-lg font-bold text-gray-950">{(value || 0).toLocaleString()}</div>
      <div className="mt-1 text-[10px] font-semibold uppercase tracking-[0.08em] text-gray-400">{label}</div>
    </div>
  );
}
