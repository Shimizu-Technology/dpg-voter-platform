import { Link } from 'react-router-dom';
import { ArrowLeft, Heart, Home, Share2 } from 'lucide-react';
import { useQuery } from '@tanstack/react-query';
import { getCampaignInfo } from '../lib/api';
import { formatElectionDate } from '../lib/datetime';
import PublicWordmark from '../components/PublicWordmark';
import { FacebookIcon, InstagramIcon } from '../components/PublicSocialIcons';
import { publicSiteConfig } from '../lib/publicSite';

export default function ThankYouPage() {
  const { data: campaignInfo } = useQuery({
    queryKey: ['campaignInfo'],
    queryFn: getCampaignInfo,
    staleTime: 300_000,
  });

  const publicSite = publicSiteConfig;
  const primaryElectionDate = formatElectionDate(campaignInfo?.primary_election_date);
  const generalElectionDate = formatElectionDate(campaignInfo?.general_election_date);
  const showReminderCard = Boolean(
    campaignInfo?.thank_you_share_prompt || primaryElectionDate || generalElectionDate
  );

  return (
    <div className="min-h-screen bg-[#f6f8fc] text-slate-900">
      <div className="bg-primary px-4 py-3 text-center text-xs font-semibold uppercase tracking-[0.24em] text-white">
        {publicSite.topBar}
      </div>

      <div className="border-b border-slate-200/80 bg-white/95 backdrop-blur">
        <div className="mx-auto flex w-full max-w-6xl items-center justify-between gap-4 px-4 py-4 md:px-6">
          <Link to="/" className="min-w-0">
            <PublicWordmark size="sm" />
          </Link>
        </div>
      </div>

      <main className="mx-auto flex w-full max-w-6xl flex-col gap-8 px-4 py-6 md:gap-10 md:px-6 md:py-12">
        <section className="grid gap-6 lg:grid-cols-[1.05fr_0.95fr] lg:items-start">
          <div className="space-y-5">
            <div className="flex h-16 w-16 items-center justify-center rounded-[22px] bg-[#fff1ef] text-cta">
              <Heart className="h-8 w-8" />
            </div>

            <div className="space-y-3">
              <h1 className="text-4xl font-extrabold tracking-tight text-slate-950 md:text-6xl">
                {publicSite.thankYouTitle}
              </h1>
              <p className="text-xl font-semibold text-primary md:text-2xl">
                {publicSite.thankYouSubtitle}
              </p>
              <p className="max-w-2xl text-base leading-8 text-slate-600 md:text-lg">
                {publicSite.thankYouBody}
              </p>
            </div>

            <div className="flex flex-col gap-3 sm:flex-row">
              <Link
                to="/"
                className="inline-flex min-h-[52px] items-center justify-center gap-2 rounded-full bg-primary px-7 text-base font-semibold text-white transition hover:bg-primary-dark"
              >
                <Home className="h-4 w-4" />
                Back to home
              </Link>
              <Link
                to="/signup"
                className="inline-flex min-h-[52px] items-center justify-center gap-2 rounded-full border border-slate-200 bg-white px-7 text-base font-semibold text-slate-700 transition hover:border-primary hover:text-primary"
              >
                <ArrowLeft className="h-4 w-4" />
                Submit another response
              </Link>
            </div>

            {(campaignInfo?.instagram_url || campaignInfo?.facebook_url) && (
              <div className="rounded-[28px] border border-slate-200 bg-white p-5 shadow-sm">
                <div className="flex items-center gap-2 text-slate-900">
                  <Share2 className="h-5 w-5 text-primary" />
                  <p className="font-semibold">{publicSite.followLabel}</p>
                </div>
                <div className="mt-4 flex flex-wrap gap-3">
                  {campaignInfo?.instagram_url && (
                    <a
                      href={campaignInfo.instagram_url}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="inline-flex min-h-[44px] items-center gap-2 rounded-full border border-slate-200 bg-white px-4 py-2 text-sm font-semibold text-slate-700 transition hover:text-primary"
                    >
                      <InstagramIcon className="h-5 w-5" />
                      Instagram
                    </a>
                  )}
                  {campaignInfo?.facebook_url && (
                    <a
                      href={campaignInfo.facebook_url}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="inline-flex min-h-[44px] items-center gap-2 rounded-full border border-slate-200 bg-white px-4 py-2 text-sm font-semibold text-slate-700 transition hover:text-primary"
                    >
                      <FacebookIcon className="h-5 w-5" />
                      Facebook
                    </a>
                  )}
                </div>
              </div>
            )}
          </div>

          <div className="space-y-5">
            <div className="overflow-hidden rounded-[32px] border border-slate-200 bg-white p-4 shadow-[0_24px_60px_-28px_rgba(15,42,91,0.22)]">
              <img
                src={publicSite.thankYouImageSrc || publicSite.featurePanelImageSrc}
                alt={publicSite.thankYouImageAlt || publicSite.featurePanelImageAlt}
                className="h-72 w-full rounded-[24px] object-cover md:h-80"
              />
            </div>

            <div className="rounded-[28px] border border-[#f0d9a4] bg-[#fff9ec] p-5 shadow-sm">
              <p className="text-xs font-semibold uppercase tracking-[0.22em] text-[#93650d]">
                {publicSite.thankYouNextStepTitle}
              </p>
              <p className="mt-3 text-sm leading-7 text-slate-700">
                {publicSite.thankYouNextStepBody}
              </p>
            </div>

            {showReminderCard && (
              <div className="rounded-[28px] border border-[#d7e5ff] bg-[#f5f9ff] p-5 shadow-sm">
                <p className="text-xs font-semibold uppercase tracking-[0.22em] text-primary">
                  Keep the momentum going
                </p>

                {campaignInfo?.thank_you_share_prompt && (
                  <p className="mt-3 text-sm leading-7 text-slate-700">
                    {campaignInfo.thank_you_share_prompt}
                  </p>
                )}

                {(primaryElectionDate || generalElectionDate) && (
                  <div className="mt-4 space-y-2 rounded-[20px] bg-white/80 p-4">
                    <p className="text-xs font-semibold uppercase tracking-[0.18em] text-slate-500">
                      Election reminders
                    </p>
                    {primaryElectionDate && (
                      <p className="text-sm font-medium text-slate-800">
                        Primary Election: <span className="font-semibold">{primaryElectionDate}</span>
                      </p>
                    )}
                    {generalElectionDate && (
                      <p className="text-sm font-medium text-slate-800">
                        General Election: <span className="font-semibold">{generalElectionDate}</span>
                      </p>
                    )}
                  </div>
                )}
              </div>
            )}
          </div>
        </section>
      </main>
    </div>
  );
}
