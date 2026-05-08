import axios from 'axios';

const API_BASE_URL = import.meta.env.VITE_API_URL
  ? `${import.meta.env.VITE_API_URL.replace(/\/$/, '')}/api/v1`
  : '/api/v1';

type QueryParams = Record<string, string | number | boolean | null | undefined>;
type JsonRecord = Record<string, unknown>;

const api = axios.create({
  baseURL: API_BASE_URL,
  headers: { 'Content-Type': 'application/json' },
});

api.interceptors.response.use(
  response => response,
  error => {
    return Promise.reject(error);
  }
);

// Dashboard
export const getDashboard = () => api.get('/dashboard').then(r => r.data);
export const getStats = () => api.get('/stats').then(r => r.data);
export const getSession = () => api.get('/session').then(r => r.data);

// Villages
export const getVillages = () => api.get('/villages').then(r => r.data);
export const getDistricts = () => api.get('/districts').then(r => r.data);
export const createDistrict = (data: JsonRecord) => api.post('/districts', { district: data }).then(r => r.data);
export const updateDistrict = (id: number, data: JsonRecord) => api.patch(`/districts/${id}`, { district: data }).then(r => r.data);
export const deleteDistrict = (id: number) => api.delete(`/districts/${id}`).then(r => r.data);
export const assignVillagesToDistrict = (id: number, villageIds: number[]) =>
  api.patch(`/districts/${id}/assign_villages`, { village_ids: villageIds }).then(r => r.data);
export const getVillage = (id: number) => api.get(`/villages/${id}`).then(r => r.data);
export const getQuotas = () => api.get('/quotas').then(r => r.data);
export const updateVillageQuota = (villageId: number, targetCount: number, changeNote?: string) =>
  api.patch(`/quotas/${villageId}`, { quota: { target_count: targetCount, change_note: changeNote } }).then(r => r.data);
export const getPrecincts = (params?: QueryParams) => api.get('/precincts', { params }).then(r => r.data);
export const updatePrecinct = (id: number, data: JsonRecord) =>
  api.patch(`/precincts/${id}`, { precinct: data }).then(r => r.data);
export const getAuditLogs = (params?: QueryParams) => api.get('/audit_logs', { params }).then(r => r.data);

// Supporters
export const createSupporter = (
  data: JsonRecord,
  leaderCode?: string,
  entryMode?: 'staff',
  entryChannel?: 'manual' | 'scan'
) => {
  const params = new URLSearchParams();
  if (leaderCode) params.set('leader_code', leaderCode);
  if (entryMode === 'staff') params.set('entry_mode', 'staff');
  if (entryMode === 'staff' && entryChannel) params.set('entry_channel', entryChannel);
  const query = params.toString();
  return api.post(`/supporters${query ? `?${query}` : ''}`, { supporter: data }).then(r => r.data);
};
export const getSupporters = (params?: QueryParams) => api.get('/supporters', { params }).then(r => r.data);
export const getSupporter = (id: number) => api.get(`/supporters/${id}`).then(r => r.data);
export const updateSupporter = (id: number, data: JsonRecord) =>
  api.patch(`/supporters/${id}`, { supporter: data }).then(r => r.data);
export const verifySupporter = (id: number, status: string) =>
  api.patch(`/supporters/${id}/verify`, { verification_status: status }).then(r => r.data);
export const bulkVerifySupporters = (ids: number[], status: string) =>
  api.post('/supporters/bulk_verify', { supporter_ids: ids, verification_status: status }).then(r => r.data);
export const getDuplicates = (villageId?: number) =>
  api.get('/supporters/duplicates', { params: villageId ? { village_id: villageId } : {} }).then(r => r.data);
export const resolveDuplicate = (id: number, resolution: string, mergeIntoId?: number) =>
  api.patch(`/supporters/${id}/resolve_duplicate`, { resolution, merge_into_id: mergeIntoId }).then(r => r.data);
export const scanDuplicates = () =>
  api.post('/supporters/scan_duplicates').then(r => r.data);
export const getOutreachSupporters = (params?: QueryParams) =>
  api.get('/supporters/outreach', { params }).then(r => r.data);
export const updateOutreachStatus = (id: number, data: JsonRecord) =>
  api.patch(`/supporters/${id}/outreach_status`, data).then(r => r.data);
// Import
export const uploadImportPreview = (file: File) => {
  const form = new FormData();
  form.append('file', file);
  return api.post('/imports/preview', form, { headers: { 'Content-Type': 'multipart/form-data' } }).then(r => r.data);
};
export const parseImportRows = (data: { import_key: string; sheet_index: number; column_mapping: Record<string, unknown> }) =>
  api.post('/imports/parse', data).then(r => r.data);
