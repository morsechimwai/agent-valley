import { CrewLoop } from '@/components/crew-loop';
import { Word } from '@/components/word';

// One session at work, drawn as the crew's org chart (motion/crew-motion.tsx): a still, and over it
// the motion once the page may move. The stills are frames of it, drawn by testing/site.sh crew.
export function Crew() {
  return (
    <section className="wrap section crew pt-[clamp(72px,14vw,128px)] pb-[clamp(64px,12vw,112px)]">
      <h2>Meet the crew.</h2>
      <p className="mt-[18px] max-w-[34em] text-[1.1875rem] leading-[1.55]">
        Every agent is a programmer from the early days of computing. One of us runs your session and phones the others for help. Each project gets a <Word id="regular">regular</Word>: the same one of us, every session.
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
    </section>
  );
}
