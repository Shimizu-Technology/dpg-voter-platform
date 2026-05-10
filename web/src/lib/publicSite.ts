export type PublicSiteVariant = 'dpg';

export type PublicSiteConfig = {
  variant: PublicSiteVariant;
  topBar: string;
  wordmark: {
    mode: 'text' | 'image';
    title: string;
    titleSecondary?: string;
    subtitle: string;
    amp?: string;
    imageSrc?: string;
    imageSrcSet?: string;
    imageAlt?: string;
    iconSrc?: string;
    iconSrcSet?: string;
  };
  officialInfoUrl: string;
  officialInfoLabel: string;
  heroEyebrow: string;
  heroTitleMobile: string;
  heroTitleDesktop: string;
  heroLeadMobile: string;
  heroSupportTextMobile: string;
  heroLeadDesktop: string;
  primaryCta: string;
  secondaryCta: string;
  featurePanelLabel: string;
  featurePanelImageSrc: string;
  featurePanelImageSrcSet?: string;
  featurePanelImageAlt: string;
  featurePanelKicker: string;
  featurePanelText: string;
  signupHeroKicker: string;
  signupHeroTitle: string;
  signupHeroDescription: string;
  signupNetworkTitle: string;
  signupNetworkImageSrc: string;
  signupNetworkImageSrcSet?: string;
  signupNetworkImageAlt: string;
  signupMobileDescription: string;
  consentName: string;
  thankYouTitle: string;
  thankYouSubtitle: string;
  thankYouBody: string;
  thankYouImageSrc?: string;
  thankYouImageSrcSet?: string;
  thankYouImageAlt?: string;
  followLabel: string;
  footerContactEmail: string;
  footerContactLabel: string;
  footerMailTitle: string;
  footerMailBody: string;
  footerDisclaimer: string;
  appTitle: string;
  metaDescription: string;
  cards: {
    supportTitle: string;
    supportBody: string;
    informedTitle: string;
    informedBody: string;
    activityTitle: string;
    activityBody: string;
  };
  signupSteps: {
    recordTitle: string;
    recordBody: string;
    helpTitle: string;
    helpBody: string;
    householdTitle: string;
    householdBody: string;
  };
  thankYouNextStepTitle: string;
  thankYouNextStepBody: string;
};


export const publicSiteConfig: PublicSiteConfig = {
  variant: 'dpg',
  topBar: 'Democratic Party of Guam',
  wordmark: {
    mode: 'image',
    title: 'Democratic Party of Guam',
    subtitle: 'Voter Engagement Platform',
    imageSrc: '/brand/dpg-wordmark-900.png',
    imageSrcSet: '/brand/dpg-wordmark-600.png 600w, /brand/dpg-wordmark-900.png 900w',
    imageAlt: 'Guam Democratic Party wordmark',
    iconSrc: '/brand/dpg-mark-384.png',
    iconSrcSet: '/brand/dpg-mark-192.png 192w, /brand/dpg-mark-384.png 384w',
  },
  officialInfoUrl: 'https://democraticpartyofguam.org',
  officialInfoLabel: 'Main party website',
  heroEyebrow: 'Official Democratic Party of Guam signup',
  heroTitleMobile: 'Connect with the Democratic Party of Guam.',
  heroTitleDesktop: 'Connect with the Democratic Party of Guam.',
  heroLeadMobile: 'Sign up, stay informed, and help the party organize across Guam.',
  heroSupportTextMobile: 'Your response helps the party understand community needs, outreach, and voter engagement across the island.',
  heroLeadDesktop: 'Sign up, stay informed, and help the Democratic Party of Guam organize voter engagement, outreach, and election operations across the island.',
  primaryCta: 'Sign up with the party',
  secondaryCta: 'Visit the main website',
  featurePanelLabel: 'Democratic Party voter engagement',
  featurePanelImageSrc: '/brand/dpg-wordmark-900.png',
  featurePanelImageSrcSet: '/brand/dpg-wordmark-600.png 600w, /brand/dpg-wordmark-900.png 900w',
  featurePanelImageAlt: 'Guam Democratic Party wordmark',
  featurePanelKicker: 'Island-wide voter engagement',
  featurePanelText: 'Every signup helps the party stay connected, support voters, and coordinate outreach ahead of election season.',
  signupHeroKicker: 'Democratic Party of Guam',
  signupHeroTitle: 'Sign up to stay connected.',
  signupHeroDescription: 'Add your information, share any voter-help needs, and help the Democratic Party of Guam coordinate outreach across the island.',
  signupNetworkTitle: 'Join the voter engagement network',
  signupNetworkImageSrc: '/brand/dpg-mark-384.png',
  signupNetworkImageSrcSet: '/brand/dpg-mark-192.png 192w, /brand/dpg-mark-384.png 384w',
  signupNetworkImageAlt: 'Democratic Party of Guam circular mark',
  signupMobileDescription: 'Add your information below to stay connected with the Democratic Party of Guam and share any voter-help needs.',
  consentName: 'Democratic Party of Guam',
  thankYouTitle: "Si Yu'os Ma'åse!",
  thankYouSubtitle: 'Thank you for connecting with the Democratic Party of Guam.',
  thankYouBody: 'Your signup helps the party understand support, voter needs, and outreach opportunities across Guam.',
  thankYouImageSrc: '/brand/dpg-mark-384.png',
  thankYouImageSrcSet: '/brand/dpg-mark-192.png 192w, /brand/dpg-mark-384.png 384w',
  thankYouImageAlt: 'Democratic Party of Guam circular mark',
  followLabel: 'Follow the party',
  footerContactEmail: 'info@democraticpartyofguam.org',
  footerContactLabel: 'Get in touch',
  footerMailTitle: 'Main website',
  footerMailBody: 'democraticpartyofguam.org',
  footerDisclaimer: 'Democratic Party of Guam · Voter Engagement & Election Operations Platform',
  appTitle: 'Democratic Party of Guam | Voter Engagement Signup',
  metaDescription: 'Connect with the Democratic Party of Guam for voter information, outreach, events, and election updates.',
  cards: {
    supportTitle: 'Connect with the party',
    supportBody: 'Add your information in a few moments and help the party understand where community engagement is growing.',
    informedTitle: 'Stay informed',
    informedBody: 'Receive party updates, announcements, voter education, and other key moments as election season moves forward.',
    activityTitle: 'Support voter outreach',
    activityBody: 'Raise your hand for events, voter assistance, and outreach efforts that help the party organize across Guam.',
  },
  signupSteps: {
    recordTitle: 'The party records your response',
    recordBody: 'Your information helps the Democratic Party of Guam understand community engagement across the island.',
    helpTitle: 'The party can follow up on voter help',
    helpBody: 'If you ask for voter-registration, absentee, homebound, or ride assistance, the team can route that request for follow-up.',
    householdTitle: 'This form supports households too',
    householdBody: 'You can add other people in the same household so they become separate records without making staff retype shared address and contact details later.',
  },
  thankYouNextStepTitle: 'Next step',
  thankYouNextStepBody: 'If you opted in for updates, the party may reach out with announcements, voter education, volunteer opportunities, and event information.',
};
