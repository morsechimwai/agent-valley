import { expect, type Page, test } from '@playwright/test';

// A mouse wheel's steps glide and a link travels (components/smooth-scroll.tsx); stopped, the
// wheel steps and a link jumps, as the browser has them.
test.use({ viewport: { width: 1280, height: 800 }, reducedMotion: 'no-preference' });

const y = (page: Page) => page.evaluate(() => scrollY);
// Lenis marks <html> lenis-smooth while it glides.
const gliding = (page: Page) => page.evaluate(() => document.documentElement.classList.contains('lenis-smooth'));

test('a wheel glides to where it was turned', async ({ page }) => {
  await page.goto('/');
  await page.mouse.move(640, 400);
  await page.mouse.wheel(0, 400);
  await expect.poll(() => gliding(page)).toBe(true);
  await expect.poll(() => y(page)).toBe(400);
  await expect.poll(() => gliding(page)).toBe(false);
});

// React is in: the Copy buttons are drawn, as Stop is, and the page has its full height, so a
// link's place is where it stays.
const ready = (page: Page) => expect(page.locator('.still-toggle')).toBeVisible();

// Where the page is on each frame from the click until it has stood still a while, and when.
const trace = (page: Page, link: string) =>
  page.evaluate((name) => {
    const a = [...document.querySelectorAll('a')].find((el) => el.textContent === name)!;
    return new Promise<{ t: number; y: number }[]>((done) => {
      const seen: { t: number; y: number }[] = [];
      const start = performance.now();
      const frame = () => {
        seen.push({ t: performance.now() - start, y: scrollY });
        const last = seen.filter((s) => s.y === scrollY);
        if (seen.length > 10 && last.length > 20) done(seen);
        else requestAnimationFrame(frame);
      };
      a.click();
      requestAnimationFrame(frame);
    });
  }, link);

test('a link to a part of the page gets there in about 0.75 s, one way only', async ({ page }) => {
  await page.goto('/');
  await ready(page);
  const seen = await trace(page, 'Install');
  const end = seen.at(-1)!.y;
  const top = await page.locator('#install').evaluate((el) => Math.round(el.getBoundingClientRect().top));
  expect(top).toBe(80);
  for (let i = 1; i < seen.length; i++) expect(seen[i].y, `frame ${i}`).toBeGreaterThanOrEqual(seen[i - 1].y);
  const there = seen.find((s) => s.y === end)!.t;
  expect(there).toBeGreaterThan(600);
  expect(there).toBeLessThan(1000);
  // Moving at once, then a long ease in: the first tenth of the time covers some of the way, not
  // most (the curve has 16%), and half the time most of it (88%).
  const at = (t: number) => seen.findLast((s) => s.t <= t)!.y;
  expect(at(0.1 * there)).toBeGreaterThan(0.05 * end);
  expect(at(0.1 * there)).toBeLessThan(0.3 * end);
  expect(at(0.5 * there)).toBeGreaterThan(0.8 * end);
});

test('Back on the way to a part of the page stops the trip where the browser puts it', async ({ page }) => {
  await page.goto('/');
  await ready(page);
  await page.evaluate(() => [...document.querySelectorAll('a')].find((el) => el.textContent === 'Install')!.click());
  await expect.poll(() => y(page)).toBeGreaterThan(0);
  await page.evaluate(() => history.back());
  await expect.poll(() => page.evaluate(() => location.hash)).toBe('');
  let last = -1;
  await expect.poll(async () => last === (last = await y(page)), { intervals: [150] }).toBe(true);
  expect(await y(page)).toBeLessThan(6000);
});

// The wheel is the browser's own: Lenis lets the event through (a listener after its own sees it
// not taken), the page moves, nothing glides.
const native = async (page: Page) => {
  await page.evaluate(() =>
    addEventListener('wheel', (e) => (document.documentElement.dataset.wheel = e.defaultPrevented ? 'taken' : 'through'), { once: true }),
  );
  await page.mouse.move(640, 400);
  await page.mouse.wheel(0, 400);
  await expect(page.locator('html')).toHaveAttribute('data-wheel', 'through');
  await expect.poll(() => y(page)).toBeGreaterThan(0);
  expect(await gliding(page)).toBe(false);
  // And a link jumps, once the wheel's own scroll has stopped.
  let last = -1;
  await expect.poll(async () => last === (last = await y(page)), { intervals: [150] }).toBe(true);
  const seen = await trace(page, 'Install');
  expect(seen.find((s) => s.y === seen.at(-1)!.y)!.t).toBeLessThan(100);
};

test('with the animations stopped, the wheel steps without a glide', async ({ page }) => {
  await page.goto('/');
  await page.locator('.still-toggle').click();
  await expect(page.locator('html')).toHaveClass(/\bstill\b/);
  await native(page);
});

test.describe('with motion reduced', () => {
  test.use({ reducedMotion: 'reduce' });
  test('the wheel steps without a glide', async ({ page }) => {
    await page.goto('/');
    await native(page);
  });
});
