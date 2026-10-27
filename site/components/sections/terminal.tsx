import { HuntPumpkin } from '@/components/hunt';
import { Icon } from '@/components/icons';
import { Mascot, type Person, type Thing } from '@/components/mascot';
import { Reveal } from '@/components/reveal';
import { Word } from '@/components/word';

// A meter of six cells, as the status line draws it in a terminal this narrow: the used part
// bright on a faint track.
function Bar({ percent }: { percent: number }) {
  const full = Math.round((percent / 100) * 6);
  return <>{'━'.repeat(full)}<span className="t-dim">{'━'.repeat(6 - full)}</span></>;
}

function Row({ who, holds, task, time, model, step }: { who: Person; holds: Thing; task: string; time: string; model: string; step: string }) {
  return (
    <div className="t-row">
      <p><span className="t-dot">○</span><Mascot who={who} pose="still" holds={holds} /><b>{task}</b><span>{time}</span><span className="t-dim">{model}</span></p>
      <p className="t-dim"><span><Icon id="folder" />shop-web</span><span><Icon id="branch" />refunds</span></p>
      <p>&gt; {step}</p>
    </div>
  );
}

// Claude Code under its prompt once the crew is in. The ● main line and the ○ dots are Claude
// Code's own; the faces in a real terminal are one character each, from the crew's font.
export function Terminal() {
  return (
    <section className="wrap section split flip terminal">
      <div className="stack">
        <h2>The crew shows up in your terminal too.</h2>
        <p className="lead">
          Claude Code&apos;s <Word id="status-line">status line</Word> gets the face of whoever runs the session, with the model, your plan and your limits. Each sub-agent row under the prompt gets its own face, its model, the step it&apos;s on, and the notch&apos;s own marks for its folder and branch. Send three or more of us and we each take one line, so nobody drops off the bottom.
        </p>
        <p>In the terminal we hold the same things, but we keep still. Until your first prompt only a coffee waits there, on standby, and when a limit runs out we go fishing, or take the van.</p>
        <p>One command from the app&apos;s settings sets it up. With the app closed your limits still show, and the coffee waits.</p>
        <p className="text-muted-foreground">We travel as a font, and we&apos;ve been seen in Terminal, iTerm2, Ghostty and Cursor.</p>
        <HuntPumpkin n={2} />
      </div>
      <Reveal>
        <figure
          className="cterm"
          role="img"
          aria-label="Claude Code in a terminal. Under the prompt, the status line shows Sunny's face, Opus 5.5 and Max 20x, then bars for context, the 5-hour limit and the weekly limit. Below it, two sub-agent rows, each with a little face, its task, time, model, folder, branch and current step."
        >
          <div aria-hidden="true">
            <p className="t-prompt">&gt; Find where we take payments, then plan refunds</p>
            <p><Mascot who="guru" pose="still" holds="calling" /><b>Opus 5.5</b><span className="t-dim">· Max 20x</span></p>
            <p className="t-meters">
              <span><span className="t-dim">context</span> <Bar percent={34} /> <b>34%</b></span>
              <span><span className="t-dim">5h</span> <Bar percent={41} /> <b>41%</b> <span className="t-dim">↻ 2h 10m</span></span>
              <span><span className="t-dim">7d</span> <Bar percent={62} /> <b>62%</b> <span className="t-dim">↻ 3d 4h</span></span>
            </p>
            <p className="t-main">● main</p>
            <Row who="afro" holds="searching" task="Map payment call sites" time="2m 56s" model="Haiku 5.5" step="Grep PaymentIntent" />
            <Row who="coder" holds="reading" task="Plan the refund flow" time="48s" model="Sonnet 5.5" step="Read refunds.ts" />
          </div>
        </figure>
      </Reveal>
    </section>
  );
}
