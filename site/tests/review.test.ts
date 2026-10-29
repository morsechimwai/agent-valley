import { expect, test } from 'vitest';
import { cleanHandle, handleOk, reviewBody, starsFromQuery } from '@/lib/review';

test('stars come from the query only when they are 1 to 5', () => {
  expect(starsFromQuery('4')).toBe(4);
  for (const bad of [null, '', '0', '6', '3.5', 'x', '12']) expect(starsFromQuery(bad)).toBeNull();
});

test('a handle loses its @ and a pasted link keeps just the name', () => {
  expect(cleanHandle(' @morse ', 'github')).toBe('morse');
  expect(cleanHandle('https://github.com/morsechimwai/agent-valley', 'github')).toBe('morsechimwai');
  expect(cleanHandle('github.com/morsechimwai', 'github')).toBe('morsechimwai');
  expect(cleanHandle('https://x.com/some_one?s=20', 'x')).toBe('some_one');
  expect(cleanHandle('www.x.com/some_one', 'x')).toBe('some_one');
  expect(cleanHandle('https://twitter.com/@a', 'x')).toBe('a');
});

test('a link to the other site is not taken as a name on this one', () => {
  expect(handleOk(cleanHandle('https://x.com/foo', 'github'), 'github')).toBe(false);
  expect(handleOk(cleanHandle('https://github.com/foo', 'x'), 'x')).toBe(false);
});

test('handles are held to each site\'s characters and length', () => {
  expect(handleOk('', 'x')).toBe(true);
  expect(handleOk('a-b', 'github')).toBe(true);
  expect(handleOk('a_b', 'github')).toBe(false);
  expect(handleOk('a'.repeat(40), 'github')).toBe(false);
  expect(handleOk('a_b', 'x')).toBe(true);
  expect(handleOk('a-b', 'x')).toBe(false);
  expect(handleOk('a'.repeat(16), 'x')).toBe(false);
});

test('the body matches what the app sends', () => {
  const r = { stars: 5, words: ' fine ', name: ' Ann ', handle: 'ann', site: 'x' as const, show: true };
  expect(reviewBody('tok', r, 'id')).toEqual({
    api_key: 'tok',
    event: 'review sent',
    distinct_id: 'id',
    properties: { stars: 5, words: 'fine', name: 'Ann', handle: 'ann', handle_site: 'x', show: true, $process_person_profile: false },
  });
  const none = reviewBody('tok', { ...r, handle: '' }, 'id').properties;
  expect(none.handle).toBeNull();
  expect(none.handle_site).toBeNull();
});

test('unticked, the review comes without a name or an account', () => {
  const r = { stars: 3, words: 'ok', name: 'Ann', handle: 'ann', site: 'github' as const, show: false };
  const p = reviewBody('tok', r, 'id').properties;
  expect(p.name).toBe('');
  expect(p.handle).toBeNull();
  expect(p.handle_site).toBeNull();
});
