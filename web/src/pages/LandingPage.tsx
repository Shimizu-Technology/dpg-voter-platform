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
    <div className="min-h-screen overflow-hidden bg-[#f7fbfc] text-slate-900">
      <div className="relative bg-[#123d70] px-4 py-3 text-center text-[10px] font-bold uppercase leading-5 tracking-[0.2em] text-white shadow-sm sm:text-[11px] sm:tracking-[0.28em]">
        <div className="absolute inset-0 bg-[linear-gradient(90deg,rgba(255,255,255,0.08),transparent,rgba(128,199,232,0.22))]" />
        <span className="relative">{publicSite.topBar}</span>
      </div>

      <header className="relative border-b border-[#dce8ef] bg-white/90 backdrop-blur-xl">
        <div className="absolute inset-x-0 bottom-0 h-px bg-linear-to-r from-transparent via-[#83c8e8] to-transparent" />
        <div className="mx-auto flex w-full max-w-6xl items-center justify-between gap-4 px-4 py-4 md:px-6">
          <Link to="/" className="min-w-0">
            <PublicWordmark size="sm" />
          </Link>
          <a
            href={publicSite.officialInfoUrl}
            target="_blank"
            rel="noopener noreferrer"
            className="hidden min-h-[44px] shrink-0 items-center justify-center rounded-full border border-[#cfe0e8] bg-white/80 px-4 text-sm font-bold text-[#123d70] shadow-sm transition hover:-translate-y-0.5 hover:border-[#83c8e8] hover:bg-[#f2fbff] sm:inline-flex md:px-5"
          >
            {publicSite.officialInfoLabel}
          </a>
        </div>
      </header>

      <main className="relative">
        <div className="absolute inset-0 -z-10 bg-[radial-gradient(circle_at_10%_10%,rgba(131,200,232,0.32),transparent_28%),radial-gradient(circle_at_88%_4%,rgba(213,163,50,0.18),transparent_30%),linear-gradient(180deg,#f7fbfc_0%,#eef6fb_52%,#ffffff_100%)]" />
        <div className="mx-auto flex w-full max-w-6xl flex-col gap-8 overflow-hidden px-4 py-8 md:gap-12 md:px-6 md:py-14">
          <section className="grid min-w-0 gap-8 lg:grid-cols-[1.02fr_0.98fr] lg:items-center">
            <div className="max-w-[calc(100vw-2rem)] space-y-6 md:max-w-none">
              <div className="inline-flex max-w-full rounded-full border border-[#d8ecf4] bg-white/80 px-4 py-2 text-center text-[11px] font-bold uppercase leading-5 tracking-[0.16em] text-[#123d70] shadow-sm md:text-sm">
                {publicSite.heroEyebrow}
              </div>

              <div className="space-y-4">
                <h1 className="max-w-3xl text-balance text-[2.45rem] leading-[0.96] font-black tracking-[-0.045em] text-[#071326] sm:text-[3rem] md:text-6xl">
                  <span className="md:hidden">{publicSite.heroTitleMobile}</span>
                  <span className="hidden md:inline">{publicSite.heroTitleDesktop}</span>
                </h1>
                <div className="max-w-2xl space-y-3">
                  <p className="text-lg leading-8 text-slate-600 md:hidden">
                    {publicSite.heroLeadMobile}
                  </p>
                  <p className="text-sm leading-6 text-slate-500 md:hidden">
                    {publicSite.heroSupportTextMobile}
                  </p>
                  <p className="hidden text-xl leading-9 text-slate-600 md:block">
                    {publicSite.heroLeadDesktop}
                  </p>
                </div>
              </div>

              <div className="flex flex-col gap-3 pt-1 sm:flex-row">
                <Link
                  to="/signup"
                  className="inline-flex min-h-[54px] w-full items-center justify-center gap-2 rounded-full bg-[#ce243c] px-7 text-base font-black text-white shadow-xl shadow-[#ce243c]/20 transition hover:-translate-y-0.5 hover:bg-[#aa1b30] sm:w-auto"
                >
                  {publicSite.primaryCta}
                  <ArrowRight className="h-5 w-5" />
                </Link>
                <a
                  href={publicSite.officialInfoUrl}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex min-h-[54px] items-center justify-center rounded-full border border-[#cfe0e8] bg-white px-7 text-base font-bold text-[#123d70] shadow-sm transition hover:-translate-y-0.5 hover:border-[#83c8e8] hover:bg-[#f4fbff]"
                >
                  {publicSite.secondaryCta}
                </a>
              </div>
            </div>

            <div className="relative hidden lg:block">
              <div className="absolute -left-4 top-8 hidden h-24 w-24 rounded-full bg-[#83c8e8]/30 blur-2xl md:block" />
              <div className="absolute -right-3 bottom-5 hidden h-32 w-32 rounded-full bg-[#d5a332]/20 blur-2xl md:block" />
              <div className="relative overflow-hidden rounded-[34px] border border-white bg-white/86 p-5 shadow-[0_28px_80px_-42px_rgba(18,61,112,0.7)] backdrop-blur">
                <div className="rounded-[28px] bg-[linear-gradient(135deg,#123d70_0%,#2468ad_58%,#84c7e8_100%)] p-5 text-white">
                  <p className="text-[11px] font-bold uppercase tracking-[0.28em] text-white/75">
                    {publicSite.featurePanelLabel}
                  </p>
                  <div className="mt-5 rounded-[24px] bg-white/95 p-5 shadow-inner shadow-[#123d70]/10">
                    <img
                      src={publicSite.featurePanelImageSrc}
                      srcSet={publicSite.featurePanelImageSrcSet}
                      sizes="(min-width: 1024px) 430px, 100vw"
                      alt={publicSite.featurePanelImageAlt}
                      className="mx-auto h-36 w-full object-contain md:h-44"
                    />
                  </div>
                  <div className="mt-5 grid gap-3 sm:grid-cols-3">
                    <div className="rounded-2xl bg-white/12 p-4 backdrop-blur">
                      <p className="text-2xl font-black">19</p>
                      <p className="mt-1 text-xs font-semibold leading-5 text-white/78">villages connected</p>
                    </div>
                    <div className="rounded-2xl bg-white/12 p-4 backdrop-blur">
                      <p className="text-2xl font-black">1</p>
                      <p className="mt-1 text-xs font-semibold leading-5 text-white/78">island-wide party hub</p>
                    </div>
                    <div className="rounded-2xl bg-white/12 p-4 backdrop-blur">
                      <p className="text-2xl font-black">24/7</p>
                      <p className="mt-1 text-xs font-semibold leading-5 text-white/78">online signup access</p>
                    </div>
                  </div>
                </div>
                <div className="mt-4 rounded-[26px] border border-[#dce8ef] bg-[#f7fbfc] p-5">
                  <p className="text-xs font-bold uppercase tracking-[0.24em] text-[#b17812]">
                    {publicSite.featurePanelKicker}
                  </p>
                  <p className="mt-3 text-base font-semibold leading-8 text-slate-700 md:text-lg">
                    {publicSite.featurePanelText}
                  </p>
                </div>
              </div>
            </div>
          </section>

          <section className="grid gap-4 md:grid-cols-3">
            <div className="rounded-[30px] border border-[#dce8ef] bg-white/90 p-6 shadow-[0_18px_50px_-36px_rgba(18,61,112,0.55)]">
              <div className="mb-5 flex h-12 w-12 items-center justify-center rounded-full bg-[#e8f7fc] text-[#123d70]">
                <Heart className="h-6 w-6" />
              </div>
              <h2 className="text-2xl font-black tracking-[-0.03em] text-[#071326]">{publicSite.cards.supportTitle}</h2>
              <p className="mt-3 text-sm leading-7 text-slate-600">
                {publicSite.cards.supportBody}
              </p>
            </div>
            <div className="rounded-[30px] border border-[#dce8ef] bg-white/90 p-6 shadow-[0_18px_50px_-36px_rgba(18,61,112,0.55)]">
              <div className="mb-5 flex h-12 w-12 items-center justify-center rounded-full bg-[#fff1ef] text-[#ce243c]">
                <BarChart3 className="h-6 w-6" />
              </div>
              <h2 className="text-2xl font-black tracking-[-0.03em] text-[#071326]">{publicSite.cards.informedTitle}</h2>
              <p className="mt-3 text-sm leading-7 text-slate-600">
                {publicSite.cards.informedBody}
              </p>
            </div>
            <div className="rounded-[30px] border border-[#dce8ef] bg-white/90 p-6 shadow-[0_18px_50px_-36px_rgba(18,61,112,0.55)]">
              <div className="mb-5 flex h-12 w-12 items-center justify-center rounded-full bg-[#fff8e7] text-[#b17812]">
                <CalendarHeart className="h-6 w-6" />
              </div>
              <h2 className="text-2xl font-black tracking-[-0.03em] text-[#071326]">{publicSite.cards.activityTitle}</h2>
              <p className="mt-3 text-sm leading-7 text-slate-600">
                {publicSite.cards.activityBody}
              </p>
            </div>
          </section>
        </div>
      </main>

      <footer className="border-t border-[#dce8ef] bg-white">
        <div className="mx-auto grid w-full max-w-6xl gap-8 px-4 py-8 text-sm md:grid-cols-3 md:px-6">
          <div>
            <h3 className="text-[11px] font-bold uppercase tracking-[0.18em] text-slate-500">{publicSite.footerContactLabel}</h3>
            <a href={`mailto:${publicSite.footerContactEmail}`} className="mt-3 inline-block font-bold text-[#123d70] hover:text-[#2468ad]">
              {publicSite.footerContactEmail}
            </a>
          </div>

          {(campaignInfo?.instagram_url || campaignInfo?.facebook_url) && (
            <div>
              <h3 className="text-[11px] font-bold uppercase tracking-[0.18em] text-slate-500">Connect</h3>
              <div className="mt-3 flex flex-wrap gap-4">
                {campaignInfo?.instagram_url && (
                  <a href={campaignInfo.instagram_url} target="_blank" rel="noopener noreferrer" className="inline-flex items-center gap-2 font-bold text-slate-700 hover:text-[#123d70]">
                    <InstagramIcon className="h-4 w-4" />
                    Instagram
                  </a>
                )}
                {campaignInfo?.facebook_url && (
                  <a href={campaignInfo.facebook_url} target="_blank" rel="noopener noreferrer" className="inline-flex items-center gap-2 font-bold text-slate-700 hover:text-[#123d70]">
                    <FacebookIcon className="h-4 w-4" />
                    Facebook
                  </a>
                )}
              </div>
            </div>
          )}

          <div>
            <h3 className="text-[11px] font-bold uppercase tracking-[0.18em] text-slate-500">{publicSite.footerMailTitle}</h3>
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

        <div className="border-t border-[#dce8ef] px-4 py-5 text-center text-[11px] text-slate-500 md:px-6">
          {publicSite.footerDisclaimer}
          <div className="mt-2">
            <Link to="/staff" className="font-bold text-slate-400 transition hover:text-[#123d70]">
              Staff portal
            </Link>
          </div>
        </div>
      </footer>
    </div>
  );
}
