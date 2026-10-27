// The app's own icons, drawn once on the page and used by name.
export type IconId = 'folder' | 'branch' | 'out' | 'eyeoff' | 'speaker' | 'pin' | 'help' | 'left' | 'right' | 'pause' | 'play' | 'back' | 'gear' | 'chart' | 'doc' | 'clear';

export function IconSprite() {
  return (
    <svg className="defs" aria-hidden="true">
      <symbol id="i-folder" viewBox="0 0 16 16"><path d="M1.5 4.5v8a1 1 0 0 0 1 1h11a1 1 0 0 0 1-1v-6a1 1 0 0 0-1-1H8L6.5 3.5h-4a1 1 0 0 0-1 1zM4 7.6h8"/></symbol>
      <symbol id="i-branch" viewBox="0 0 16 16"><path d="M8 14.3V9.9C8 7 9 5.4 11.2 3.9M8 9.9C8 7 7 5.4 4.8 3.9"/><path d="M14 1.8l-1.8 4-2.6-3.5zM2 1.8l1.8 4 2.6-3.5z" fill="currentColor" strokeWidth="1"/></symbol>
      <symbol id="i-out" viewBox="0 0 16 16"><path d="M5 11l6-6M6.5 5H11v4.5"/></symbol>
      <symbol id="i-eyeoff" viewBox="0 0 16 16"><path d="M1.5 8s2.5-4.5 6.5-4.5S14.5 8 14.5 8 12 12.5 8 12.5 1.5 8 1.5 8z"/><circle cx="8" cy="8" r="2"/><path d="M2.5 13.5l11-11"/></symbol>
      <symbol id="i-speaker" viewBox="0 0 16 16"><path d="M2.5 6h2.5L8.5 3v10L5 10H2.5zM11 5.6a3.2 3.2 0 0 1 0 4.8M13 3.7a6 6 0 0 1 0 8.6"/></symbol>
      <symbol id="i-pin" viewBox="0 0 16 16"><path d="M6 2h4l-.5 4 2 2.5h-7l2-2.5zM8 8.5v6"/></symbol>
      <symbol id="i-help" viewBox="0 0 16 16" strokeWidth="2"><path d="M5.6 5.8a2.4 2.4 0 1 1 3.4 2.2c-.7.4-1 .9-1 1.6v.4"/><path d="M8 13v.1"/></symbol>
      <symbol id="i-left" viewBox="0 0 16 16"><path d="M10 3L5 8l5 5"/></symbol>
      <symbol id="i-right" viewBox="0 0 16 16"><path d="M6 3l5 5-5 5"/></symbol>
      <symbol id="i-pause" viewBox="0 0 16 16" strokeWidth="2"><path d="M5.5 3.5v9M10.5 3.5v9"/></symbol>
      <symbol id="i-play" viewBox="0 0 16 16"><path d="M5 3.5l7.5 4.5L5 12.5z"/></symbol>
      <symbol id="i-back" viewBox="0 0 16 16"><path d="M13.5 8h-11M6.5 4l-4 4 4 4"/></symbol>
      <symbol id="i-doc" viewBox="0 0 16 16"><path d="M9.5 1.5h-6v13h9V4.5zM9.5 1.5v3h3M8 7v5M5.8 9.8L8 12l2.2-2.2"/></symbol>
      <symbol id="i-clear" viewBox="0 0 16 16"><circle cx="8" cy="8" r="6.5" fill="currentColor" stroke="none"/><path d="M5.9 5.9l4.2 4.2M10.1 5.9l-4.2 4.2" stroke="var(--ink)" strokeWidth="1.6"/></symbol>
      <symbol id="i-chart" viewBox="0 0 16 16"><path d="M2 13.5h12M4.5 11V8M8 11V3.5M11.5 11V6"/></symbol>
      <symbol id="i-gear" viewBox="0 0 16 16"><circle cx="8" cy="8" r="2.2"/><path d="M6.09 3.38L6.74 1.52H9.26L9.91 3.38L11.69 2.53L13.47 4.31L12.62 6.09L14.48 6.74V9.26L12.62 9.91L13.47 11.69L11.69 13.47L9.91 12.62L9.26 14.48H6.74L6.09 12.62L4.31 13.47L2.53 11.69L3.38 9.91L1.52 9.26V6.74L3.38 6.09L2.53 4.31L4.31 2.53z"/></symbol>
    </svg>
  );
}

export function Icon({ id, className }: { id: IconId; className?: string }) {
  return (
    <svg className={className ? `i ${className}` : 'i'} aria-hidden="true">
      <use href={`#i-${id}`} />
    </svg>
  );
}