export const confirmImport = (data: { import_key: string; village_id?: number; rows: Record<string, unknown>[] }) =>
  api.post('/imports/confirm', data).then(r => r.data);

export const checkDuplicate = (name: string, villageId: number, firstName?: string, lastName?: string) =>
  api.get('/supporters/check_duplicate', { params: { name, village_id: villageId, first_name: firstName, last_name: lastName } }).then(r => r.data);
export const exportSupporters = (params?: QueryParams) =>
  api.get('/supporters/export', { params: { ...params, format_type: 'xlsx' }, responseType: 'blob' }).then(r => {
    const ext = (params as Record<string, string>)?.format_type === 'csv' ? 'csv' : 'xlsx';
    const url = URL.createObjectURL(r.data);
    const a = document.createElement('a');
    a.href = url;
    a.download = `supporters-${new Date().toISOString().slice(0, 10)}.${ext}`;
    a.click();
    URL.revokeObjectURL(url);
    return { downloaded: true };
  });

// Leaderboard
export const getLeaderboard = () => api.get('/leaderboard').then(r => r.data);
export const getQrCodeAssignees = () => api.get('/qr_codes/assignees').then(r => r.data);
export const generateQrCode = (data: JsonRecord) => api.post('/qr_codes/generate', data).then(r => r.data);

// Events
export const getEvents = (params?: QueryParams) => api.get('/events', { params }).then(r => r.data);
export const getEvent = (id: number) => api.get(`/events/${id}`).then(r => r.data);
export const createEvent = (data: JsonRecord) => api.post('/events', { event: data }).then(r => r.data);
export const checkInAttendee = (eventId: number, supporterId: number) =>
  api.post(`/events/${eventId}/check_in`, { supporter_id: supporterId }).then(r => r.data);
export const getEventAttendees = (eventId: number, search?: string) =>
  api.get(`/events/${eventId}/attendees`, { params: { search } }).then(r => r.data);
export const sendEventSms = (eventId: number, data: { message: string; dry_run?: string }) =>
  api.post(`/events/${eventId}/send_sms`, data).then(r => r.data);
export const sendEventEmail = (eventId: number, data: { subject: string; body: string; dry_run?: string }) =>
  api.post(`/events/${eventId}/send_email`, data).then(r => r.data);

export const getWarRoom = () => api.get('/war_room').then(r => r.data);
export const createWarRoomContactAttempt = (supporterId: number, data: JsonRecord) =>
  api.post(`/war_room/supporters/${supporterId}/contact_attempts`, { contact_attempt: data }).then(r => r.data);

export const getPollWatcher = () => api.get('/poll_watcher').then(r => r.data);
export const submitPollReport = (data: JsonRecord) => api.post('/poll_watcher/report', { report: data }).then(r => r.data);
export const getPrecinctHistory = (id: number) => api.get(`/poll_watcher/precinct/${id}/history`).then(r => r.data);
export const getPollWatcherStrikeList = (params: QueryParams) =>
  api.get('/poll_watcher/strike_list', { params }).then(r => r.data);
export const updateStrikeListTurnout = (voterId: number, data: JsonRecord) =>
  api.patch(`/poll_watcher/strike_list/${voterId}/turnout`, { turnout: data }).then(r => r.data);

// Form Scanner (OCR)
export const scanForm = (image: string) =>
  api.post('/scan', { image }).then(r => r.data);
export const scanBatchForm = (image: string, defaultVillageId: number) =>
  api.post('/scan/batch', { image, default_village_id: defaultVillageId }).then(r => r.data);
export const trackScanBatchTelemetry = (telemetry: JsonRecord) =>
  api.post('/scan/telemetry', { telemetry }).then(r => r.data);

// SMS
export const getSmsStatus = () => api.get('/sms/status').then(r => r.data);
export const sendTestSms = (phone: string, message: string) =>
  api.post('/sms/send', { phone, message }).then(r => r.data);
export const sendSmsBlast = (data: { message: string; village_id?: number; registered_voter?: string; dry_run?: string }) =>
  api.post('/sms/blast', data).then(r => r.data);
export const sendEventNotify = (eventId: number, type: string) =>
  api.post('/sms/event_notify', { event_id: eventId, type }).then(r => r.data);
export const getSmsBlasts = () => api.get('/sms/blasts').then(r => r.data);
export const getSmsBlastStatus = (id: number) => api.get(`/sms/blasts/${id}`).then(r => r.data);

// Email
export const getEmailStatus = () => api.get('/email/status').then(r => r.data);
export const sendEmailBlast = (data: { subject: string; body: string; village_id?: number; registered_voter?: string; dry_run?: string }) =>
  api.post('/email/blast', data).then(r => r.data);

