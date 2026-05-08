import type { ReactNode } from 'react';

type WorkspacePageWidth = 'full' | 'standard' | 'narrow';

const WIDTH_CLASSES: Record<WorkspacePageWidth, string> = {
  full: 'w-full',
  standard: 'max-w-7xl mx-auto w-full',
  narrow: 'max-w-4xl mx-auto w-full',
};

interface WorkspacePageProps {
  children: ReactNode;
  className?: string;
  width: WorkspacePageWidth;
}

export default function WorkspacePage({
  children,
  className = '',
  width,
}: WorkspacePageProps) {
  return (
    <div
      className={[
        'px-4 py-4 sm:px-6 sm:py-6 lg:px-8 lg:py-8',
        WIDTH_CLASSES[width],
        className,
      ].join(' ').trim()}
    >
      {children}
    </div>
  );
}
