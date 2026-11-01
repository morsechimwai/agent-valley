import { cn } from '@/lib/utils';

export type Person = 'guru' | 'walrus' | 'engineer' | 'pearls' | 'coder' | 'afro' | 'beatnik';
type Pose = 'work' | 'wave' | 'quiet' | 'done' | 'still';

// A mascot: the pose, and over it the pose it moves to. Quiet, done and still are one picture.
const FRAMES: Record<Pose, string[]> = {
  work: ['working', 'blink'],
  wave: ['wave0', 'wave1'],
  quiet: ['quiet'],
  done: ['done'],
  still: ['working'],
};

// What a working agent holds, by its open call, as the app draws it.
export type Thing = 'thinking' | 'reading' | 'typing' | 'running' | 'searching' | 'calling';
// Frames in each thing's strip: one loop, blinks included (SiteMascotsTests.loop).
const LOOP: Record<Thing, number> = { thinking: 24, reading: 8, typing: 8, running: 8, searching: 8, calling: 8 };

// Lazy by default: most of the crew is further down the page. On the first screen (`eager`) a picture
// loads at once and first in line: lazy, it came 0.7 s after the words on a slow line.
const fetching = (eager?: boolean) => (eager ? ({ fetchPriority: 'high' } as const) : ({ loading: 'lazy' } as const));

export function Mascot({ who, pose, holds, size, dot, eager, className }: { who: Person; pose: Pose; holds?: Thing; size?: string; dot?: boolean; eager?: boolean; className?: string }) {
  const style = size ? ({ '--s': size } as React.CSSProperties) : undefined;
  const load = fetching(eager);
  // Still: the thing in hand as the terminal draws it.
  if (holds && pose === 'still') {
    return <span className={cn('m', className)} style={style}><img src={`/mascots/${who}-${holds}.svg`} alt="" {...load} /></span>;
  }
  // At work: the thing in hand, moving, for six seconds, then two with it put down and a thought coming, as the app
  // does; with nothing to hold, the thought alone. Never bare and bobbing: that read as idle.
  if (pose === 'work') {
    const thing = holds === 'thinking' ? undefined : holds;
    const strip = (shown: Thing, part?: string) => (
      <span className={part} style={{ '--n': LOOP[shown] } as React.CSSProperties}>
        <img src={`/mascots/${who}-${shown}-run.svg`} alt="" {...load} />
      </span>
    );
    return <span className={cn('m holds', className)} style={style}>{strip('thinking', thing && 'bare')}{thing && strip(thing, 'strip')}</span>;
  }
  return (
    <span
      className={cn('m', pose === 'wave' && pose, className)}
      style={style}
    >
      {FRAMES[pose].map((frame) => <img key={frame} src={`/mascots/${who}-${frame}.svg`} alt="" {...load} />)}
      {dot && <i className="dot" />}
    </span>
  );
}

// Nothing running: a cup of coffee, steaming.
export function Mug({ eager, className }: { eager?: boolean; className?: string }) {
  const load = fetching(eager);
  return (
    <span className={cn('m steam', className)}>
      <img src="/mascots/mug-0.svg" alt="" {...load} />
      <img src="/mascots/mug-1.svg" alt="" {...load} />
    </span>
  );
}
