import { ArrowUpRight, CirclePause, Mail } from 'lucide-react';
import { publicSiteConfig } from '../lib/publicSite';

export default function PlatformPausedPage() {
  return (
    <main className="relative min-h-screen overflow-hidden bg-[#f3efe5] text-[#172238]">
      <div aria-hidden="true" className="absolute inset-0 opacity-60 [background-image:linear-gradient(to_right,rgba(27,58,107,0.045)_1px,transparent_1px),linear-gradient(to_bottom,rgba(27,58,107,0.045)_1px,transparent_1px)] [background-size:32px_32px]" />
      <div aria-hidden="true" className="absolute top-0 right-0 h-64 w-64 translate-x-1/3 -translate-y-1/3 rounded-full border-[48px] border-[#c5a55a]/12 sm:h-96 sm:w-96 sm:border-[72px]" />

      <div className="relative mx-auto flex min-h-screen max-w-7xl flex-col px-5 py-6 sm:px-8 sm:py-8 lg:px-12">
        <header className="flex items-center justify-between border-b border-[#cfc5b1] pb-5 sm:pb-6">
          <img
            src={publicSiteConfig.wordmark.imageSrc}
            srcSet={publicSiteConfig.wordmark.imageSrcSet}
            sizes="(max-width: 640px) 210px, 300px"
            alt={publicSiteConfig.wordmark.imageAlt}
            className="h-auto w-[210px] sm:w-[300px]"
          />
          <span className="hidden text-xs font-bold tracking-[0.2em] text-[#766c5b] uppercase sm:block">
            Voter Engagement Platform
          </span>
        </header>

        <div className="grid flex-1 items-center gap-12 py-12 sm:py-16 lg:grid-cols-12 lg:gap-16 lg:py-20">
          <section className="lg:col-span-7">
            <div className="mb-8 inline-flex items-center gap-3 border-y border-[#b9aa8c] py-3 text-xs font-bold tracking-[0.18em] text-[#6e5a1e] uppercase">
              <CirclePause aria-hidden="true" className="h-4 w-4" />
              Platform paused
            </div>
            <h1 className="max-w-4xl text-[clamp(2.7rem,8vw,5.8rem)] leading-[0.98] font-extrabold tracking-[-0.055em] text-[#0f2a5b]">
              The voter engagement platform is currently paused.
            </h1>
            <p className="mt-8 max-w-2xl text-lg leading-8 text-[#46536a] sm:text-xl sm:leading-9">
              Platform access and online signup are paused while the Democratic Party of Guam coordinates its next operating period.
            </p>

            <div className="mt-10 flex flex-col gap-3 sm:flex-row">
              <a
                href={publicSiteConfig.officialInfoUrl}
                className="group inline-flex min-h-12 items-center justify-center gap-2 rounded-full bg-[#1b3a6b] px-6 py-3 text-sm font-bold text-white shadow-[0_16px_36px_-18px_rgba(15,42,91,0.9)] hover:-translate-y-0.5 hover:bg-[#0f2a5b] focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-[#1b3a6b] motion-reduce:transform-none"
              >
                Visit the main party website
                <ArrowUpRight aria-hidden="true" className="h-4 w-4 transition-transform duration-200 group-hover:translate-x-0.5 group-hover:-translate-y-0.5 motion-reduce:transform-none" />
              </a>
              <a
                href={`mailto:${publicSiteConfig.footerContactEmail}`}
                className="inline-flex min-h-12 items-center justify-center gap-2 rounded-full border border-[#aa9c82] bg-[#f8f5ed]/70 px-6 py-3 text-sm font-bold text-[#1b3a6b] hover:border-[#1b3a6b] hover:bg-[#fbfaf6] focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-[#1b3a6b]"
              >
                <Mail aria-hidden="true" className="h-4 w-4" />
                Contact DPG
              </a>
            </div>
          </section>

          <aside className="relative border-l-2 border-[#c5a55a] pl-7 sm:pl-9 lg:col-span-4 lg:col-start-9">
            <img
              src={publicSiteConfig.wordmark.iconSrc}
              srcSet={publicSiteConfig.wordmark.iconSrcSet}
              sizes="112px"
              alt=""
              aria-hidden="true"
              className="mb-8 h-24 w-24 object-contain opacity-95 sm:h-28 sm:w-28"
            />
            <p className="text-xs font-bold tracking-[0.2em] text-[#766c5b] uppercase">Current status</p>
            <p className="mt-4 text-xl leading-8 font-semibold text-[#0f2a5b]">
              The platform is not accepting new signups or staff activity at this time.
            </p>
            <p className="mt-5 text-base leading-7 text-[#596276]">
              Existing platform records are being retained while the service is paused. The main DPG website remains available for current party information and contact details.
            </p>
          </aside>
        </div>

        <footer className="flex flex-col gap-2 border-t border-[#cfc5b1] pt-5 text-xs leading-5 text-[#6f685d] sm:flex-row sm:items-center sm:justify-between">
          <span>Democratic Party of Guam</span>
          <span>Voter Engagement Platform</span>
        </footer>
      </div>
    </main>
  );
}
