import { STRIPS } from '../app/comics/strips';
import { expect, test } from '@playwright/test';

for (const path of ['/', '/comics/', '/privacy/', '/404.html', ...STRIPS.map((s) => `/comics/${s.slug}/`)]) {
  for (const width of [320, 390, 768, 900, 1280]) {
    test(`nothing scrolls sideways on ${path} at ${width}px`, async ({ page }) => {
      await page.setViewportSize({ width, height: 800 });
      await page.goto(path);
      await page.waitForTimeout(300);
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    });
  }
}

for (const width of [320, 390]) {
  test(`a phone keeps the panel to its two cards at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 800 });
    await page.goto('/');
    await expect(page.locator('.panel .extra')).toBeHidden();
  });
}

test('a flipped section gives its picture the wide column', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.goto('/');
  for (const cols of await page.locator('section.flip').evaluateAll((all) => all.map((s) => getComputedStyle(s).gridTemplateColumns))) {
    const [left, right] = cols.split(' ').map(parseFloat);
    expect(left).toBeGreaterThan(right);
  }
});

test('the short side of Trust stays in view while the long side scrolls', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.goto('/');
  for (const name of ['trust']) {
    const section = page.locator(`section.${name}`);
    await section.evaluate((el) => scrollTo(0, el.getBoundingClientRect().top + scrollY + 300));
    await page.waitForTimeout(100);
    const top = await section.locator('h2').evaluate((el) => el.getBoundingClientRect().top);
    expect(top, name).toBeGreaterThan(0);
  }
});

test('Words is a two-column index, each word on the line of its meaning', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.goto('/');
  const list = page.locator('section.words dl');
  expect(await list.evaluate((el) => getComputedStyle(el).columnCount)).toBe('2');
  for (const gap of await list.locator(':scope > div').evaluateAll((all) =>
    all.map((d) => Math.abs(d.querySelector('dt')!.getBoundingClientRect().bottom - d.querySelector('dd')!.getClientRects()[0].bottom)),
  )) expect(gap).toBeLessThan(6);
});

test("the printout's lines sit on its 24px rows", async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.goto('/');
  for (const off of await page.locator('.paper').evaluate((paper) =>
    [...paper.querySelectorAll('li')].map((li) => li.getBoundingClientRect().top - paper.getBoundingClientRect().top),
  )) expect(Math.round(off) % 24).toBe(0);
});

test('the hero keeps "With or without a notch" on one line', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.goto('/');
  const part = page.locator('.hero .nw', { hasText: 'With or without a notch' });
  expect(await part.evaluate((el) => el.getClientRects().length)).toBe(1);
});

test('the footer: the logo on the left, its links on the right, the small print under a rule', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.goto('/');
  const foot = page.locator('footer');
  const name = await foot.locator('svg.wordmark').boundingBox();
  const github = await foot.getByRole('link', { name: 'AgentValley on GitHub' }).boundingBox();
  const print = await foot.getByText('Not affiliated with Anthropic.', { exact: true }).boundingBox();
  expect(github!.x).toBeGreaterThan(name!.x + name!.width);
  expect(github!.height).toBeGreaterThanOrEqual(44);
  expect(print!.y).toBeGreaterThan(github!.y + github!.height);
});
