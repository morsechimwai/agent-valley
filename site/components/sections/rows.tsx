import { Clock } from '@/components/clock';
import { Mascot } from '@/components/mascot';
import { Reveal } from '@/components/reveal';
import { Word } from '@/components/word';

// A note in pen, drawn out of the black box onto the page: its label where the line starts, the
// line, and a head where it meets the part. Lines are in a 72 × 80 box, 16 to the em; `at` is
// where along the part the head lands, `side` which edge of the part it meets.
type Note = {
  side: 'top' | 'bottom';
  at: string;
  tail: readonly [number, number];
  tip: readonly [number, number];
  line: string;
  head: string;
};
const NOTES: Record<string, Note> = {
  task: {
    side: 'top',
    at: '1.6em',
    tail: [3, 6],
    tip: [56, 77],
    line: 'M3 6 C14 5 27 3 38 7 C50 12 57 30 56.5 47 C56.2 58 56 68 56 77',
    head: 'M48 66 C51 70 54 74 56 77.5 C58.5 73 61 69 65 65',
  },
  'time · model': {
    side: 'top',
    at: '40%',
    tail: [69, 6],
    tip: [34, 77],
    line: 'M69 6 C58 7 46 12 40 22 C34 33 33 52 34 77',
    head: 'M26 66 C29 70 32 74 34 77.5 C36.5 73 39 69 43 65',
  },
  'latest step · steps so far': {
    side: 'bottom',
    at: '2.2em',
    tail: [3, 74],
    tip: [56, 3],
    line: 'M3 74 C14 75 27 77 38 73 C50 68 57 50 56.5 33 C56.2 22 56 12 56 3',
    head: 'M48 14 C51 10 54 6 56 2.5 C58.5 7 61 11 65 15',
  },
  type: {
    side: 'bottom',
    at: '50%',
    tail: [69, 74],
    tip: [34, 3],
    line: 'M69 74 C58 73 46 68 40 58 C34 47 33 28 34 3',
    head: 'M26 14 C29 10 32 6 34 2.5 C36.5 7 39 11 43 15',
  },
};

function Note({ part, order }: { part: keyof typeof NOTES; order: number }) {
  const n = NOTES[part];
  const em = (units: number) => `${units / 16}em`;
  const pct = (units: number, of: number) => `${(units / of) * 100}%`;
  // The head lands a hair off the part, so the pen does not cross its letters.
  const top = n.side === 'top' ? `calc(${em(-n.tip[1])} - .1em)` : `calc(100% + .1em - ${em(n.tip[1])})`;
  const fromLeft = n.tail[0] < 36;
  return (
    <span className="note" data-for={part} style={{ left: `calc(${n.at} - ${em(n.tip[0])})`, top, '--i': order } as React.CSSProperties}>
      <svg viewBox="0 0 72 80">
        <path className="line" pathLength={1} d={n.line} />
        <path className="head" pathLength={1} d={n.head} />
      </svg>
      <span
        className="note-label"
        // In shares of the note's box: the label's own em is its larger type's.
        style={{
          ...(n.side === 'top' ? { bottom: `calc(${pct(80 - n.tail[1], 80)} + 2px)` } : { top: `calc(${pct(n.tail[1], 80)} + 2px)` }),
          ...(fromLeft ? { left: pct(n.tail[0] - 2, 72) } : { right: pct(72 - n.tail[0] - 2, 72) }),
        }}
      >
        {part}
      </span>
    </span>
  );
}

export function Rows() {
  return (
    <section className="wrap section split flip">
      <div className="stack">
        <h2>Every agent gets a row.</h2>
        <p className="lead">
          Sessions get a <Word id="panel">card</Word>. <Word id="sub-agent">Sub-agents</Word> get rows under it. Each row shows the task, the <Word id="model">model</Word> and the latest <Word id="step">step</Word>. Sub-agent rows count their steps too.
        </p>
        <p>Every session in one list, whichever terminal it runs in, grouped by project. <Word id="worktree">Worktrees</Word> count as their project. Run more sessions than the panel fits and they fold to one line each, quiet ones first. One that needs you never folds.</p>
        <p>
          Pixel lines run from the lead to each sub-agent, and turn red when one waits on you. The triangle on a working sub-agent&apos;s row opens Asked: the whole prompt its lead gave it. When one finishes, it goes into a sealed envelope under its session, and what it handed back waits there until you&apos;ve seen it: who, how long ago, the first two lines, and Read all for the rest. Click the envelope to list everyone who&apos;s done.
        </p>
        <p className="text-muted-foreground">No guessed progress bars. If an agent goes <Word id="quiet">quiet</Word>, AgentValley says so.</p>
      </div>
      {/* One row, taken out of the panel and marked up part by part in pen. */}
      <Reveal>
        <figure className="notes" role="img" aria-label="One sub-agent row, enlarged and labelled: the task, the time and model, the latest step with the step count, and the agent's type.">
          <div className="anatomy" aria-hidden="true">
            <div className="row">
              <Mascot who="afro" pose="work" holds="searching" />
              <div>
                <p className="p-line">
                  <b data-part="task">Map payment call sites<Note part="task" order={0} /></b>
                  <span data-part="time · model"><span className="tick"><Clock from={176} /></span> <span className="model">Haiku 5.5</span><Note part="time · model" order={1} /></span>
                </p>
                <p className="p-line p-dim">
                  <span data-part="latest step · steps so far">&gt; Grep PaymentIntent · 1 step<Note part="latest step · steps so far" order={2} /></span>
                  <span data-part="type">Explore<Note part="type" order={3} /></span>
                </p>
              </div>
            </div>
          </div>
        </figure>
      </Reveal>
    </section>
  );
}
