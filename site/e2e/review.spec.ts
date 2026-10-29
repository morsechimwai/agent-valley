import { expect, test } from '@playwright/test';

// The review page: stars from the link, a live preview, and a send that thanks only on a 2xx.
async function fill(page: import('@playwright/test').Page) {
  await page.goto('/review/?stars=4');
  await expect(page.getByRole('button', { name: '4 stars' })).toHaveAttribute('aria-pressed', 'true');
  await page.getByLabel('Your words').fill('Lives in my notch, pays no rent.');
  await page.getByLabel(/^Name/).fill('Ann Lee');
  await page.getByLabel('Account (optional)').fill('https://github.com/annlee');
  await page.getByLabel(/OK to show/).check();
  const card = page.getByTestId('preview');
  await expect(card).toContainText('Lives in my notch, pays no rent.');
  await expect(card).toContainText('Ann Lee');
  await expect(card).toContainText('@annlee on GitHub');
}

test('a review is sent and thanked on a 2xx', async ({ page }) => {
  let sent: { event: string; properties: Record<string, unknown> } | undefined;
  await page.route('**/ingest/i/v0/e/', (route) => {
    sent = route.request().postDataJSON();
    return route.fulfill({ json: { status: 1 } });
  });
  await fill(page);
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByRole('status')).toContainText('Got it.');
  expect(sent?.event).toBe('review sent');
  expect(sent?.properties).toMatchObject({ stars: 4, name: 'Ann Lee', handle: 'annlee', handle_site: 'github', show: true });
});

test('a failed send keeps the words and offers another try', async ({ page }) => {
  await page.route('**/ingest/i/v0/e/', (route) => route.fulfill({ status: 500, body: 'no' }));
  await fill(page);
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByRole('status')).toContainText('hello@agentvalley.app');
  await expect(page.getByLabel('Your words')).toHaveValue('Lives in my notch, pays no rent.');
  await expect(page.getByRole('button', { name: 'Try again' })).toBeEnabled();
});
