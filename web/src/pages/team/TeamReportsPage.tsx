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
  Eye,
  Link2,
  SearchCheck,
  MapPinned,
} from 'lucide-react';
import WorkspacePage from '../../components/WorkspacePage';
import {
  SUPPORT_STATUS_OPTIONS,
  VOLUNTEER_STATUS_OPTIONS,
} from '../../lib/relationshipStatus';

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

  const quickStats = reportsList?.quick_stats;
  const selectedReportInfo = (reportsList?.available_reports || []).find((report: Record<string, unknown>) => report.type === selectedReport) as Record<string, unknown> | undefined;
  const selectedReportName = (selectedReportInfo?.name as string | undefined) || selectedReport.replace(/_/g, ' ');
  const selectedReportDescription = reportDescriptions[selectedReport] || (selectedReportInfo?.description as string | undefined);

  return (
    <WorkspacePage width="full" className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight text-gray-900">Reports</h1>
        <p className="text-sm text-gray-500 mt-0.5">Preview filtered reports in the app, then download the final export</p>
      </div>

      {/* Quick Stats */}
      {quickStats && (
        <div className="grid grid-cols-2 md:grid-cols-4 xl:grid-cols-10 gap-3">
          <MiniStat label="Official Supporters" value={quickStats.official_supporters ?? quickStats.total_active} />
          <MiniStat label="Matched To Voter List" value={quickStats.matched_to_gec ?? quickStats.total_verified} />
          <MiniStat label="Unlinked Contacts" value={quickStats.dpg_contacts_unlinked_from_gec ?? 0} />
          <MiniStat label="GEC Outreach Gaps" value={quickStats.gec_voters_not_in_dpg ?? 0} />
          <MiniStat label="Possible Matches" value={quickStats.possible_gec_matches ?? 0} />
          <MiniStat label="Village Changes" value={quickStats.transfer_list_size ?? quickStats.transfers} />
          <MiniStat label="Referral List Size" value={quickStats.referral_list_size ?? 0} />
          <MiniStat label="Mapping Issues" value={quickStats.mapping_issues_list_size ?? 0} />
          <MiniStat label="Purge List Size" value={quickStats.purge_list_size ?? quickStats.purged_voters} />
          <MiniStat label="Unregistered" value={quickStats.unregistered} />
        </div>
      )}
      {quickStats && (
        <div className="text-xs text-gray-500 -mt-3">
          Village Changes are real GEC village-to-village moves. Referrals are supporter submissions under the wrong village. Mapping Issues are GEC rows that became unassigned or could not be mapped cleanly.
        </div>
      )}

      {/* Filters */}
      <div className="grid md:grid-cols-3 gap-3">
        <select
          value={selectedDistrict}
          onChange={e => {
            setSelectedDistrict(e.target.value);
            setSelectedVillage('');
            setSelectedPrecinct('');
          }}
          className="px-3 py-2 text-sm border border-gray-200 rounded-lg focus:ring-2 focus:ring-blue-500"
        >
          <option value="">All Districts</option>
          {(districts?.districts || []).map((d: Record<string, unknown>) => (
            <option key={d.id as number} value={d.id as number}>{d.name as string}</option>
          ))}
        </select>
        <select
          value={selectedVillage}
          onChange={e => {
            setSelectedVillage(e.target.value);
            setSelectedPrecinct('');
          }}
          className="px-3 py-2 text-sm border border-gray-200 rounded-lg focus:ring-2 focus:ring-blue-500"
        >
          <option value="">All Villages</option>
          {(villages?.villages || [])
            .filter((v: Record<string, unknown>) => !selectedDistrict || String(v.district_id || '') === selectedDistrict)
            .map((v: Record<string, unknown>) => (
            <option key={v.id as number} value={v.id as number}>{v.name as string}</option>
          ))}
        </select>
        <select
          value={selectedPrecinct}
          onChange={e => setSelectedPrecinct(e.target.value)}
          className="px-3 py-2 text-sm border border-gray-200 rounded-lg focus:ring-2 focus:ring-blue-500"
        >
          <option value="">All Precincts</option>
          {(precincts?.precincts || []).map((p: Record<string, unknown>) => (
            <option key={p.id as number} value={p.id as number}>
              {(p.village_name as string) ? `${p.village_name as string} · ${p.number as string}` : (p.number as string)}
            </option>
          ))}
        </select>
      </div>
      {supportsSupporterFilters && (
        <div className="space-y-2">
          <div className="grid md:grid-cols-4 gap-3">
            <select
              value={registeredStatusFilter}
              onChange={e => setRegisteredStatusFilter(e.target.value)}
              className="px-3 py-2 text-sm border border-gray-200 rounded-lg focus:ring-2 focus:ring-blue-500"
            >
              <option value="">All self-reported voter status</option>
              <option value="yes">Self-reported yes</option>
              <option value="no">Self-reported no</option>
              <option value="not_sure">Self-reported not sure</option>
            </select>
            <select
              value={supportStatusFilter}
              onChange={e => setSupportStatusFilter(e.target.value)}
              className="px-3 py-2 text-sm border border-gray-200 rounded-lg focus:ring-2 focus:ring-blue-500"
            >
              <option value="">All support statuses</option>
              {SUPPORT_STATUS_OPTIONS.map((option) => (
                <option key={option.value} value={option.value}>{option.label}</option>
              ))}
            </select>
            <select
              value={volunteerStatusFilter}
              onChange={e => setVolunteerStatusFilter(e.target.value)}
              className="px-3 py-2 text-sm border border-gray-200 rounded-lg focus:ring-2 focus:ring-blue-500"
            >
              <option value="">All volunteer statuses</option>
              {VOLUNTEER_STATUS_OPTIONS.map((option) => (
                <option key={option.value} value={option.value}>{option.label}</option>
              ))}
            </select>
            <select
              value={supportNeedFilter}
              onChange={e => setSupportNeedFilter(e.target.value)}
              className="px-3 py-2 text-sm border border-gray-200 rounded-lg focus:ring-2 focus:ring-blue-500"
            >
              <option value="">All support requests</option>
              <option value="registration">Registration help</option>
              <option value="absentee">Absentee help</option>
              <option value="homebound">Homebound help</option>
              <option value="ride">Ride to polls</option>
              <option value="volunteer">Volunteer</option>
              <option value="any">Any help request</option>
            </select>
            <select
              value={registrationFollowUpFilter}
              onChange={e => setRegistrationFollowUpFilter(e.target.value)}
              className="px-3 py-2 text-sm border border-gray-200 rounded-lg focus:ring-2 focus:ring-blue-500"
            >
              <option value="">All registration follow-up results</option>
              <option value="contacted">Contacted</option>
              <option value="registered">Registered via follow-up</option>
              <option value="declined">Declined</option>
            </select>
            <select
              value={supportFollowUpFilter}
              onChange={e => setSupportFollowUpFilter(e.target.value)}
              className="px-3 py-2 text-sm border border-gray-200 rounded-lg focus:ring-2 focus:ring-blue-500"
            >
              <option value="">All support follow-up progress</option>
              <option value="in_progress">In progress</option>
              <option value="completed">Completed</option>
              <option value="declined">Declined</option>
            </select>
          </div>
          <p className="text-xs text-gray-500">
            Supporter filters apply to DPG contact/supporter reports. Membership roster reporting is intentionally reserved until DPG provides actual official roster files.
          </p>
        </div>
      )}

      {/* Report cards */}
      <div className="space-y-3">
        {(reportsList?.available_reports || []).map((report: Record<string, unknown>) => {
          const type = report.type as string;
          const Icon = reportIcons[type] || FileSpreadsheet;
          const isDownloading = downloadingReport === type;
          const isSelected = selectedReport === type;

          return (
            <div key={type} className={`bg-white rounded-xl border p-5 flex items-start gap-4 ${isSelected ? 'border-blue-300 ring-2 ring-blue-100' : 'border-gray-200'}`}>
              <div className="w-10 h-10 rounded-lg bg-blue-50 flex items-center justify-center shrink-0">
                <Icon className="w-5 h-5 text-blue-600" />
              </div>
              <div className="flex-1 min-w-0">
                <h3 className="font-semibold text-gray-900 text-sm">{report.name as string}</h3>
                <p className="text-xs text-gray-500 mt-1 leading-relaxed">{reportDescriptions[type] || report.description as string}</p>
              </div>
              <div className="flex flex-col gap-2 shrink-0">
                <button
                  onClick={() => setSelectedReport(type)}
                  className={`flex items-center gap-2 px-4 py-2 text-sm font-medium rounded-lg transition-colors ${isSelected ? 'bg-blue-600 text-white hover:bg-blue-700' : 'bg-blue-50 text-blue-700 hover:bg-blue-100'}`}
                >
                  <Eye className="w-4 h-4" />
                  {isSelected ? 'Previewing' : 'Preview'}
                </button>
                <button
                  onClick={() => handleDownload(type)}
                  disabled={isDownloading}
                  className="flex items-center gap-2 px-4 py-2 bg-green-600 text-white text-sm font-medium rounded-lg hover:bg-green-700 disabled:opacity-50 transition-colors"
                >
                  {isDownloading ? (
                    <Loader2 className="w-4 h-4 animate-spin" />
                  ) : (
                    <Download className="w-4 h-4" />
                  )}
                  {isDownloading ? 'Generating...' : 'Download'}
                </button>
              </div>
            </div>
          );
        })}
      </div>

      {/* Preview */}
      <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
        <div className="px-5 py-4 border-b border-gray-100">
          <div className="flex items-center justify-between gap-3">
            <div>
              <h2 className="text-sm font-semibold text-gray-900">Report Preview</h2>
              <p className="text-xs text-gray-500 mt-1">
                Showing up to 100 rows for <span className="font-medium text-gray-700">{selectedReportName}</span> before export.
              </p>
              {selectedReportDescription && (
                <p className="mt-2 max-w-3xl text-xs leading-relaxed text-gray-500">{selectedReportDescription}</p>
              )}
            </div>
            {preview?.total_count !== undefined && (
              <span className="text-xs text-gray-500">
                {preview.total_count.toLocaleString()} matching rows
              </span>
            )}
          </div>
        </div>

        {previewLoading ? (
          <div className="p-8 flex items-center gap-3 text-sm text-gray-500">
            <Loader2 className="w-4 h-4 animate-spin" />
            Loading preview...
          </div>
        ) : preview?.rows?.length ? (
          <div className="overflow-x-auto">
            <table className="min-w-full text-sm">
              <thead className="bg-gray-50 border-b border-gray-100">
                <tr>
                  {(preview.columns || []).map((column: string) => (
                    <th key={column} className="text-left py-3 px-4 text-xs font-semibold text-gray-400 uppercase whitespace-nowrap">
                      {column}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {(preview.rows || []).map((row: unknown[], index: number) => (
                  <tr key={index} className="border-b border-gray-50">
                    {row.map((cell: unknown, cellIndex: number) => {
                      const column = String((preview.columns || [])[cellIndex] || '');
                      return (
                        <td key={`${index}-${cellIndex}`} className="py-3 px-4 text-gray-700 whitespace-nowrap">
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
          <div className="p-8 text-sm text-gray-500">
            No rows match the current filters for this report.
          </div>
        )}
      </div>

      {/* GEC info */}
      {reportsList && (
        <div className="p-4 bg-gray-50 rounded-xl border border-gray-100 text-xs text-gray-500">
          <div className="flex items-center gap-2">
            {reportsList.gec_data_loaded ? (
              <>
                <CheckCircle className="w-4 h-4 text-green-500" />
                Voter-list data loaded (latest: {new Date(reportsList.latest_gec_list_date).toLocaleDateString()}). Purge List Size reflects currently removed GEC voters, not just the latest import.
              </>
            ) : (
              <><FileSpreadsheet className="w-4 h-4 text-amber-500" /> No voter-list data loaded — purge and transfer reports will be empty</>
            )}
          </div>
        </div>
      )}
    </WorkspacePage>
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
    <div className="bg-white rounded-lg border border-gray-200 p-3 text-center">
      <div className="text-lg font-bold text-gray-900">{(value || 0).toLocaleString()}</div>
      <div className="text-[10px] text-gray-400 font-medium uppercase">{label}</div>
    </div>
  );
}
