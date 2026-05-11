import PublicWordmark from './PublicWordmark';
import { publicSiteConfig } from '../lib/publicSite';

type WorkspaceBrandPanelProps = {
  workspaceName: string;
  workspaceDescription: string;
  badge?: string;
  compact?: boolean;
  rail?: boolean;
  centered?: boolean;
  className?: string;
};

export default function WorkspaceBrandPanel({
  workspaceName,
  workspaceDescription,
  badge = "Internal DPG workspace",
  compact = false,
  rail = false,
  centered = false,
  className = "",
}: WorkspaceBrandPanelProps) {
  if (compact) {
    const iconSrc = publicSiteConfig.wordmark.iconSrc;

    if (rail) {
      return (
        <div
          className={[
            "flex min-h-16 items-center justify-center rounded-2xl border border-slate-200 bg-white shadow-[0_14px_32px_-26px_rgba(15,42,91,0.35)]",
            className,
          ].join(" ")}
        >
          {iconSrc ? (
            <img
              src={iconSrc}
              srcSet={publicSiteConfig.wordmark.iconSrcSet}
              sizes="40px"
              alt="Democratic Party of Guam circular mark"
              className="h-10 w-10 rounded-2xl object-contain drop-shadow-sm"
            />
          ) : (
            <PublicWordmark size="sm" />
          )}
          <span className="sr-only">{workspaceName}</span>
        </div>
      );
    }

    return (
      <div
        className={[
          "overflow-hidden rounded-[20px] border border-slate-200 bg-white shadow-[0_14px_32px_-26px_rgba(15,42,91,0.35)]",
          className,
        ].join(" ")}
      >
        <div className="bg-primary px-3 py-1.5 text-center text-[9px] font-semibold uppercase leading-4 tracking-[0.2em] text-white">
          Building Guam&apos;s Future Together
        </div>
        <div className="p-3">
          <div className="flex items-center gap-3">
            {iconSrc ? (
              <img
                src={iconSrc}
                srcSet={publicSiteConfig.wordmark.iconSrcSet}
                sizes="44px"
                alt="Democratic Party of Guam circular mark"
                className="h-11 w-11 shrink-0 rounded-2xl object-contain drop-shadow-sm"
              />
            ) : (
              <PublicWordmark size="sm" />
            )}
            <div className="min-w-0">
              <div className="inline-flex max-w-full rounded-full border border-[#d8e4f2] bg-[#eef4ff] px-2.5 py-1 text-[8px] font-semibold uppercase tracking-[0.18em] text-primary">
                <span className="truncate">{badge}</span>
              </div>
              <h2 className="mt-2 truncate text-[15px] font-bold tracking-tight text-slate-950">
                {workspaceName}
              </h2>
            </div>
          </div>
          <p className="mt-2 line-clamp-2 text-xs leading-5 text-slate-500">
            {workspaceDescription}
          </p>
        </div>
      </div>
    );
  }

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
      <div className="space-y-4 p-5 md:p-6">
        <PublicWordmark size="md" centered={centered} />
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
