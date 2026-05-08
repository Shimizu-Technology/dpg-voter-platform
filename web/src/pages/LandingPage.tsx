import { Link } from 'react-router-dom';
import { ArrowRight, BarChart3, CalendarHeart, Heart } from 'lucide-react';
import { useQuery } from '@tanstack/react-query';
import { getCampaignInfo } from '../lib/api';
import PublicWordmark from '../components/PublicWordmark';
import { FacebookIcon, InstagramIcon } from '../components/PublicSocialIcons';
import { publicSiteConfig } from '../lib/publicSite';

export default function LandingPage() {
  const { data: campaignInfo } = useQuery({
    queryKey: ['campaignInfo'],
    queryFn: getCampaignInfo,
    staleTime: 300_000,
  });

  const publicSite = publicSiteConfig;

  return (
    <div className="min-h-screen bg-[#f6f8fc] text-slate-900">
      <div className="bg-primary px-4 py-3 text-center text-xs font-semibold uppercase tracking-[0.24em] text-white">
        {publicSite.topBar}
      </div>

      <div className="border-b border-slate-200/80 bg-white/95 backdrop-blur">
        <div className="mx-auto grid w-full max-w-6xl grid-cols-[minmax(0,1fr)_auto] items-center gap-3 px-4 py-4 md:gap-4 md:px-6">
          <Link to="/" className="min-w-0">
            <PublicWordmark size="sm" />
          </Link>
          <a
            href={publicSite.officialInfoUrl}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex min-h-[44px] min-w-[172px] shrink-0 items-center justify-center rounded-full border border-slate-200 px-5 text-center text-sm leading-none font-semibold text-slate-700 whitespace-nowrap transition hover:border-primary hover:text-primary md:min-w-[190px]"
          >
            {publicSite.officialInfoLabel}
          </a>
        </div>
      </div>

      <main className="mx-auto flex w-full max-w-6xl flex-col gap-8 px-4 py-5 md:gap-10 md:px-6 md:py-12">
        <section className="grid gap-6 lg:grid-cols-[1.1fr_0.9fr] lg:items-center">
          <div className="space-y-4 md:space-y-5">
            <div className="inline-flex rounded-full border border-[#f1d1cf] bg-[#fff5f4] px-4 py-2 text-xs font-semibold text-[#b3271d] md:text-sm">
              {publicSite.heroEyebrow}
            </div>

            <div className="space-y-3 md:space-y-4">
              <h1 className="max-w-3xl text-balance text-[2.15rem] leading-[0.97] font-extrabold tracking-tight text-slate-950 sm:text-[2.6rem] sm:leading-[0.98] md:text-6xl">
                <span className="md:hidden">{publicSite.heroTitleMobile}</span>
                <span className="hidden md:inline">{publicSite.heroTitleDesktop}</span>
              </h1>
              <div className="max-w-2xl space-y-3">
                <p className="text-[1.02rem] leading-7 text-slate-600 md:hidden">
                  {publicSite.heroLeadMobile}
                </p>
                <p className="text-sm leading-6 text-slate-500 md:hidden">
                  {publicSite.heroSupportTextMobile}
                </p>
                <p className="hidden text-lg leading-8 text-slate-600 md:block">
                  {publicSite.heroLeadDesktop}
                </p>
              </div>
            </div>

            <div className="flex flex-col gap-3 pt-1 sm:flex-row">
              <Link
                to="/signup"
                className="inline-flex min-h-[50px] w-full items-center justify-center gap-2 rounded-full bg-cta px-6 text-base font-bold text-white shadow-lg shadow-red-500/20 transition hover:-translate-y-0.5 hover:bg-cta-hover sm:w-auto md:min-h-[52px] md:px-7"
              >
                {publicSite.primaryCta}
                <ArrowRight className="h-5 w-5" />
              </Link>
              <a
                href={publicSite.officialInfoUrl}
                target="_blank"
                rel="noopener noreferrer"
                className="hidden min-h-[52px] items-center justify-center rounded-full border border-slate-200 bg-white px-7 text-base font-semibold text-slate-700 transition hover:border-primary hover:text-primary sm:inline-flex"
              >
                {publicSite.secondaryCta}
              </a>
            </div>
            <a
              href={publicSite.officialInfoUrl}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center justify-center text-sm font-semibold text-primary underline-offset-4 transition hover:text-primary-dark hover:underline sm:hidden"
            >
              {publicSite.secondaryCta}
            </a>
          </div>

          <div className="relative hidden overflow-hidden rounded-[32px] border border-slate-200 bg-white p-4 shadow-[0_24px_60px_-28px_rgba(15,42,91,0.35)] lg:block">
            <div className="absolute inset-x-0 top-0 h-24 bg-linear-to-r from-primary via-[#2b67be] to-[#87bbe9]" />
            <div className="relative space-y-4 rounded-[24px] bg-[#f8fbff] p-4 pt-7 md:p-5 md:pt-8">
              <div className="rounded-full border border-slate-200 bg-white px-4 py-2.5 text-center shadow-sm">
                <p className="text-[11px] font-semibold uppercase tracking-[0.24em] text-primary">
                  {publicSite.featurePanelLabel}
                </p>
              </div>
              <div className="overflow-hidden rounded-[24px] border border-slate-200 bg-white p-3">
                <img
                  src={publicSite.featurePanelImageSrc}
                  alt={publicSite.featurePanelImageAlt}
                  className="h-44 w-full object-contain md:h-56"
                />
              </div>
              <div className="rounded-[24px] bg-primary px-5 py-5 text-white">
                <p className="text-xs font-semibold uppercase tracking-[0.24em] text-blue-100">
                  {publicSite.featurePanelKicker}
                </p>
                <p className="mt-3 text-base font-semibold leading-8 md:text-lg">
                  {publicSite.featurePanelText}
                </p>
              </div>
            </div>
          </div>
        </section>

        <section className="grid gap-4 md:grid-cols-3">
          <div className="rounded-[28px] border border-slate-200 bg-white p-5 shadow-sm md:p-6">
            <div className="mb-4 flex h-12 w-12 items-center justify-center rounded-2xl bg-primary/10 text-primary">
              <Heart className="h-6 w-6" />
            </div>
            <h2 className="text-2xl font-bold text-slate-950">{publicSite.cards.supportTitle}</h2>
            <p className="mt-3 text-sm leading-7 text-slate-600">
              {publicSite.cards.supportBody}
            </p>
          </div>
          <div className="rounded-[28px] border border-slate-200 bg-white p-5 shadow-sm md:p-6">
            <div className="mb-4 flex h-12 w-12 items-center justify-center rounded-2xl bg-[#fff1ef] text-cta">
              <BarChart3 className="h-6 w-6" />
            </div>
            <h2 className="text-2xl font-bold text-slate-950">{publicSite.cards.informedTitle}</h2>
            <p className="mt-3 text-sm leading-7 text-slate-600">
              {publicSite.cards.informedBody}
            </p>
          </div>
          <div className="rounded-[28px] border border-slate-200 bg-white p-5 shadow-sm md:p-6">
            <div className="mb-4 flex h-12 w-12 items-center justify-center rounded-2xl bg-[#fff8eb] text-[#ad7a12]">
              <CalendarHeart className="h-6 w-6" />
            </div>
            <h2 className="text-2xl font-bold text-slate-950">{publicSite.cards.activityTitle}</h2>
            <p className="mt-3 text-sm leading-7 text-slate-600">
              {publicSite.cards.activityBody}
            </p>
          </div>
        </section>
      </main>

      <footer className="border-t border-slate-200 bg-white">
        <div className="mx-auto grid w-full max-w-6xl gap-8 px-4 py-8 text-sm md:grid-cols-3 md:px-6">
          <div>
            <h3 className="text-[11px] font-semibold uppercase tracking-[0.18em] text-slate-500">{publicSite.footerContactLabel}</h3>
            <a href={`mailto:${publicSite.footerContactEmail}`} className="mt-3 inline-block font-semibold text-primary hover:text-primary-dark">
              {publicSite.footerContactEmail}
            </a>
          </div>

          {(campaignInfo?.instagram_url || campaignInfo?.facebook_url) && (
            <div>
              <h3 className="text-[11px] font-semibold uppercase tracking-[0.18em] text-slate-500">Connect</h3>
              <div className="mt-3 flex flex-wrap gap-4">
                {campaignInfo?.instagram_url && (
                  <a
                    href={campaignInfo.instagram_url}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="inline-flex items-center gap-2 font-semibold text-slate-700 hover:text-primary"
                  >
                    <InstagramIcon className="h-4 w-4" />
                    Instagram
                  </a>
                )}
                {campaignInfo?.facebook_url && (
                  <a
                    href={campaignInfo.facebook_url}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="inline-flex items-center gap-2 font-semibold text-slate-700 hover:text-primary"
                  >
                    <FacebookIcon className="h-4 w-4" />
                    Facebook
                  </a>
                )}
              </div>
            </div>
          )}

          <div>
            <h3 className="text-[11px] font-semibold uppercase tracking-[0.18em] text-slate-500">{publicSite.footerMailTitle}</h3>
            <p className="mt-3 leading-6 text-slate-600">
              {publicSite.footerMailBody.split('\n').map((line, index) => (
                <span key={line}>
                  {index > 0 && <br />}
                  {line}
                </span>
              ))}
            </p>
          </div>
        </div>

        <div className="border-t border-slate-200 px-4 py-5 text-center text-[11px] text-slate-500 md:px-6">
          {publicSite.footerDisclaimer}
          <div className="mt-2">
            <Link to="/staff" className="font-semibold text-slate-400 transition hover:text-primary">
              Staff portal
            </Link>
          </div>
        </div>
      </footer>
    </div>
  );
}
