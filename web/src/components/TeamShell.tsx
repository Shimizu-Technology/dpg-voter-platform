import { useEffect, useState } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { UserButton } from '@clerk/clerk-react';
import { useSession } from '../hooks/useSession';
import { useCampaignUpdates } from '../hooks/useCampaignUpdates';
import { useRealtimeToast } from '../hooks/useRealtimeToast';
import { formatRoleLabel } from '../lib/roles';
import {
  LayoutDashboard,
  Users,
  Shield,
  Upload,
  FileSpreadsheet,
  ClipboardPlus,
  ScrollText,
  Copy,
  Menu,
  X,
  Home,
  MapPin,
  Settings,
} from 'lucide-react';
import WorkspaceBrandPanel from './WorkspaceBrandPanel';
import { publicSiteConfig } from '../lib/publicSite';

interface NavItem {
  to: string;
  label: string;
  icon: React.ComponentType<{ className?: string }>;
  badge?: number;
}

interface NavGroup {
  label: string;
  items: NavItem[];
}

const teamSidebarStorageKey = 'dpg-team-sidebar-collapsed';

export default function TeamShell({ children }: { children: React.ReactNode }) {
  const location = useLocation();
  const { data: sessionData } = useSession();
  const { toasts, handleEvent, dismiss } = useRealtimeToast();
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [desktopCollapsed, setDesktopCollapsed] = useState(() => {
    if (typeof window === 'undefined') return false;
    return window.localStorage.getItem(teamSidebarStorageKey) === 'true';
  });
  const [railTooltip, setRailTooltip] = useState<{ label: string; top: number; left: number } | null>(null);
  const counts = sessionData?.counts;
  useCampaignUpdates(handleEvent, true);

  const navGroups: NavGroup[] = [
    {
      label: 'Overview',
      items: [
        { to: '/data', label: 'Dashboard', icon: LayoutDashboard },
        { to: '/data/supporters', label: 'Supporters', icon: Users },
      ],
    },
    {
      label: 'Data Entry',
      items: [
        { to: '/data/entry', label: 'Manual Entry', icon: ClipboardPlus },
        { to: '/data/import', label: 'Excel Import', icon: Upload },
      ],
    },
    {
      label: 'Review',
      items: [
        { to: '/data/duplicates', label: 'Duplicates', icon: Copy },
      ],
    },
    {
      label: 'Reports',
      items: [
        { to: '/data/reports', label: 'Generate Reports', icon: FileSpreadsheet },
        { to: '/data/audit-logs', label: 'Activity Log', icon: ScrollText },
      ],
    },
    ...((sessionData?.permissions?.can_manage_users ||
      sessionData?.permissions?.can_manage_data_configuration ||
      sessionData?.permissions?.can_manage_configuration)
      ? [
          {
            label: 'DPG Setup',
            items: [
              ...(sessionData?.permissions?.can_manage_users ? [ { to: '/data/users', label: 'Users', icon: Shield } ] : []),
              ...(sessionData?.permissions?.can_manage_data_configuration ? [ { to: '/data/districts', label: 'Districts', icon: MapPin } ] : []),
              ...(sessionData?.permissions?.can_manage_data_configuration ? [ { to: '/data/precincts', label: 'Precincts', icon: MapPin } ] : []),
              ...(sessionData?.permissions?.can_manage_configuration ? [ { to: '/data/campaign-settings', label: 'SMS & Public Settings', icon: Settings } ] : []),
            ],
          },
        ]
      : []),
  ].filter(g => g.items.length > 0);

  const isActive = (to: string) => {
    if (to === '/data') return location.pathname === '/data';
    if (location.pathname === to) return true;
    if (location.pathname.startsWith(to + '/')) {
      const allPaths = navGroups.flatMap(g => g.items.map(i => i.to));
      return !allPaths.some(p => p !== to && p.startsWith(to) && location.pathname.startsWith(p));
    }
    return false;
  };

  useEffect(() => {
    if (typeof window === 'undefined') return;
    window.localStorage.setItem(teamSidebarStorageKey, String(desktopCollapsed));
  }, [desktopCollapsed]);

  const showRailTooltip = (label: string, element: HTMLElement) => {
    const rect = element.getBoundingClientRect();
    setRailTooltip({
      label,
      top: rect.top + rect.height / 2,
      left: rect.right + 12,
    });
  };

  const hideRailTooltip = () => setRailTooltip(null);

  const navLink = (item: NavItem, collapsed = false) => {
    const Icon = item.icon;
    const active = isActive(item.to);
    return (
      <Link
        key={item.to}
        to={item.to}
        onClick={() => { hideRailTooltip(); setSidebarOpen(false); }}
        onMouseEnter={(event) => collapsed && showRailTooltip(item.label, event.currentTarget)}
        onMouseLeave={hideRailTooltip}
        onFocus={(event) => collapsed && showRailTooltip(item.label, event.currentTarget)}
        onBlur={hideRailTooltip}
        aria-label={collapsed ? item.label : undefined}
        title={collapsed ? item.label : undefined}
        className={`group relative flex min-h-11 items-center rounded-xl px-3 py-2 text-[13px] font-medium transition-all duration-150 ${
          collapsed ? 'justify-center gap-0' : 'gap-2.5'
        } ${
          active
            ? 'bg-primary text-white shadow-[0_12px_24px_-16px_rgba(15,42,91,0.8)]'
            : 'text-slate-600 hover:bg-slate-100 hover:text-slate-900'
        }`}
      >
        <Icon className={`h-4 w-4 shrink-0 ${active ? 'text-blue-100' : 'text-slate-400'}`} />
        <span className={collapsed ? 'sr-only' : 'truncate'}>{item.label}</span>
        {item.badge && item.badge > 0 ? (
          <span className={`${collapsed ? 'absolute right-1 top-1' : 'ml-auto'} bg-red-500 text-white text-[10px] font-bold px-1.5 py-0.5 rounded-full min-w-[18px] text-center leading-tight`}>
            {item.badge > 99 ? '99+' : item.badge}
          </span>
        ) : null}
      </Link>
    );
  };

  const utilityLink = (to: string, label: string, Icon: React.ComponentType<{ className?: string }>, collapsed = false) => (
    <Link
      to={to}
      onClick={() => { hideRailTooltip(); setSidebarOpen(false); }}
      onMouseEnter={(event) => collapsed && showRailTooltip(label, event.currentTarget)}
      onMouseLeave={hideRailTooltip}
      onFocus={(event) => collapsed && showRailTooltip(label, event.currentTarget)}
      onBlur={hideRailTooltip}
      aria-label={collapsed ? label : undefined}
      title={collapsed ? label : undefined}
      className={`group relative flex min-h-11 items-center rounded-xl px-3 py-2 text-[13px] font-medium text-slate-500 transition-all duration-150 hover:bg-slate-100 hover:text-slate-900 ${
        collapsed ? 'justify-center gap-0' : 'gap-2.5'
      }`}
    >
      <Icon className="h-4 w-4 shrink-0 text-slate-400" />
      <span className={collapsed ? 'sr-only' : ''}>{label}</span>
    </Link>
  );

  const sidebarContent = (collapsed = false) => (
    <nav className="flex flex-col h-full">
      {/* Brand */}
      <div className={collapsed ? 'px-3 pt-3 pb-2' : 'px-3 pt-4 pb-3'}>
        <Link to="/data" className="block" onClick={() => { hideRailTooltip(); setSidebarOpen(false); }} title={collapsed ? 'Data Ops Workspace' : undefined}>
          <WorkspaceBrandPanel
            compact
            rail={collapsed}
            workspaceName="Data Ops Workspace"
            workspaceDescription="Daily voter operations, imports, and supporter review."
            badge="Internal DPG workspace"
          />
        </Link>
        <button
          type="button"
          onClick={() => { hideRailTooltip(); setDesktopCollapsed((value) => !value); }}
          onMouseEnter={(event) => collapsed && showRailTooltip('Expand sidebar', event.currentTarget)}
          onMouseLeave={hideRailTooltip}
          onFocus={(event) => collapsed && showRailTooltip('Expand sidebar', event.currentTarget)}
          onBlur={hideRailTooltip}
          className={`mt-2 hidden min-h-11 w-full items-center rounded-xl border border-slate-200 bg-white px-3 py-2 text-[12px] font-semibold text-slate-500 shadow-sm transition hover:bg-slate-50 hover:text-slate-900 lg:flex ${
            collapsed ? 'justify-center' : 'justify-between'
          }`}
          aria-label={collapsed ? 'Expand sidebar' : 'Collapse sidebar'}
          aria-expanded={!collapsed}
        >
          <Menu className="h-4 w-4" />
          <span className={collapsed ? 'sr-only' : ''}>{collapsed ? 'Expand' : 'Collapse'}</span>
        </button>
      </div>

      {/* Supporter summary */}
      {counts?.official_supporters !== undefined && !collapsed && (
        <div className="mx-3 mb-3 flex items-center justify-between gap-3 rounded-2xl border border-blue-100 bg-blue-50 px-3 py-2 shadow-sm">
          <div className="min-w-0 text-[9px] font-semibold uppercase tracking-[0.16em] text-blue-600">Official Supporters</div>
          <div className="shrink-0 text-lg font-bold text-blue-900">{(counts.official_supporters || 0).toLocaleString()}</div>
        </div>
      )}

      {/* Nav Groups */}
      <div className={`flex-1 overflow-y-auto pb-3 ${collapsed ? 'space-y-2 px-3' : 'space-y-4 px-3'}`}>
        {navGroups.map((group) => (
          <div key={group.label}>
            <div className={collapsed ? 'sr-only' : 'mb-1.5 px-3 text-[10px] font-semibold uppercase tracking-[0.12em] text-slate-400'}>
              {group.label}
            </div>
            <div className="space-y-0.5">
              {group.items.map((item) => navLink(item, collapsed))}
            </div>
          </div>
        ))}
      </div>

      {/* Admin link (for campaign_admin users) */}
      {sessionData?.user?.role === 'campaign_admin' && (
        <div className="border-t border-slate-200 px-3 pt-2 pb-2">
          {utilityLink('/admin', 'More DPG Tools', Settings, collapsed)}
        </div>
      )}

      {/* View Public Site */}
      <div className="border-t border-slate-200 px-3 pt-2 pb-2">
        {utilityLink('/', 'View Public Site', Home, collapsed)}
      </div>

      {/* User */}
      <div className={`flex items-center border-t border-slate-200 px-4 py-3 ${collapsed ? 'justify-center' : 'gap-3'}`}>
        <UserButton afterSignOutUrl="/" />
        <div className={collapsed ? 'sr-only' : 'min-w-0 flex-1'}>
          <div className="truncate text-[13px] font-medium text-slate-900">
            {sessionData?.user?.name || sessionData?.user?.email || 'Loading...'}
          </div>
          <div className="truncate text-[11px] capitalize text-slate-400">
            {formatRoleLabel(sessionData?.user?.role)}
          </div>
        </div>
      </div>
    </nav>
  );

  return (
    <div className="min-h-screen bg-[#f6f8fc]">
      {sidebarOpen && (
        <div
          className="fixed inset-0 bg-black/30 backdrop-blur-sm z-40 lg:hidden"
          onClick={() => { hideRailTooltip(); setSidebarOpen(false); }}
        />
      )}

      <aside className={`z-30 hidden border-r border-slate-200 bg-[#f8fbff] shadow-sm transition-all duration-300 lg:fixed lg:inset-y-0 lg:left-0 lg:flex lg:flex-col ${
        desktopCollapsed ? 'lg:w-[88px]' : 'lg:w-[240px]'
      }`}>
        {sidebarContent(desktopCollapsed)}
      </aside>
      {desktopCollapsed && railTooltip && (
        <div
          className="pointer-events-none fixed z-[80] hidden -translate-y-1/2 whitespace-nowrap rounded-lg bg-slate-950 px-3 py-2 text-xs font-semibold text-white shadow-xl lg:block"
          style={{ top: railTooltip.top, left: railTooltip.left }}
        >
          {railTooltip.label}
        </div>
      )}

      <aside
        className={`fixed inset-y-0 left-0 z-50 w-[300px] transform border-r border-slate-200 bg-[#f8fbff] shadow-xl transition-transform duration-200 ease-out lg:hidden ${
          sidebarOpen ? 'translate-x-0' : '-translate-x-full'
        }`}
      >
        <button
          onClick={() => { hideRailTooltip(); setSidebarOpen(false); }}
          className="absolute top-5 right-4 rounded-lg p-1 text-slate-400 transition-colors hover:bg-slate-100 hover:text-slate-600"
        >
          <X className="w-5 h-5" />
        </button>
        {sidebarContent(false)}
      </aside>

      <div className={`transition-[padding] duration-300 ${desktopCollapsed ? 'lg:pl-[88px]' : 'lg:pl-[240px]'}`}>
        {toasts.length > 0 && (
          <div className="fixed top-16 left-2 right-2 sm:left-auto sm:right-4 z-50 space-y-2 max-w-sm sm:max-w-md">
            {toasts.map(toast => (
              <div
                key={toast.id}
                className={`rounded-lg p-3 pr-8 shadow-lg border text-sm animate-slide-in relative ${
                  toast.type === 'success' ? 'bg-green-50 border-green-200 text-green-800' :
                  toast.type === 'warning' ? 'bg-yellow-50 border-yellow-200 text-yellow-800' :
                  'bg-blue-50 border-blue-200 text-blue-800'
                }`}
              >
                {toast.message}
                <button
                  onClick={() => dismiss(toast.id)}
                  className="absolute top-2 right-2 text-gray-400 hover:text-gray-600"
                >
                  <X className="w-3.5 h-3.5" />
                </button>
              </div>
            ))}
          </div>
        )}

        <header className="sticky top-0 z-20 flex items-center justify-between border-b border-slate-200 bg-white/95 px-4 py-3 shadow-sm backdrop-blur-md lg:hidden">
          <button
            onClick={() => setSidebarOpen(true)}
            className="rounded-lg p-1.5 text-slate-500 transition-colors hover:bg-slate-100 hover:text-slate-700"
          >
            <Menu className="w-5 h-5" />
          </button>
          <div className="text-center">
            <div className="text-[10px] font-semibold uppercase tracking-[0.18em] text-slate-400">{publicSiteConfig.wordmark.title}</div>
            <h1 className="text-sm font-bold tracking-tight text-slate-900">Data Ops</h1>
          </div>
          <UserButton afterSignOutUrl="/" />
        </header>

        <main>
          {children}
        </main>
      </div>
    </div>
  );
}
