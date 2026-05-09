import { useState } from 'react';
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
  Shield,
  MapPin,
  ScrollText,
  Upload,
  FileSpreadsheet,
  Menu,
  X,
  Home,
  Database,
  Copy,
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

export default function AdminShell({ children }: { children: React.ReactNode }) {
  const location = useLocation();
  const { data: sessionData } = useSession();
  const { toasts, handleEvent, dismiss } = useRealtimeToast();
  const [sidebarOpen, setSidebarOpen] = useState(false);
  useCampaignUpdates(handleEvent, true);

  const permissions = sessionData?.permissions;

  const navGroups: NavGroup[] = [
    {
      label: 'Overview',
      items: [
        { to: '/admin', label: 'Dashboard', icon: LayoutDashboard },
        ...(permissions?.can_view_supporters ? [ { to: '/admin/supporters', label: 'Supporters', icon: Users } ] : []),
      ],
    },
    {
      label: 'Data Entry',
      items: [
        ...(permissions?.can_create_staff_supporters ? [ { to: '/admin/supporters/new', label: 'New Entry', icon: ClipboardPlus } ] : []),
        ...(permissions?.can_import_supporters ? [ { to: '/admin/import', label: 'Excel Import', icon: Upload } ] : []),
      ],
    },
    {
      label: 'Outreach',
      items: [
        ...(permissions?.can_view_supporters ? [ { to: '/admin/outreach', label: 'Voter Help Follow-Up', icon: ClipboardCheck } ] : []),
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

  const navLink = (item: NavItem) => {
    const Icon = item.icon;
    const active = isActive(item.to);
    return (
      <Link
        key={item.to}
        to={item.to}
        onClick={() => setSidebarOpen(false)}
        className={`flex items-center gap-2.5 rounded-xl px-3 py-2.5 text-[13px] font-medium transition-all duration-150 ${
          active
            ? 'bg-primary text-white shadow-[0_12px_24px_-16px_rgba(15,42,91,0.8)]'
            : 'text-slate-600 hover:bg-slate-100 hover:text-slate-900'
        }`}
      >
        <Icon className={`h-4 w-4 shrink-0 ${active ? 'text-blue-100' : 'text-slate-400'}`} />
        <span className="truncate">{item.label}</span>
        {item.badge && item.badge > 0 ? (
          <span className="ml-auto bg-red-500 text-white text-[10px] font-bold px-1.5 py-0.5 rounded-full min-w-[18px] text-center leading-tight">
            {item.badge}
          </span>
        ) : null}
      </Link>
    );
  };

  const sidebarContent = (
    <nav className="flex flex-col h-full">
      {/* Brand */}
      <div className="px-4 pt-5 pb-4">
        <Link to="/admin" className="block" onClick={() => setSidebarOpen(false)}>
          <WorkspaceBrandPanel
            compact
            workspaceName="DPG Operations"
            workspaceDescription="Leadership, outreach, and voter engagement tools."
            badge="Internal DPG workspace"
          />
        </Link>
      </div>

      {/* Nav Groups */}
      <div className="flex-1 space-y-5 overflow-y-auto px-3 pb-4">
        {navGroups.map((group) => (
          <div key={group.label}>
            <div className="mb-1.5 px-3 text-[10px] font-semibold uppercase tracking-[0.12em] text-slate-400">
              {group.label}
            </div>
            <div className="space-y-0.5">
              {group.items.map(navLink)}
            </div>
          </div>
        ))}
      </div>

      {/* Data Ops link */}
      {sessionData?.permissions?.can_access_data_team && (
        <div className="px-3 pb-2">
          <Link
            to="/data"
            className="flex items-center gap-2.5 rounded-xl border border-blue-200 bg-blue-50 px-3 py-2.5 text-[13px] font-semibold text-blue-700 transition-all duration-150 hover:bg-blue-100"
          >
            <Database className="h-4 w-4 shrink-0 text-blue-500" />
            <span>Open Data Ops</span>
          </Link>
        </div>
      )}

      {/* View Public Site */}
      <div className="mt-auto border-t border-slate-200 px-3 pt-3 pb-4">
        <Link
          to="/"
          className="flex items-center gap-2.5 rounded-xl px-3 py-2.5 text-[13px] font-medium text-slate-500 transition-all duration-150 hover:bg-slate-100 hover:text-slate-900"
        >
          <Home className="h-4 w-4 shrink-0 text-slate-400" />
          <span>View Public Site</span>
        </Link>
      </div>

      {/* User */}
      <div className="flex items-center gap-3 border-t border-slate-200 px-4 py-4">
        <UserButton afterSignOutUrl="/" />
        <div className="min-w-0 flex-1">
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
          onClick={() => setSidebarOpen(false)}
        />
      )}

      {/* Sidebar - desktop */}
      <aside className="z-30 hidden border-r border-slate-200 bg-[#f8fbff] shadow-sm lg:fixed lg:inset-y-0 lg:left-0 lg:flex lg:w-[240px] lg:flex-col">
        {sidebarContent}
      </aside>

      {/* Sidebar - mobile */}
      <aside
        className={`fixed inset-y-0 left-0 z-50 w-[300px] transform border-r border-slate-200 bg-[#f8fbff] shadow-xl transition-transform duration-200 ease-out lg:hidden ${
          sidebarOpen ? 'translate-x-0' : '-translate-x-full'
        }`}
      >
        <button
          onClick={() => setSidebarOpen(false)}
          className="absolute top-5 right-4 rounded-lg p-1 text-slate-400 transition-colors hover:bg-slate-100 hover:text-slate-600"
        >
          <X className="w-5 h-5" />
        </button>
        {sidebarContent}
      </aside>

      {/* Main content */}
      <div className="lg:pl-[240px]">
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
