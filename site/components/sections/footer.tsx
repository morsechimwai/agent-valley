import { HuntPumpkin } from '@/components/hunt';
import { SponsorButton } from '@/components/sponsor-button';
import { StillToggle } from '@/components/still-toggle';
import { Wordmark } from '@/components/wordmark';

// The block-letter name on the left with the motto under it, the links on the right, and the small
// print under a rule. `hunt`: the home page, where Halloween's last pumpkin hides by the name.
// `still`: a page whose animations can be stopped, the home page.
export function Footer({ hunt = false, still = false }: { hunt?: boolean; still?: boolean }) {
  return (
    <footer className="wrap foot border-t pt-12 pb-10 font-mono text-sm text-muted-foreground">
      <div className="flex flex-wrap items-start justify-between gap-x-10 gap-y-6">
        <div>
          <div className="flex items-center gap-2">
            <Wordmark />
            {hunt && <HuntPumpkin n={4} />}
          </div>
          <p className="mt-3">A small valley of programmers in your notch.</p>
        </div>
        {/* The page asks for the crew's coffee twice, both after the install: under their photo and here. */}
        <ul className="flex flex-wrap items-center gap-x-6 gap-y-2" role="list">
          <li><a className="inline-flex min-h-11 items-center" href="/comics/">Comics</a></li>
          <li><a className="inline-flex min-h-11 items-center" href="https://github.com/morsechimwai/agent-valley" aria-label="AgentValley on GitHub">GitHub</a></li>
          <li><a className="inline-flex min-h-11 items-center" href="https://x.com/morsechimwai" aria-label="morsechimwai on X">X</a></li>
          <li><a className="inline-flex min-h-11 items-center" href="https://bsky.app/profile/morsechimwai.bsky.social" aria-label="morsechimwai on Bluesky">Bluesky</a></li>
          <li>
            <SponsorButton />
          </li>
        </ul>
      </div>
      <div className="mt-8 flex flex-wrap items-center justify-between gap-x-6 gap-y-1 border-t pt-5 text-[.8125rem]">
        <p>Made by morsechimwai</p>
        {still && <StillToggle />}
        {/* lib/analytics.ts; the app itself counts nothing. */}
        <p>This page counts visits with PostHog. No cookies.</p>
        <p className="flex gap-x-4">
          <a className="inline-flex min-h-11 items-center" href="/privacy/">Privacy</a>
          <a className="inline-flex min-h-11 items-center" href="https://github.com/morsechimwai/agent-valley/blob/main/LICENSE">MIT License</a>
        </p>
        <p>Not affiliated with Anthropic.</p>
      </div>
    </footer>
  );
}
