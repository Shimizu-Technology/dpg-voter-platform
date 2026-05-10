import { publicSiteConfig } from '../lib/publicSite';

type PublicWordmarkProps = {
  size?: 'sm' | 'md' | 'lg';
  centered?: boolean;
  className?: string;
};

const SIZE_STYLES = {
  sm: {
    title: 'text-xl md:text-2xl',
    amp: 'text-lg md:text-xl',
    subtitle: 'text-[8px] md:text-[9px]',
    gap: 'gap-1',
  },
  md: {
    title: 'text-4xl md:text-5xl',
    amp: 'text-3xl md:text-4xl',
    subtitle: 'text-[10px] md:text-xs',
    gap: 'gap-1.5',
  },
  lg: {
    title: 'text-5xl md:text-6xl',
    amp: 'text-4xl md:text-5xl',
    subtitle: 'text-xs md:text-sm',
    gap: 'gap-2',
  },
} as const;

export default function PublicWordmark({
  size = 'md',
  centered = false,
  className = '',
}: PublicWordmarkProps) {
  const styles = SIZE_STYLES[size];
  const config = publicSiteConfig.wordmark;

  if (config.mode === 'image' && config.imageSrc) {
    const wordmarkSize = size === 'sm' ? 'h-14 md:h-16 lg:h-18' : size === 'lg' ? 'h-24 md:h-32 lg:h-36' : 'h-18 md:h-24';
    const iconSize = size === 'sm' ? 'h-14 w-14' : size === 'lg' ? 'h-20 w-20' : 'h-16 w-16';

    return (
      <div
        className={[
          'inline-flex leading-none',
          centered ? 'items-center text-center' : 'items-start text-left',
          className,
        ].join(' ')}
      >
        {config.iconSrc && (
          <img
            src={config.iconSrc}
            srcSet={config.iconSrcSet}
            sizes={size === 'sm' ? '56px' : '64px'}
            alt={config.imageAlt || config.title}
            className={`${iconSize} object-contain drop-shadow-sm md:hidden`}
          />
        )}
        <img
          src={config.imageSrc}
          srcSet={config.imageSrcSet}
          sizes={size === 'sm' ? '(min-width: 1024px) 250px, (min-width: 768px) 220px, 56px' : '(min-width: 1024px) 520px, 360px'}
          alt={config.imageAlt || config.title}
          className={`${config.iconSrc ? 'hidden md:block' : ''} ${wordmarkSize} max-w-[min(78vw,520px)] object-contain drop-shadow-sm`}
        />
        <span className="sr-only">{config.title} · {config.subtitle}</span>
      </div>
    );
  }

  return (
    <div
      className={[
        'inline-flex flex-col leading-none',
        centered ? 'items-center text-center' : 'items-start text-left',
        className,
      ].join(' ')}
    >
      <div className={`flex items-end ${styles.gap}`}>
        <span className={`${styles.title} -skew-x-12 font-black uppercase tracking-[-0.08em] text-primary`}>
          {config.title}
        </span>
        {config.amp && (
          <span className={`${styles.amp} font-black uppercase text-cta`}>
            {config.amp}
          </span>
        )}
        {config.titleSecondary && (
          <span className={`${styles.title} -skew-x-12 font-black uppercase tracking-[-0.08em] text-primary`}>
            {config.titleSecondary}
          </span>
        )}
      </div>
      <p className={`${styles.subtitle} mt-1 font-semibold uppercase tracking-[0.22em] text-slate-500`}>
        {config.subtitle}
      </p>
    </div>
  );
}
