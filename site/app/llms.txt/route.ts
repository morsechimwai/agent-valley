import { STRIPS } from '../comics/strips';

export const dynamic = 'force-static';

// The site in plain Markdown for AI assistants and the search engines built on them (llmstxt.org).
export function GET() {
  const comics = STRIPS.map((s) => `- [${s.headline}](https://agentvalley.app/comics/${s.slug}/): ${s.description}`).join('\n');
  const text = `# AgentValley

> A free, open-source Mac app that shows every Claude Code agent, sub-agents too, in your Mac's notch: who is working, on which model, and who needs you.

AgentValley is for Claude Code on macOS 15 or later. It sits in a MacBook's notch, or at the top of the main display on a Mac without one. Download AgentValley.dmg from the latest GitHub release (signed with a Developer ID and notarized by Apple), or install it with Homebrew: \`brew install --cask morsechimwai/tap/agent-valley\`. The source is on GitHub under the MIT license. It is not affiliated with Anthropic.

## Pages

- [AgentValley](https://agentvalley.app/): what the app shows in the notch, and how to install it
- [Source code](https://github.com/morsechimwai/agent-valley): the app, its Claude Code plugin and this site
- [The Valley Funnies](https://agentvalley.app/comics/): four-panel comics about working with Claude Code, each with a short article

## Comics

${comics}
`;
  return new Response(text, { headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
}
