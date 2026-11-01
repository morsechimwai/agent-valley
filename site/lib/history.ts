// History as the app draws it. The numbers are made up but the same on every visit, on the
// reader's own calendar: three months of them, up to now.

export type Span = 'Day' | 'Week' | 'Month';
// `first`: the day a week starts on, 0 for Sunday, as the reader's region has it.
export type Pick = { span: Span; anchor: Date; project: number | null; day: Date | null; hour: number | null; first: number };
export type Action = { a: 'span' | 'step' | 'day' | 'hour' | 'project' | 'up'; v: string };

export type Bar = { key: number; label: string; price: string; height: string; future: boolean };
export type Bars = { kind: 'day' | 'hour'; list: Bar[]; picked: number | null; small: boolean };
export type Split = { parts: { flex: number; color: string }[]; text: string };
export type Row = { key: number | string; name: string; price: string };
export type HistoryView = {
  span: Span;
  project: string | null;
  title: string;
  total: string;
  canEarlier: boolean;
  canLater: boolean;
  bars: Bars;
  hourBars: Bars | null;
  // The orange line under the bars once one is picked; its ✕ lets go of an hour, then of the day.
  pickLine: { text: string; clear: Action; label: string } | null;
  models: Split | null;
  agents: Split | null;
  quiet: boolean;
  rows: { kind: 'PROJECTS' | 'SESSIONS'; list: Row[] };
  since: string;
  announce: string;
};

export const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
export const DAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
// Short, as the app writes them; the page spells each one out (components/history-panel.tsx).
const mon = (d: Date) => MONTHS[d.getMonth()].slice(0, 3);
const hh = (h: number) => String(h).padStart(2, '0') + ':00';
const cents = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' });
const whole = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', maximumFractionDigits: 0 });
export const dollars = (v: number) => (v > 0 && v < 0.005 ? '<$0.01' : cents.format(v));
export const wholeDollars = (v: number) => (v > 0 && v < 0.5 ? '<$1' : whole.format(v));

export const PROJECTS = [
  { name: 'shop-web', busy: 1, models: { 'Opus 5.5': 0.82, 'Sonnet 5.5': 0.15, 'Haiku 5.5': 0.03 }, agents: { main: 0.76, Explore: 0.16, Plan: 0.08 },
    sessions: ['Refactor checkout flow', 'Deploy preview build', 'Fix coupon rounding', 'Add Apple Pay to checkout'] },
  { name: 'api', busy: 0.7, models: { 'Opus 5.5': 0.6, 'Sonnet 5.5': 0.4 }, agents: { main: 0.86, Explore: 0.14 },
    sessions: ['Rate limits for the public API', 'Move auth to sessions', 'Fix the slow orders query'] },
  { name: 'mobile-app', busy: 0.45, models: { 'Sonnet 5.5': 0.9, 'Haiku 5.5': 0.1 }, agents: { main: 0.9, 'general-purpose': 0.1 },
    sessions: ['Push notifications on Android', 'Offline cart'] },
  { name: 'docs', busy: 0.25, models: { 'Sonnet 5.5': 0.7, 'Haiku 5.5': 0.3 }, agents: { main: 1 },
    sessions: ['Rewrite the install guide', 'API reference from OpenAPI'] },
];

// The same made-up number for the same project, day and hour, on every visit.
export function noise(...keys: number[]): number {
  let h = 2166136261;
  for (const k of keys) { h = Math.imul(h ^ k, 16777619); h ^= h >>> 13; }
  h = Math.imul(h, 1540483477); h ^= h >>> 15;
  return (h >>> 0) / 4294967296;
}

// The day a week starts on where `lang` is spoken, 0 for Sunday: the app takes the Mac's.
export function weekStart(lang: string): number {
  try {
    const l = new Intl.Locale(lang) as Intl.Locale & { getWeekInfo?: () => { firstDay: number }; weekInfo?: { firstDay: number } };
    return ((l.getWeekInfo?.() ?? l.weekInfo)?.firstDay ?? 1) % 7;
  } catch {
    return 1;
  }
}

// Where the page opens. The app opens on this month, but in a month's first week that is a few
// bars or none, so the page opens on the last day of the month before, a whole month of them.
export const openAt = (now: Date) => now.getDate() < 8 ? new Date(now.getFullYear(), now.getMonth(), 0) : now;

