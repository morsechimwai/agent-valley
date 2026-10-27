import { expect, test, type Page } from '@playwright/test';
import { STRIPS } from '../app/comics/strips';

// Halloween 2026 (docs/superpowers/specs/2026-10-18-halloween-design.md). These tests set the
// visitor's clock themselves, so the storage flag HALLOWEEN=1 puts in is cleared here.
test.use({ storageState: { cookies: [], origins: [] } });

const on = (page: Page) => page.clock.setFixedTime(new Date('2026-10-31T12:00:00'));
const off = (page: Page) => page.clock.setFixedTime(new Date('2026-11-05T12:00:00'));
const html = (page: Page) => page.locator('html');

test.describe('the switch', () => {
  test('the switch is on on 31 October', async ({ page }) => {
    await on(page);
    await page.goto('/');
    await expect(html(page)).toHaveClass(/\bhalloween\b/);
  });

  test('the switch is on at 23:59 on 1 November', async ({ page }) => {
    await page.clock.setFixedTime(new Date('2026-11-01T23:59:00'));
    await page.goto('/');
    await expect(html(page)).toHaveClass(/\bhalloween\b/);
  });

  test('the switch is off on 5 November', async ({ page }) => {
    await off(page);
    await page.goto('/');
    await expect(html(page)).toHaveAttribute('data-live', '');
    await expect(html(page)).not.toHaveClass(/\bhalloween\b/);
  });

  test('?halloween turns it on any day and is remembered', async ({ page }) => {
    await page.clock.setFixedTime(new Date('2026-10-18T12:00:00'));
    await page.goto('/?halloween');
    await expect(html(page)).toHaveClass(/\bhalloween\b/);
    await page.goto('/comics/');
    await expect(html(page)).toHaveClass(/\bhalloween\b/);
    await page.goto('/?halloween=0');
    await expect(html(page)).not.toHaveClass(/\bhalloween\b/);
    await page.goto('/comics/');
    await expect(html(page)).not.toHaveClass(/\bhalloween\b/);
  });

  test('a remembered ?halloween ends with Halloween', async ({ page }) => {
    await page.addInitScript(() => localStorage.setItem('halloween', '1'));
    await off(page);
    await page.goto('/');
    await expect(html(page)).toHaveAttribute('data-live', '');
    await expect(html(page)).not.toHaveClass(/\bhalloween\b/);
    await page.goto('/?halloween');
    await expect(html(page)).toHaveClass(/\bhalloween\b/);
  });

  test('?halloween works with storage blocked', async ({ page }) => {
    const errors: string[] = [];
    page.on('pageerror', (e) => errors.push(e.message));
    await page.addInitScript(() => {
      const no = () => { throw new Error('storage blocked'); };
      Object.defineProperty(window, 'localStorage', { get: () => ({ getItem: no, setItem: no, removeItem: no }) });
    });
    await off(page);
    await page.goto('/?halloween');
    await expect(html(page)).toHaveClass(/\bhalloween\b/);
    await expect(html(page)).toHaveAttribute('data-live', '');
    expect(errors).toEqual([]);
  });
});

// Spec A: the hero at dusk.
const running = (page: Page, within: string) =>
  page.evaluate((sel) => document.getAnimations().filter((a) => a.playState === 'running' && ((a.effect as KeyframeEffect)?.target as Element | null)?.closest(sel)).length, within);

