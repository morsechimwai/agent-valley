import { CopyCommand } from '@/components/copy-command';
import { HeroScreen } from '@/components/hero-screen';
import { Clock } from '@/components/clock';
import { Icon } from '@/components/icons';
import { Mascot } from '@/components/mascot';
import { Button } from '@/components/ui/button';
import { TrickOrTreat } from '@/components/trick-or-treat';
import { Word } from '@/components/word';

// Product Hunt's #4 of the day badge (24 Oct 2026), their embed code as they give it, image from
// their server (vercel.json lets it in). At the top of the hero, over both columns, so the picture
// still stands level with the heading. Pixel sparkles take turns around it and a gleam crosses it now and then.
function PhBadge() {
  return (
    <a className="ph min-[900px]:[grid-area:badge]" href="https://www.producthunt.com/products/agentvalley?embed=true&utm_source=badge-top-post-badge&utm_medium=badge&utm_campaign=badge-agentvalley" target="_blank" rel="noopener noreferrer">
      <img src="https://api.producthunt.com/widgets/embed-image/v1/top-post-badge.svg?post_id=1286641&theme=light&period=daily" alt="AgentValley - Every Claude Code agent, at a glance, in your Mac's notch | Product Hunt" style={{ width: 250, height: 54 }} width="250" height="54" />
      {['s1', 's2', 's3', 's4'].map((s) => (
        <svg key={s} className={`spark ${s}`} viewBox="0 0 7 7" aria-hidden="true">
          <path d="M3 0h1v7H3zM0 3h7v1H0zM2 2h3v3H2z" />
        </svg>
      ))}
    </a>
  );
}

export function Hero() {
  return (
    <section className="wrap hero grid gap-y-[18px] pt-8 pb-[clamp(64px,12vw,112px)] min-[900px]:grid-cols-[minmax(0,1.1fr)_minmax(0,1fr)] min-[900px]:grid-rows-[auto_auto_1fr] min-[900px]:gap-x-14 min-[900px]:gap-y-8 min-[900px]:[grid-template-areas:'badge_badge'_'head_screen'_'copy_screen']">
      <PhBadge />
      <div className="min-[900px]:[grid-area:head]">
        <h1>Every agent, at a glance, right in your notch.</h1>
        {/* A badge in the page's own type, not Claude's logo: Anthropic's marks need its written leave. */}
        <p className="mt-5 w-fit rounded-full border border-accent-text/40 bg-card px-3.5 py-1 font-mono text-[.9375rem] font-semibold text-accent-text min-[400px]:text-[1.0625rem]">
          Only for Claude Code, on Mac
        </p>
      </div>
      <div className="min-[900px]:[grid-area:copy]">
        <p className="max-w-[34em] text-[1.1875rem] leading-[1.55]">
          Each agent, sub-agents too, gets its own row and its own little programmer. See who is working, on which model, and who needs you, without leaving your app.
        </p>
        <div className="mt-8">
          <GetIt quiet>
            <Terms />
          </GetIt>
          <OnPhone />
        </div>
      </div>
      {/* Stacked, the heading and the copy below it are one block; the picture keeps its distance.
          Side by side, it stands beside the words from the top, so the first screen holds all of it. */}
      <div className="mt-8 min-[900px]:mt-0 min-[900px]:[grid-area:screen]">
        <HeroScreen>
          <ScreenDrawing />
        </HeroScreen>
      </div>
    </section>
  );
}

// The two ways in, in the hero, at the end and under a strip: the dmg of the latest release, or the
// cask. What it costs sits right under Download (children). Quiet: the Copy beside the cask stays
// plain, so Download is the one thing that stands out; only the page's last install lights it amber.
// Off this page there is no Words list for Homebrew to point at (words={false}).
export function GetIt({ quiet = false, words = true, children }: { quiet?: boolean; words?: boolean; children?: React.ReactNode }) {
  return (
    <>
      <Button asChild className="h-12 rounded-lg border-0 px-5 font-mono text-[1.0625rem] font-semibold text-primary-foreground no-underline hover:bg-primary/85 hover:text-primary-foreground">
        <a href="https://github.com/morsechimwai/agent-valley/releases/latest/download/AgentValley.dmg">Download for Mac</a>
      </Button>
      {children}
      <p className="mt-6 mb-2.5 font-mono text-[.9375rem]">
        Or with {words ? <Word id="homebrew">Homebrew</Word> : 'Homebrew'}:
      </p>
      <CopyCommand quiet={quiet}>
        brew install --cask morsechimwai/<wbr />tap/<wbr /><span className="nw">agent-valley</span>
      </CopyCommand>
    </>
  );
}

// What it costs and who checked it, under Download. Open source leads to the code. The end of the page says what it needs on its own line.
export function Terms({ needs = true }: { needs?: boolean }) {
  return (
    <>
      <p className="mt-4 font-mono text-[.9375rem]">
        <strong className="font-semibold text-accent-text">Free</strong> · <a href="https://github.com/morsechimwai/agent-valley">Open source</a>
        {/* Beside the picture the column is too narrow for one line: what it needs goes on its own. */}
        {needs && <><span className="min-[900px]:hidden"> · </span><span className="min-[900px]:block">macOS 15 or later · <span className="nw">For MacBooks with a notch</span></span></>}
      </p>
      <p className="small">Signed, and Apple checked our papers.</p>
    </>
  );
}

