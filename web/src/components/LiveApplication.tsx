import { StrictMode } from 'react';
import { ClerkProvider } from '@clerk/clerk-react';
import { PostHogProvider } from '@posthog/react';
import App from '../App';
import { isAnalyticsEnabled } from '../lib/analytics';
import { isPlaceholderClerkKey } from '../lib/clerkConfig';
import { AppErrorBoundary, ConfigurationNeededPage } from './ConfigurationNeededPage';

const CLERK_KEY = import.meta.env.VITE_CLERK_PUBLISHABLE_KEY;
const posthogKey = import.meta.env.VITE_PUBLIC_POSTHOG_KEY;
const posthogHost = import.meta.env.VITE_PUBLIC_POSTHOG_HOST || 'https://us.i.posthog.com';

const posthogOptions = {
  api_host: posthogHost,
  person_profiles: 'identified_only' as const,
  capture_pageview: false,
  capture_pageleave: false,
  autocapture: false,
  disable_session_recording: true,
};

export default function LiveApplication() {
  const app = isPlaceholderClerkKey(CLERK_KEY)
    ? <ConfigurationNeededPage />
    : (
        <StrictMode>
          <AppErrorBoundary>
            <ClerkProvider publishableKey={CLERK_KEY}>
              <App />
            </ClerkProvider>
          </AppErrorBoundary>
        </StrictMode>
      );

  return posthogKey && isAnalyticsEnabled
    ? <PostHogProvider apiKey={posthogKey} options={posthogOptions}>{app}</PostHogProvider>
    : app;
}