export const startOf = (span: Span, d: Date, first: number) => span === 'Month' ? new Date(d.getFullYear(), d.getMonth(), 1)
  : new Date(d.getFullYear(), d.getMonth(), d.getDate() - (span === 'Week' ? (d.getDay() - first + 7) % 7 : 0));
export const step = (span: Span, d: Date, by: number) => span === 'Month' ? new Date(d.getFullYear(), d.getMonth() + by, 1)
  : new Date(d.getFullYear(), d.getMonth(), d.getDate() + by * (span === 'Week' ? 7 : 1));
const daysIn = (start: Date, end: Date) => {
  const out: Date[] = [];
  for (let d = start; d < end; d = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1)) out.push(d);
  return out;
};
const dayTitle = (d: Date) => `${mon(d)} ${d.getDate()}`;
export function spanTitle(span: Span, start: Date, end: Date): string {
  if (span === 'Month') return `${MONTHS[start.getMonth()]} ${start.getFullYear()}`;
  if (span === 'Day') return `${DAYS[start.getDay()].slice(0, 3)}, ${dayTitle(start)}, ${start.getFullYear()}`;
  const last = new Date(end.getFullYear(), end.getMonth(), end.getDate() - 1);
  return `${dayTitle(start)} – ${last.getMonth() === start.getMonth() ? last.getDate() : dayTitle(last)}, ${last.getFullYear()}`;
}

type Spend = { cost: number; session: string };
type Hour = Spend & { p: number };
const sum = (list: { cost: number }[]) => list.reduce((total, x) => total + x.cost, 0);
const lines = <K>(list: Hour[], key: (x: Hour) => [K, number][]) => {
  const by = new Map<K, number>();
  for (const x of list) for (const [name, share] of key(x)) by.set(name, (by.get(name) || 0) + x.cost * share);
  return [...by].map(([name, cost]) => ({ name, cost })).filter((l) => l.cost > 0).sort((a, b) => b.cost - a.cost);
};
// By place, as the app: the mascots' amber glass, the mug's cream, a warm grey for the rest.
const PARTS = ['var(--part1)', 'var(--part2)', 'var(--part3)'];
const split = (all: { name: string; cost: number }[]): Split | null => {
  if (!all.length) return null;
  const shown = all.length > 3 ? [...all.slice(0, 2), { name: 'others', cost: sum(all.slice(2)) }] : all;
  const total = sum(shown);
  return {
    parts: shown.map((l, i) => ({ flex: l.cost / total, color: PARTS[Math.min(i, PARTS.length - 1)] })),
    text: shown.map((l) => `${l.name} ${wholeDollars(l.cost)}`).join(' · '),
  };
};

