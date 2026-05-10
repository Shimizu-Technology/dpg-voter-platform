import { useEffect, useCallback } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { useAuth } from '@clerk/clerk-react';
import { subscribeToCampaign, type CampaignEvent, type CampaignEventType } from '../lib/cable';

/**
 * Hook that subscribes to real-time DPG updates and
 * automatically invalidates the relevant TanStack Query caches.
 *
 * Usage: just call useCampaignUpdates() in any admin page.
 * Optionally pass an onEvent callback for custom handling (e.g. toast notifications).
 */
export function useCampaignUpdates(onEvent?: (event: CampaignEvent) => void, enabled = true) {
  const queryClient = useQueryClient();
  const { getToken, isLoaded, isSignedIn } = useAuth();

  const handleEvent = useCallback((event: CampaignEvent) => {
    // Invalidate relevant queries based on event type
    const invalidations: Record<CampaignEventType, string[]> = {
      new_supporter: [
        'dashboard',
        'supporters',
        'session',
        'village',
        'vetting-supporters',
        'vetting-queue',
        'public-review',
        'reports-list',
      ],
      supporter_updated: [
        'supporters',
        'dashboard',
        'session',
        'village',
        'vetting-supporters',
        'vetting-queue',
        'public-review',
        'reports-list',
        'duplicates',
      ],
      stats_update: [
        'dashboard',
        'session',
        'supporters',
        'village',
        'vetting-supporters',
        'vetting-queue',
        'public-review',
        'reports-list',
      ],
    };

    const keys = invalidations[event.type] || [];
    keys.forEach(key => {
      queryClient.invalidateQueries({ queryKey: [key] });
    });

    // Call custom handler if provided
    onEvent?.(event);
  }, [queryClient, onEvent]);

  useEffect(() => {
    if (!enabled || !isLoaded || !isSignedIn) return;

    let unsubscribe: (() => void) | undefined;
    let cancelled = false;

    const connect = async () => {
      const token = await getToken();
      if (cancelled) return;

      if (!token) return;
      unsubscribe = subscribeToCampaign(handleEvent, token);
    };

    connect();

    return () => {
      cancelled = true;
      unsubscribe?.();
    };
  }, [enabled, getToken, handleEvent, isLoaded, isSignedIn]);
}
