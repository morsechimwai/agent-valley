import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { expect, test } from 'vitest';

// Every text colour on the page is held to WCAG AAA, 7:1, against each surface it sits on.
const css = readFileSync(join(__dirname, '../app/globals.css'), 'utf8');
const root = css.match(/:root\s*{([^}]*)}/)?.[1] ?? '';
const tokens = Object.fromEntries(
  [...root.matchAll(/--([\w-]+):\s*(#[0-9a-f]{3,6})\b/gi)].map(([, name, hex]) => [name, hex]),
);

function luminance(hex: string): number {
  const h = hex.slice(1);
  const full = h.length === 3 ? [...h].map((c) => c + c).join('') : h;
  const [r, g, b] = [0, 2, 4].map((i) => {
    const c = parseInt(full.slice(i, i + 2), 16) / 255;
    return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

function ratio(fg: string, bg: string): number {
  const [a, b] = [luminance(fg), luminance(bg)].sort((x, y) => y - x);
  return (a + 0.05) / (b + 0.05);
}

const PAIRS = [
  ['foreground', 'background'], ['muted-foreground', 'background'], ['accent-text', 'background'],
  ['foreground', 'card'], ['muted-foreground', 'card'], ['accent-text', 'card'],
  ['primary-foreground', 'primary'], ['on-amber', 'amber'],
  ['type', 'paper'], ['type', 'greenbar'], ['term-fg', 'term-bg'], ['app-fg', 'ink'], ['app-dim', 'ink'],
  ['term-dim', 'term-head'], ['red-text', 'term-head'], ['app-tab', 'app-fill'], ['app-dim', 'app-card'],
  // The note in pen on the hero's sky, by the notch.
  ['accent-text', 'sky'],
  // The Download button over the office picture: cream on the building's rust wood.
  ['sky-hi', 'hz4'],
];

test.each(PAIRS)('%s on %s reaches 7:1', (fg, bg) => {
  expect(tokens[fg], `--${fg} is missing`).toBeDefined();
  expect(tokens[bg], `--${bg} is missing`).toBeDefined();
  expect(ratio(tokens[fg], tokens[bg])).toBeGreaterThanOrEqual(7);
});

// A word's dotted underline is the colour of its text, lifted toward the page by --w-line; it is
// what marks the link, so it keeps 3:1 (WCAG 1.4.11) on the page and on a card.
function mix(fg: string, bg: string, share: number): string {
  const rgb = (hex: string) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));
  const [a, b] = [rgb(fg), rgb(bg)];
  return '#' + a.map((c, i) => Math.round(c * share + b[i] * (1 - share)).toString(16).padStart(2, '0')).join('');
}
const share = Number(css.match(/--w-line:\s*([\d.]+)%/)?.[1]) / 100;

test.each([
  ['foreground', 'background'], ['muted-foreground', 'background'], ['foreground', 'card'], ['muted-foreground', 'card'],
])('the underline of a word in %s on %s reaches 3:1', (fg, bg) => {
  expect(share, '--w-line is missing').toBeGreaterThan(0);
  expect(ratio(mix(tokens[fg], tokens[bg], share), tokens[bg])).toBeGreaterThanOrEqual(3);
});