test.describe('the hero at dusk', () => {
  test.use({ viewport: { width: 1280, height: 800 } });

  test('a spider hangs under the notch with its note', async ({ page }) => {
    await on(page);
    await page.goto('/');
    await expect(page.locator('.screen .bat')).toHaveCount(3);
    const spider = page.locator('.screen .spider');
    await expect(spider).toBeVisible();
    const lens = (await page.locator('.screen .bar .lens').boundingBox())!;
    expect((await spider.boundingBox())!.y).toBeGreaterThanOrEqual(lens.y + lens.height);
    const note = page.locator('.screen .spider-note');
    await expect(note).toHaveText('He moved in last week. Pays no rent.');
    expect(await note.evaluate((el) => getComputedStyle(el).fontFamily)).toMatch(/Caveat/);
  });

  test('every night piece is hidden from screen readers', async ({ page }) => {
    await on(page);
    await page.goto('/');
    for (const el of await page.locator('.bat, .spider, .spider-note').all()) {
      expect(await el.evaluate((e) => !!e.closest('[aria-hidden="true"]'))).toBe(true);
    }
  });

  test('nothing night shows on 5 November', async ({ page }) => {
    await off(page);
    await page.goto('/');
    await expect(page.locator('.screen .bat').first()).toBeHidden();
    await expect(page.locator('.screen .spider')).toBeHidden();
  });

  test('with reduced motion nothing moves at night', async ({ page }) => {
    await page.emulateMedia({ reducedMotion: 'reduce' });
    await on(page);
    await page.goto('/');
    await page.waitForTimeout(500);
    expect(await running(page, 'html')).toBe(0);
  });

  test('Stop holds the night still', async ({ page }) => {
    await on(page);
    await page.goto('/');
    await page.getByRole('button', { name: 'Stop the animations' }).click();
    await page.waitForTimeout(300);
    expect(await running(page, '.screen')).toBe(0);
  });

  for (const width of [320, 390]) {
    test(`at ${width}px the night does not scroll sideways`, async ({ page }) => {
      await page.setViewportSize({ width, height: 800 });
      await on(page);
      await page.goto('/');
      await expect(page.locator('.screen .spider')).toBeVisible();
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    });
  }
});

// Spec B: Trick or treat in the hero panel.
const NOTCH = 'The notch: the AgentValley panel';
const ALLOW_REPLY = 'Thanks. Walt already took the peanut butter cups.';
const DENY_REPLY = 'Fair. Trick it is.';
const ANSWERED_OPEN = 'The top of a MacBook screen. The AgentValley panel is open under the notch: four agents are working, and nobody needs you.';
const ANSWERED_SHUT = 'The top of a MacBook screen. Beside the notch, a working programmer: nobody needs you.';
const lightsOut = (page: Page) =>
  page.evaluate(() => document.getAnimations().filter((a) => (a as CSSAnimation).animationName === 'lights-out' && a.playState === 'running').length);

// It stands open from the start; the notch takes the keyboard first.
async function openPanel(page: Page) {
  await expect(page.locator('.screen')).toHaveAttribute('data-ready', '');
  await expect(page.locator('.screen')).toHaveAttribute('data-state', 'open');
  await page.getByRole('button', { name: NOTCH }).focus();
}

