import { expect, test } from '@playwright/test';

// A reader in Britain: weeks start on Monday there.
test.use({ timezoneId: 'Asia/Bangkok', locale: 'en-GB' });

const open = async (page: import('@playwright/test').Page) => {
  await page.clock.setFixedTime(new Date('2026-10-16T15:30:00+07:00'));
  await page.goto('/');
  return page.getByRole('group', { name: 'The History page' });
};

test("History is drawn on the reader's own calendar", async ({ page }) => {
  const hist = await open(page);
  await expect(hist.locator('.h-title')).toHaveText('October 2026');
  await expect(hist.locator('.h-total b')).toHaveText('$1,261.12');
  await hist.getByRole('button', { name: 'Week' }).click();
  await expect(page.locator('#said')).toHaveText('October 12 – 18, 2026, $467.41');
  await hist.getByRole('button', { name: /^shop-web/ }).click();
  await expect(hist.getByRole('button', { name: 'All projects' })).toBeFocused();
});

test('in the first week of a month it opens on the month before', async ({ page }) => {
  await page.clock.setFixedTime(new Date('2026-11-01T09:00:00+07:00'));
  await page.goto('/');
  const hist = page.getByRole('group', { name: 'The History page' });
  await expect(hist.locator('.h-title')).toHaveText('October 2026');
  await expect(hist.getByRole('button', { name: /^shop-web/ })).toBeVisible();
});

test.describe('in America', () => {
  test.use({ locale: 'en-US' });
  test('a week starts on Sunday', async ({ page }) => {
    const hist = await open(page);
    await hist.getByRole('button', { name: 'Week' }).click();
    await expect(hist.locator('.h-title')).toHaveText('Oct 11 – 17, 2026');
  });
});

test('the top row is the app\'s: back to the agents, Export PDF, and the spans', async ({ page }) => {
  const hist = await open(page);
  await expect(hist.getByRole('link', { name: 'Agents' })).toHaveAttribute('href', '#top');
  await expect(hist.getByRole('link', { name: 'Export PDF' })).toHaveAttribute('href', '#report');
  await expect(page.locator('section.costs #report')).toHaveCount(1);
  const top = (name: string) => hist.getByRole(name === 'Month' ? 'button' : 'link', { name }).evaluate((el) => Math.round(el.getBoundingClientRect().top));
  expect(await top('Export PDF')).toBe(await top('Agents'));
  // The arrows hug the title, as in the app, and each is still a 24px target on top of it.
  const title = (await hist.locator('.h-title').boundingBox())!;
  const [earlier, later] = await hist.locator('.h-step svg').all();
  const left = title.x - ((await earlier.boundingBox())!.x + (await earlier.boundingBox())!.width);
  const right = (await later.boundingBox())!.x - (title.x + title.width);
  for (const gap of [left, right]) {
    expect(gap).toBeGreaterThanOrEqual(0);
    expect(gap).toBeLessThan(10);
  }
  await hist.locator('.h-stretch').evaluate((el) => el.scrollIntoView({ block: 'center', behavior: 'instant' }));
  for (const step of await hist.locator('.h-step').all()) {
    const box = (await step.boundingBox())!;
    expect([box.width, box.height]).toEqual([24, 24]);
    const hit = await step.evaluate((el) => {
      const r = el.getBoundingClientRect();
      return [r.left + 2, r.right - 2].map((x) => el.contains(document.elementFromPoint(x, r.top + r.height / 2)));
    });
    expect(hit).toEqual([true, true]);
  }
});

test('short names are spelled out where the pointer rests', async ({ page }) => {
  const hist = await open(page);
  await hist.getByRole('button', { name: 'Week' }).click();
  await expect(hist.locator('.h-title abbr')).toHaveAttribute('title', 'October');
  await expect(hist.locator('.h-foot')).toHaveText('History since Aug 1, 2026 · API prices as of Oct 15, 2026');
  await expect(hist.locator('.h-foot abbr')).toHaveText(['Aug', 'API', 'Oct']);
});

