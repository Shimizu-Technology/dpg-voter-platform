import { useCallback, useEffect, useState } from 'react';
import { LoaderCircle, RotateCw, WifiOff } from 'lucide-react';
import { checkBackendAvailability } from '../lib/backendAvailability';
import { publicSiteConfig } from '../lib/publicSite';

type Availability = 'checking' | 'available' | 'unavailable';

const HEALTH_CHECK_TIMEOUT_MS = 5_000;

function ServiceStatusShell({
  children,
  icon,
}: {
  children: React.ReactNode;
  icon: React.ReactNode;
}) {
  return (
    <main className="min-h-screen bg-[#f4f1e9] px-5 py-8 text-[#172238] sm:px-8 sm:py-12">
      <div className="mx-auto flex min-h-[calc(100vh-4rem)] max-w-3xl items-center justify-center sm:min-h-[calc(100vh-6rem)]">
        <section className="w-full border border-[#d9d1c0] bg-[#fbfaf6] px-6 py-10 shadow-[0_24px_80px_-48px_rgba(15,42,91,0.55)] sm:px-10 sm:py-12">
          <img
            src={publicSiteConfig.wordmark.imageSrc}
            srcSet={publicSiteConfig.wordmark.imageSrcSet}
            sizes="(max-width: 640px) 220px, 280px"
            alt={publicSiteConfig.wordmark.imageAlt}
            className="mb-10 h-auto w-[220px] sm:w-[280px]"
          />
          <div className="mb-6 flex h-12 w-12 items-center justify-center rounded-full bg-[#1b3a6b]/10 text-[#1b3a6b]">
            {icon}
          </div>
          {children}
        </section>
      </div>
    </main>
  );
}

function ServiceCheckingPage() {
  return (
    <ServiceStatusShell icon={<LoaderCircle aria-hidden="true" className="h-6 w-6 animate-spin motion-reduce:animate-none" />}>
      <p className="mb-3 text-xs font-bold tracking-[0.2em] text-[#806922] uppercase">Service check</p>
      <h1 className="text-3xl leading-tight font-bold tracking-tight text-[#0f2a5b] sm:text-4xl">
        Checking platform services.
      </h1>
      <p className="mt-5 max-w-xl text-base leading-7 text-[#4e596b]">
        Please wait while the voter engagement platform confirms that its secure services are available.
      </p>
    </ServiceStatusShell>
  );
}

function ServiceUnavailablePage({ onRetry }: { onRetry: () => void }) {
  return (
    <ServiceStatusShell icon={<WifiOff aria-hidden="true" className="h-6 w-6" />}>
      <p className="mb-3 text-xs font-bold tracking-[0.2em] text-[#806922] uppercase">Temporary interruption</p>
      <h1 className="text-3xl leading-tight font-bold tracking-tight text-[#0f2a5b] sm:text-4xl">
        Platform services are temporarily unavailable.
      </h1>
      <p className="mt-5 max-w-xl text-base leading-7 text-[#4e596b]">
        We could not reach the voter engagement platform. No information was submitted. Please try again, or visit the Democratic Party of Guam website for current party information.
      </p>
      <div className="mt-8 flex flex-col gap-3 sm:flex-row">
        <button
          type="button"
          onClick={onRetry}
          className="inline-flex min-h-12 items-center justify-center gap-2 rounded-full bg-[#1b3a6b] px-6 py-3 text-sm font-bold text-white shadow-[0_12px_30px_-16px_rgba(15,42,91,0.9)] hover:bg-[#0f2a5b] focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-[#1b3a6b]"
        >
          <RotateCw aria-hidden="true" className="h-4 w-4" />
          Try again
        </button>
        <a
          href={publicSiteConfig.officialInfoUrl}
          className="inline-flex min-h-12 items-center justify-center rounded-full border border-[#bdb4a1] px-6 py-3 text-sm font-bold text-[#1b3a6b] hover:border-[#1b3a6b] hover:bg-white focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-[#1b3a6b]"
        >
          Visit the main party website
        </a>
      </div>
    </ServiceStatusShell>
  );
}

export default function ServiceAvailabilityGate({ children }: { children: React.ReactNode }) {
  const [availability, setAvailability] = useState<Availability>('checking');
  const [attempt, setAttempt] = useState(0);

  const retry = useCallback(() => {
    setAvailability('checking');
    setAttempt((currentAttempt) => currentAttempt + 1);
  }, []);

  useEffect(() => {
    const controller = new AbortController();
    let active = true;
    const timeoutId = window.setTimeout(() => controller.abort(), HEALTH_CHECK_TIMEOUT_MS);

    void checkBackendAvailability(controller.signal).then((available) => {
      if (active) {
        setAvailability(available ? 'available' : 'unavailable');
      }
    });

    return () => {
      active = false;
      window.clearTimeout(timeoutId);
      controller.abort();
    };
  }, [attempt]);

  if (availability === 'checking') return <ServiceCheckingPage />;
  if (availability === 'unavailable') return <ServiceUnavailablePage onRetry={retry} />;

  return <>{children}</>;
}
