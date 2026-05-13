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
export const getPrecincts = (params?: QueryParams) => api.get('/precincts', { params }).then(r => r.data);
export const updatePrecinct = (id: number, data: JsonRecord) =>
  api.patch(`/precincts/${id}`, { precinct: data }).then(r => r.data);
export const getAuditLogs = (params?: QueryParams) => api.get('/audit_logs', { params }).then(r => r.data);

// Supporters
export const createSupporter = (
  data: JsonRecord,
  leaderCode?: string,
  entryMode?: 'staff',
  entryChannel?: 'manual'
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
export const getSupporterContactAttempts = (supporterId: number) =>
  api.get(`/supporters/${supporterId}/contact_attempts`).then(r => r.data);
export const createSupporterContactAttempt = (supporterId: number, data: JsonRecord) =>
  api.post(`/supporters/${supporterId}/contact_attempts`, { contact_attempt: data }).then(r => r.data);

// SMS/email outreach
export const getSmsStatus = () => api.get('/sms/status').then(r => r.data);
export const sendTestSms = (phone: string, message: string) =>
  api.post('/sms/send', { phone, message }).then(r => r.data);
export const sendSmsBlast = (data: { message: string; village_id?: number; registered_voter?: string; dry_run?: string; recipient_reviewed?: boolean; expected_recipient_count?: number }) =>
  api.post('/sms/blast', data).then(r => r.data);
export const getSmsBlasts = () => api.get('/sms/blasts').then(r => r.data);
export const getSmsBlastStatus = (id: number) => api.get(`/sms/blasts/${id}`).then(r => r.data);
export const getEmailStatus = () => api.get('/email/status').then(r => r.data);
export const sendEmailBlast = (data: { subject: string; body: string; village_id?: number; registered_voter?: string; dry_run?: string; recipient_reviewed?: boolean; expected_recipient_count?: number }) =>
  api.post('/email/blast', data).then(r => r.data);
// Import
export const uploadImportPreview = (file: File) => {
  const form = new FormData();
  form.append('file', file);
  return api.post('/imports/preview', form).then(r => r.data);
};
export const parseImportRows = (data: { import_key: string; sheet_index: number; column_mapping: Record<string, unknown> }) =>
  api.post('/imports/parse', data).then(r => r.data);
export const confirmImport = (data: { import_key: string; village_id?: number; rows: Record<string, unknown>[] }) =>
  api.post('/imports/confirm', data).then(r => r.data);

// GEC Voter List
export const getGecStats = () => api.get('/gec_voters/stats').then(r => r.data);
export const getGecVoters = (params?: QueryParams) => api.get('/gec_voters', { params }).then(r => r.data);
export const getGecHouseholds = (params?: QueryParams) => api.get('/gec_voters/households', { params }).then(r => r.data);
export const getGecImports = () => api.get('/gec_voters/imports').then(r => r.data);
export const previewGecList = (file: File, gecListDate?: string, limit = 20, previewRequestId?: string) => {
  const form = new FormData();
  form.append('file', file);
  form.append('limit', String(limit));
  if (gecListDate) form.append('gec_list_date', gecListDate);
  if (previewRequestId) form.append('preview_request_id', previewRequestId);
  return api.post('/gec_voters/preview', form).then(r => r.data);
};
export const getGecPdfPreviewStatus = (previewRequestId: string) =>
  api.get('/gec_voters/preview_status', { params: { preview_request_id: previewRequestId } }).then(r => r.data);
export const uploadGecList = (file: File, gecListDate: string, importType = 'full_list', confirmReview = false) => {
  const form = new FormData();
  form.append('file', file);
  form.append('gec_list_date', gecListDate);
  form.append('import_type', importType);
  if (confirmReview) form.append('confirm_review', 'true');
  return api.post('/gec_voters/upload', form).then(r => r.data);
};
export const activateGecImport = (importId: number) =>
  api.post(`/gec_voters/imports/${importId}/activate`).then(r => r.data);
export const createContactFromGecVoter = (gecVoterId: number, contactClassification = 'active_contact') =>
  api.post(`/gec_voters/${gecVoterId}/create_contact`, { contact_classification: contactClassification }).then(r => r.data);
export const linkContactToGecVoter = (gecVoterId: number, supporterId: number) =>
  api.post(`/gec_voters/${gecVoterId}/link_contact`, { supporter_id: supporterId }).then(r => r.data);

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

export default api;