test.describe('Trick or treat', () => {
  test.use({ reducedMotion: 'reduce' });

  test('the first row asks for candy', async ({ page }) => {
    await on(page);
    await page.goto('/');
    await openPanel(page);
    const panel = page.locator('.screen .panel');
    for (const words of ['Trick or treat', 'haunted-house', 'porch', '> Bash eat ./candy/*']) {
      await expect(panel.getByText(words, { exact: true }).filter({ visible: true })).toHaveCount(1);
    }
    await expect(panel.getByText('Go to Terminal').filter({ visible: true })).toHaveCount(0);
    await expect(page.getByRole('group', { name: 'Trick or treat. Sunny asks to run eat ./candy/*.' })).toBeVisible();
  });

  test('the answer buttons cannot be reached while the panel is shut', async ({ page }) => {
    await on(page);
    await page.goto('/');
    await expect(page.locator('.screen')).toHaveAttribute('data-ready', '');
    await page.getByRole('button', { name: NOTCH }).press('Enter');
    await expect(page.locator('.screen')).toHaveAttribute('data-state', 'shut');
    await expect(page.getByRole('button', { name: 'Allow once' })).toHaveCount(0);
    await page.keyboard.press('Tab');
    expect(await page.evaluate(() => document.activeElement?.textContent)).not.toMatch(/Allow once|Deny/);
  });

  test('Allow once from the keyboard', async ({ page }) => {
    await on(page);
    await page.goto('/');
    await openPanel(page);
    await page.keyboard.press('Tab');
    await expect(page.getByRole('button', { name: 'Allow once' })).toBeFocused();
    await page.keyboard.press('Enter');
    const screen = page.locator('.screen');
    await expect(screen).toHaveAttribute('data-answered', 'allow');
    await expect(screen.getByText(ALLOW_REPLY).filter({ visible: true })).toHaveCount(1);
    await expect(page.locator('#said')).toHaveText(ALLOW_REPLY);
    await expect(page.getByRole('button', { name: 'Allow once' })).toHaveCount(0);
    await expect(page.getByRole('button', { name: 'Deny' })).toHaveCount(0);
    await expect(page.getByRole('button', { name: NOTCH })).toBeFocused();
    await expect(screen.locator('.bar .count')).toBeHidden();
    await expect(screen.locator('.p-head').filter({ visible: true })).toHaveText('4 working');
    await expect(screen.getByText('needs you', { exact: true }).filter({ visible: true })).toHaveCount(0);
    await expect(screen.locator('> [role=img]')).toHaveAttribute('aria-label', ANSWERED_OPEN);
  });

  test('Allow once with the mouse', async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await on(page);
    await page.goto('/');
    await expect(page.locator('.screen')).toHaveAttribute('data-ready', '');
    await page.getByRole('button', { name: NOTCH }).hover();
    await expect(page.locator('.screen')).toHaveAttribute('data-state', 'open');
    await page.getByRole('button', { name: 'Allow once' }).click();
    await expect(page.locator('.screen')).toHaveAttribute('data-answered', 'allow');
    await expect(page.locator('.screen')).toHaveAttribute('data-state', 'open');
  });

  test('Esc on an answer button shuts the panel and lands on the notch', async ({ page }) => {
    await on(page);
    await page.goto('/');
    await openPanel(page);
    await page.keyboard.press('Tab');
    await expect(page.getByRole('button', { name: 'Allow once' })).toBeFocused();
    await page.keyboard.press('Escape');
    await expect(page.locator('.screen')).toHaveAttribute('data-state', 'shut');
    await expect(page.getByRole('button', { name: NOTCH })).toBeFocused();
  });

  test('a pointer that shuts the panel under a focused answer button leaves focus on the notch', async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await on(page);
    await page.goto('/');
    await openPanel(page);
    await page.keyboard.press('Tab');
    await expect(page.getByRole('button', { name: 'Allow once' })).toBeFocused();
    const panel = (await page.locator('.screen .panel').boundingBox())!;
    await page.mouse.move(panel.x + panel.width / 2, panel.y + panel.height / 2);
    await page.mouse.move(panel.x + panel.width / 2, panel.y + panel.height + 300);
    await expect(page.locator('.screen')).toHaveAttribute('data-state', 'shut');
    await expect(page.getByRole('button', { name: NOTCH })).toBeFocused();
  });

  test('the shut picture says nobody needs you after an answer', async ({ page }) => {
    await on(page);
    await page.goto('/');
    await openPanel(page);
    await page.getByRole('button', { name: 'Deny' }).click();
    await expect(page.locator('#said')).toHaveText(DENY_REPLY);
    await page.getByRole('button', { name: NOTCH }).press('Enter');
    await expect(page.locator('.screen')).toHaveAttribute('data-state', 'shut');
    await expect(page.locator('.screen > [role=img]')).toHaveAttribute('aria-label', ANSWERED_SHUT);
  });

  test('each answer button is at least 44 by 44', async ({ page }) => {
    for (const width of [320, 1280]) {
      await page.setViewportSize({ width, height: 900 });
      await on(page);
      await page.goto('/');
      await openPanel(page);
      const allow = (await page.getByRole('button', { name: 'Allow once' }).boundingBox())!;
      const deny = (await page.getByRole('button', { name: 'Deny' }).boundingBox())!;
      for (const box of [allow, deny]) {
        expect(box.width).toBeGreaterThanOrEqual(44);
        expect(box.height).toBeGreaterThanOrEqual(44);
      }
      expect(allow.x + allow.width <= deny.x || deny.x + deny.width <= allow.x).toBe(true);
    }
  });

  test('outside Halloween the row is the deploy', async ({ page }) => {
    await off(page);
    await page.goto('/');
    await openPanel(page);
    const panel = page.locator('.screen .panel');
    await expect(panel.getByText('Deploy preview').filter({ visible: true })).toHaveCount(1);
    await expect(panel.getByText('Go to Terminal').filter({ visible: true })).toHaveCount(1);
    await expect(panel.getByText('Trick or treat').filter({ visible: true })).toHaveCount(0);
    await expect(page.getByRole('button', { name: 'Allow once' })).toHaveCount(0);
  });
});