test('a bar picked with the pointer shows the pick line, and its ✕ lets go', async ({ page }) => {
  const hist = await open(page);
  await expect(hist.locator('.h-pick')).toHaveCount(0);
  await hist.getByRole('option', { name: /^October 14, / }).click();
  await expect(hist.locator('.h-pick')).toHaveText(/^Oct 14 · \$\d/);
  await expect(page.locator('#said')).toHaveText(/^October 2026, \$1,261\.12; October 14, \$/);
  await expect(hist.getByRole('listbox', { name: 'Hours' })).toBeVisible();
  // The click picked without taking the keyboard to the bars.
  await expect(hist.getByRole('listbox', { name: 'Days' })).not.toBeFocused();
  // A press on the line's words lets go of nothing; the ✕ does.
  const words = (await hist.locator('.h-pick > span').boundingBox())!;
  await page.mouse.click(words.x + words.width - 2, words.y + words.height / 2);
  await expect(hist.locator('.h-pick')).toHaveCount(1);
  await hist.getByRole('button', { name: 'Show all of October 2026' }).click();
  await expect(hist.locator('.h-pick')).toHaveCount(0);
  await expect(hist.getByRole('listbox', { name: 'Hours' })).toHaveCount(0);
  await expect(hist.getByRole('listbox', { name: 'Days' })).toBeFocused();
});

test('from the keyboard the arrows walk the days, and Escape lets go', async ({ page }) => {
  const hist = await open(page);
  const days = hist.getByRole('listbox', { name: 'Days' });
  await days.focus();
  // End is today: the days after it are not there yet.
  await page.keyboard.press('End');
  await expect(hist.getByRole('option', { selected: true })).toHaveAccessibleName(/^October 16, /);
  await page.keyboard.press('ArrowLeft');
  await page.keyboard.press('ArrowLeft');
  await expect(hist.getByRole('option', { selected: true })).toHaveAccessibleName(/^October 14, \$/);
  await expect(hist.locator('.h-pick')).toHaveText(/^Oct 14 · /);
  await expect(days).toBeFocused();
  await expect(days).toHaveAttribute('aria-activedescendant', (await hist.getByRole('option', { selected: true }).first().getAttribute('id'))!);
  // On into its hours.
  await page.keyboard.press('Tab');
  await expect(hist.getByRole('button', { name: 'Show all of October 2026' })).toBeFocused();
  await page.keyboard.press('Tab');
  await expect(hist.getByRole('listbox', { name: 'Hours' })).toBeFocused();
  await page.keyboard.press('ArrowRight');
  await expect(hist.locator('.h-pick')).toHaveText(/^Oct 14, 00:00 · /);
  await page.keyboard.press('Escape');
  await expect(hist.locator('.h-pick')).toHaveText(/^Oct 14 · /);
  await days.focus();
  await page.keyboard.press('Escape');
  await expect(hist.locator('.h-pick')).toHaveCount(0);
});

test('the arrows keep the keyboard', async ({ page }) => {
  const hist = await open(page);
  await hist.getByRole('button', { name: 'Earlier' }).click();
  await expect(hist.locator('.h-title')).toHaveText('September 2026');
  await expect(hist.getByRole('button', { name: 'Earlier' })).toBeFocused();
  await hist.getByRole('button', { name: 'Earlier' }).click();
  // Two months back the earlier arrow is off; the keyboard moves to the later one.
  await expect(hist.getByRole('button', { name: 'Earlier' })).toBeDisabled();
  await expect(hist.getByRole('button', { name: 'Later' })).toBeFocused();
});

test('the built page holds no History numbers', async ({ request }) => {
  const html = await (await request.get('/')).text();
  expect(html).not.toContain('h-total');
});

test.describe('under a finger', () => {
  test.use({ hasTouch: true });
  test('every control of History is a 44px target', async ({ page }) => {
    const hist = await open(page);
    for (const control of await hist.locator('.h-back, .h-pdf, .h-seg button, .h-step, .h-list button').all()) {
      const box = (await control.boundingBox())!;
      expect(Math.min(box.width, box.height)).toBeGreaterThanOrEqual(44);
    }
  });
});
