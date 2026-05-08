import { useState, useCallback, useEffect, useRef } from 'react';
import type { CampaignEvent } from '../lib/cable';

export interface Toast {
  id: number;
  message: string;
  type: 'info' | 'success' | 'warning';
}

function eventToToast(event: CampaignEvent): { message: string; type: Toast['type'] } | null {
  const data = event?.data ?? {};

  switch (event.type) {
    case 'new_supporter':
      return {
        message: `New supporter: ${data.print_name ?? 'Unknown'} (${data.village_name ?? 'Unknown'})`,
        type: 'success',
      };
    case 'poll_report':
      {
        const count = Number(data.voter_count ?? 0);
        const votersLabel = `${count.toLocaleString()} voter${count === 1 ? '' : 's'}`;
      return {
        message: `Precinct ${data.precinct_number ?? 'Unknown'}: ${votersLabel} (${data.turnout_pct ?? 0}%)`,
        type: 'info',
      };
      }
    case 'event_check_in':
      return {
        message: `${data.supporter_name ?? 'Supporter'} checked in at ${data.event_name ?? 'event'}`,
        type: 'success',
      };
    case 'supporter_updated': {
      const name = data.print_name ?? `Supporter #${data.supporter_id ?? '?'}`;
      const village = data.village_name ? ` (${data.village_name})` : '';
      const action = String(data.action ?? 'updated');
      const status = String(data.status ?? '');

      if (action === 'verification_changed') {
        return {
          message: `Verification updated: ${name}${village}`,
          type: 'info',
        };
      }

      if (action === 'duplicate_resolved') {
        return {
          message: `Duplicate review resolved: ${name}${village}`,
          type: 'info',
        };
      }

      if (status === 'removed') {
        return {
          message: `Supporter removed from active lists: ${name}${village}`,
          type: 'warning',
        };
      }

      return {
        message: `Supporter record updated: ${name}${village}`,
        type: 'info',
      };
    }
    default:
      return null;
  }
}

export function useRealtimeToast(maxToasts = 5) {
  const [toasts, setToasts] = useState<Toast[]>([]);
  const idRef = useRef(0);
  const timeoutIdsRef = useRef<number[]>([]);

  useEffect(() => {
    return () => {
      timeoutIdsRef.current.forEach((timeoutId) => window.clearTimeout(timeoutId));
      timeoutIdsRef.current = [];
    };
  }, []);

  const handleEvent = useCallback((event: CampaignEvent) => {
    const toast = eventToToast(event);
    if (!toast) return;

    const id = ++idRef.current;
    setToasts(prev => [{ id, ...toast }, ...prev].slice(0, maxToasts));

    // Auto-remove after 5s
    const timeoutId = window.setTimeout(() => {
      setToasts(prev => prev.filter(t => t.id !== id));
    }, 5000);
    timeoutIdsRef.current.push(timeoutId);
  }, [maxToasts]);

  const dismiss = useCallback((id: number) => {
    setToasts(prev => prev.filter(t => t.id !== id));
  }, []);

  return { toasts, handleEvent, dismiss };
}