// Users (admin)
export const getUsers = () => api.get('/users').then(r => r.data);
export const createUser = (data: JsonRecord) => api.post('/users', { user: data }).then(r => r.data);
export const updateUser = (id: number, data: JsonRecord) =>
  api.patch(`/users/${id}`, { user: data }).then(r => r.data);
export const resendUserInvite = (id: number) => api.post(`/users/${id}/resend_invite`).then(r => r.data);
export const deleteUser = (id: number) => api.delete(`/users/${id}`).then(r => r.data);

// Settings
export const getSettings = () => api.get('/settings').then(r => r.data);
export const updateSettings = (data: JsonRecord) => api.patch('/settings', data).then(r => r.data);

// Campaign Info (public)
export const getCampaignInfo = () => api.get('/campaign_info').then(r => r.data);

export const getGecStats = () => api.get('/gec_voters/stats').then(r => r.data);
export const getGecVoters = (params?: QueryParams) => api.get('/gec_voters', { params }).then(r => r.data);
export const getGecImports = () => api.get('/gec_voters/imports').then(r => r.data);
export const getGecImportViewData = (
  importId: number,
  page: number = 1,
  perPage: number = 100,
  q?: string,
  village?: string
) =>
  api.get(`/gec_voters/imports/${importId}/view_data`, {
    params: {
      page,
      per_page: perPage,
      ...(q ? { q } : {}),
      ...(village ? { village } : {}),
    }
  }).then(r => r.data);
export const getGecImportOriginalView = (importId: number) =>
  api.get<{ view_url: string; filename: string; content_type: string; inline_supported: boolean }>(`/gec_voters/imports/${importId}/view_original`).then(r => r.data);
export const getGecImportChanges = (
  importId: number,
  page: number = 1,
  perPage: number = 100,
  type?: string,
  q?: string
) =>
  api.get(`/gec_voters/imports/${importId}/changes`, {
    params: {
      page,
      per_page: perPage,
      ...(type ? { type } : {}),
      ...(q ? { q } : {}),
    }
  }).then(r => r.data);
export const getGecImportSkippedRows = (
  importId: number,
  page: number = 1,
  perPage: number = 25,
  status?: string,
  q?: string
) =>
  api.get(`/gec_voters/imports/${importId}/skipped_rows`, {
    params: {
      page,
      per_page: perPage,
      ...(status ? { status } : {}),
      ...(q ? { q } : {}),
    }
  }).then(r => r.data);
export const previewGecImportSkippedRowResolution = (
  importId: number,
  skippedRowId: number,
  correctedValues: Record<string, unknown>,
  selectedGecVoterId?: number | null
) =>
  api.post(`/gec_voters/imports/${importId}/skipped_rows/${skippedRowId}/preview_resolution`, {
    corrected_values: correctedValues,
    ...(selectedGecVoterId ? { selected_gec_voter_id: selectedGecVoterId } : {}),
  }).then(r => r.data);
export const resolveGecImportSkippedRow = (
  importId: number,
  skippedRowId: number,
  correctedValues: Record<string, unknown>,
  selectedGecVoterId?: number | null
) =>
  api.post(`/gec_voters/imports/${importId}/skipped_rows/${skippedRowId}/resolve`, {
    corrected_values: correctedValues,
    ...(selectedGecVoterId ? { selected_gec_voter_id: selectedGecVoterId } : {}),
  }).then(r => r.data);
export const dismissGecImportSkippedRow = (importId: number, skippedRowId: number) =>
  api.post(`/gec_voters/imports/${importId}/skipped_rows/${skippedRowId}/dismiss`).then(r => r.data);
export const uploadGecList = (
  file: File,
  gecListDate: string,
  sheetName?: string,
  importType: string = 'full_list',
  parseCacheKey?: string,
  confirmReview: boolean = false,
  asyncImport: boolean = true,
  uploadRequestId?: string
) => {
  const form = new FormData();
  form.append('file', file);
  form.append('gec_list_date', gecListDate);
  form.append('import_type', importType);
  if (sheetName) form.append('sheet_name', sheetName);
  if (parseCacheKey) form.append('parse_cache_key', parseCacheKey);
  if (confirmReview) form.append('confirm_review', 'true');
  form.append('async_import', asyncImport ? 'true' : 'false');
  if (uploadRequestId) form.append('upload_request_id', uploadRequestId);
  return api.post('/gec_voters/upload', form, { headers: { 'Content-Type': 'multipart/form-data' } }).then(r => r.data);
};
export const previewGecList = (file: File, sheetName?: string, previewRequestId?: string) => {
  const form = new FormData();
  form.append('file', file);
  if (sheetName) form.append('sheet_name', sheetName);
  if (previewRequestId) form.append('preview_request_id', previewRequestId);
  return api.post('/gec_voters/preview', form, { headers: { 'Content-Type': 'multipart/form-data' } }).then(r => r.data);
};
export const getGecPdfPreviewStatus = (previewRequestId: string) =>
  api.get('/gec_voters/preview_status', { params: { preview_request_id: previewRequestId } }).then(r => r.data);
