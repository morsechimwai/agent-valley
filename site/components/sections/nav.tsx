import { masthead } from '@/app/fonts';
import { NavFold } from '@/components/nav-fold';
import { Button } from '@/components/ui/button';
import { Wordmark } from '@/components/wordmark';

// The block-letter name at the very top; down the page the crew in the notch takes its place.
// The link keeps its name either way. `sub`: a page other than the home page, which has no
// animations to stop and sends Install back home.
export function Nav({ sub = false }: { sub?: boolean }) {
  return (
    <header className="wrap nav">
      <a className="brand" href="/" aria-label="AgentValley">
        <img src="/mark.svg" alt="" width="32" height="26" />
        <Wordmark />
      </a>
      <nav aria-label="Main">
        {/* Words on this page is reached from every dotted word. A phone keeps the bar to one row: GitHub is in the hero and at the foot,
            and on the home page Comics is at the foot too. */}
        {/* The paper's nameplate: its name small over Funnies in the masthead's blackletter. */}
        <a className={`nameplate ${sub ? '' : 'max-[559px]:hidden'}`} href="/comics/">
          <small>The Valley</small> <span className={masthead.className}>Funnies</span>
        </a>
        {/* No star count yet: the repo has none to show (2026-10-19). */}
        <Button asChild variant="outline" className="h-11 gap-2 rounded-lg bg-background px-3 font-mono text-foreground hover:bg-card hover:text-foreground max-[479px]:hidden">
          <a href="https://github.com/morsechimwai/agent-valley" aria-label="Star AgentValley on GitHub">
            <svg viewBox="0 0 16 16" width="16" height="16" fill="currentColor" aria-hidden="true">
              <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8z" />
            </svg>
            Star
          </a>
        </Button>
        <Button asChild className="to-install h-11 rounded-lg border-0 px-3.5 font-mono text-primary-foreground hover:bg-primary/85 hover:text-primary-foreground min-[400px]:px-4">
          <a href={sub ? '/#install' : '#install'}>Install</a>
        </Button>
      </nav>
      <NavFold />
    </header>
  );
}
