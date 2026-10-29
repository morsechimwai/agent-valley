import { DisplayLoop } from '@/components/display-loop';
import { Word } from '@/components/word';

type Item = { term: string; text: React.ReactNode };

// A spec sheet, not a row of cards: ruled lines, two across on a wide screen.
function Sheet({ items }: { items: Item[] }) {
  return (
    <dl className="grid border-t min-[760px]:grid-cols-2 min-[760px]:gap-x-14">
      {items.map((item) => (
        <div key={item.term} className="grid content-start gap-1.5 border-b py-[22px]">
          <dt className="font-mono font-semibold">{item.term}</dt>
          <dd className="max-w-[36em] text-[.9375rem] text-muted-foreground">{item.text}</dd>
        </div>
      ))}
    </dl>
  );
}

export function Also() {
  return (
    <section className="wrap section more also py-[clamp(56px,10vw,88px)]">
      <h2 className="mb-7">Also in the panel.</h2>
      <Sheet
        items={[
          { term: 'Plan limits', text: "Your Claude 5-hour and weekly limits, with time left until reset. Off until you turn it on. When one runs out we go fishing, or take the van for the weekly one, and a sign says when we're back." },
          { term: 'Token use', text: <><Word id="tokens">Tokens</Word> for the last 5 hours and today, with a 12-hour chart.</> },
          { term: 'Task list', text: "When the lead keeps a task list, its card shows it under the step it's on, in Claude Code's own marks: ✓ done, ■ under way, □ to do. Past five tasks the done ones fold into one line. The list goes once everything is done." },
          { term: 'Jobs left running', text: "When an agent leaves something running in the background, a green screen sits beside the coffee on the bar until it ends. A dev server, or anything else serving on a port, gets a small server sending out waves instead. The session's card lists each one and how long it has run: a screen for a command, a server for a port, an eye for a Monitor. After half an hour they stop and dim." },
          { term: 'Keyboard', text: <>Press <abbr title="Control-Option-Command-A">⌃⌥⌘A</abbr> from any app. Arrows to pick, Return to jump.</> },
          {
            term: 'Another display',
            text: (
              <>
                MacBook off to the side, big screen in front? Settings › General › Display moves us to the top of the big one, on any display plugged into your Mac. Unplug it and we go back to the notch. Asked for in{' '}
                <a href="https://github.com/morsechimwai/agent-valley/issues/1">issue #1</a>.
                {/* A sign drawn by testing/site.sh display: a still, and over it the motion once the page may move. */}
                <figure
                  className="d-figure mt-5 max-w-[360px]"
                  role="img"
                  aria-label="A big display with a MacBook in front of it. The notch, with one of us in it, lifts off the MacBook, glides to the top of the big display and settles there, then glides back."
                >
                  <img className="d-still" src="/display/still.webp" width={720} height={450} alt="" loading="lazy" decoding="async" />
                  <DisplayLoop />
                </figure>
              </>
            ),
          },
        ]}
      />
    </section>
  );
}