export const bulkVetSupporters = (params?: QueryParams) => api.post('/gec_voters/bulk_vet', params).then(r => r.data);
export const activateGecElectionDayImport = (importId: number) =>
  api.post(`/gec_voters/imports/${importId}/activate_election_day`).then(r => r.data);
export const downloadGecImportFile = (importId: number) =>
  api.get<{ download_url: string; filename: string }>(`/gec_voters/imports/${importId}/download`).then(r => {
    const { download_url, filename } = r.data;
    const a = document.createElement('a');
    a.href = download_url;
    a.download = filename; // Hint only — ignored for cross-origin S3 URLs; actual filename set by Content-Disposition header
    document.body.appendChild(a);
    a.click();
    a.remove();
  });
export const matchGecVoter = (params: { first_name: string; last_name: string; dob?: string; village_name?: string }) =>
  api.post('/gec_voters/match', params).then(r => r.data);

// Reports
export const getReportsList = () => api.get('/reports').then(r => r.data);
export const getReportPreview = (reportType: string, params?: QueryParams) =>
  api.get(`/reports/${reportType}/preview`, { params }).then(r => r.data);
export const downloadReport = (reportType: string, params?: QueryParams) =>
  api.get(`/reports/${reportType}`, { params, responseType: 'blob' }).then(r => {
    const url = window.URL.createObjectURL(new Blob([r.data]));
    const link = document.createElement('a');
    link.href = url;
    const disposition = r.headers['content-disposition'];
    const filename = disposition?.match(/filename="?(.+?)"?$/)?.[1] || `${reportType}.xlsx`;
    link.setAttribute('download', filename);
    document.body.appendChild(link);
    link.click();
    link.remove();
    window.URL.revokeObjectURL(url);
  });

// Vetting Queue
export const getVettingQueue = (params?: QueryParams) => api.get('/supporters/vetting_queue', { params }).then(r => r.data);
export const revetSupporter = (id: number) => api.patch(`/supporters/${id}/revet`).then(r => r.data);
export const bulkRevetSupporters = (payload: { supporter_ids?: number[]; apply_current_filters?: boolean } & QueryParams) =>
  api.post('/supporters/bulk_revet', payload).then(r => r.data);

// Public Review
export const getPublicReview = (params?: QueryParams) => api.get('/supporters/public_review', { params }).then(r => r.data);
export const acceptToQuota = (id: number) => api.patch(`/supporters/${id}/accept_to_quota`).then(r => r.data);
export const rejectPublicReview = (id: number) => api.patch(`/supporters/${id}/reject_public_review`).then(r => r.data);
export const approveSupporter = (id: number) => api.patch(`/supporters/${id}/approve_supporter`).then(r => r.data);
export const rejectSupporterReview = (id: number) => api.patch(`/supporters/${id}/reject_supporter`).then(r => r.data);

export default api;

// Campaign Cycles
export const getCampaignCycles = (params?: QueryParams) => api.get('/campaign_cycles', { params }).then(r => r.data);
export const getCurrentCycle = () => api.get('/campaign_cycles/current').then(r => r.data);
export const createCampaignCycle = (data: Record<string, unknown>) => api.post('/campaign_cycles', data).then(r => r.data);
export const updateCampaignCycle = (id: number, data: Record<string, unknown>) => api.patch(`/campaign_cycles/${id}`, data).then(r => r.data);

// Quota Periods
export const getQuotaPeriod = (id: number) => api.get(`/quota_periods/${id}`).then(r => r.data);
export const updateQuotaPeriod = (id: number, data: Record<string, unknown>) => api.patch(`/quota_periods/${id}`, data).then(r => r.data);
export const submitQuotaPeriod = (id: number) => api.post(`/quota_periods/${id}/submit`).then(r => r.data);
export const getVillageQuotas = (periodId: number) => api.get(`/quota_periods/${periodId}/village_quotas`).then(r => r.data);
export const updateVillageQuotas = (periodId: number, quotas: Array<{ village_id: number; target: number }>) =>
  api.patch(`/quota_periods/${periodId}/village_quotas`, { village_quotas: quotas }).then(r => r.data);