export function historyView(pick: Pick, now: Date): HistoryView {
  const since = new Date(now.getFullYear(), now.getMonth() - 2, 1);
  const spent = new Map<string, Spend[]>();
  // What a project spent in each hour of a day, and on which of its sessions.
  const dayOf = (p: number, day: Date) => {
    const n = Date.UTC(day.getFullYear(), day.getMonth(), day.getDate()) / 864e5;
    if (!spent.has(p + ':' + n)) {
      const weekend = day.getDay() % 6 === 0;
      const on = noise(p, n, 1) < PROJECTS[p].busy * (weekend ? 0.35 : 1);
      const scale = (3 + 9 * noise(p, n, 2)) * PROJECTS[p].busy;
      const list = PROJECTS[p].sessions, first = Math.floor((n + p * 2) / 3) % list.length;
      const split = noise(p, n, 3) < 0.4;
      spent.set(p + ':' + n, Array.from({ length: 24 }, (_, h) => {
        const at = new Date(day.getFullYear(), day.getMonth(), day.getDate(), h);
        const work = h >= 9 && h < 19 ? 1 : h >= 19 && h < 23 ? 0.35 : 0;
        const cost = on && work && at >= since && at <= now && noise(p, n, h + 10) < 0.75 ? Math.round(scale * work * (0.3 + noise(p, n, h + 40)) * 100) / 100 : 0;
        return { cost, session: list[(first + (split && h >= 14 ? 1 : 0)) % list.length] };
      }));
    }
    return spent.get(p + ':' + n)!;
  };
  // Every hour of the days given, of the project picked or of all of them.
  const hours = (days: Date[], project: number | null, hour: number | null) => {
    const out: Hour[] = [];
    for (const day of days) for (let p = 0; p < PROJECTS.length; p++) {
      if (project !== null && p !== project) continue;
      dayOf(p, day).forEach((spend, h) => { if (spend.cost && (hour === null || h === hour)) out.push({ p, ...spend }); });
    }
    return out;
  };
  type Raw = { key: number; cost: number; future: boolean; label: string };
  const bars = (list: Raw[], picked: number | null, kind: 'day' | 'hour', small: boolean): Bars => {
    const top = Math.max(...list.map((b) => b.cost));
    return {
      kind, picked, small,
      list: list.map((b) => ({
        key: b.key, label: b.label, price: dollars(b.cost), future: b.future,
        height: b.future || !top ? '2px' : `max(2px,${(b.cost / top) * 100}%)`,
      })),
    };
  };
  const hourBars = (day: Date): Raw[] => Array.from({ length: 24 }, (_, h) => {
    const at = new Date(day.getFullYear(), day.getMonth(), day.getDate(), h);
    return { key: h, cost: sum(hours([day], pick.project, h)), future: at > now, label: hh(h) };
  });

  const { span, project } = pick;
  const start = startOf(span, pick.anchor, pick.first), end = step(span, start, 1);
  const days = daysIn(start, end);
  const title = spanTitle(span, start, end);
  const all = hours(days, project, null);
  const focus = hours(pick.day ? [pick.day] : days, project, pick.hour);
  const picked = pick.hour !== null || pick.day !== null;
  const pickDay = pick.day || start;
  const pickTitle = pick.hour !== null ? `${dayTitle(pickDay)}, ${hh(pick.hour)}` : pick.day ? dayTitle(pick.day) : '';
  const daily = span === 'Day' ? hourBars(start)
    : days.map((d) => ({ key: d.getTime(), cost: sum(hours([d], project, null)), future: d > now, label: dayTitle(d) }));
  const rows = project === null
    ? { kind: 'PROJECTS' as const, list: lines(focus, (x) => [[x.p, 1]]).map((r) => ({ key: r.name, name: PROJECTS[r.name].name, price: dollars(r.cost) })) }
    : { kind: 'SESSIONS' as const, list: lines(focus, (x) => [[x.session, 1]]).map((r) => ({ key: r.name, name: r.name, price: dollars(r.cost) })) };
  return {
    span,
    project: project === null ? null : PROJECTS[project].name,
    title,
    total: dollars(sum(all)),
    canEarlier: start > since,
    canLater: end <= now,
    bars: bars(daily, span === 'Day' ? pick.hour : pick.day && pick.day.getTime(), span === 'Day' ? 'hour' : 'day', false),
    hourBars: span !== 'Day' && pick.day ? bars(hourBars(pick.day), pick.hour, 'hour', true) : null,
    pickLine: picked ? {
      text: `${pickTitle} · ${dollars(sum(focus))}`,
      clear: pick.hour !== null ? { a: 'hour', v: '' } : { a: 'day', v: '' },
      label: `Show all of ${pick.hour !== null && pick.day ? dayTitle(pick.day) : title}`,
    } : null,
    models: split(lines(focus, (x) => Object.entries(PROJECTS[x.p].models))),
    agents: split(lines(focus, (x) => Object.entries(PROJECTS[x.p].agents))),
    quiet: !focus.length,
    rows,
    since: `History since ${dayTitle(since)}, ${since.getFullYear()} · API prices as of Oct 15, 2026`,
    announce: `${title}${project !== null ? ', ' + PROJECTS[project].name : ''}, ${dollars(sum(all))}${picked ? `; ${pickTitle}, ${dollars(sum(focus))}` : ''}`,
  };
}

// A bar clicked twice lets go, and so does an empty value, the pick line's ✕.
export function nextPick(pick: Pick, { a, v }: Action): Pick {
  const start = startOf(pick.span, pick.anchor, pick.first);
  if (a === 'span') return { ...pick, span: v as Span, anchor: pick.day || pick.anchor, day: null, hour: null };
  if (a === 'step') return { ...pick, anchor: step(pick.span, start, +v), day: null, hour: null };
  if (a === 'day') return { ...pick, day: v === '' || (pick.day && pick.day.getTime() === +v) ? null : new Date(+v), hour: null };
  if (a === 'hour') return { ...pick, hour: v === '' || pick.hour === +v ? null : +v };
  if (a === 'project') return { ...pick, project: +v };
  return { ...pick, project: null };
}