test.describe('Trick or treat, lights out', () => {
  test.use({ reducedMotion: 'no-preference' });

  test('Deny turns the lights out once', async ({ page }) => {
    await on(page);
    await page.goto('/');
    await openPanel(page);
    await page.getByRole('button', { name: 'Deny' }).click();
    await expect(page.locator('.screen')).toHaveAttribute('data-answered', 'deny');
    await expect(page.locator('.screen').getByText(DENY_REPLY).filter({ visible: true })).toHaveCount(1);
    expect(await lightsOut(page)).toBeGreaterThan(0);
    await page.waitForTimeout(2000);
    expect(await lightsOut(page)).toBe(0);
  });

  test('the crew still move, any day: each strip of frames steps along', async ({ page }) => {
    // The lights-out eyes once took the mascots' keyframes' name, and the crew stopped blinking.
    // The blinks are frames of the strips now.
    await off(page);
    await page.goto('/');
    await expect(html(page)).toHaveAttribute('data-live', '');
    const props = await page.evaluate(() =>
      document.querySelector('.holds>span img')!.getAnimations().flatMap((a) =>
        (a.effect as KeyframeEffect).getKeyframes().flatMap((k) => Object.keys(k))));
    expect(props).toContain('transform');
  });

  test('Deny with Stop on shows only the words', async ({ page }) => {
    await on(page);
    await page.goto('/');
    await page.getByRole('button', { name: 'Stop the animations' }).click();
    await openPanel(page);
    await page.getByRole('button', { name: 'Deny' }).click();
    await expect(page.locator('.screen')).toHaveAttribute('data-answered', 'deny');
    expect(await lightsOut(page)).toBe(0);
  });
});

// Spec D: the funnies' Halloween edition.
test.describe('the funnies', () => {
  test.use({ viewport: { width: 1280, height: 800 } });
  const shown = (page: Page, sel: string) => page.locator(sel).filter({ visible: true });

  test('the funnies print a Halloween edition', async ({ page }) => {
    await on(page);
    await page.goto('/comics/');
    await expect(shown(page, '.f-ear').first()).toContainText('Fog over the valley.');
    await expect(shown(page, '.f-ear').last()).toContainText('Notice');
    await expect(shown(page, '.f-ear').last()).toContainText('knock on the notch');
    await expect(page.locator('.f-date').getByText('Halloween Edition').filter({ visible: true })).toHaveCount(1);
    const lit = page.locator('.funnies header [aria-hidden=true] img[src*="pumpkin"]').filter({ visible: true });
    await expect(lit).toHaveCount(1);
  });

  test('the funnies are the usual paper on 5 November', async ({ page }) => {
    await off(page);
    await page.goto('/comics/');
    await expect(shown(page, '.f-ear').first()).toContainText('98% of the weekly limit');
    await expect(shown(page, '.f-ear').last()).toContainText('Home delivery');
    await expect(page.getByText('Halloween Edition').filter({ visible: true })).toHaveCount(0);
    await expect(page.locator('.funnies img[src*="pumpkin"]').filter({ visible: true })).toHaveCount(0);
  });
});

// Spec E: the small things.
test.describe('the small things', () => {
  const icon = (page: Page, type: string) => page.locator(`link[rel~="icon"][type="${type}"]`);

  test('a band over the top bar decodes the greeting and scrolls away', async ({ page }) => {
    await on(page);
    await page.goto('/comics/');
    const band = page.getByRole('complementary', { name: 'Halloween' });
    await expect(band.locator('strong span').first()).toHaveText('Happy Halloween.');
    await expect(band.getByRole('link', { name: /read the comic Tab 7/ })).toHaveAttribute('href', '/comics/tab-7/');
    await page.evaluate(() => scrollTo(0, 300));
    expect(await page.evaluate(() => [document.querySelector('.nav')!.getBoundingClientRect().top, document.querySelector('.hbar')!.getBoundingClientRect().bottom < 0])).toEqual([0, true]);
    await off(page);
    await page.goto('/comics/');
    await expect(html(page)).not.toHaveClass(/\bhalloween\b/);
    await expect(band).toBeHidden();
  });

  test('the tab icon is a pumpkin in Halloween', async ({ page }) => {
    await on(page);
    await page.goto('/');
    await expect(html(page)).toHaveAttribute('data-live', '');
    // Browsers take the last icon link: the pumpkin, added once after React has set its own.
    await page.waitForTimeout(300);
    await expect(page.locator('link[rel~="icon"]').last()).toHaveAttribute('href', /\/pumpkin\.svg$/);
    await expect(icon(page, 'image/svg+xml')).toHaveCount(2);
    // Browsers that draw no SVG icon keep the usual one.
    await expect(page.locator('link[rel~="icon"][href$="favicon.ico"]')).toHaveCount(1);
  });

  test('the tab icon is the crew outside Halloween', async ({ page }) => {
    await off(page);
    await page.goto('/');
    await expect(html(page)).toHaveAttribute('data-live', '');
    await expect(page.locator('link[rel~="icon"][href$="pumpkin.svg"]')).toHaveCount(0);
  });

  test('the console says boo once', async ({ page }) => {
    const said: string[] = [];
    page.on('console', (m) => said.push(m.text()));
    await on(page);
    await page.goto('/');
    await expect(html(page)).toHaveAttribute('data-live', '');
    await page.waitForTimeout(300);
    expect(said.filter((t) => t.includes('Boo.'))).toHaveLength(1);
    expect(said.find((t) => t.includes('Boo.'))).toContain("Looking for the source? It's MIT: github.com/morsechimwai/agent-valley");
  });

  test('the console keeps quiet outside Halloween', async ({ page }) => {
    const said: string[] = [];
    page.on('console', (m) => said.push(m.text()));
    await off(page);
    await page.goto('/');
    await expect(html(page)).toHaveAttribute('data-live', '');
    await page.waitForTimeout(300);
    expect(said.filter((t) => t.includes('Boo.'))).toHaveLength(0);
  });

  test('the 404 page is a ghost at Halloween', async ({ page }) => {
    await on(page);
    await page.goto('/404.html');
    await expect(page.getByRole('heading', { level: 1 })).toHaveText('This page is a ghost.');
    await expect(page.getByText('We looked under every desk.')).toBeVisible();
    await expect(page.getByRole('link', { name: 'Back to the valley' })).toHaveAttribute('href', '/');
    await expect(page.getByRole('img', { name: /bedsheet ghost costume/ })).toBeVisible();
    await expect(page.getByRole('img', { name: /file shelves/ })).toBeHidden();
  });
});

