import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { ClerkProvider } from '@clerk/clerk-react'
import { PostHogProvider } from '@posthog/react'
import './index.css'
import App from './App'
import { isAnalyticsEnabled } from './lib/analytics'

const CLERK_KEY = import.meta.env.VITE_CLERK_PUBLISHABLE_KEY

if (!CLERK_KEY) {
  throw new Error('Missing VITE_CLERK_PUBLISHABLE_KEY')
}

const posthogKey = import.meta.env.VITE_PUBLIC_POSTHOG_KEY
const posthogHost = import.meta.env.VITE_PUBLIC_POSTHOG_HOST || 'https://us.i.posthog.com'

const posthogOptions = {
  api_host: posthogHost,
  person_profiles: 'identified_only' as const,
  capture_pageview: false,
  capture_pageleave: true,
  autocapture: true,
  disable_session_recording: false,
  session_recording: {
    maskAllInputs: true,
  },
}

const app = (
  <StrictMode>
    <ClerkProvider publishableKey={CLERK_KEY}>
      <App />
    </ClerkProvider>
  </StrictMode>
)

createRoot(document.getElementById('root')!).render(
  posthogKey && isAnalyticsEnabled
    ? <PostHogProvider apiKey={posthogKey} options={posthogOptions}>{app}</PostHogProvider>
    : app,
)

// Register service worker for PWA
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/sw.js').catch(() => {})
  })
}
