import { lazy, StrictMode, Suspense } from 'react';
import { LoaderCircle } from 'lucide-react';
import { getServiceMode } from '../lib/serviceMode';
import PlatformPausedPage from '../pages/PlatformPausedPage';
import ServiceAvailabilityGate from './ServiceAvailabilityGate';

const LiveApplication = lazy(() => import('./LiveApplication'));

function LiveApplicationLoader() {
  return (
    <main className="flex min-h-screen items-center justify-center bg-[#f4f1e9] text-[#1b3a6b]">
      <div className="flex items-center gap-3 text-sm font-bold">
        <LoaderCircle aria-hidden="true" className="h-5 w-5 animate-spin motion-reduce:animate-none" />
        Opening the voter engagement platform
      </div>
    </main>
  );
}

function LazyLiveApplication() {
  return (
    <Suspense fallback={<LiveApplicationLoader />}>
      <LiveApplication />
    </Suspense>
  );
}

export default function ServiceModeRoot() {
  const serviceMode = getServiceMode();

  if (serviceMode === 'paused') {
    return (
      <StrictMode>
        <PlatformPausedPage />
      </StrictMode>
    );
  }

  if (serviceMode === 'auto') {
    return (
      <ServiceAvailabilityGate>
        <LazyLiveApplication />
      </ServiceAvailabilityGate>
    );
  }

  return <LazyLiveApplication />;
}
