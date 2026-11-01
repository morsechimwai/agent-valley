import { expect, test } from '@playwright/test';

// The page a wrong link lands on.
const ALT = 'Faye, the Explore agent, stands by the file shelves of the computer room holding an open folder, sand still on her jeans from the search.';

test('Faye says the page is not there', async ({ page }) => {
  await page.goto('/404.html');
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Faye looked everywhere.');
  await expect(page.getByText('Every folder, twice. No page by that name.')).toBeVisible();
  await expect(page.getByRole('link', { name: 'Back to the valley' })).toHaveAttribute('href', '/');
  await expect(page.getByRole('img', { name: ALT })).toBeVisible();
});

test("the tag sits above the picture's left half, off the drawing", async ({ page }) => {
  await page.goto('/404.html');
  const tag = (await page.getByText('Explore · 404 tool uses').filter({ visible: true }).boundingBox())!;
  const art = (await page.getByRole('img', { name: ALT }).boundingBox())!;
  expect(tag.x).toBeGreaterThanOrEqual(art.x);
  expect(tag.x + tag.width).toBeLessThanOrEqual(art.x + art.width / 2);
  expect(tag.y + tag.height).toBeLessThanOrEqual(art.y);
});

test('a wide screen puts the words left of the picture', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.goto('/404.html');
  const h1 = (await page.getByRole('heading', { level: 1 }).boundingBox())!;
  const art = (await page.getByRole('img', { name: ALT }).boundingBox())!;
  expect(h1.x + h1.width).toBeLessThanOrEqual(art.x);
});

test('a phone puts the picture over the words', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 800 });
  await page.goto('/404.html');
  const h1 = (await page.getByRole('heading', { level: 1 }).boundingBox())!;
  const art = (await page.getByRole('img', { name: ALT }).boundingBox())!;
  expect(art.y + art.height).toBeLessThanOrEqual(h1.y);
});

test('the page stays out of search engines, under its own title', async ({ page }) => {
  await page.goto('/404.html');
  // Next's own robots line and ours: none of them may say index.
  const robots = await page.locator('meta[name="robots"]').evaluateAll((all) => all.map((m) => m.getAttribute('content') ?? ''));
  expect(robots.length).toBeGreaterThan(0);
  for (const r of robots) expect(r).toMatch(/noindex/);
  await expect(page).toHaveTitle('Page not found · AgentValley');
});
