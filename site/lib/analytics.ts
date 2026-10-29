import type { PostHog } from 'posthog-js';

// Visits counted with PostHog, on the live site and Vercel's previews only, so tests and this
// Mac's servers count nothing. Nothing is kept in the visitor's browser: no cookie, no storage,
// so each page load is a new visitor. PostHog reads the country from the IP, then drops the IP
// (a setting of the AgentValley project). Events go to /ingest on this site, which Vercel
// passes on to PostHog (vercel.json), so the page still loads nothing from another site.
// ponytail: memory persistence over-counts people who reload; fine for one page.

// The project's public key: it can only send events, never read them.
export const TOKEN = 'phc_BW9fdvDdnyfQmKArTiTCJnQdBwXEFqi7LALhqcYQpAqb'; // gitleaks:allow

let posthog: Promise<PostHog> | undefined;

export function startAnalytics() {
  const host = location.hostname;
  if (host !== 'agentvalley.app' && !host.endsWith('.vercel.app')) return;
  posthog = import('posthog-js').then(({ default: ph }) => {
    ph.init(TOKEN, {
      api_host: '/ingest',
      ui_host: 'https://us.posthog.com',
      defaults: '2026-08-30',
      persistence: 'memory',
      // Page views, clicks on links and buttons, and how far down people read. No recordings,
      // surveys or flags, and no scripts fetched later.
      disable_external_dependency_loading: true,
      disable_session_recording: true,
      disable_surveys: true,
      advanced_disable_flags: true,
    });
    return ph;
  });
}

export function track(event: string, properties?: Record<string, string>) {
  void posthog?.then((ph) => ph.capture(event, properties));
}
