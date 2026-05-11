export interface OutreachRecipient {
  id: number;
  name: string;
  village_name?: string | null;
  contact_number?: string | null;
  email?: string | null;
  registered_voter_status?: string | null;
  contact_classification?: string | null;
}
