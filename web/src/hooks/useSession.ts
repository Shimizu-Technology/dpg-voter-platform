import { useAuth } from '@clerk/clerk-react';
import { useQuery } from '@tanstack/react-query';
import { getSession } from '../lib/api';

export interface SessionResponse {
  user: {
    id: number;
    email: string;
    name: string | null;
    role: string;
    assigned_village_id: number | null;
    assigned_district_id: number | null;
    assigned_block_id: number | null;
    scoped_village_ids: number[] | null;
  };
  counts: {
    total_contacts: number;
    new_intake: number;
    supporters: number;
    members: number;
    volunteers: number;
    needs_follow_up: number;
    pending_vetting: number;
    flagged_supporters: number;
    public_signups_pending: number;
    official_supporters: number;
    matched_to_gec: number;
  };
  permissions: {
    can_manage_users: boolean;
    can_manage_configuration: boolean;
    can_manage_data_configuration: boolean;
    can_send_sms: boolean;
    can_send_email: boolean;
    can_edit_supporters: boolean;
    can_view_supporters: boolean;
    can_create_staff_supporters: boolean;
    can_import_supporters: boolean;
    can_access_duplicates: boolean;
    can_access_audit_logs: boolean;
    can_access_data_team: boolean;
    can_access_reports: boolean;
    can_upload_gec: boolean;
    can_bulk_vet: boolean;
    can_review_public: boolean;
    default_route: string;
    manageable_roles: string[];
  };
}

export function useSession() {
  const { isLoaded, userId } = useAuth();

  return useQuery<SessionResponse>({
    queryKey: ['session', userId ?? 'anonymous'],
    queryFn: getSession,
    enabled: isLoaded && !!userId,
    staleTime: 60_000,
    // Avoid long exponential retries for auth/permission failures.
    retry: (failureCount, error) => {
      const status = (error as { response?: { status?: number } })?.response?.status;
      if (status === 401 || status === 403) return false;
      return failureCount < 1;
    },
  });
}
