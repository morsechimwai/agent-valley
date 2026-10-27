import { NeedsYouLoop } from '@/components/needs-you-loop';
import { Word } from '@/components/word';

// A small square in the accent colour marks each point.
const TICK = "relative pl-[1.4em] before:absolute before:top-[.62em] before:left-[.15em] before:size-[.5em] before:bg-accent-text before:content-['']";

export function NeedsYou() {
  return (
    <section className="wrap section split needs-you">
      <div className="stack">
        <h2>Know the moment one needs you.</h2>
        <p className="lead">
          When an agent asks a question or waits for permission, a red count appears beside the <Word id="notch">notch</Word>. Open the panel to read the question or the command. Each one that waits gets a red badge with how long it has waited, and past a minute the longest wait shows beside the notch too.
        </p>
        <ul className="max-w-[36em] space-y-3.5" role="list">
          <li className={TICK}>
            <Word id="jump">Jump</Word> to its app in one click. Turn on Go to the session&apos;s tab, and Terminal and iTerm2 open the exact tab. Ghostty does too, unless two sessions run in the same folder.
          </li>
          <li className={TICK}>
            Answer Claude Code from the notch with Allow once or Deny, using a <Word id="plugin">plugin</Word> that comes with the app: press Install the plugin in the Claude Code settings, then start Claude Code again.
          </li>
          <li className={TICK}>
            With sounds on, we talk. Whoever runs the session plays a few notes on their own instrument and says what it needs: a command, an edit, a question, a plan. Rather have a plain chime? Settings has one. Sounds are on from the start, and one switch in Settings turns them off.
          </li>
        </ul>
      </div>
      {/* A Mac screen with the app's own panel, drawn by testing/site.sh needs-you: a still, and
          over it the motion once the page may move. */}
      <figure
        className="s-figure min-w-0"
        role="img"
        aria-label="The top of a Mac screen. An agent works in a terminal. It asks to run git push origin preview: the terminal waits and a red 1 appears beside the notch. The pointer opens the panel over the terminal and presses Allow once. The panel shuts and the push goes through."
      >
        <img className="s-still" src="/needs-you/still.webp" width={1500} height={1125} alt="" loading="lazy" decoding="async" />
        <NeedsYouLoop />
      </figure>
    </section>
  );
}
