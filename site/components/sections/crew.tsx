import { CrewLoop } from '@/components/crew-loop';
import { Mascot, Mug, type Thing } from '@/components/mascot';
import { Word } from '@/components/word';

// How to read us, as the README has it: how we stand, then what we hold.
const STATES = [
  { pose: 'still', name: 'Working', how: 'we blink' },
  { pose: 'wave', name: 'Needs you', how: 'we wave' },
  { pose: 'quiet', name: 'Quiet', how: 'we look away' },
  { pose: 'done', name: 'Done', how: 'our eyes close' },
] as const;
const THINGS: { thing: Thing; name: string; how: string }[] = [
  { thing: 'thinking', name: 'Thinking', how: 'chin in hand' },
  { thing: 'reading', name: 'Read', how: 'a printout' },
  { thing: 'typing', name: 'Edit', how: 'a keyboard' },
  { thing: 'running', name: 'Bash', how: 'a terminal' },
  { thing: 'searching', name: 'Grep', how: 'a magnifier' },
  { thing: 'calling', name: 'Agent', how: 'on the phone' },
];
// Wide enough for Nothing running on one line, so every caption sits level.
const KEY = 'mt-6 grid max-w-[900px] grid-cols-[repeat(auto-fill,minmax(140px,1fr))] gap-x-3 gap-y-6';
const CELL = 'grid justify-items-center gap-1 text-center [--s:48px]';

function Cell({ figure, name, how }: { figure: React.ReactNode; name: string; how: string }) {
  return (
    <li className={CELL}>
      {figure}
      <b className="mt-1.5 font-mono text-[.9375rem] font-semibold">{name}</b>
      <span className="text-[.9375rem] text-muted-foreground">{how}</span>
    </li>
  );
}

// One session at work, drawn as the crew's org chart (motion/crew-motion.tsx): a still, and over it
// the motion once the page may move. The stills are frames of it, drawn by testing/site.sh crew.
export function Crew() {
  return (
    <section className="wrap section crew pt-[clamp(72px,14vw,128px)] pb-[clamp(64px,12vw,112px)]">
      <h2>Meet the crew.</h2>
      <p className="mt-[18px] max-w-[34em] text-[1.1875rem] leading-[1.55]">
        Every agent is a programmer from the early days of computing. One of us runs your session and phones the others for help. Each project gets a <Word id="regular">regular</Word>: the same one of us, every session. Open a second session there at the same time and a colleague takes it, since nobody is in two places at once.
      </p>
      <p className="mt-4 max-w-[34em] text-[1.1875rem] leading-[1.55]">
        In Claude Code we call each other by name. Norm hands a search to Faye with “Faye takes the search. Sending it now.” and Faye brings it back with “Norm, two call sites, no surprises.” We each talk in our own voice, in the language you write in. Your code, commits and files stay exactly as they would be without us. It comes with the plugin, from your next session on. Crew names in Claude Code, in the Claude Code settings, turns it off.
      </p>
      <figure
        className="c-figure mt-10"
        role="img"
        aria-label="One session at work, drawn as an org chart. Sunny adds a Pro paywall to an AI meeting notes app and phones two sub-agents: Faye finds the AI features and Judy plans the Stripe checkout. Each row shows its latest step, and each face holds what its agent is doing. Then Felix writes the paywall tests and runs them, Sunny builds the paywall, and the session ends with a cup of coffee."
      >
        {/* The source's media is NARROW in crew-loop.tsx. */}
        <picture>
          <source media="(max-width: 640px)" srcSet="/crew/still-tall.webp" width={1280} height={1560} />
          <img className="c-still" src="/crew/still.webp" width={2400} height={1200} alt="" loading="lazy" decoding="async" />
        </picture>
        <CrewLoop />
      </figure>
      <h3 className="mt-14 font-mono text-[1.3125rem] leading-[1.3]">How to read us.</h3>
      <p className="mt-3 max-w-[34em]">How we stand tells you how the agent is doing.</p>
      <ul className={KEY} role="list">
        {STATES.map((s) => <Cell key={s.name} figure={<Mascot who="guru" pose={s.pose} />} name={s.name} how={s.how} />)}
        <Cell figure={<Mug />} name="Nothing running" how="a cup of coffee" />
      </ul>
      <p className="mt-10 max-w-[34em]">While the agent works, we hold what it&apos;s on. Six seconds in hand, two to put it down.</p>
      <ul className={KEY} role="list">
        {THINGS.map((t) => <Cell key={t.name} figure={<Mascot who="guru" pose="work" holds={t.thing} />} name={t.name} how={t.how} />)}
      </ul>
    </section>
  );
}
