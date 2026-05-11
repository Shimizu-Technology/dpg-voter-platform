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
  ClipboardCheck,
  ClipboardPlus,
  MessageSquare,
  Mail,
  Shield,
  MapPin,
  ScrollText,
  Upload,
  FileSpreadsheet,
  Menu,
  X,
  Home,
  Settings,
  Copy,
  Database,
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

const adminSidebarStorageKey = 'dpg-admin-sidebar-collapsed';

export default function AdminShell({ children }: { children: React.ReactNode }) {
  const location = useLocation();
  const { data: sessionData } = useSession();
  const { toasts, handleEvent, dismiss } = useRealtimeToast();
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [desktopCollapsed, setDesktopCollapsed] = useState(() => {
    if (typeof window === 'undefined') return false;
    return window.localStorage.getItem(adminSidebarStorageKey) === 'true';
  });
  const [railTooltip, setRailTooltip] = useState<{ label: string; top: number; left: number } | null>(null);
  useCampaignUpdates(handleEvent, true);

  const permissions = sessionData?.permissions;

  const navGroups: NavGroup[] = [
    {
      label: 'Overview',
      items: [
        { to: '/admin', label: 'Dashboard', icon: LayoutDashboard },
        ...(permissions?.can_view_supporters ? [ { to: '/admin/supporters', label: 'Contacts', icon: Users } ] : []),
        ...(permissions?.can_view_supporters ? [ { to: '/admin/intake', label: 'Intake', icon: ClipboardCheck, badge: sessionData?.counts?.new_intake } ] : []),
        ...(permissions?.can_view_supporters ? [ { to: '/admin/gec-voters', label: 'GEC Voters', icon: Database } ] : []),
      ],
    },
    {
      label: 'Data Entry',
      items: [
        ...(permissions?.can_create_staff_supporters ? [ { to: '/admin/supporters/new', label: 'New Entry', icon: ClipboardPlus } ] : []),
        ...(permissions?.can_import_supporters ? [ { to: '/admin/import', label: 'Import Contacts', icon: Upload } ] : []),
      ],
    },
    {
      label: 'Outreach',
      items: [
        ...(permissions?.can_view_supporters ? [ { to: '/admin/outreach', label: 'Follow-Up', icon: ClipboardCheck } ] : []),
        ...(permissions?.can_send_sms ? [ { to: '/admin/sms', label: 'SMS Blasts', icon: MessageSquare } ] : []),
        ...(permissions?.can_send_email ? [ { to: '/admin/email', label: 'Email Blasts', icon: Mail } ] : []),
      ],
    },
    {
      label: 'Review',
      items: [
        ...(permissions?.can_access_reports ? [ { to: '/admin/reports', label: 'Reports', icon: FileSpreadsheet } ] : []),
        ...(permissions?.can_access_duplicates ? [ { to: '/admin/duplicates', label: 'Duplicates', icon: Copy } ] : []),
        ...(permissions?.can_access_audit_logs ? [ { to: '/admin/audit-logs', label: 'Activity Log', icon: ScrollText } ] : []),
      ],
    },
    {
      label: 'Settings',
      items: [
        ...(permissions?.can_manage_users ? [ { to: '/admin/users', label: 'Users', icon: Shield } ] : []),
        ...(permissions?.can_manage_configuration ? [ { to: '/admin/districts', label: 'Districts', icon: MapPin } ] : []),
        ...(permissions?.can_manage_configuration ? [ { to: '/admin/precincts', label: 'Precincts', icon: MapPin } ] : []),
        ...(permissions?.can_manage_configuration ? [ { to: '/admin/sms/settings', label: 'SMS & Public Settings', icon: Settings } ] : []),
      ],
    },
  ].filter(g => g.items.length > 0);

  const isActive = (to: string) => {
    if (to === '/admin') return location.pathname === '/admin';
    if (location.pathname === to) return true;
    // For sub-pages like /admin/supporters/123, highlight the parent nav item
    // but NOT when another nav item is a more specific match (e.g. /admin/supporters/new)
    if (location.pathname.startsWith(to + '/')) {
      // Check if any other nav item is a more specific match
      const allPaths = navGroups.flatMap(g => g.items.map(i => i.to));
      return !allPaths.some(p => p !== to && p.startsWith(to) && location.pathname.startsWith(p));
    }
    return false;
  };

  const campaignName = publicSiteConfig.wordmark.subtitle;

  useEffect(() => {
    if (typeof window === 'undefined') return;
    window.localStorage.setItem(adminSidebarStorageKey, String(desktopCollapsed));
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

  const utilityLink = (to: string, label: string, Icon: React.ComponentType<{ className?: string }>, collapsed = false, className = '') => (
    <Link
      to={to}
      onClick={() => { hideRailTooltip(); setSidebarOpen(false); }}
      onMouseEnter={(event) => collapsed && showRailTooltip(label, event.currentTarget)}
      onMouseLeave={hideRailTooltip}
      onFocus={(event) => collapsed && showRailTooltip(label, event.currentTarget)}
      onBlur={hideRailTooltip}
      aria-label={collapsed ? label : undefined}
      title={collapsed ? label : undefined}
      className={`group relative flex min-h-11 items-center rounded-xl px-3 py-2 text-[13px] transition-all duration-150 ${
        collapsed ? 'justify-center gap-0' : 'gap-2.5'
      } ${className}`}
    >
      <Icon className="h-4 w-4 shrink-0 text-current" />
      <span className={collapsed ? 'sr-only' : ''}>{label}</span>
    </Link>
  );

  const sidebarContent = (collapsed = false) => (
    <nav className="flex flex-col h-full">
      {/* Brand */}
      <div className={collapsed ? 'px-3 pt-3 pb-2' : 'px-3 pt-4 pb-3'}>
        <Link to="/admin" className="block" onClick={() => { hideRailTooltip(); setSidebarOpen(false); }} title={collapsed ? 'DPG Operations' : undefined}>
          <WorkspaceBrandPanel
            compact
            rail={collapsed}
            workspaceName="DPG Operations"
            workspaceDescription="Leadership, outreach, and voter engagement tools."
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

      {/* View Public Site */}
      <div className="mt-auto border-t border-slate-200 px-3 pt-2 pb-2">
        {utilityLink('/', 'View Public Site', Home, collapsed, 'font-medium text-slate-500 hover:bg-slate-100 hover:text-slate-900')}
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
      {/* Mobile overlay */}
      {sidebarOpen && (
        <div
          className="fixed inset-0 bg-black/30 backdrop-blur-sm z-40 lg:hidden"
          onClick={() => { hideRailTooltip(); setSidebarOpen(false); }}
        />
      )}

      {/* Sidebar - desktop */}
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

      {/* Sidebar - mobile */}
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

      {/* Main content */}
      <div className={`transition-[padding] duration-300 ${desktopCollapsed ? 'lg:pl-[88px]' : 'lg:pl-[240px]'}`}>
        {/* Real-time toast notifications */}
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

        {/* Mobile top bar */}
        <header className="sticky top-0 z-20 flex items-center justify-between border-b border-slate-200 bg-white/95 px-4 py-3 shadow-sm backdrop-blur-md lg:hidden">
          <button
            onClick={() => setSidebarOpen(true)}
            className="rounded-lg p-1.5 text-slate-500 transition-colors hover:bg-slate-100 hover:text-slate-700"
          >
            <Menu className="w-5 h-5" />
          </button>
          <div className="text-center">
            <div className="text-[10px] font-semibold uppercase tracking-[0.18em] text-slate-400">{publicSiteConfig.wordmark.title}</div>
            <h1 className="text-sm font-bold tracking-tight text-slate-900">{campaignName}</h1>
          </div>
          <UserButton afterSignOutUrl="/" />
        </header>

        {/* Page content */}
        <main>
          {children}
        </main>
      </div>
    </div>
  );
}
