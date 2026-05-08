import WorkspacePage from './WorkspacePage';
function Pulse({ className }: { className?: string }) {
  return <div className={`animate-pulse rounded-lg bg-gray-200 ${className || ''}`} />;
}

export default function DashboardSkeleton() {
  return (
    <WorkspacePage width="full">
      {/* Page Header */}
      <div className="mb-8">
        <Pulse className="h-7 w-36 mb-2" />
        <Pulse className="h-4 w-64" />
      </div>

      {/* Summary Cards */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
        {[ 0, 1, 2, 3 ].map(i => (
          <div key={i} className="app-card p-5 space-y-3">
            <div className="flex items-center gap-3">
              <Pulse className="h-9 w-9 rounded-xl" />
              <Pulse className="h-3 w-20" />
            </div>
            <Pulse className="h-8 w-16" />
            <Pulse className="h-3.5 w-24" />
          </div>
        ))}
      </div>

      {/* Progress Bar */}
      <div className="app-card p-5 mb-8">
        <div className="flex justify-between mb-3">
          <Pulse className="h-4 w-40" />
          <Pulse className="h-4 w-24" />
        </div>
        <Pulse className="h-3 w-full rounded-full" />
      </div>

      {/* Village Grid Header */}
      <div className="mb-5">
        <Pulse className="h-6 w-40 mb-2" />
        <Pulse className="h-4 w-56" />
      </div>

      {/* Village Grid */}
      <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-4">
        {Array.from({ length: 6 }).map((_, i) => (
          <div key={i} className="app-card p-4 space-y-3">
            <div className="flex justify-between">
              <Pulse className="h-5 w-28" />
              <Pulse className="h-3.5 w-14" />
            </div>
            <div className="flex justify-between">
              <Pulse className="h-3.5 w-16" />
              <Pulse className="h-3.5 w-10" />
            </div>
            <Pulse className="h-2 w-full rounded-full" />
            <Pulse className="h-3 w-24" />
          </div>
        ))}
      </div>
    </WorkspacePage>
  );
}
