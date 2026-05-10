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
    <div className="min-h-screen overflow-hidden bg-[#f7fbfc] text-slate-900">
      <div className="relative bg-[#123d70] px-4 py-3 text-center text-[10px] font-bold uppercase leading-5 tracking-[0.2em] text-white shadow-sm sm:text-[11px] sm:tracking-[0.28em]">
        <div className="absolute inset-0 bg-[linear-gradient(90deg,rgba(255,255,255,0.08),transparent,rgba(128,199,232,0.22))]" />
        <span className="relative">
        {publicSite.topBar}
        </span>
      </div>

      <div className="border-b border-[#dce8ef] bg-white/90 backdrop-blur-xl">
        <div className="mx-auto flex w-full max-w-6xl items-center justify-between gap-4 px-4 py-4 md:px-6">
          <Link to="/" className="min-w-0">
            <PublicWordmark size="sm" />
          </Link>
        </div>
      </div>

      <main className="relative mx-auto flex w-full max-w-6xl flex-col gap-8 px-4 py-8 md:gap-10 md:px-6 md:py-14">
        <div className="absolute inset-0 -z-10 bg-[radial-gradient(circle_at_12%_2%,rgba(131,200,232,0.28),transparent_32%),radial-gradient(circle_at_90%_10%,rgba(213,163,50,0.16),transparent_34%),linear-gradient(180deg,#eef6fb_0%,#f7fbfc_48%,#ffffff_100%)]" />
        <section className="grid gap-6 lg:grid-cols-[1.02fr_0.98fr] lg:items-start">
          <div className="space-y-5">
            <div className="flex h-16 w-16 items-center justify-center rounded-full bg-[#fff1ef] text-[#ce243c] shadow-sm">
              <Heart className="h-8 w-8" />
            </div>

            <div className="space-y-3">
              <h1 className="text-4xl font-black tracking-[-0.045em] text-[#071326] md:text-6xl">
                {publicSite.thankYouTitle}
              </h1>
              <p className="text-xl font-bold text-[#123d70] md:text-2xl">
                {publicSite.thankYouSubtitle}
              </p>
              <p className="max-w-2xl text-base leading-8 text-slate-600 md:text-lg">
                {publicSite.thankYouBody}
              </p>
            </div>

            <div className="flex flex-col gap-3 sm:flex-row">
              <Link
                to="/"
                className="inline-flex min-h-[52px] items-center justify-center gap-2 rounded-full bg-[#123d70] px-7 text-base font-bold text-white shadow-lg shadow-[#123d70]/15 transition hover:-translate-y-0.5 hover:bg-[#0c2c52]"
              >
                <Home className="h-4 w-4" />
                Back to home
              </Link>
              <Link
                to="/signup"
                className="inline-flex min-h-[52px] items-center justify-center gap-2 rounded-full border border-[#cfe0e8] bg-white px-7 text-base font-bold text-slate-700 shadow-sm transition hover:-translate-y-0.5 hover:border-[#83c8e8] hover:text-[#123d70]"
              >
                <ArrowLeft className="h-4 w-4" />
                Submit another response
              </Link>
            </div>

            {(campaignInfo?.instagram_url || campaignInfo?.facebook_url) && (
              <div className="rounded-[30px] border border-[#dce8ef] bg-white/92 p-5 shadow-sm">
                <div className="flex items-center gap-2 text-slate-900">
                  <Share2 className="h-5 w-5 text-[#123d70]" />
                  <p className="font-bold">{publicSite.followLabel}</p>
                </div>
                <div className="mt-4 flex flex-wrap gap-3">
                  {campaignInfo?.instagram_url && (
                    <a
                      href={campaignInfo.instagram_url}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="inline-flex min-h-[44px] items-center gap-2 rounded-full border border-[#dce8ef] bg-white px-4 py-2 text-sm font-bold text-slate-700 transition hover:text-[#123d70]"
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
                      className="inline-flex min-h-[44px] items-center gap-2 rounded-full border border-[#dce8ef] bg-white px-4 py-2 text-sm font-bold text-slate-700 transition hover:text-[#123d70]"
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
            <div className="overflow-hidden rounded-[34px] border border-white bg-white/90 p-4 shadow-[0_28px_80px_-44px_rgba(18,61,112,0.68)]">
              <div className="rounded-[28px] bg-[linear-gradient(135deg,#123d70_0%,#2468ad_58%,#84c7e8_100%)] p-8">
                <img
                  src={publicSite.thankYouImageSrc || publicSite.featurePanelImageSrc}
                  srcSet={publicSite.thankYouImageSrcSet || publicSite.featurePanelImageSrcSet}
                  sizes="(min-width: 768px) 320px, 100vw"
                  alt={publicSite.thankYouImageAlt || publicSite.featurePanelImageAlt}
                  className="mx-auto h-56 w-full object-contain drop-shadow-xl md:h-72"
                />
              </div>
            </div>

            <div className="rounded-[30px] border border-[#f0d9a4] bg-[#fffaf0] p-5 shadow-sm">
              <p className="text-xs font-bold uppercase tracking-[0.22em] text-[#93650d]">
                {publicSite.thankYouNextStepTitle}
              </p>
              <p className="mt-3 text-sm leading-7 text-slate-700">
                {publicSite.thankYouNextStepBody}
              </p>
            </div>

            {showReminderCard && (
              <div className="rounded-[30px] border border-[#dce8ef] bg-[#f2fbff] p-5 shadow-sm">
                <p className="text-xs font-bold uppercase tracking-[0.22em] text-[#123d70]">
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