// Spec C: the pumpkin hunt.
const SECTIONS = ['.problem', '.costs', '.terminal', '.trust', '.foot'];
const pumpkin = (page: Page, section: string) => page.locator(section).getByRole('button', { name: 'Pumpkin' });
const counter = (page: Page) => page.locator('.nav .hunt-count');
const stamp = (page: Page) => page.locator('.credits .stamp').filter({ visible: true });

async function lightAll(page: Page) {
  for (const s of SECTIONS) await pumpkin(page, s).click();
}

test.describe('the pumpkin hunt', () => {
  test.use({ reducedMotion: 'reduce' });

  test('five pumpkins, one per section', async ({ page }) => {
    await on(page);
    await page.goto('/');
    await expect(page.getByRole('button', { name: 'Pumpkin' })).toHaveCount(5);
    for (const s of SECTIONS) await expect(pumpkin(page, s)).toHaveCount(1);
    await expect(pumpkin(page, '.hero')).toHaveCount(0);
    await expect(pumpkin(page, '#install')).toHaveCount(0);
  });

  test('the hunt is only on the home page', async ({ page }) => {
    await on(page);
    for (const path of ['/comics/', `/comics/${STRIPS[0].slug}/`, '/404.html']) {
      await page.goto(path);
      await expect(page.locator('.foot')).toBeVisible();
      await expect(page.getByRole('button', { name: 'Pumpkin' })).toHaveCount(0);
    }
  });

  test('lighting one shows the counter', async ({ page }) => {
    await on(page);
    await page.goto('/');
    await expect(html(page)).toHaveAttribute('data-live', '');
    await expect(counter(page)).toHaveCount(0);
    await pumpkin(page, '.problem').click();
    await expect(pumpkin(page, '.problem')).toHaveAttribute('aria-pressed', 'true');
    await expect(counter(page)).toBeVisible();
    await expect(counter(page)).toContainText('1 of 5 found');
    await expect(page.locator('#said')).toHaveText('Pumpkin lit. 1 of 5 found.');
  });

  test('a pumpkin lights from the keyboard', async ({ page }) => {
    await on(page);
    await page.goto('/');
    await expect(html(page)).toHaveAttribute('data-live', '');
    await pumpkin(page, '.costs').focus();
    await page.keyboard.press('Space');
    await expect(pumpkin(page, '.costs')).toHaveAttribute('aria-pressed', 'true');
  });

  test('found pumpkins stay lit after a reload', async ({ page }) => {
    await on(page);
    await page.goto('/');
    await expect(html(page)).toHaveAttribute('data-live', '');
    await pumpkin(page, '.problem').click();
    await pumpkin(page, '.trust').click();
    await page.reload();
    await expect(html(page)).toHaveAttribute('data-live', '');
    await expect(page.getByRole('button', { name: 'Pumpkin', pressed: true })).toHaveCount(2);
    await expect(counter(page)).toContainText('2 of 5 found');
  });

  test('all five change the crew photo', async ({ page }) => {
    await on(page);
    await page.goto('/');
    await expect(html(page)).toHaveAttribute('data-live', '');
    await expect(stamp(page)).toHaveText("'69 7 20");
    await lightAll(page);
    await expect(stamp(page)).toHaveText("'69 10 31");
    await expect(page.locator('.credits figcaption')).toContainText('Go trick-or-treating.');
    await expect(page.locator('.credits figcaption').getByText('Go take a break.')).toBeHidden();
    const link = page.getByRole('link', { name: '5 of 5 found' });
    await expect(link).toHaveAttribute('href', '#crew-photo');
    await expect(page.locator('#crew-photo')).toHaveCount(1);
    await expect(page.locator('#said')).toHaveText('All five lit. Check our photo at the bottom of the page.');
  });

  test('a returning finder sees the new photo from the first paint', async ({ page }) => {
    await page.addInitScript(() => localStorage.setItem('pumpkins', '[0,1,2,3,4]'));
    await page.route((url) => url.pathname.endsWith('.js'), (route) => route.abort());
    await on(page);
    await page.goto('/');
    await expect(html(page)).toHaveAttribute('data-pumpkins', 'all');
    await expect(stamp(page)).toHaveText("'69 10 31");
  });

  test('the hunt works with storage blocked', async ({ page }) => {
    const errors: string[] = [];
    page.on('pageerror', (e) => errors.push(e.message));
    await page.addInitScript(() => {
      const no = () => { throw new Error('storage blocked'); };
      Object.defineProperty(window, 'localStorage', { get: () => ({ getItem: no, setItem: no, removeItem: no }) });
    });
    await on(page);
    await page.goto('/');
    await expect(html(page)).toHaveAttribute('data-live', '');
    await pumpkin(page, '.problem').click();
    await pumpkin(page, '.foot').click();
    await expect(counter(page)).toContainText('2 of 5 found');
    expect(errors).toEqual([]);
  });

  test('every pumpkin is at least 44 by 44 and clickable', async ({ page }) => {
    for (const width of [320, 1280]) {
      await page.setViewportSize({ width, height: 900 });
      await on(page);
      await page.goto('/');
      await expect(html(page)).toHaveAttribute('data-live', '');
      for (const s of SECTIONS) {
        const box = (await pumpkin(page, s).boundingBox())!;
        expect(box.width).toBeGreaterThanOrEqual(44);
        expect(box.height).toBeGreaterThanOrEqual(44);
        await pumpkin(page, s).click();
      }
    }
  });

  test('the finished counter is at least 44 by 44 on a phone', async ({ page }) => {
    await page.addInitScript(() => localStorage.setItem('pumpkins', '[0,1,2,3,4]'));
    for (const width of [320, 390, 639]) {
      await page.setViewportSize({ width, height: 900 });
      await on(page);
      await page.goto('/');
      await expect(html(page)).toHaveAttribute('data-live', '');
      const box = (await page.getByRole('link', { name: '5 of 5 found' }).boundingBox())!;
      expect(box.width).toBeGreaterThanOrEqual(44);
      expect(box.height).toBeGreaterThanOrEqual(44);
    }
  });

  test('at 320px with all five found nothing scrolls sideways', async ({ page }) => {
    // With motion, the top bar also holds the Stop button: its fullest.
    await page.emulateMedia({ reducedMotion: 'no-preference' });
    for (const width of [320, 375, 390, 559, 600]) {
      await page.setViewportSize({ width, height: 900 });
      await on(page);
      await page.goto('/');
      await expect(html(page)).toHaveAttribute('data-live', '');
      await lightAll(page);
      await expect(counter(page)).toBeVisible();
      expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
    }
  });

  test('outside Halloween there is no hunt', async ({ page }) => {
    await page.addInitScript(() => localStorage.setItem('pumpkins', '[0,1,2,3,4]'));
    await off(page);
    await page.goto('/');
    await expect(html(page)).toHaveAttribute('data-live', '');
    await expect(page.getByRole('button', { name: 'Pumpkin' })).toHaveCount(0);
    await expect(counter(page).filter({ visible: true })).toHaveCount(0);
    await expect(stamp(page)).toHaveText("'69 7 20");
  });
});
