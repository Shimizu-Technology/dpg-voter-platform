import { useAuth } from '@clerk/clerk-react';
import { useEffect, useRef } from 'react';
import { useLocation } from 'react-router-dom';
import { capturePageview, isAnalyticsEnabled, resetAnalytics } from '../lib/analytics';

export default function AnalyticsTracker() {
  const location = useLocation();
  const { isLoaded, isSignedIn } = useAuth();
  const lastPageKeyRef = useRef('');
  const hadSignedInSessionRef = useRef(false);

  useEffect(() => {
    if (!isAnalyticsEnabled) return;

    const pageKey = `${location.pathname}${location.search}`;
    if (lastPageKeyRef.current === pageKey) return;

    lastPageKeyRef.current = pageKey;
    capturePageview(location.pathname, location.search);
  }, [location.pathname, location.search]);

  useEffect(() => {
    if (!isAnalyticsEnabled || !isLoaded) return;

    if (!isSignedIn) {
      if (hadSignedInSessionRef.current) {
        resetAnalytics();
        hadSignedInSessionRef.current = false;
      }
      return;
    }

    hadSignedInSessionRef.current = true;
  }, [isLoaded, isSignedIn]);

  return null;
}
