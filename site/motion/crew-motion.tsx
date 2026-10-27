import type React from 'react';
import { AbsoluteFill, Easing, Img, interpolate, spring, staticFile, useCurrentFrame } from 'remotion';
import { elapsed } from '../lib/clock';

// One session from start to coffee, drawn as the crew's org chart: the notch at the top, the
// session's card under it, and below it the sub-agents it phones. A line is drawn to a
// desk as the job goes down and a dot runs back up with the result. Every row shows its latest
// step and every face holds what its agent is on, as the app draws them. It ends as it starts:
// the notch alone with a cup of coffee. Asking for the person is the needs-you section's to show.
export type CrewMotionProps = {
  readonly base: string;
  readonly tall?: boolean;
  // Under it, for the README's GIF; the site shows it on the page's own cream.
  readonly paper?: string;
};

type Who = 'guru' | 'afro' | 'coder' | 'beatnik';
export type Thing = 'thinking' | 'reading' | 'typing' | 'running' | 'searching' | 'calling';
// From which frame, the line the row shows (null while it thinks), what the agent holds.
type Step = readonly [at: number, line: string | null, thing: Thing];

const FPS = 60;
const s = (seconds: number) => Math.round(seconds * FPS);
// The story's pace: when things happen stretches with it, how fast each one moves does not.
const PACE = 1.15;
const at = (seconds: number) => s(seconds * PACE);
// The app's tick, 0.4 s; a thing is in hand for six seconds of every eight.
const TICK = s(0.4);
const HOLD = s(8);
const LOOP: Record<Thing, number> = {
  thinking: 24,
  reading: 8,
  typing: 8,
  running: 8,
  searching: 8,
  calling: 8,
};

const INK = '#000';
const FG = '#fff';
const DIM = '#a8a8ad';
const PEN = '#723a00';
const SIGNAL = '#e8890c';
const APP = 'ui-monospace, "SF Mono", Menlo, monospace';
// The page's hand; a render has Caveat from the entry (motion/index.tsx).
const HAND = 'var(--hand, Caveat, "Bradley Hand", cursive)';

