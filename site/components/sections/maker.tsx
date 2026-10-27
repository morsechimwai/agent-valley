'use client';

import type { PointerEvent } from 'react';
import { Word } from '@/components/word';
import './maker.css';

const LIGHT = ['--mx', '--my', '--rx', '--ry'];

// Where the pointer is on the card sets the glare, the foil and the tilt (maker.css).
function follow(e: PointerEvent<HTMLDivElement>) {
  const hang = e.currentTarget;
  const r = hang.querySelector('.id-card')!.getBoundingClientRect();
  const x = Math.min(1, Math.max(0, (e.clientX - r.left) / r.width));
  const y = Math.min(1, Math.max(0, (e.clientY - r.top) / r.height));
  hang.classList.add('live');
  hang.style.setProperty('--mx', `${x * 100}%`);
  hang.style.setProperty('--my', `${y * 100}%`);
  hang.style.setProperty('--rx', `${(0.5 - y) * 16}deg`);
  hang.style.setProperty('--ry', `${(x - 0.5) * 22}deg`);
}

function rest(e: PointerEvent<HTMLDivElement>) {
  e.currentTarget.classList.remove('live');
  for (const p of LIGHT) e.currentTarget.style.removeProperty(p);
}

// The maker, after the crew he calls his employees: his staff badge on a lanyard, brushed aluminium
// with a foil film, and a few lines in his own words (from his Product Hunt launch comment).
export function Maker() {
  return (
    <section className="wrap section split maker">
      <div
        className="id-hang"
        onPointerMove={follow}
        onPointerLeave={rest}
        role="img"
        aria-label="Morse's staff badge: a brushed aluminium card on a lanyard with his photo in a teal beanie, the AgentValley logo, Maker, Thailand, number 001, since October 16, 2026."
      >
        <div className="id-strap"><span>AGENT VALLEY · AGENT VALLEY · AGENT VALLEY</span></div>
        <div className="id-clip"><i /></div>
        <div className="id-tongue" />
        <div className="id-lift">
          <div className="id-card">
            <div className="id-layer id-metal" />
            <div className="id-layer id-brush" />
            <div className="id-layer id-holo" />
            <div className="id-face">
              <div className="id-brand"><img src="/logo.svg" alt="" width={88} height={12} loading="lazy" /><b>STAFF</b></div>
              <div className="id-kicker">NOTCH OFFICE · ID CARD</div>
              <div className="id-portrait">
                <img src="/morse.webp" alt="" width={420} height={490} loading="lazy" />
                <div className="id-seal"><img src="/mark.svg" alt="" width={16} height={13} loading="lazy" /></div>
              </div>
              <div className="id-name">MORSE CHIMWAI</div>
              <div className="id-role">MAKER</div>
              <div className="id-fields">
                <div><small>BASE</small>Thailand</div>
                <div><small>NO.</small>001</div>
                <div><small>SINCE</small>&apos;26 10 16</div>
              </div>
              <div className="id-code"><div className="id-bars" /><span>AV-0001</span></div>
            </div>
            <div className="id-layer id-sheen" />
            <div className="id-layer id-glare" />
            <div className="id-layer id-edge" />
            <div className="id-slot" />
          </div>
        </div>
      </div>
      <div className="stack">
        <h2>Hi, I&apos;m Morse.</h2>
        <p className="lead">
          I&apos;m a developer in Thailand, and AgentValley is the first app I&apos;ve <Word id="nerve">had the nerve</Word> to <Word id="ship">ship</Word>. I run a few Claude Code windows at once and wanted one place to see who&apos;s working and who&apos;s waiting on me. So I put them in the notch.
        </p>
        <p className="lead">The crew is my favorite part. They feel like my employees now.</p>
        <p className="font-mono text-[.9375rem] text-muted-foreground">
          Questions or ideas: <a href="mailto:morse@agentvalley.app">morse@agentvalley.app</a> or{' '}
          <a href="https://x.com/morsechimwai">@morsechimwai</a> on X.
        </p>
      </div>
    </section>
  );
}
