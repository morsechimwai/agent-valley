'use client';

import { useEffect, useRef, useState } from 'react';

// The picture's words follow it: open, the panel; shut, the bar.
const TOLD = {
  open: 'The top of a MacBook screen. The AgentValley panel is open under the notch: one session needs you, another is working with two sub-agents.',
  shut: 'The top of a MacBook screen. Beside the notch, a waving programmer and a red 1: an agent needs you.',
};

// How long a mouse rests on the bar before the panel opens, as the app waits (EntryWatch.dwell):
// one crossing the bar on its way elsewhere is gone by then.
const DWELL = 100;

// The hero's panel, under the bar beside the notch. It stands open from the first paint, so the
// first thing the reader sees is the list itself (owner's pick, 2026-10-24), and stays open until a
// pointer that came into it leaves, or the notch is pressed. Without scripts the button stays
// hidden. A mouse works it as on a Mac: resting on the bar opens
// it, and once in, leaving the panel shuts it; Esc shuts it too. A press with the mouse only opens
// it, so one pressing the bar the pointer has just opened does not shut it again. Keys and a
// finger, which cannot rest on it, open and shut it by pressing.
export function HeroScreen({ children }: { children: React.ReactNode }) {
  const [state, setState] = useState<'open' | 'shut'>('open');
  const [ready, setReady] = useState(false);
  const button = useRef<HTMLButtonElement>(null);
  const figure = useRef<HTMLElement>(null);
  // Whether the mouse is in the panel or on the bar; whether resting on the bar may open it (not
  // right after it was Esc'd shut there); the wait before it opens; what last pressed the bar.
  const inside = useRef(false);
  const armed = useRef(true);
  const dwell = useRef(0);
  const presser = useRef('');

  // Shut by hand: the resting mouse does not open it again until it goes and comes back.
  const shut = () => {
    armed.current = false;
    clearTimeout(dwell.current);
    dwell.current = 0;
    setState('shut');
  };

  useEffect(() => {
    // React is here: the layout's first script keeps js, so the pictures wait for their moment.
    document.documentElement.dataset.live = '';
    setReady(true);
    return () => clearTimeout(dwell.current);
  }, []);

  useEffect(() => {
    if (state !== 'open') return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && (inside.current || figure.current?.contains(document.activeElement))) shut();
    };
    addEventListener('keydown', onKey);
    return () => removeEventListener('keydown', onKey);
  }, [state]);

  const track = (e: React.PointerEvent<HTMLElement>, gone = false) => {
    if (e.pointerType !== 'mouse') return;
    const over = (el: Element | null) => {
      const box = el?.getBoundingClientRect();
      return !!box && e.clientX >= box.left && e.clientX < box.right && e.clientY >= box.top && e.clientY < box.bottom;
    };
    const onBar = !gone && over(button.current);
    const now = onBar || (!gone && state === 'open' && over(e.currentTarget.querySelector('.panel')));
    if (!onBar) {
      clearTimeout(dwell.current);
      dwell.current = 0;
      armed.current = true;
    }
    if (state === 'open' && inside.current && !now) setState('shut');
    inside.current = now;
    if (state === 'shut' && onBar && armed.current && !dwell.current) {
      dwell.current = window.setTimeout(() => {
        dwell.current = 0;
        setState('open');
      }, DWELL);
    }
  };

  return (
    <figure
      ref={figure}
      className="screen"
      data-state={state}
      data-ready={ready ? '' : undefined}
      onPointerMove={(e) => track(e)}
      onPointerLeave={(e) => track(e, true)}
    >
      <span role="img" aria-label={TOLD[state]} />
      {/* The notch comes first for the keyboard: the panel it opens follows it. */}
      <button
        ref={button}
        className="bar-hit"
        type="button"
        aria-expanded={state === 'open'}
        aria-label="The notch: the AgentValley panel"
        hidden={!ready}
        onPointerDown={(e) => (presser.current = e.pointerType)}
        onClick={(e) => {
          if (state === 'shut') setState('open');
          // A click from the keyboard has no detail, and one from a screen reader no press before it.
          else if (!e.detail || presser.current !== 'mouse') shut();
          presser.current = '';
        }}
      />
      <div>{children}</div>
    </figure>
  );
}