const snap = Easing.bezier(0.2, 0, 0, 1);
const swing = Easing.bezier(0.65, 0, 0.35, 1);
const clamp = { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' } as const;
const tween = (f: number, a: number, b: number, from = 0, to = 1, easing = snap) => interpolate(f, [a, b], [from, to], { ...clamp, easing });
const pop = (f: number, at: number) =>
  f < at
    ? 0
    : spring({
        frame: f - at,
        fps: FPS,
        config: { damping: 15, stiffness: 230, mass: 0.7 },
      });

// When things happen.
export const T = {
  open: 0,
  callFaye: at(1),
  callJudy: at(1.5),
  fayeDone: at(5.2),
  judyDone: at(5.7),
  fold1: at(6.2),
  callFelix: at(6.4),
  felixDone: at(9.6),
  fold2: at(10.1),
  done: at(12.4),
  close: [at(13.6), at(13.6) + s(0.5)],
  end: at(14.8),
} as const;

// Places, in the picture's pixels. Wide, the desks sit side by side under the card; tall, for a
// phone, they stand one under the other with the line coming down the left.
type Box = { x: number; y: number; w: number; h: number };
type Layout = {
  W: number;
  H: number;
  bar: { x: number; w: number; h: number; face: number };
  card: Box & { face: number; font: number };
  desks: readonly Box[];
  row: { face: number; font: number };
  // Notes sit under the card while it works alone, and under the rows while anyone is phoned.
  notes: { high: number; low: number; size: number };
  side: boolean;
};
const WIDE: Layout = {
  W: 1200,
  H: 600,
  bar: { x: 440, w: 320, h: 52, face: 34 },
  card: { x: 250, y: 96, w: 700, h: 150, face: 72, font: 22 },
  desks: [
    { x: 20, y: 340, w: 560, h: 110 },
    { x: 620, y: 340, w: 560, h: 110 },
  ],
  row: { face: 60, font: 19 },
  notes: { high: 290, low: 488, size: 42 },
  side: false,
};
const TALL: Layout = {
  W: 640,
  H: 780,
  bar: { x: 200, w: 240, h: 44, face: 30 },
  card: { x: 20, y: 72, w: 600, h: 160, face: 72, font: 24 },
  desks: [
    { x: 64, y: 290, w: 556, h: 140 },
    { x: 64, y: 460, w: 556, h: 140 },
  ],
  row: { face: 60, font: 22 },
  notes: { high: 276, low: 650, size: 40 },
  side: true,
};
const config = (l: Layout) => ({ width: l.W, height: l.H, fps: FPS, durationInFrames: T.end }) as const;
export const CREW_MOTION = config(WIDE);
export const CREW_MOTION_TALL = config(TALL);

type Agent = {
  who: Who;
  task: string;
  model: string;
  type?: string;
  start: number;
  done: number;
  steps: readonly Step[];
};
const SUNNY: Agent = {
  who: 'guru',
  task: 'Add a Pro paywall',
  model: 'Opus 5.5',
  start: T.open,
  done: T.done,
  steps: [
    [T.open, null, 'thinking'],
    [T.callFaye, 'Agent Find the AI features', 'calling'],
    [T.callJudy, 'Agent Plan Stripe checkout', 'calling'],
    [T.callFelix, 'Agent Write paywall tests', 'calling'],
    [at(10.3), 'Edit Paywall.tsx', 'typing'],
    [at(11.2), 'Bash npm test', 'running'],
  ],
};
// The session's project and branch, under its name on the card.
const PROJECT = 'meeting-ai';
const BRANCH = 'pro-paywall';
const FAYE: Agent = {
  who: 'afro',
  task: 'Find the AI features',
  model: 'Haiku 5.5',
  type: 'Explore',
  start: T.callFaye + s(0.25),
  done: T.fayeDone,
  steps: [
    [T.callFaye + s(0.25), 'Grep summarize(', 'searching'],
    [at(2.3), 'Read notes.ts', 'reading'],
    [at(3.3), 'Grep askAI(', 'searching'],
    [at(4.2), 'Read chat.ts', 'reading'],
  ],
};
const JUDY: Agent = {
  who: 'coder',
  task: 'Plan Stripe checkout',
  model: 'Sonnet 5.5',
  type: 'Plan',
  start: T.callJudy + s(0.25),
  done: T.judyDone,
  steps: [
    [T.callJudy + s(0.25), null, 'thinking'],
    [at(2.7), 'Read pricing.ts', 'reading'],
    [at(3.6), 'Read webhook.ts', 'reading'],
    [at(4.6), 'Grep isPro', 'searching'],
  ],
};
const FELIX: Agent = {
  who: 'beatnik',
  task: 'Write paywall tests',
  model: 'Sonnet 5.5',
  start: T.callFelix + s(0.25),
  done: T.felixDone,
  steps: [
    [T.callFelix + s(0.25), 'Edit paywall.test.ts', 'typing'],
    [at(7.6), 'Edit paywall.test.ts', 'typing'],
    [at(8.4), 'Bash npm test', 'running'],
  ],
};

// What the notes in pen say, and when.
const NOTES: readonly (readonly [from: number, to: number, text: string])[] = [
  [at(0.1), at(1), 'Sunny runs your session.'],
  [at(1.4), at(2.9), 'He phones Faye and Judy for help.'],
  [at(3), at(6.2), 'What we hold says what the agent is doing.'],
  [at(6.6), at(10.1), 'Felix writes the tests and runs them.'],
  [at(10.45), at(12.3), 'Sunny builds the paywall himself.'],
  [at(12.4), at(14.6), 'Done. Nothing running? Just a cup of coffee.'],
];

const AGENTS = [SUNNY, FAYE, JUDY, FELIX];
/** What the motion draws from, for the site to have ready before it plays. */
export const MASCOTS = [
  ...AGENTS.flatMap(({ who, steps }) => [
    `${who}-done.svg`,
    ...new Set([...steps.map(([, , thing]) => `${who}-${thing}-run.svg`), `${who}-thinking-run.svg`]),
  ]),
  'mug-0.svg',
  'mug-1.svg',
];

type File = (name: string) => string;

// A face as the app draws it, from the frame: a thing in hand six seconds of every eight, chin in
// hand with a thought coming the rest of the time or with nothing to hold, never bobbing, or eyes
// shut when done. `lag` keeps two faces off each other's beat.
export const Face: React.FC<{
  who: string;
  done?: boolean;
  holds?: Thing;
  size: number;
  f: number;
  lag?: number;
  file: File;
}> = ({ who, done, holds, size, f, lag = 0, file }) => {
  const tick = Math.floor((f + lag) / TICK);
  const img = (name: string, style?: React.CSSProperties) => (
    <Img
      src={file(`${who}-${name}.svg`)}
      style={{
        position: 'absolute',
        left: 0,
        top: 0,
        width: size,
        height: size,
        maxWidth: 'none',
        imageRendering: 'pixelated',
        ...style,
      }}
    />
  );
  const box: React.CSSProperties = {
    position: 'relative',
    flex: 'none',
    width: size,
    height: size,
  };
  if (done) return <div style={box}>{img('done')}</div>;
  const shown: Thing = holds && (f + lag) % HOLD < HOLD * 0.75 ? holds : 'thinking';
  const n = LOOP[shown];
  const step = (size * 13) / 12;
  return (
    <div style={{ ...box, overflow: 'hidden' }}>
      {img(`${shown}-run`, {
        width: step * n,
        translate: `${-(tick % n) * step}px 0`,
      })}
    </div>
  );
};

const Mug: React.FC<{ size: number; f: number; file: File }> = ({ size, f, file }) => (
  <Img
    src={file(`mug-${Math.floor(f / (2 * TICK)) % 2}.svg`)}
    style={{
      width: size,
      height: size,
      maxWidth: 'none',
      imageRendering: 'pixelated',
    }}
  />
);

const current = (steps: readonly Step[], f: number) => steps.reduce((at, step, i) => (step[0] <= f ? i : at), -1);

// The latest step, the one before it sliding up and out as the new one comes in.
const Ticker: React.FC<{ f: number; agent: Agent; counted?: boolean }> = ({ f, agent, counted }) => {
  const at = Math.min(f, agent.done);
  const i = current(agent.steps, at);
  if (i < 0) return null;
  const said = (j: number) => {
    const line = agent.steps[j][1];
    if (line === null) return <span style={{ color: DIM }}>thinking…</span>;
    const n = agent.steps.slice(0, j + 1).filter(([, l]) => l !== null).length;
    return `> ${line}${counted ? ` · ${n} step${n === 1 ? '' : 's'}` : ''}`;
  };
  const p = tween(at, agent.steps[i][0], agent.steps[i][0] + s(0.22));
  const row = (j: number, y: number, opacity: number) => (
    <div
      style={{
        position: 'absolute',
        left: 0,
        right: 0,
        top: 0,
        whiteSpace: 'nowrap',
        translate: `0 ${y * 1.5}em`,
        opacity,
      }}
    >
      {said(j)}
    </div>
  );
  return (
    <div
      style={{
        position: 'relative',
        height: '1.5em',
        overflow: 'hidden',
        flex: 1,
      }}
    >
      {i > 0 && p < 1 && row(i - 1, -p, 1 - p)}
      {row(i, 1 - p, p)}
    </div>
  );
};

// A little hop each time an agent takes up a new step, so the eye goes where the work moved.
const hop = (f: number, agent: Agent) => {
  const i = current(agent.steps, Math.min(f, agent.done));
  if (i <= 0) return 0;
  return interpolate(f - agent.steps[i][0], [0, s(0.08), s(0.24)], [0, -7, 0], {
    ...clamp,
    easing: Easing.out(Easing.quad),
  });
};

const Folder = () => (
  <svg
    viewBox="0 0 16 16"
    style={{
      width: '1em',
      height: '1em',
      marginRight: '.3em',
      fill: 'none',
      stroke: 'currentColor',
      strokeWidth: 1.5,
      strokeLinecap: 'round',
      strokeLinejoin: 'round',
    }}
  >
    <path d="M1.5 4.5v8a1 1 0 0 0 1 1h11a1 1 0 0 0 1-1v-6a1 1 0 0 0-1-1H8L6.5 3.5h-4a1 1 0 0 0-1 1zM4 7.6h8" />
  </svg>
);
const Branch = () => (
  <svg
    viewBox="0 0 16 16"
    style={{
      width: '1em',
      height: '1em',
      marginRight: '.3em',
      fill: 'none',
      stroke: 'currentColor',
      strokeWidth: 1.5,
      strokeLinecap: 'round',
      strokeLinejoin: 'round',
    }}
  >
    <path d="M8 14.3V9.9C8 7 9 5.4 11.2 3.9M8 9.9C8 7 7 5.4 4.8 3.9" />
    <path d="M14 1.8l-1.8 4-2.6-3.5zM2 1.8l1.8 4 2.6-3.5z" fill="currentColor" strokeWidth={1} />
  </svg>
);

// Text lines of a card or row: one line apart on a wide picture, wrapped onto the next on a tall one.
const Line: React.FC<{
  children: React.ReactNode;
  style?: React.CSSProperties;
}> = ({ children, style }) => (
  <div
    style={{
      display: 'flex',
      flexWrap: 'wrap',
      justifyContent: 'space-between',
      columnGap: 16,
      ...style,
    }}
  >
    {children}
  </div>
);
const nowrap: React.CSSProperties = { whiteSpace: 'nowrap' };

// The session's card: it drops out of the notch, works, and goes back up into it.
const Card: React.FC<{ l: Layout; f: number; file: File }> = ({ l, f, file }) => {
  const done = f >= T.done;
  const enter = pop(f, T.open);
  const leave = tween(f, T.close[0], T.close[1], 0, 1, swing);
  const i = current(SUNNY.steps, Math.min(f, T.done));
  return (
    <div
      style={{
        position: 'absolute',
        left: l.card.x,
        top: l.card.y,
        width: l.card.w,
        height: l.card.h,
        boxSizing: 'border-box',
        padding: '22px 26px',
        display: 'grid',
        gridTemplateColumns: `${l.card.face}px minmax(0,1fr)`,
        columnGap: 18,
        alignItems: 'start',
        borderRadius: 24,
        background: INK,
        color: FG,
        font: `400 ${l.card.font}px/1.5 ${APP}`,
        boxShadow: '0 30px 60px -30px rgba(0,0,0,.45)',
        transformOrigin: '50% 0',
        translate: `0 ${(1 - enter) * -50 - leave * 60}px`,
        scale: String(0.94 + 0.06 * enter - 0.06 * leave),
        opacity: Math.min(1, enter * 1.4) * (1 - leave),
      }}
    >
      <div style={{ paddingTop: 6, translate: `0 ${hop(f, SUNNY)}px` }}>
        <Face who="guru" done={done} holds={SUNNY.steps[i][2]} size={l.card.face} f={f} file={file} />
      </div>
      <div style={{ opacity: done ? 0.6 : 1 }}>
        <Line>
          <b style={{ fontWeight: 600, ...nowrap }}>{SUNNY.task}</b>
          <span style={{ ...nowrap, marginLeft: 'auto' }}>
            {done ? 'idle' : <span style={{ color: DIM }}>{elapsed(Math.floor(f / FPS))}</span>} <span style={{ color: DIM }}>{SUNNY.model}</span>
          </span>
        </Line>
        <div style={{ display: 'flex', alignItems: 'center', color: DIM }}>
          <Folder />
          <span style={{ marginRight: '1em' }}>{PROJECT}</span>
          <Branch />
          {BRANCH}
        </div>
        <div style={{ display: 'flex' }}>
          <Ticker f={f} agent={SUNNY} />
        </div>
      </div>
    </div>
  );
};

// A sub-agent's row at its desk: it drops in when phoned, shuts its eyes when done, and leaves.
const Row: React.FC<{
  l: Layout;
  agent: Agent;
  desk: Box;
  fold: number;
  f: number;
  lag: number;
  file: File;
}> = ({ l, agent, desk, fold, f, lag, file }) => {
  if (f < agent.start || f > fold + s(0.4)) return null;
  const done = f >= agent.done;
  const enter = pop(f, agent.start);
  const leave = tween(f, fold, fold + s(0.3));
  const i = current(agent.steps, Math.min(f, agent.done));
  const time = (
    <span style={{ ...nowrap, marginLeft: 'auto' }}>
      {done ? 'done' : <span style={{ color: DIM }}>{elapsed(Math.floor((f - agent.start) / FPS))}</span>} <span style={{ color: DIM }}>{agent.model}</span>
      {l.side && agent.type && <span style={{ color: DIM }}> · {agent.type}</span>}
    </span>
  );
  return (
    <div
      style={{
        position: 'absolute',
        left: desk.x,
        top: desk.y,
        width: desk.w,
        height: desk.h,
        boxSizing: 'border-box',
        padding: '0 24px',
        display: 'grid',
        gridTemplateColumns: `${l.row.face}px minmax(0,1fr)`,
        columnGap: 16,
        alignItems: 'center',
        borderRadius: 20,
        background: INK,
        color: FG,
        font: `400 ${l.row.font}px/1.5 ${APP}`,
        boxShadow: '0 24px 50px -28px rgba(0,0,0,.45)',
        transformOrigin: l.side ? '0 50%' : '50% 0',
        translate: l.side ? `${(1 - enter) * -30}px ${-leave * 30}px` : `0 ${(1 - enter) * -36 - leave * 40}px`,
        scale: String(0.9 + 0.1 * enter - 0.08 * leave),
        opacity: Math.min(1, enter * 1.4) * (1 - leave),
      }}
    >
      <div style={{ translate: `0 ${hop(f, agent)}px` }}>
        <Face who={agent.who} done={done} holds={agent.steps[i][2]} size={l.row.face} f={f} lag={lag} file={file} />
      </div>
      <div style={{ opacity: done ? 0.6 : 1 }}>
        <Line>
          <span style={nowrap}>{agent.task}</span>
          {time}
        </Line>
        <Line style={{ color: DIM, flexWrap: 'nowrap' }}>
          <Ticker f={f} agent={agent} counted />
          {!l.side && agent.type && <span style={nowrap}>{agent.type}</span>}
        </Line>
      </div>
    </div>
  );
};

// The line from the card down to a desk, drawn in pen: down the middle and across on a wide
// picture, down the left and in on a tall one.
type Points = readonly (readonly [number, number])[];
const wire = (l: Layout, desk: Box): Points => {
  const bottom = l.card.y + l.card.h;
  if (l.side) {
    const x = l.card.x + 22;
    const y = desk.y + desk.h / 2;
    return [
      [x, bottom],
      [x, y],
      [desk.x, y],
    ];
  }
  const x0 = l.card.x + l.card.w / 2;
  const mid = (bottom + desk.y) / 2;
  const x1 = desk.x + desk.w / 2;
  return [
    [x0, bottom],
    [x0, mid],
    [x1, mid],
    [x1, desk.y],
  ];
};
const along = (points: Points, t: number) => {
  const legs = points.slice(1).map((p, i) => Math.hypot(p[0] - points[i][0], p[1] - points[i][1]));
  let left = t * legs.reduce((a, b) => a + b, 0);
  for (let i = 0; i < legs.length; i++) {
    if (left <= legs[i] || i === legs.length - 1) {
      const k = legs[i] ? Math.min(1, left / legs[i]) : 0;
      return [points[i][0] + (points[i + 1][0] - points[i][0]) * k, points[i][1] + (points[i + 1][1] - points[i][1]) * k];
    }
    left -= legs[i];
  }
  return points[0];
};

// Who sits at which desk, when the line to it is drawn, and when it is taken away.
const SEATS = [
  { agent: FAYE, desk: 0, call: T.callFaye, fold: T.fold1, lag: 0 },
  { agent: JUDY, desk: 1, call: T.callJudy, fold: T.fold1, lag: s(1.2) },
  { agent: FELIX, desk: 0, call: T.callFelix, fold: T.fold2, lag: s(2.2) },
];

// The lines to the desks: the job runs down as one is drawn, and a dot carries the result back up
// when the agent is done.
const Wires: React.FC<{ l: Layout; f: number }> = ({ l, f }) => (
  <svg width={l.W} height={l.H} style={{ position: 'absolute', inset: 0, overflow: 'visible' }}>
    {SEATS.map(({ agent, desk, call, fold }) => {
      const run = s(0.3);
      const drawn = tween(f, call, call + run) - tween(f, fold, fold + run);
      if (drawn <= 0) return null;
      const points = wire(l, l.desks[desk]);
      const down = f < call + run ? tween(f, call, call + run) : -1;
      const up = tween(f, agent.done, agent.done + s(0.4), 0, 1, swing);
      const dot = down >= 0 ? along(points, down) : up > 0 && up < 1 ? along(points, 1 - up) : null;
      return (
        <g key={agent.who}>
          <path
            d={`M${points.map((p) => p.join(' ')).join(' L')}`}
            pathLength={1}
            fill="none"
            stroke={PEN}
            strokeWidth={3}
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeDasharray="1 1"
            strokeDashoffset={1 - drawn}
          />
          {dot && <circle cx={dot[0]} cy={dot[1]} r={8} fill={SIGNAL} stroke="#fff" strokeWidth={3} />}
        </g>
      );
    })}
  </svg>
);

// The notch with the bar beside it: who leads and what they hold, or a cup of coffee.
const Bar: React.FC<{ l: Layout; f: number; file: File }> = ({ l, f, file }) => {
  const idle = f >= T.done || f < s(0.1);
  const i = current(SUNNY.steps, f);
  const size = l.bar.h * 0.5;
  const wing = (child: React.ReactNode) => <div style={{ display: 'grid', placeItems: 'center', width: l.bar.h * 1.5 }}>{child}</div>;
  return (
    <div
      style={{
        position: 'absolute',
        left: l.bar.x,
        top: 0,
        width: l.bar.w,
        height: l.bar.h,
        display: 'flex',
        justifyContent: 'space-between',
        borderRadius: `0 0 ${l.bar.h * 0.42}px ${l.bar.h * 0.42}px`,
        background: INK,
      }}
    >
      {wing(idle ? <Mug size={l.bar.face} f={f} file={file} /> : <Face who="guru" holds={SUNNY.steps[i][2]} size={l.bar.face} f={f} file={file} />)}
      {wing(
        <span
          style={{
            width: size,
            height: size,
            borderRadius: '50%',
            background: 'conic-gradient(#fff 0 42%, #3a3a3c 42%)',
            WebkitMask: 'radial-gradient(circle, transparent 52%, #000 54%)',
            mask: 'radial-gradient(circle, transparent 52%, #000 54%)',
          }}
        />,
      )}
    </div>
  );
};

// A note in pen under the chart, written out left to right and lifted off when the next comes.
const Notes: React.FC<{ l: Layout; f: number }> = ({ l, f }) => {
  // They move down as the first line is drawn and back up once the last row leaves, between notes.
  const phoned = tween(f, T.callFaye, T.callFaye + s(0.45), 0, 1, swing) - tween(f, T.fold2, T.fold2 + s(0.45), 0, 1, swing);
  // On a tall picture Felix sits alone at the first desk, so the notes come up to him.
  const low = l.notes.low - tween(f, T.fold1, T.fold1 + s(0.45), 0, 1, swing) * (l.desks[1].y - l.desks[0].y);
  const top = l.notes.high + (low - l.notes.high) * phoned;
  return (
    <>
      {NOTES.map(([from, to, text]) => {
        if (f < from || f > to) return null;
        const write = tween(f, from, from + s(0.4), 0, 1, Easing.out(Easing.quad));
        const lift = tween(f, to - s(0.15), to);
        return (
          <div
            key={from}
            style={{
              position: 'absolute',
              left: 24,
              right: 24,
              top,
              textAlign: 'center',
              color: PEN,
              fontFamily: HAND,
              fontSize: l.notes.size,
              fontWeight: 600,
              lineHeight: 1.15,
              textWrap: 'balance',
              clipPath: `inset(0 ${(1 - write) * 100}% 0 0)`,
              opacity: 1 - lift,
              translate: `0 ${-lift * 10}px`,
            }}
          >
            {text}
          </div>
        );
      })}
    </>
  );
};

export const CrewMotion: React.FC<CrewMotionProps> = ({ base, tall, paper }) => {
  const f = useCurrentFrame();
  const l = tall ? TALL : WIDE;
  // On the site the crew sits in /mascots/; a render reads it from its public folder.
  const file = (name: string) => (base ? base + name : staticFile(`mascots/${name}`));
  return (
    <AbsoluteFill style={{ overflow: 'hidden', background: paper }}>
      <Wires l={l} f={f} />
      {SEATS.map((seat) => (
        <Row key={seat.agent.who} l={l} agent={seat.agent} desk={l.desks[seat.desk]} fold={seat.fold} f={f} lag={seat.lag} file={file} />
      ))}
      <Card l={l} f={f} file={file} />
      <Bar l={l} f={f} file={file} />
      <Notes l={l} f={f} />
    </AbsoluteFill>
  );
};
