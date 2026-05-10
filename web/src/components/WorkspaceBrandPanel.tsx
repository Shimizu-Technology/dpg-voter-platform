import PublicWordmark from './PublicWordmark';

type WorkspaceBrandPanelProps = {
  workspaceName: string;
  workspaceDescription: string;
  badge?: string;
  compact?: boolean;
  centered?: boolean;
  className?: string;
};

export default function WorkspaceBrandPanel({
  workspaceName,
  workspaceDescription,
  badge = "Internal DPG workspace",
  compact = false,
  centered = false,
  className = "",
}: WorkspaceBrandPanelProps) {
  return (
    <div
      className={[
        "overflow-hidden rounded-[22px] border border-slate-200 bg-white shadow-[0_18px_40px_-28px_rgba(15,42,91,0.35)]",
        className,
      ].join(" ")}
    >
      <div className="bg-primary px-4 py-2 text-center text-[11px] font-semibold uppercase tracking-[0.24em] text-white">
        Building Guam&apos;s Future Together
      </div>
      <div className={compact ? "space-y-3 p-4" : "space-y-4 p-5 md:p-6"}>
        <PublicWordmark size={compact ? "sm" : "md"} centered={centered} />
        <div className={centered ? "text-center" : ""}>
          <div className="inline-flex rounded-full border border-[#d8e4f2] bg-[#eef4ff] px-3 py-1.5 text-[10px] font-semibold uppercase tracking-[0.22em] text-primary">
            {badge}
          </div>
          <h2 className="mt-3 text-base font-bold tracking-tight text-slate-950 md:text-lg">
            {workspaceName}
          </h2>
          <p className="mt-1 text-sm leading-6 text-slate-500">
            {workspaceDescription}
          </p>
        </div>
      </div>
    </div>
  );
}
