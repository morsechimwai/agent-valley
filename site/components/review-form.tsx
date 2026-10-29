'use client';

import { useEffect, useState } from 'react';
import { Button } from '@/components/ui/button';
import { TOKEN } from '@/lib/analytics';
import { cleanHandle, handleOk, MAX_WORDS, reviewBody, starsFromQuery, type HandleSite } from '@/lib/review';

// The review page's form and its live preview. It posts to PostHog's capture endpoint through
// /ingest, the way the app sends its events. The thank-you shows only on a 2xx.
const SITES: { id: HandleSite; label: string; on: string }[] = [
  { id: 'github', label: 'GitHub', on: 'on GitHub' },
  { id: 'x', label: 'X', on: 'on X' },
];
const field = 'w-full rounded-lg border border-foreground/60 bg-background px-3 font-mono text-base text-foreground';

export function ReviewForm() {
  const [stars, setStars] = useState(0);
  const [words, setWords] = useState('');
  const [name, setName] = useState('');
  const [site, setSite] = useState<HandleSite>('github');
  const [handleText, setHandleText] = useState('');
  const [show, setShow] = useState(false);
  const [state, setState] = useState<'idle' | 'sending' | 'failed' | 'sent'>('idle');
  useEffect(() => setStars(starsFromQuery(new URLSearchParams(location.search).get('stars')) ?? 0), []);

  const handle = cleanHandle(handleText, site);
  const badHandle = !handleOk(handle, site);
  const on = SITES.find((s) => s.id === site)!.on;
  const shownName = name.trim() || 'Your name';

  async function send(event: React.FormEvent) {
    event.preventDefault();
    if (state === 'sending') return;
    setState('sending');
    try {
      const body = reviewBody(TOKEN, { stars, words, name, handle, site, show }, crypto.randomUUID());
      const res = await fetch('/ingest/i/v0/e/', { method: 'POST', body: JSON.stringify(body) });
      setState(res.ok ? 'sent' : 'failed');
    } catch {
      setState('failed');
    }
  }

  if (state === 'sent')
    return (
      <p role="status" className="mt-12 max-w-[40ch] text-xl">
        Got it. We read these ourselves, over coffee. Thanks for taking the time.
        {show && ' If we put yours up, it will look like the card you saw.'}
      </p>
    );

  return (
    <div className="mt-12 grid items-start gap-12 min-[900px]:grid-cols-2">
      <form onSubmit={send} className="grid min-w-0 gap-6">
        <fieldset className="grid gap-2">
          <legend className="font-mono text-[.9375rem]">Stars</legend>
          <div className="flex gap-1">
            {[1, 2, 3, 4, 5].map((n) => (
              <button
                key={n}
                type="button"
                aria-label={`${n} star${n > 1 ? 's' : ''}`}
                aria-pressed={stars === n}
                onClick={() => setStars(n)}
                className="size-11 text-3xl leading-none"
                style={{ color: n <= stars ? 'var(--amber)' : 'var(--border)' }}
              >
                ★
              </button>
            ))}
          </div>
        </fieldset>

        <div className="grid gap-2">
          <label htmlFor="review-words" className="font-mono text-[.9375rem]">Your words</label>
          <textarea
            id="review-words"
            required
            rows={5}
            maxLength={MAX_WORDS}
            value={words}
            onChange={(e) => setWords(e.target.value)}
            className={`${field} py-2`}
          />
          {words.length > MAX_WORDS - 100 && (
            <p className="font-mono text-sm text-muted-foreground">{words.length} of {MAX_WORDS}</p>
          )}
        </div>

        <div className="grid gap-2">
          <label htmlFor="review-name" className="font-mono text-[.9375rem]">Name{show ? '' : ' (only if you tick the box below)'}</label>
          <input id="review-name" required={show} maxLength={60} autoComplete="name" value={name} onChange={(e) => setName(e.target.value)} className={`${field} h-12`} />
        </div>

        <div className="grid gap-2">
          <label htmlFor="review-handle" className="font-mono text-[.9375rem]">Account (optional)</label>
          <div role="radiogroup" aria-label="Account site" className="flex gap-2">
            {SITES.map((s) => (
              <button
                key={s.id}
                type="button"
                role="radio"
                aria-checked={site === s.id}
                onClick={() => setSite(s.id)}
                className={`h-10 rounded-lg border border-foreground/60 px-4 font-mono text-sm ${site === s.id ? 'bg-primary text-primary-foreground' : 'bg-background'}`}
              >
                {s.label}
              </button>
            ))}
          </div>
          <input
            id="review-handle"
            value={handleText}
            onChange={(e) => setHandleText(e.target.value)}
            autoComplete="off"
            aria-invalid={badHandle}
            aria-describedby="review-handle-note"
            className={`${field} h-12`}
          />
          <p id="review-handle-note" className="font-mono text-sm text-muted-foreground">
            {badHandle
              ? site === 'github' ? 'GitHub names are letters, digits and dashes, up to 39.' : 'X names are letters, digits and underscores, up to 15.'
              : 'A name or a profile link both work.'}
          </p>
        </div>

        <div className="grid gap-1">
          <label className="flex items-start gap-3">
            <input type="checkbox" checked={show} onChange={(e) => setShow(e.target.checked)} className="mt-1 size-5 shrink-0 accent-[var(--primary)]" />
            <span>OK to show this on agentvalley.app with my name.</span>
          </label>
          <p className="pl-8 font-mono text-sm text-muted-foreground">Leave it unticked and we still read it, privately and without your name.</p>
        </div>

        <div className="grid gap-2">
          <Button
            type="submit"
            disabled={state === 'sending' || stars === 0 || badHandle || words.trim() === '' || (show && name.trim() === '')}
            className="h-12 justify-self-start rounded-lg px-5 font-mono text-base font-semibold text-primary-foreground hover:bg-primary/85"
          >
            {state === 'sending' ? 'Sending' : state === 'failed' ? 'Try again' : 'Send'}
          </Button>
          {stars === 0 && <p className="font-mono text-sm text-muted-foreground">Pick your stars first.</p>}
          {state === 'failed' && (
            <p role="status" className="font-mono text-[.9375rem] font-semibold text-destructive">
              That didn&apos;t go through, and what you wrote is still here. Try again, or mail it to hello@agentvalley.app.
            </p>
          )}
        </div>
      </form>

      <aside aria-label="Preview" className="grid min-w-0 gap-3">
        <h2 className="font-mono text-[.9375rem] font-normal">How it would look on our site</h2>
        <figure className={`m-0 grid gap-3 rounded-xl border border-border bg-card p-5 ${show ? '' : 'opacity-60'}`} data-testid="preview">
          <div aria-label={stars ? `${stars} out of 5 stars` : 'No stars yet'} style={{ color: 'var(--amber)' }} className="text-xl tracking-wide">
            {'★'.repeat(stars)}
            <span style={{ color: 'var(--border)' }}>{'★'.repeat(5 - stars)}</span>
          </div>
          <blockquote className="m-0 break-words">&ldquo;{words.trim() || 'What you write shows up here.'}&rdquo;</blockquote>
          <figcaption className="flex items-center gap-3">
            <span aria-hidden="true" className="grid size-10 shrink-0 place-items-center rounded-full bg-accent font-semibold">
              {shownName[0].toUpperCase()}
            </span>
            <span className="min-w-0 break-words">
              <b>{shownName}</b>
              {handle && !badHandle && <span className="block text-sm text-accent-text">@{handle} {on}</span>}
            </span>
          </figcaption>
        </figure>
        {!show && <p className="font-mono text-sm text-muted-foreground">Dimmed because it stays private unless you tick the box.</p>}
      </aside>
    </div>
  );
}
