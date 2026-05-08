import { createConsumer } from '@rails/actioncable';

// Connect to ActionCable on the Rails API
const API_BASE = import.meta.env.VITE_API_URL || 'http://localhost:3000';
const WS_BASE = API_BASE.replace(/^http/, 'ws');

function buildCableUrl(token?: string): string {
  const url = new URL('/cable', `${WS_BASE}/`);
  if (token) {
    url.searchParams.set('token', token);
  }
  return url.toString();
}

export type CampaignEventType = 'new_supporter' | 'poll_report' | 'event_check_in' | 'supporter_updated' | 'stats_update';

export interface CampaignEvent {
  type: CampaignEventType;
  data: Record<string, unknown>;
  timestamp: string;
}

export type CampaignEventHandler = (event: CampaignEvent) => void;

/**
 * Subscribe to the CampaignChannel for real-time updates.
 * Returns an unsubscribe function.
 */
export function subscribeToCampaign(onEvent: CampaignEventHandler, token?: string): () => void {
  const consumer = createConsumer(buildCableUrl(token));
  const subscription = consumer.subscriptions.create('CampaignChannel', {
    connected() {
      console.log('[Cable] Connected to CampaignChannel');
    },
    disconnected() {
      console.log('[Cable] Disconnected from CampaignChannel');
    },
    received(event: CampaignEvent) {
      console.log('[Cable] Event:', event.type, event.data);
      onEvent(event);
    },
  });

  return () => {
    subscription.unsubscribe();
    consumer.disconnect();
  };
}

export default createConsumer(buildCableUrl());
