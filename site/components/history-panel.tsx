'use client';

import { useEffect, useId, useRef, useState } from 'react';
import { announce } from '@/components/announcer';
import { Icon } from '@/components/icons';
import { DAYS, historyView, MONTHS, nextPick, openAt, weekStart, type Action, type Bars, type Pick, type Split } from '@/lib/history';

const SPANS = ['Day', 'Week', 'Month'] as const;

// The app's short names (WCAG 3.1.4): on screen each is spelled out where the pointer rests, and
// what a screen reader is given has them in full.
const FULL = new Map([...MONTHS, ...DAYS].map((w) => [w.slice(0, 3), w]));
FULL.set('API', 'application programming interface');
const SHORT = new RegExp(`\\b(${[...FULL.keys()].join('|')})\\b`, 'g');
const spell = (text: string) =>
  text.split(SHORT).map((part, i) => (i % 2 && FULL.get(part) !== part ? <abbr key={i} title={FULL.get(part)}>{part}</abbr> : part));
const aloud = (text: string) => text.replace(SHORT, (w) => (w === 'API' ? w : FULL.get(w)!));

// History as the app draws it, on the reader's own calendar. Drawn only once the page runs on the
// reader's machine: built ahead of time it would show the build day's numbers. Without scripts the
// figure stays hidden.
export function HistoryPanel() {
  const hist = useRef<HTMLDivElement>(null);
  const id = useId();
  const [now, setNow] = useState<Date | null>(null);
  const [pick, setPick] = useState<Pick | null>(null);
  // `want`: the button that keeps the keyboard when the one pressed is gone.
  const refocus = useRef<{ had: string | undefined; want: string } | null>(null);

  useEffect(() => {
    const at = new Date();
    setNow(at);
    setPick({ span: 'Month', anchor: openAt(at), project: null, day: null, hour: null, first: weekStart(navigator.language) });
  }, []);

  useEffect(() => {
    const r = refocus.current;
    const box = hist.current;
    refocus.current = null;
    if (!r?.had || !box) return;
    const find = (selector: string) => box.querySelector<HTMLElement>(selector);
    (find(`[data-k="${r.had}"]:not(:disabled)`) || find(`[data-k="${r.want}"]`) || find('.h-step:not(:disabled)') || box).focus();
  }, [pick]);

  const view = now && pick ? historyView(pick, now) : null;

  // `say`: off where the screen reader reads the change itself.
  function act(action: Action, want: string, say = true) {
    if (!now || !pick) return;
    const active = document.activeElement as HTMLElement | null;
    refocus.current = { had: hist.current?.contains(active) ? active?.dataset.k : undefined, want };
    const next = nextPick(pick, action);
    setPick(next);
    if (say) announce(aloud(historyView(next, now).announce));
  }
  const click = (action: Action) => act(action, action.a === 'project' ? 'up' : `p-${pick?.project}`);

  // The bars, as the app has them: the pointer picks one, and from the keyboard the arrows walk
  // them, picking as they go, read out as a list. Escape lets go.
  const bars = (b: Bars) => {
    const live = b.list.filter((bar) => !bar.future);
    const at = live.findIndex((bar) => bar.key === b.picked);
    const key = (e: React.KeyboardEvent) => {
      if (e.key === 'Escape' && b.picked !== null) {
        e.preventDefault();
        act({ a: b.kind, v: '' }, `bars-${b.kind}`, false);
        return;
      }
      const to = ({ ArrowRight: at + 1, ArrowDown: at + 1, ArrowLeft: at < 0 ? live.length - 1 : at - 1, ArrowUp: at < 0 ? live.length - 1 : at - 1, Home: 0, End: live.length - 1 } as Record<string, number>)[e.key];
      if (to === undefined) return;
      e.preventDefault();
      const bar = live[Math.max(0, Math.min(live.length - 1, to))];
      if (bar.key !== b.picked) act({ a: b.kind, v: String(bar.key) }, `bars-${b.kind}`, false);
    };
    return (
      <>
        <div
          className={`h-bars${b.small ? ' hours' : ''}${b.picked !== null ? ' picking' : ''}`}
          role="listbox"
          aria-label={b.kind === 'day' ? 'Days' : 'Hours'}
          tabIndex={0}
          data-k={`bars-${b.kind}`}
          aria-activedescendant={at < 0 ? undefined : `${id}${b.kind}${b.picked}`}
          onKeyDown={key}
          // A click picks without taking the keyboard there: the page says what was picked, once.
          onMouseDown={(e) => e.preventDefault()}
        >
          {b.list.map((bar) =>
            bar.future ? (
              <span key={bar.key} className="future" aria-hidden="true"><i style={{ height: '2px' }} /></span>
            ) : (
              <span
                key={bar.key}
                id={`${id}${b.kind}${bar.key}`}
                role="option"
                aria-selected={bar.key === b.picked}
                aria-label={aloud(`${bar.label}, ${bar.price}`)}
                data-a={b.kind}
                className={bar.key === b.picked ? 'on' : undefined}
                title={`${bar.label}, ${bar.price}`}
                onClick={() => click({ a: b.kind, v: String(bar.key) })}
              >
                <i style={{ height: bar.height }} />
              </span>
            ),
          )}
        </div>
        <div className="h-axis" aria-hidden="true"><span>{spell(b.list[0].label)}</span><span>{spell(b.list[b.list.length - 1].label)}</span></div>
      </>
    );
  };

  const split = (s: Split | null) =>
    s && (
      <div className="h-split">
        <p aria-hidden="true">{s.parts.map((part, i) => <i key={i} style={{ flex: part.flex, background: part.color }} />)}</p>
        <span>{s.text}</span>
      </div>
    );

  const rows = view && (
    <>
      <h3 className="h-head">{view.rows.kind}</h3>
      <div className="h-list">
        {view.rows.kind === 'PROJECTS'
          ? view.rows.list.map((r) => (
              <button
                key={r.key}
                type="button"
                data-k={`p-${r.key}`}
                aria-label={`${r.name}, ${r.price}`}
                onClick={() => click({ a: 'project', v: String(r.key) })}
              >
                <b>{r.name}</b>
                <Icon id="right" />
                <span className="v">{r.price}</span>
              </button>
            ))
          : view.rows.list.map((r) => (
              <p key={r.key}><b>{r.name}</b><span className="v">{r.price}</span></p>
            ))}
      </div>
    </>
  );

  return (
    <figure hidden={!view}>
      <div className="hist" role="group" aria-label="The History page" tabIndex={-1} ref={hist}>
        {view && (
          <>
            <div className="h-top">
              {/* The agents are the panel at the top of this page, and what Export PDF makes is the
                  next section down. */}
              {view.project === null ? (
                <a className="h-back" href="#top"><Icon id="back" />Agents</a>
              ) : (
                <button type="button" className="h-back" data-k="up" onClick={() => click({ a: 'up', v: '' })}>
                  <Icon id="back" />All projects
                </button>
              )}
              <a className="h-pdf" href="#report"><Icon id="doc" />Export PDF</a>
              <div className="h-seg" role="group" aria-label="Span">
                {SPANS.map((s) => (
                  <button key={s} type="button" data-k={`span-${s}`} aria-pressed={s === view.span} onClick={() => click({ a: 'span', v: s })}>
                    {s}
                  </button>
                ))}
              </div>
            </div>
            <div className="h-stretch">
              <button type="button" className="h-step" data-k="earlier" aria-label="Earlier" disabled={!view.canEarlier} onClick={() => click({ a: 'step', v: '-1' })}>
                <Icon id="left" />
              </button>
              <span className="h-title">{spell(view.title)}</span>
              <button type="button" className="h-step" data-k="later" aria-label="Later" disabled={!view.canLater} onClick={() => click({ a: 'step', v: '1' })}>
                <Icon id="right" />
              </button>
              <span className="h-total"><b>{view.total}</b><span className="h-small">at API prices</span></span>
            </div>
            {view.project !== null && <div className="h-name">{view.project}</div>}
            {bars(view.bars)}
            {view.pickLine && (
              <p className="h-pick">
                <span>{spell(view.pickLine.text)}</span>
                <button type="button" className="h-clear" data-k="clear" aria-label={aloud(view.pickLine.label)} onClick={() => act(view.pickLine!.clear, `bars-${view.bars.kind}`)}>
                  <Icon id="clear" />
                </button>
              </p>
            )}
            {view.hourBars && bars(view.hourBars)}
            {view.quiet && <p className="h-quiet">No token use in this period.</p>}
            {view.project === null ? <>{split(view.models)}{split(view.agents)}{rows}</> : <>{rows}{split(view.models)}{split(view.agents)}</>}
            <p className="h-foot">{spell(view.since)}</p>
          </>
        )}
      </div>
      <figcaption className="font-mono text-sm text-muted-foreground">Click around. The numbers are made up.</figcaption>
    </figure>
  );
}
