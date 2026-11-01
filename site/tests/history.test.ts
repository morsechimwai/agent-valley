import { expect, test } from 'vitest';
import { dollars, historyView, nextPick, noise, openAt, spanTitle, startOf, weekStart, wholeDollars, type Pick, type Span } from '@/lib/history';

// The values are the old page's own, worked out by its script for this same moment.
const now = new Date(2026, 9, 16, 15, 30);
const at = (span: Span, extra: Partial<Pick> = {}): Pick => ({ span, anchor: now, project: null, day: null, hour: null, first: 1, ...extra });

test('month', () => expect(historyView(at('Month'), now).announce).toBe('October 2026, $1,261.12'));
test('week', () => expect(historyView(at('Week'), now).announce).toBe('Oct 12 – 18, 2026, $467.41'));
test('day', () => expect(historyView(at('Day'), now).announce).toBe('Fri, Oct 16, 2026, $42.38'));
test('one project', () => expect(historyView(at('Month', { project: 0 }), now).announce).toBe('October 2026, shop-web, $628.47'));
test('two months back', () => expect(historyView(at('Month', { anchor: new Date(2026, 7, 1) }), now).announce).toBe('August 2026, $2,101.27'));
test('no earlier than two months back', () => expect(historyView(at('Month', { anchor: new Date(2026, 7, 1) }), now).canEarlier).toBe(false));
test('opens on the month before in the first week', () => expect([
  openAt(new Date(2026, 10, 1, 9)).getTime(), openAt(new Date(2026, 10, 7, 23)).getTime(), openAt(new Date(2026, 10, 8, 0)).getTime(), openAt(new Date(2026, 0, 3)).getTime(),
]).toEqual([new Date(2026, 9, 31).getTime(), new Date(2026, 9, 31).getTime(), new Date(2026, 10, 8, 0).getTime(), new Date(2025, 11, 31).getTime()]));
test('the month before is a full one', () => {
  const nov1 = new Date(2026, 10, 1, 9);
  const v = historyView(at('Month', { anchor: openAt(nov1) }), nov1);
  expect([v.title, v.quiet, v.canLater]).toEqual(['October 2026', false, true]);
});
test('no later than now', () => expect(historyView(at('Month'), now).canLater).toBe(false));
test('money', () => expect([dollars(0), dollars(0.004), dollars(12.5), wholeDollars(0.4), wholeDollars(1234.5)]).toEqual(['$0.00', '<$0.01', '$12.50', '<$1', '$1,235']));
test('titles', () => expect([
  spanTitle('Week', new Date(2026, 8, 28), new Date(2026, 9, 5)),
  spanTitle('Day', new Date(2026, 9, 16), new Date(2026, 9, 17)),
  spanTitle('Month', new Date(2026, 9, 1), new Date(2026, 10, 1)),
]).toEqual(['Sep 28 – Oct 4, 2026', 'Fri, Oct 16, 2026', 'October 2026']));
test('noise', () => expect([noise(0, 20000, 1), noise(3, 20742, 2)]).toEqual([0.24252661713398993, 0.8758266272488981]));
test('picking a day twice clears it', () => {
  const v = String(new Date(2026, 9, 14).getTime());
  const once = nextPick(at('Month'), { a: 'day', v });
  expect(once.day?.getTime()).toBe(+v);
  expect(nextPick(once, { a: 'day', v }).day).toBeNull();
});
test('a picked day and hour join the announcement', () => {
  const day = nextPick(at('Month'), { a: 'day', v: String(new Date(2026, 9, 14).getTime()) });
  const hour = nextPick(day, { a: 'hour', v: '10' });
  expect(historyView(hour, now).announce).toMatch(/^October 2026, \$1,261\.12; Oct 14, 10:00, \$\d/);
});
test("the pick line's ✕ lets go of the hour, then of the day", () => {
  const day = nextPick(at('Month'), { a: 'day', v: String(new Date(2026, 9, 14).getTime()) });
  const hour = nextPick(day, { a: 'hour', v: '10' });
  const line = historyView(hour, now).pickLine!;
  expect(line.text).toMatch(/^Oct 14, 10:00 · \$\d/);
  expect(line.label).toBe('Show all of Oct 14');
  const back = nextPick(hour, line.clear);
  expect([back.day?.getTime(), back.hour]).toEqual([day.day!.getTime(), null]);
  const dayLine = historyView(back, now).pickLine!;
  expect(dayLine.text).toMatch(/^Oct 14 · \$\d/);
  expect(dayLine.label).toBe('Show all of October 2026');
  expect(nextPick(back, dayLine.clear).day).toBeNull();
  expect(historyView(at('Month'), now).pickLine).toBeNull();
});
test('in a day, the ✕ lets go of its hour', () => {
  const line = historyView(nextPick(at('Day'), { a: 'hour', v: '10' }), now).pickLine!;
  expect([line.text.split(' · ')[0], line.label, line.clear.a]).toEqual(['Oct 16, 10:00', 'Show all of Fri, Oct 16, 2026', 'hour']);
});
test('the footnote says since when, and as of when the prices are', () =>
  expect(historyView(at('Month'), now).since).toBe('History since Aug 1, 2026 · API prices as of Oct 15, 2026'));
test("a week starts where the reader's region starts it", () => {
  expect([weekStart('en-US'), weekStart('en-GB'), weekStart('th-TH'), weekStart('not a language')]).toEqual([0, 1, 0, 1]);
  expect(historyView(at('Week', { first: 0 }), now).title).toBe('Oct 11 – 17, 2026');
  // Whatever the first day, the week holds today and starts on it.
  for (let first = 0; first < 7; first++) {
    const start = startOf('Week', now, first);
    expect([start.getDay(), (now.getTime() - start.getTime()) / 864e5 < 7, start <= now]).toEqual([first, true, true]);
  }
});
