import type { Metadata } from 'next';
import { Footer } from '@/components/sections/footer';
import { Nav } from '@/components/sections/nav';

const PAGE = 'https://agentvalley.app/privacy/';
const TITLE = 'Privacy · AgentValley';
const DESCRIPTION =
  'What AgentValley and agentvalley.app collect: the app sends one anonymous count a day, the site counts visits without cookies, your email is used only for release news, and a review keeps the name you put on it.';

export const metadata: Metadata = {
  title: TITLE,
  description: DESCRIPTION,
  alternates: { canonical: PAGE },
  openGraph: { type: 'website', url: PAGE, title: TITLE, description: DESCRIPTION },
};

const MAIL = 'morse@agentvalley.app';

// Every fact here is checked against the code: the app (Sources/, build-app.sh), the site's
// analytics (lib/analytics.ts, vercel.json) and the mailing list (api/subscribe.py). Change one,
// change the other, and the date.
export default function Privacy() {
  return (
    <>
      <Nav sub />
      <main className="wrap py-24">
        <article className="grid max-w-[68ch] gap-12 [&_h2]:mb-4 [&_li]:mt-2 [&_p+p]:mt-4 [&_ul]:list-disc [&_ul]:pl-5">
          <header className="grid gap-4">
            <h1>Privacy</h1>
            <p className="lead">The app sends us one anonymous count a day, and you can turn it off. The website counts visits without cookies, keeps your email only if you ask for news, and keeps a review with the name you put on it.</p>
            <p className="font-mono text-sm text-muted-foreground">Last changed October 29, 2026</p>
          </header>

          <section>
            <p>
              AgentValley is made by Morse Chimwai. &ldquo;We&rdquo; on this page means him. Questions, or anything you want
              changed or deleted: <a href={`mailto:${MAIL}`}>{MAIL}</a>.
            </p>
          </section>

          <section>
            <h2>The Mac app</h2>
            <p>
              AgentValley has no account and no crash reports, and it doesn&apos;t record what you do in it. It reads the
              files Claude Code writes in ~/.claude to show your sessions and count tokens. What it keeps, like your
              History, stays on your Mac in ~/Library/Application Support/AgentValley.
            </p>
            <p>It talks to the internet in four places:</p>
            <ul>
              <li>
                A daily count, so we know how many Macs run the app. Once a day it tells us it ran: the app version, the
                macOS version, and whether this is the Mac&apos;s first count. Nothing else: no name, no ID that ties one
                day to the next, nothing about your sessions, projects or code. It goes through agentvalley.app to
                PostHog, which works out the country from your IP address and then drops the address. Once, the panel
                also asks where you heard about us, and if you skip, once more a week later. The same way then sends your
                answer, or that you skipped, with the app version, one time. You can turn it all off in Settings, About.
              </li>
              <li>
                A rating, if you give one. A week after that question the panel asks for one to five stars. The stars you
                press go the same way as the daily count, with the app version, and the same switch turns them off.
              </li>
              <li>
                Plan limits, only if you turn it on. The app reads your Claude Code login from the Keychain and sends it to
                api.anthropic.com to ask how much of your plan is left. The login is not stored or sent anywhere else.
              </li>
              <li>
                Updates. Once an hour the app downloads the list of versions from GitHub. GitHub sees your IP address, as it
                does for any download. No details about your Mac are sent. You can turn this off in Settings, About.
              </li>
              <li>
                Report a bug and Sponsor the crew open GitHub in your browser. The bug form comes filled in with the app
                version, macOS version and Mac model, and nothing is sent until you submit it there yourself.
              </li>
            </ul>
          </section>

          <section>
            <h2>This website</h2>
            <p>
              agentvalley.app is hosted on Vercel. Like any web host, Vercel sees your IP address and browser when a page
              loads, and keeps short-lived logs. Its firewall also uses your IP address to stop anyone sending too many
              sign-ups at once.
            </p>
            <p>
              We count visits with PostHog: which pages you open, which links and buttons you click, how far you scroll, and
              the country worked out from your IP address. PostHog then drops the IP address. There are no cookies, nothing
              is saved in your browser, and nothing is recorded. The data goes through this site to PostHog&apos;s servers in
              the United States. A blocker that stops PostHog won&apos;t break anything here.
            </p>
            <p>
              The Product Hunt badge on the home page is loaded from Product Hunt, so they see your IP address too.
              Everything else, fonts and videos included, comes from this site.
            </p>
          </section>

          <section>
            <h2>Reviews</h2>
            <p>
              After a star press the app offers &ldquo;Write a few words&rdquo;, which opens the review page here. If you send
              one, we get your stars, your words and whether you ticked the box that lets us show it. Only if you ticked it,
              we also get your name and your GitHub or X name if you gave it. It goes through agentvalley.app to PostHog. We put a review on the site only if you ticked
              that box, and only the ones we pick. To have one taken down or deleted, write to{' '}
              <a href="mailto:hello@agentvalley.app">hello@agentvalley.app</a>.
            </p>
          </section>

          <section>
            <h2>Email</h2>
            <p>
              When you type your email under Get updates, we send one mail with a link through Resend. Your address goes on
              the list only after you open that link and press the button. If you never do, we don&apos;t write again.
            </p>
            <p>
              The list lives in Resend and is used for one thing: telling you when a new version is out. Every one of those
              mails has an unsubscribe link. We don&apos;t sell or share the list, and there are no ads anywhere.
            </p>
            <p>
              Mail you send to an @agentvalley.app address is passed on by Cloudflare to our Gmail inbox and kept there like
              any other email.
            </p>
          </section>

          <section>
            <h2>Who else handles it</h2>
            <p>
              Vercel hosts the site, PostHog counts the visits and the app&apos;s daily count, Resend sends the mail and holds the list, Cloudflare runs the
              domain and forwards mail to Gmail, and GitHub hosts the code, the downloads, bug reports and sponsorships. Each
              of them has its own privacy policy. Nobody else gets anything.
            </p>
          </section>

          <section>
            <h2>Your say</h2>
            <p>
              Write to <a href={`mailto:${MAIL}`}>{MAIL}</a> to find out what we hold about you, or to have it fixed or
              deleted. We answer within 30 days. To leave the mailing list, the unsubscribe link in any mail does it at once.
            </p>
            <p>
              If this page changes, the date at the top changes with it. The site is open source, so every past version is
              on <a href="https://github.com/morsechimwai/agent-valley/commits/main/site/app/privacy/page.tsx">GitHub</a>.
            </p>
          </section>
        </article>
      </main>
      <Footer />
    </>
  );
}
