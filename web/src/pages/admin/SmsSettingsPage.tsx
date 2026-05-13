import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { getSettings, updateSettings } from '../../lib/api';
import { Save, RotateCcw, MessageSquare, Info, Globe } from 'lucide-react';
import WorkspacePage from '../../components/WorkspacePage';

interface SettingsData {
  welcome_sms_template: string;
  welcome_sms_preview: string;
  available_variables: string[];
  instagram_url: string | null;
  facebook_url: string | null;
  tiktok_url: string | null;
  twitter_url: string | null;
  signup_share_prompt: string | null;
  thank_you_share_prompt: string | null;
  primary_election_date: string | null;
  general_election_date: string | null;
}

export default function SmsSettingsPage() {
  const queryClient = useQueryClient();
  const [template, setTemplate] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);
  const [socialLinks, setSocialLinks] = useState<{
    instagram_url: string;
    facebook_url: string;
    tiktok_url: string;
    twitter_url: string;
  } | null>(null);
  const [socialSaved, setSocialSaved] = useState(false);
  const [thankYouSettings, setThankYouSettings] = useState<{
    signup_share_prompt: string;
    thank_you_share_prompt: string;
    primary_election_date: string;
    general_election_date: string;
  } | null>(null);
  const [thankYouSaved, setThankYouSaved] = useState(false);

  const { data: settings, isLoading } = useQuery<SettingsData>({
    queryKey: ['settings'],
    queryFn: getSettings,
  });

  // Use server value until user starts editing
  const displayTemplate = template ?? settings?.welcome_sms_template ?? '';

  const saveMutation = useMutation({
    mutationFn: (newTemplate: string) => updateSettings({ welcome_sms_template: newTemplate }),
    onSuccess: (data: SettingsData) => {
      queryClient.setQueryData(['settings'], data);
      setTemplate(null);
      setSaved(true);
      setTimeout(() => setSaved(false), 3000);
    },
  });

  const resetMutation = useMutation({
    mutationFn: () => updateSettings({ welcome_sms_template: '' }),
    onSuccess: (data: SettingsData) => {
      queryClient.setQueryData(['settings'], data);
      setTemplate(null);
      setSaved(true);
      setTimeout(() => setSaved(false), 3000);
    },
  });

  const displaySocial = {
    instagram_url: socialLinks?.instagram_url ?? settings?.instagram_url ?? '',
    facebook_url: socialLinks?.facebook_url ?? settings?.facebook_url ?? '',
    tiktok_url: socialLinks?.tiktok_url ?? settings?.tiktok_url ?? '',
    twitter_url: socialLinks?.twitter_url ?? settings?.twitter_url ?? '',
  };

  const hasSocialChanges = socialLinks !== null && settings && (
    socialLinks.instagram_url !== (settings.instagram_url ?? '') ||
    socialLinks.facebook_url !== (settings.facebook_url ?? '') ||
    socialLinks.tiktok_url !== (settings.tiktok_url ?? '') ||
    socialLinks.twitter_url !== (settings.twitter_url ?? '')
  );

  const saveSocialMutation = useMutation({
    mutationFn: (data: typeof displaySocial) => updateSettings(data),
    onSuccess: (data: SettingsData) => {
      queryClient.setQueryData(['settings'], data);
      setSocialLinks(null);
      setSocialSaved(true);
      setTimeout(() => setSocialSaved(false), 3000);
    },
  });

  const displayThankYouSettings = {
    signup_share_prompt: thankYouSettings?.signup_share_prompt ?? settings?.signup_share_prompt ?? '',
    thank_you_share_prompt: thankYouSettings?.thank_you_share_prompt ?? settings?.thank_you_share_prompt ?? '',
    primary_election_date: thankYouSettings?.primary_election_date ?? settings?.primary_election_date ?? '',
    general_election_date: thankYouSettings?.general_election_date ?? settings?.general_election_date ?? '',
  };

  const hasThankYouChanges = thankYouSettings !== null && settings && (
    thankYouSettings.signup_share_prompt !== (settings.signup_share_prompt ?? '') ||
    thankYouSettings.thank_you_share_prompt !== (settings.thank_you_share_prompt ?? '') ||
    thankYouSettings.primary_election_date !== (settings.primary_election_date ?? '') ||
    thankYouSettings.general_election_date !== (settings.general_election_date ?? '')
  );

  const saveThankYouMutation = useMutation({
    mutationFn: (data: typeof displayThankYouSettings) => updateSettings(data),
    onSuccess: (data: SettingsData) => {
      queryClient.setQueryData(['settings'], data);
      setThankYouSettings(null);
      setThankYouSaved(true);
      setTimeout(() => setThankYouSaved(false), 3000);
    },
  });

  const charCount = displayTemplate.length;
  const smsSegments = charCount <= 160 ? 1 : Math.ceil(charCount / 153);
  const hasChanges = template !== null && settings && template !== settings.welcome_sms_template;

  // Live preview with sample data
  const previewText = displayTemplate
    .replace(/\{first_name\}/g, 'Maria')
    .replace(/\{last_name\}/g, 'Cruz')
    .replace(/\{village\}/g, 'Tamuning');

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-20">
        <div className="animate-pulse text-(--text-muted) text-sm font-medium">Loading settings...</div>
      </div>
    );
  }

  return (
    <WorkspacePage width="full" className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight text-gray-900">SMS, Social &amp; Public Settings</h1>
        <p className="text-sm text-(--text-secondary) mt-1">
          Manage the welcome text template plus the public social links and signup or thank-you reminders shown across the site.
        </p>
      </div>

      <div className="space-y-6">
        {/* Welcome SMS Template */}
        <div className="app-card p-6 space-y-4">
          <div className="flex items-center gap-2">
            <MessageSquare className="w-5 h-5 text-primary" />
            <h2 className="text-lg font-semibold text-(--text-primary)">Welcome SMS Template</h2>
          </div>
          <p className="text-sm text-(--text-secondary)">
            This message is sent automatically when a new supporter signs up (if they opt in to text messages).
          </p>

          {/* Variables */}
          <div className="bg-blue-50 border border-blue-200 rounded-xl p-4">
            <div className="flex items-start gap-2">
              <Info className="w-4 h-4 text-blue-600 mt-0.5 shrink-0" />
              <div>
                <p className="text-sm font-medium text-blue-900">Available variables</p>
                <p className="text-sm text-blue-700 mt-1">
                  Click to insert: {settings?.available_variables.map((v) => (
                    <button
                      key={v}
                      onClick={() => setTemplate((prev) => (prev ?? settings?.welcome_sms_template ?? '') + `{${v}}`)}
                      className="inline-block bg-blue-100 hover:bg-blue-200 text-blue-800 px-2 py-0.5 rounded text-xs font-mono mr-1.5 mb-1"
                    >
                      {`{${v}}`}
                    </button>
                  ))}
                </p>
              </div>
            </div>
          </div>

          {/* Editor */}
          <div>
            <textarea
              value={displayTemplate}
              onChange={(e) => setTemplate(e.target.value)}
              rows={4}
              maxLength={320}
              className="w-full border border-(--border-soft) rounded-xl px-4 py-3 text-sm focus:ring-2 focus:ring-primary focus:border-transparent resize-none"
              placeholder="Enter your welcome SMS template..."
            />
            <div className="flex justify-between mt-1">
              <span className={`text-xs ${charCount > 160 ? 'text-amber-600' : 'text-(--text-muted)'}`}>
                {charCount}/320 chars · {smsSegments} SMS segment{smsSegments !== 1 ? 's' : ''}
              </span>
              {charCount > 160 && (
                <span className="text-xs text-amber-600">
                  Messages over 160 chars use multiple segments (higher cost)
                </span>
              )}
            </div>
          </div>

          {/* Preview */}
          <div>
            <p className="text-xs font-medium text-(--text-secondary) uppercase tracking-wide mb-2">Preview</p>
            <div className="bg-green-50 border border-green-200 rounded-xl p-4">
              <p className="text-sm text-(--text-primary) whitespace-pre-wrap">{previewText || '(empty)'}</p>
              <p className="text-xs text-(--text-muted) mt-2">Sample: Maria Cruz from Tamuning</p>
            </div>
          </div>

          {/* Actions */}
          <div className="flex items-center gap-3 pt-2">
            <button
              onClick={() => saveMutation.mutate(displayTemplate)}
              disabled={saveMutation.isPending || !hasChanges}
              className="inline-flex items-center gap-2 px-5 py-2.5 bg-primary text-white rounded-lg hover:bg-[#15305a] disabled:opacity-50 text-sm font-medium"
            >
              <Save className="w-4 h-4" />
              {saveMutation.isPending ? 'Saving...' : 'Save Template'}
            </button>
            <button
              onClick={() => resetMutation.mutate()}
              disabled={resetMutation.isPending}
              className="inline-flex items-center gap-2 px-5 py-2.5 bg-(--surface-overlay) text-(--text-primary) rounded-lg hover:bg-gray-200 disabled:opacity-50 text-sm font-medium"
            >
              <RotateCcw className="w-4 h-4" />
              Reset to Default
            </button>
            {saved && (
              <span className="text-sm text-green-600 font-medium">Saved!</span>
            )}
          </div>

          {saveMutation.isError && (
            <div className="bg-red-50 border border-red-200 rounded-xl p-4 text-red-600 text-sm">
              {(saveMutation.error as Error)?.message || 'Failed to save. Please try again.'}
            </div>
          )}
        </div>

        {/* Social Media Links */}
        <div className="app-card p-6 space-y-4">
          <div className="flex items-center gap-2">
            <Globe className="w-5 h-5 text-primary" />
            <h2 className="text-lg font-semibold text-(--text-primary)">Social Media Links</h2>
          </div>
          <p className="text-sm text-(--text-secondary)">
            These links appear on the public landing page and thank-you page. Leave blank to hide a link.
          </p>

          <div className="space-y-3">
            {([
              { key: 'instagram_url' as const, label: 'Instagram URL', placeholder: 'https://www.instagram.com/yourpage' },
              { key: 'facebook_url' as const, label: 'Facebook URL', placeholder: 'https://www.facebook.com/yourpage' },
              { key: 'tiktok_url' as const, label: 'TikTok URL', placeholder: 'https://www.tiktok.com/@yourpage' },
              { key: 'twitter_url' as const, label: 'X (Twitter) URL', placeholder: 'https://x.com/yourhandle' },
            ]).map(({ key, label, placeholder }) => (
              <div key={key}>
                <label className="block text-sm font-medium text-(--text-secondary) mb-1">{label}</label>
                <input
                  type="url"
                  value={displaySocial[key]}
                  onChange={(e) => setSocialLinks((prev) => ({
                    ...displaySocial,
                    ...prev,
                    [key]: e.target.value,
                  }))}
                  placeholder={placeholder}
                  className="w-full border border-(--border-soft) rounded-xl px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent"
                />
              </div>
            ))}
          </div>

          <div className="flex items-center gap-3 pt-2">
            <button
              onClick={() => saveSocialMutation.mutate(displaySocial)}
              disabled={saveSocialMutation.isPending || !hasSocialChanges}
              className="inline-flex items-center gap-2 px-5 py-2.5 bg-primary text-white rounded-lg hover:bg-[#15305a] disabled:opacity-50 text-sm font-medium"
            >
              <Save className="w-4 h-4" />
              {saveSocialMutation.isPending ? 'Saving...' : 'Save Links'}
            </button>
            {socialSaved && (
              <span className="text-sm text-green-600 font-medium">Saved!</span>
            )}
          </div>

          {saveSocialMutation.isError && (
            <div className="bg-red-50 border border-red-200 rounded-xl p-4 text-red-600 text-sm">
              {(saveSocialMutation.error as Error)?.message || 'Failed to save. Please try again.'}
            </div>
          )}
        </div>

        <div className="app-card p-6 space-y-4">
          <div className="flex items-center gap-2">
            <Globe className="w-5 h-5 text-primary" />
            <h2 className="text-lg font-semibold text-(--text-primary)">Public Reminder Settings</h2>
          </div>
          <p className="text-sm text-(--text-secondary)">
            Control the compact signup teaser, the fuller thank-you page share prompt, and the election dates shown across the public flow.
          </p>

          <div>
            <label className="block text-sm font-medium text-(--text-secondary) mb-1">Signup page teaser</label>
            <textarea
              value={displayThankYouSettings.signup_share_prompt}
              onChange={(e) => setThankYouSettings((prev) => ({
                ...displayThankYouSettings,
                ...prev,
                signup_share_prompt: e.target.value,
              }))}
              rows={2}
              className="w-full border border-(--border-soft) rounded-xl px-4 py-3 text-sm focus:ring-2 focus:ring-primary focus:border-transparent resize-none"
              placeholder="Example: Know other supporters? Finish your signup, then share this form with them too."
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-(--text-secondary) mb-1">Thank-you page share prompt</label>
            <textarea
              value={displayThankYouSettings.thank_you_share_prompt}
              onChange={(e) => setThankYouSettings((prev) => ({
                ...displayThankYouSettings,
                ...prev,
                thank_you_share_prompt: e.target.value,
              }))}
              rows={3}
              className="w-full border border-(--border-soft) rounded-xl px-4 py-3 text-sm focus:ring-2 focus:ring-primary focus:border-transparent resize-none"
              placeholder="Example: Share this signup link with family and friends who want to stay connected."
            />
          </div>

          <div className="grid gap-4 md:grid-cols-2">
            <div>
              <label className="block text-sm font-medium text-(--text-secondary) mb-1">Primary election date</label>
              <input
                type="date"
                value={displayThankYouSettings.primary_election_date}
                onChange={(e) => setThankYouSettings((prev) => ({
                  ...displayThankYouSettings,
                  ...prev,
                  primary_election_date: e.target.value,
                }))}
                className="w-full border border-(--border-soft) rounded-xl px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-(--text-secondary) mb-1">General election date</label>
              <input
                type="date"
                value={displayThankYouSettings.general_election_date}
                onChange={(e) => setThankYouSettings((prev) => ({
                  ...displayThankYouSettings,
                  ...prev,
                  general_election_date: e.target.value,
                }))}
                className="w-full border border-(--border-soft) rounded-xl px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent"
              />
            </div>
          </div>

          <div className="flex items-center gap-3 pt-2">
            <button
              onClick={() => saveThankYouMutation.mutate(displayThankYouSettings)}
              disabled={saveThankYouMutation.isPending || !hasThankYouChanges}
              className="inline-flex items-center gap-2 px-5 py-2.5 bg-primary text-white rounded-lg hover:bg-[#15305a] disabled:opacity-50 text-sm font-medium"
            >
              <Save className="w-4 h-4" />
              {saveThankYouMutation.isPending ? 'Saving...' : 'Save Reminder'}
            </button>
            {thankYouSaved && (
              <span className="text-sm text-green-600 font-medium">Saved!</span>
            )}
          </div>

          {saveThankYouMutation.isError && (
            <div className="bg-red-50 border border-red-200 rounded-xl p-4 text-red-600 text-sm">
              {(saveThankYouMutation.error as Error)?.message || 'Failed to save. Please try again.'}
            </div>
          )}
        </div>
      </div>
    </WorkspacePage>
  );
}
