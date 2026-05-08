import { useEffect } from 'react';
import { publicSiteConfig } from '../lib/publicSite';

function setMeta(selector: string, value: string) {
  const element = document.head.querySelector<HTMLMetaElement>(selector);
  if (element) element.content = value;
}

export default function PublicHeadManager() {
  useEffect(() => {
    document.title = publicSiteConfig.appTitle;
    setMeta('meta[name="title"]', publicSiteConfig.appTitle);
    setMeta('meta[name="description"]', publicSiteConfig.metaDescription);
    setMeta('meta[property="og:title"]', publicSiteConfig.appTitle);
    setMeta('meta[property="og:description"]', publicSiteConfig.metaDescription);
    setMeta('meta[property="og:site_name"]', publicSiteConfig.wordmark.title);
    setMeta('meta[property="twitter:title"]', publicSiteConfig.appTitle);
    setMeta('meta[property="twitter:description"]', publicSiteConfig.metaDescription);
    setMeta('meta[name="apple-mobile-web-app-title"]', publicSiteConfig.wordmark.title);
  }, []);

  return null;
}
