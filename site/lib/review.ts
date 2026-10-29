export type HandleSite = 'github' | 'x';

export const MAX_WORDS = 500;
const SHAPE = { github: /^[A-Za-z0-9-]{1,39}$/, x: /^[A-Za-z0-9_]{1,15}$/ };

// The stars from ?stars=: 1 to 5, or none.
export function starsFromQuery(value: string | null): number | null {
  return value && /^[1-5]$/.test(value) ? Number(value) : null;
}

const HOST = { github: 'github\\.com', x: '(x|twitter)\\.com' };

// What was typed or pasted for a handle: a leading @ or a profile link goes, the name stays.
// Only a link to the picked site: one to the other site is left as it is, and fails the check.
export function cleanHandle(raw: string, site: HandleSite): string {
  const link = new RegExp(`^(https?://)?(www\\.|mobile\\.)?${HOST[site]}/`, 'i');
  return raw.trim().replace(link, '').replace(/^@/, '').split(/[/?#\s]/)[0];
}

// An empty handle is fine; a typed one must fit the site's rules.
export function handleOk(handle: string, site: HandleSite): boolean {
  return handle === '' || SHAPE[site].test(handle);
}

// The body for PostHog's capture endpoint, the way the app sends its events.
export function reviewBody(
  token: string,
  r: { stars: number; words: string; name: string; handle: string; site: HandleSite; show: boolean },
  id: string,
) {
  // Unticked, it stays private, so it comes without who wrote it.
  const handle = (r.show && r.handle) || null;
  return {
    api_key: token,
    event: 'review sent',
    distinct_id: id,
    properties: {
      stars: r.stars,
      words: r.words.trim(),
      name: r.show ? r.name.trim() : '',
      handle,
      handle_site: handle ? r.site : null,
      show: r.show,
      $process_person_profile: false,
    },
  };
}
