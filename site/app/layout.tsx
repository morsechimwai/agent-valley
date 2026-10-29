import type { Metadata } from 'next';
import { GeistMono } from 'geist/font/mono';
import { GeistSans } from 'geist/font/sans';
import { Caveat } from 'next/font/google';
import { Announcer } from '@/components/announcer';
import { HalloweenTouches } from '@/components/halloween-touches';
import { IconSprite } from '@/components/icons';
import { SmoothScroll } from '@/components/smooth-scroll';
import './globals.css';
import { CSP } from '@/lib/csp';
import { isHalloween } from '@/lib/halloween';
import { FEED } from './comics/strips';

// The hand the row's notes are written in; Next keeps a copy with the site, so nothing loads from Google.
const hand = Caveat({ subsets: ['latin'], weight: '600', variable: '--font-hand' });

const TITLE = 'AgentValley — Every Claude Code agent in your notch';
const DESCRIPTION =
  'A free, open-source Mac app that shows every Claude Code agent, sub-agents too, in your notch. See who is working, on which model, and who needs you.';

export const metadata: Metadata = {
  metadataBase: new URL('https://agentvalley.app'),
  title: TITLE,
  description: DESCRIPTION,
  alternates: { canonical: 'https://agentvalley.app/', types: FEED },
  // Search engines may show the pictures large, and the snippets as long as they like.
  robots: { index: true, follow: true, 'max-image-preview': 'large', 'max-snippet': -1 },
  openGraph: {
    type: 'website',
    url: 'https://agentvalley.app/',
    title: TITLE,
    description: DESCRIPTION,
    images: ['https://agentvalley.app/og.png'],
  },
  twitter: { card: 'summary_large_image' },
  icons: {
    icon: [
      { url: '/favicon.ico', sizes: '32x32' },
      { url: '/mark.svg', type: 'image/svg+xml' },
    ],
    apple: '/apple-touch-icon.png',
  },
};

// For search engines: what this page is about, in their own terms.
const SOFTWARE = {
  '@context': 'https://schema.org',
  '@type': 'SoftwareApplication',
  name: 'AgentValley',
  description: DESCRIPTION,
  url: 'https://agentvalley.app/',
  image: 'https://agentvalley.app/og.png',
  applicationCategory: 'DeveloperApplication',
  operatingSystem: 'macOS 15 or later',
  offers: { '@type': 'Offer', price: '0', priceCurrency: 'USD' },
  license: 'https://opensource.org/licenses/MIT',
  author: { '@type': 'Person', name: 'morsechimwai', url: 'https://github.com/morsechimwai' },
  sameAs: ['https://github.com/morsechimwai/agent-valley'],
};

// The site's own name, for the name search engines put above its results.
const WEBSITE = { '@context': 'https://schema.org', '@type': 'WebSite', name: 'AgentValley', url: 'https://agentvalley.app/' };

// Before the first paint: js marks that scripts run, so a picture may wait to come up; a stop
// chosen on an earlier visit holds from the start, not a moment later. If React has not arrived
// 3 s later (a bundle blocked, failed or too slow), js goes again and the page stands as it does
// without scripts. Then Halloween (lib/halloween.ts): on by the visitor's date, or by ?halloween,
// which this browser remembers until ?halloween=0 or the end of Halloween (2 November 2026).
const EARLY =
  "var d=document.documentElement;d.classList.add('js');setTimeout(function(){d.hasAttribute('data-live')||d.classList.remove('js')},3000);try{localStorage.getItem('still')==='1'&&d.classList.add('still')}catch(e){}" +
  `;var q=new URLSearchParams(location.search).get('halloween'),f=q!==null&&q!=='0';try{q==='0'?localStorage.removeItem('halloween'):f?localStorage.setItem('halloween','1'):f=localStorage.getItem('halloween')==='1'&&new Date()<new Date(2026,10,2)}catch(e){};(f||(${isHalloween.toString()})(new Date()))&&d.classList.add('halloween');try{JSON.parse(localStorage.getItem('pumpkins')||'[]').length===5&&(d.dataset.pumpkins='all')}catch(e){}`;

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    // The early script changes <html>'s classes before React arrives; that difference is expected.
    <html lang="en" data-scroll-behavior="smooth" className={`${GeistSans.variable} ${GeistMono.variable} ${hand.variable}`} suppressHydrationWarning>
      <head>
        <meta httpEquiv="Content-Security-Policy" content={CSP} />
        <script dangerouslySetInnerHTML={{ __html: EARLY }} />
        <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(SOFTWARE) }} />
        <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(WEBSITE) }} />
      </head>
      <body>
        <IconSprite />
        {children}
        <Announcer />
        <HalloweenTouches />
        <SmoothScroll />
      </body>
    </html>
  );
}