// Shown only on a touch screen without a pointer: the command is for a Mac.
export function OnPhone() {
  return (
    <p className="mt-4 hidden font-mono text-[.9375rem] font-semibold text-accent-text [@media(hover:none)_and_(pointer:coarse)]:block">
      Reading this on a phone? We only fit in a MacBook&apos;s notch. Open this page on your Mac, or <a href="#updates">get updates</a> for later.
    </p>
  );
}

// Halloween dusk on the wallpaper, under the panel: three bats over the setting sun, and a spider
// let down on its thread from under the notch, with a note in pen.
function Night() {
  return (
    <div className="night hw" aria-hidden="true">
      {['b1', 'b2', 'b3'].map((b) => (
        <span key={b} className={`m wave bat ${b}`}>
          <img src="/mascots/bat-0.svg" alt="" fetchPriority="high" />
          <img src="/mascots/bat-1.svg" alt="" fetchPriority="high" />
        </span>
      ))}
      <span className="web">
        <i className="silk" />
        <img className="spider" src="/mascots/spider.svg" alt="" fetchPriority="high" />
      </span>
      <p className="spider-note">He moved in last week. Pays no rent.</p>
    </div>
  );
}

// The top of a MacBook screen: menu bar, the notch with the bar beside it, the panel under it, and
// the sun setting on the horizon below.
function ScreenDrawing() {
  return (
    <>
      <i className="sun" aria-hidden="true" />
      <div className="menubar" aria-hidden="true">
        <span className="menus"><i /><i /><i /></span>
        <span className="status"><i className="battery" /><span className="clock">Thu 9:41</span></span>
      </div>
      <Night />
      <p className="notch-note" aria-hidden="true">
        {/* The pen of the row's note on the task (sections/rows.tsx), turned to point up. */}
        <svg viewBox="0 0 72 80">
          <path className="line" d="M3 6 C14 5 27 3 38 7 C50 12 57 30 56.5 47 C56.2 58 56 68 56 77" />
          <path d="M48 66 C51 70 54 74 56 77.5 C58.5 73 61 69 65 65" />
        </svg>
        The notch. Point at it or press it to open the panel.
      </p>
      <div className="panel">
        <div className="draw" aria-hidden="true">
        <div className="p-top">
          <span className="p-left">
            <span className="seg"><b>ALL</b>STATUS</span>
            <span className="faces3">
              <img src="/mascots/guru-working.svg" alt="" />
              <img src="/mascots/walrus-working.svg" alt="" />
              <img src="/mascots/afro-working.svg" alt="" />
            </span>
          </span>
          <span className="p-icons"><Icon id="speaker" /><Icon id="pin" /><Icon id="chart" /><Icon id="help" /><Icon id="gear" /></span>
        </div>
        <div className="p-head wait-only"><em>1 needs you</em><span className="extra"> · 3 working</span></div>
        <div className="p-head after-only">4 working</div>
        {/* The ALL tab puts each project's line over its cards (0.2.10). */}
        <p className="p-group not-hw">shop-web · 2 sessions</p>
        </div>
        <div className="p-card not-hw" aria-hidden="true">
          <Mascot who="guru" pose="wave" dot />
          <div>
            <p className="p-line">
              <b className="t">Deploy preview <Icon id="out" /></b>
              <span><em>needs you</em> <span className="p-wait"><Clock from={25} /></span> <span className="model">Sonnet 5.5</span> <Icon id="eyeoff" className="model" /></span>
            </p>
            <p className="p-dim"><Icon id="branch" />preview</p>
            <p>&gt; Bash git push origin preview</p>
            {/* As the app has it until the plugin is in: the second button leads to Install the plugin. */}
            <span className="p-go">Go to Terminal</span> <span className="p-go p-next">Answer here next time</span>
          </div>
        </div>
        <TrickOrTreat />
        <p className="p-group hw" aria-hidden="true">shop-web · 1 session</p>
        <div className="p-card team" aria-hidden="true">
          <Mascot who="walrus" pose="work" holds="reading" />
          <div>
            <p className="p-line"><b className="t">Refactor checkout flow <Icon id="out" /></b><span><span className="tick">3m 16s</span> <span className="model">Opus 5.5</span></span></p>
            <p className="p-dim"><Icon id="branch" />checkout-refactor</p>
            <p>&gt; Read index.tsx</p>
          </div>
          {/* The sub-agents one step in, on the app's pixel lines from the lead (0.3.5). */}
          <div className="p-subs">
            <div className="p-sub">
              <Mascot who="afro" pose="work" holds="searching" />
              <div>
                <p className="p-line"><b>Map payment call sites</b><span><span className="tick">2m 56s</span> <span className="model">Haiku 5.5</span></span></p>
                <p className="p-line p-dim"><span>&gt; Grep PaymentIntent · 1 step</span><span>Explore</span></p>
              </div>
            </div>
            <div className="p-sub">
              <Mascot who="beatnik" pose="work" holds="typing" />
              <div>
                <p className="p-line"><b>Write cart total tests</b><span><span className="tick">1m 08s</span> <span className="model">Sonnet 5.5</span></span></p>
                <p className="p-dim">&gt; Edit cart.test.ts · 4 steps</p>
              </div>
            </div>
          </div>
        </div>
        <i className="lights hw" aria-hidden="true"><b /><b /></i>
      </div>
      <div className="bar" aria-hidden="true">
        <span className="wing"><Mascot who="guru" pose="wave" className="wait-only" eager /><Mascot who="guru" pose="work" holds="running" className="after-only" /><span className="count wait-only">1</span></span>
        <span className="lens" />
        <span className="wing"><span className="gauge" /></span>
      </div>
    </>
  );
}
