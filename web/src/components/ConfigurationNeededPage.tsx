import { Component, type ErrorInfo, type ReactNode } from 'react';

export function AppCrashPage({ error }: { error?: Error }) {
  return (
    <div className="min-h-screen bg-[#f6f8fc] px-6 py-12 text-slate-900">
      <div className="mx-auto flex min-h-[calc(100vh-6rem)] max-w-xl items-center">
        <div className="w-full rounded-[32px] border border-slate-200 bg-white p-8 shadow-[0_24px_60px_-32px_rgba(15,42,91,0.35)]">
          <p className="text-xs font-bold uppercase tracking-[0.22em] text-[#1B3A6B]">DPG app error</p>
          <h1 className="mt-4 text-3xl font-black tracking-tight">Something went wrong while loading the app.</h1>
          <p className="mt-4 text-sm leading-7 text-slate-600">
            Refresh the page and try again. If this keeps happening, check the browser console and deployment logs for the underlying error.
          </p>
          {error?.message ? (
            <div className="mt-6 rounded-2xl bg-slate-50 p-4 text-sm text-slate-600">
              <span className="font-semibold text-slate-800">Error:</span> {error.message}
            </div>
          ) : null}
        </div>
      </div>
    </div>
  );
}

export function ConfigurationNeededPage() {
  return (
    <div className="min-h-screen bg-[#f6f8fc] px-6 py-12 text-slate-900">
      <div className="mx-auto flex min-h-[calc(100vh-6rem)] max-w-xl items-center">
        <div className="w-full rounded-[32px] border border-slate-200 bg-white p-8 shadow-[0_24px_60px_-32px_rgba(15,42,91,0.35)]">
          <p className="text-xs font-bold uppercase tracking-[0.22em] text-[#1B3A6B]">DPG setup required</p>
          <h1 className="mt-4 text-3xl font-black tracking-tight">Add your Clerk publishable key to run the app.</h1>
          <p className="mt-4 text-sm leading-7 text-slate-600">
            The Democratic Party of Guam platform is ready to boot, but the browser app needs a real
            <code className="mx-1 rounded bg-slate-100 px-1.5 py-0.5 text-xs">VITE_CLERK_PUBLISHABLE_KEY</code>
            in <code className="mx-1 rounded bg-slate-100 px-1.5 py-0.5 text-xs">web/.env</code> before it can render login-aware pages.
          </p>
          <div className="mt-6 rounded-2xl bg-slate-50 p-4 text-sm text-slate-600">
            Copy <code className="rounded bg-white px-1.5 py-0.5 text-xs">web/.env.example</code> to
            <code className="mx-1 rounded bg-white px-1.5 py-0.5 text-xs">web/.env</code>, then replace the placeholder Clerk key with the DPG Clerk app key.
          </div>
        </div>
      </div>
    </div>
  );
}

export class AppErrorBoundary extends Component<{ children: ReactNode }, { error?: Error }> {
  state: { error?: Error } = {};

  static getDerivedStateFromError(error: Error) {
    return { error };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error('[DPG App] Render failed', error, info);
  }

  render() {
    if (this.state.error) {
      return <AppCrashPage error={this.state.error} />;
    }

    return this.props.children;
  }
}
