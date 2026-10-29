'use client';

import Lenis from 'lenis';
import { useEffect } from 'react';

// How much of what is left the wheel's glide covers each frame (1 = no glide): at 0.18 a turn is
// 90% there in about 0.2 s.
const LERP = 0.18;
// cubic-bezier(x1, y1, x2, y2) as CSS draws it: the curve's x found by halving, its y returned.
const bezier = (x1: number, y1: number, x2: number, y2: number) => {
  const at = (a: number, b: number, s: number) => 3 * a * s * (1 - s) ** 2 + 3 * b * s ** 2 * (1 - s) + s ** 3;
  return (t: number) => {
    let lo = 0;
    let hi = 1;
    for (let i = 0; i < 20; i++) {
      const s = (lo + hi) / 2;
      if (at(x1, x2, s) < t) lo = s;
      else hi = s;
    }
    return at(y1, y2, (lo + hi) / 2);
  };
};
// A link to a part of the page: there in 0.75 s on Material 3's standard curve, a short speed-up
// and a long ease in, so the page moves the moment it is clicked (16% of the way in the first
// tenth of the time) without a jolt.
const LINK_TRIP = { duration: 0.75, easing: bezier(0.2, 0, 0, 1) };

// The mouse wheel glides and links to a part of the page travel there (Lenis). The page itself
// still scrolls, so every scroll listener keeps reading scrollY as before. Touch, keys and the
// scrollbar stay the browser's own: a press, a key or Back drops what is still gliding, so a
// click, an arrow key or the page before does what it says. Reduce Motion and the Stop button
// leave the wheel to the browser and make a link jump.
export function SmoothScroll() {
  useEffect(() => {
    const html = document.documentElement;
    const reduce = matchMedia('(prefers-reduced-motion: reduce)');
    const still = () => reduce.matches || html.classList.contains('still');
    const lenis = new Lenis({ autoRaf: true, lerp: LERP, virtualScroll: () => !still() });
    // Stopped and started again: Lenis's public way to drop a glide where it is.
    const drop = () => {
      lenis.stop();
      lenis.start();
    };
    // The #part the last trip's own click goes to; none is null, as '' is the page with no #part.
    let own: string | null = null;
    // A plain click on a link to this page's #part. The browser still follows the link (the
    // address, Back, :target), and Lenis's first frame takes over its scroll.
    const trip = (e: MouseEvent) => {
      const a = (e.target as Element).closest?.('a');
      if (!a?.hash || a.origin !== location.origin || a.pathname !== location.pathname) return;
      if (e.defaultPrevented || e.button || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey || still()) return;
      own = a.hash;
      lenis.scrollTo(decodeURIComponent(a.hash), LINK_TRIP);
    };
    // Back or Forward. A link to a #part fires popstate too, and must not stop its own trip.
    const moved = () => {
      if (location.hash !== own) drop();
      own = null;
    };
    const on = ['pointerdown', 'keydown'];
    for (const type of on) addEventListener(type, drop);
    addEventListener('popstate', moved);
    addEventListener('click', trip);
    return () => {
      for (const type of on) removeEventListener(type, drop);
      removeEventListener('popstate', moved);
      removeEventListener('click', trip);
      lenis.destroy();
    };
  }, []);
  return null;
}
