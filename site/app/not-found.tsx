import type { Metadata } from 'next';
import { Footer } from '@/components/sections/footer';
import { Nav } from '@/components/sections/nav';

// A link that leads nowhere, all year, kept out of search engines: the site's own robots line
// says index, so this page says otherwise.
export const metadata: Metadata = {
  title: 'Page not found · AgentValley',
  robots: { index: false, follow: true },
};

const BACK = 'inline-flex min-h-11 items-center font-mono';

// Words beside a cut-out picture of the crew, standing on the page with no backdrop; on a phone
// the picture comes first. The tag sits above it, where it covers nothing.
function Lost({ title, lead, art, alt }: { title: string; lead: string; art: string; alt: string }) {
  return (
    <div className={`grid items-center gap-8 md:grid-cols-[2fr_3fr] md:gap-12`}>
      <div className="grid justify-items-start gap-4">
        <h1>{title}</h1>
        <p className="lead">{lead}</p>
        <a className={BACK} href="/">Back to the valley</a>
      </div>
      <figure className="-order-1 m-0 md:order-none">
        <span className="tool-tag">Explore · 404 tool uses</span>
        <img
          className="block h-auto w-full"
          src={`/${art}.webp`}
          srcSet={`/${art}-640.webp 640w, /${art}-1024.webp 1024w, /${art}.webp 2048w`}
          sizes="(min-width: 1180px) 640px, (min-width: 768px) 56vw, calc(100vw - 32px)"
          width={2048}
          height={1536}
          // Lazy, or React preloads it on every page of the site.
          loading="lazy"
          alt={alt}
        />
      </figure>
    </div>
  );
}

// Faye at the filing cabinet.
export default function NotFound() {
  return (
    <>
      <Nav sub />
      <main className="wrap grid min-h-[60vh] content-center py-24">
        <Lost
          title="Faye looked everywhere."
          lead="Every folder, twice. No page by that name."
          art="faye-404"
          alt="Faye, the Explore agent, stands by the file shelves of the computer room holding an open folder, sand still on her jeans from the search."
        />
      </main>
      <Footer />
    </>
  );
}
