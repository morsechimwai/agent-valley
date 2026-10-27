import { STRIPS } from '../app/comics/strips';
import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

// WCAG AAA, as the old page held, with the panel open and shut.
const check = (page: import('@playwright/test').Page) =>
  new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag2aaa']).analyze();

test.use({ reducedMotion: 'reduce' });

test('no AAA violations with the panel open', async ({ page }) => {
  await page.goto('/');
  await page.locator('.hist .h-title').waitFor();
  await expect(page.locator('.screen')).toHaveAttribute('data-state', 'open');
  const { violations } = await check(page);
  expect(violations.map((v) => `${v.id}: ${v.nodes.map((n) => n.target.join(' ')).join(', ')}`)).toEqual([]);
});

test('no AAA violations with the panel shut', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('.screen')).toHaveAttribute('data-ready', '');
  await page.getByRole('button', { name: 'The notch: the AgentValley panel' }).press('Enter');
  await expect(page.locator('.screen')).toHaveAttribute('data-state', 'shut');
  const { violations } = await check(page);
  expect(violations.map((v) => `${v.id}: ${v.nodes.map((n) => n.target.join(' ')).join(', ')}`)).toEqual([]);
});

test.describe('with the needs-you player loaded', () => {
  test.use({ reducedMotion: 'no-preference', viewport: { width: 1280, height: 800 } });
  test('no AAA violations with the needs-you player loaded', async ({ page }) => {
    await page.goto('/');
    await page.locator('.needs-you').scrollIntoViewIfNeeded();
    await page.locator('.s-player').waitFor();
    await page.waitForTimeout(300);
    const { violations } = await check(page);
    expect(violations.map((v) => `${v.id}: ${v.nodes.map((n) => n.target.join(' ')).join(', ')}`)).toEqual([]);
  });
});

for (const path of ['/comics/', '/privacy/', '/404.html', ...STRIPS.map((s) => `/comics/${s.slug}/`)]) {
  test(`no AAA violations on ${path}`, async ({ page }) => {
    await page.goto(path);
    const { violations } = await check(page);
    expect(violations.map((v) => `${v.id}: ${v.nodes.map((n) => n.target.join(' ')).join(', ')}`)).toEqual([]);
  });
}
