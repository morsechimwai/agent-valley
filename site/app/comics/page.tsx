import type { Metadata } from 'next';
import { Newsreader } from 'next/font/google';
import { masthead } from '@/app/fonts';
import { Reveal } from '@/components/reveal';
import { GetTheApp } from './comic-page';
import { Footer } from '@/components/sections/footer';
import { Nav } from '@/components/sections/nav';
import { AUTHOR, FEED, STRIPS } from './strips';
import './funnies.css';

// An old Sunday paper: a blackletter name (app/fonts.ts), and the rest in Newsreader, a serif drawn
// for reading news on a screen. Next keeps a copy of both with the site, so nothing loads from Google.
const news = Newsreader({ subsets: ['latin'], style: ['normal', 'italic'], variable: '--font-news' });

const PAGE = 'https://agentvalley.app/comics/';
const TITLE = 'The Valley Funnies: comics about Claude Code';
const DESCRIPTION =
  'Four-panel pixel comics about working with Claude Code: permission prompts, weekly limits, typos and sub-agents, drawn with the AgentValley crew.';

export const metadata: Metadata = {
  title: TITLE,
  description: DESCRIPTION,
  alternates: { canonical: PAGE, types: FEED },
  openGraph: {
    type: 'website',
    url: PAGE,
    title: TITLE,
    description: DESCRIPTION,
    images: [{ url: 'https://agentvalley.app/comics/funnies-og.jpg', width: 1200, height: 630 }],
  },
  twitter: { card: 'summary_large_image' },
};

// A day in words, the American way, in the Gregorian calendar: Friday, October 23, 2026.
const dayName = (d: string) =>
  new Date(`${d}T00:00:00Z`).toLocaleDateString('en-US', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric', timeZone: 'UTC' });

// The edition is the newest strip's day.
const latest = STRIPS.map((s) => s.date).sort().at(-1)!;
const edition = dayName(latest);

// The strips by the day they came out, newest first; each keeps its number. The seven of the first
// day came out together, so they print as the first edition rather than seven strips on one date.
const newestFirst = STRIPS.map((s, i) => ({ s, n: i + 1 })).reverse().map((x, i) => ({ ...x, i }));
const days = [...new Set(newestFirst.map(({ s }) => s.date))].map((date) => ({
  date,
  strips: newestFirst.filter(({ s }) => s.date === date),
}));
const WORDS = ['no', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten'];

// For search engines: a collection of the strips, in order, and where it sits on the site.
const LD = {
  '@context': 'https://schema.org',
  '@graph': [
    {
      '@type': 'CollectionPage',
      '@id': PAGE,
      url: PAGE,
      name: 'The Valley Funnies',
      description: DESCRIPTION,
      mainEntity: {
        '@type': 'ItemList',
        itemListElement: STRIPS.map((s, i) => ({ '@type': 'ListItem', position: i + 1, name: s.title, url: `${PAGE}${s.slug}/` })),
      },
    },
    {
      '@type': 'BreadcrumbList',
      itemListElement: [
        { '@type': 'ListItem', position: 1, name: 'AgentValley', item: 'https://agentvalley.app/' },
        { '@type': 'ListItem', position: 2, name: 'The Valley Funnies', item: PAGE },
      ],
    },
  ],
};

export default function Funnies() {
  return (
    <>
      <Nav sub />
      <main className="wrap pt-8 pb-24">
        <div className={`funnies ${masthead.variable} ${news.variable}`}>
          <header>
            <div className="f-top">
              <p className="f-ear"><b>Weather</b>98% of the weekly limit. Clearing Thursday.</p>
              <h1 className="f-name">The Valley Funnies</h1>
              <p className="f-ear"><b>Home delivery</b>To your notch, whenever an agent needs you.</p>
            </div>
            <p className="f-motto">Comics from a small valley of programmers in your notch.</p>
            <p className="f-date">
              <span>Vol. I, No. {STRIPS.length}</span>
              <span><time dateTime={latest}>{edition}</time></span>
              <span>Price: free</span>
            </p>
          </header>

          {/* Each day under its own dateline. A day with one strip lays it out wide, picture beside the
              words; the newest day's strips wear a NEW stamp, which moves on when the next strip comes out. */}
          {days.map(({ date, strips }) => (
            <section key={date} className="f-day" aria-labelledby={`day-${date}`}>
              <h2 id={`day-${date}`} className="f-dateline">
                <time dateTime={date}>{dayName(date)}</time>
              </h2>
              {date === STRIPS[0].date && (
                <p className="f-edition">The first edition: {WORDS[strips.length] ?? strips.length} strips</p>
              )}
              <ol className={strips.length === 1 ? 'f-strips f-one' : 'f-strips'} role="list">
                {strips.map(({ s, n, i }) => {
                  // The newest strip is on screen at once, so it stands from the start; later cards print in.
                  const card = (
                    <article className="f-card" aria-labelledby={s.slug}>
                      <p className="f-kicker">
                        No. {n} · Starring {s.starring}
                        {s.date === latest && <span className="f-new">New</span>}
                      </p>
                      <h3 id={s.slug} className="f-head">
                        <a href={`/comics/${s.slug}/`}>{s.title}</a>
                      </h3>
                      <p className="f-byline">By {AUTHOR.name}</p>
                      <img
                        className="f-strip"
                        src={`/comics/${s.slug}-1024.webp`}
                        srcSet={`/comics/${s.slug}-640.webp 640w, /comics/${s.slug}-1024.webp 1024w, /comics/${s.slug}.webp 2048w`}
                        sizes="(min-width: 1180px) 480px, (min-width: 768px) calc(50vw - 90px), calc(100vw - 66px)"
                        width={2048}
                        height={2144}
                        loading={i === 0 ? 'eager' : 'lazy'}
                        fetchPriority={i === 0 ? 'high' : undefined}
                        alt={s.alt}
                      />
                      <p className="f-deck">{s.deck}</p>
                      <p className="f-inside">{s.inside}</p>
                    </article>
                  );
                  return <li key={s.slug}>{i === 0 ? card : <Reveal>{card}</Reveal>}</li>;
                })}
              </ol>
            </section>
          ))}
        </div>
        <GetTheApp className="mx-auto mt-14 max-w-[44rem]" />
      </main>
      <Footer />
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(LD).replace(/</g, '\\u003c') }} />
    </>
  );
}
