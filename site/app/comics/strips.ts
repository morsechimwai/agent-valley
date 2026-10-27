// The funnies' RSS feed, named in the head of every page so readers can find it.
export const FEED = { 'application/rss+xml': [{ url: 'https://agentvalley.app/comics/feed.xml', title: 'The Valley Funnies' }] };

// Who draws and writes the strips: the byline on every strip, and the author for search engines.
export const AUTHOR = { name: 'morsechimwai', url: 'https://github.com/morsechimwai' };

/** A strip's day in words, the American way, in the Gregorian calendar: October 23, 2026. */
export const longDate = (d: string) =>
  new Date(`${d}T00:00:00Z`).toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric', timeZone: 'UTC' });

// Every crew comic, oldest first. The funnies page, each story page, the sitemap and the edition
// line all read this; a story page adds its own article under the strip.
export type Strip = {
  slug: string;
  title: string;
  date: string;
  starring: string;
  /** On the funnies page: what happens, and what the story page explains. */
  deck: string;
  inside: string;
  /** The picture in words, with everything said in it. */
  alt: string;
  /** The story page's title and summary for search results and shares, and its first paragraph. */
  headline: string;
  description: string;
  lead: string;
  /** What they say, panel by panel: the time or number on the panel, then the words. */
  panels: [string, string][];
};

export const STRIPS: Strip[] = [
  {
    slug: 'lunch-break',
    title: 'Lunch break',
    date: '2026-10-18',
    starring: 'Sunny',
    deck: 'Claude Code asks to run npm install a minute after you leave for lunch, then waits the whole hour for an answer.',
    inside: 'Inside: why it waits, and the fix.',
    alt: 'Four-panel comic. 12:00, Sunny at his desk: “You’re at lunch? I’ll have the refactor done before you’re back.” 12:01, pointing at a dialog on his screen: “First, may I run npm install?” 12:40, he waves by the empty chair. 1:05, still waving: “I switched arms at half past.”',
    headline: 'Lunch break: Claude Code waits for permission while you eat',
    description:
      'A four-panel comic about Claude Code asking to run npm install a minute after you leave for lunch, and how to stop it waiting an hour for you.',
    lead: 'You leave Claude Code with a refactor and go to lunch. A minute later it asks to run a command, and then it waits for you the whole hour.',
    panels: [
      ['12:00', 'Sunny, at the desk: “You’re at lunch? I’ll have the refactor done before you’re back.”'],
      ['12:01', 'Sunny points at a dialog on the screen: “First, may I run npm install?”'],
      ['12:40', 'Sunny stands by the empty chair, waving.'],
      ['1:05', 'Sunny, still waving: “I switched arms at half past.”'],
    ],
  },
  {
    slug: 'last-prompt',
    title: 'Last prompt',
    date: '2026-10-18',
    starring: 'Norm, Sunny and Walt',
    deck: 'Two percent of the weekly limit left, one prompt to spend, and it goes on “fix it”.',
    inside: 'Inside: where to see your limits, and a prompt worth the last two percent.',
    alt: 'Four-panel comic. Tuesday. Norm points at a meter on his screen: “Weekly limit at 98 percent.” Sunny folds his hands: “Last prompt of the week. Let’s make it count.” The screen reads “> fix it”. Norm, Sunny and Walt sit over coffee, and Walt says: “See you Thursday.”',
    headline: 'Last prompt: Claude Code at 98% of the weekly limit',
    description:
      'A four-panel comic about spending the last prompt of the week on “fix it”, and how to watch your Claude Code limits and write a prompt that counts.',
    lead: 'The weekly limit is at 98 percent. There is room for one more prompt, so the crew thinks it over, and sends “fix it”.',
    panels: [
      ['1', 'Tuesday. Norm points at a meter on his screen: “Weekly limit at 98 percent.”'],
      ['2', 'Sunny, hands folded: “Last prompt of the week. Let’s make it count.”'],
      ['3', 'The screen: “> fix it”'],
      ['4', 'Norm, Sunny and Walt over coffee. Walt: “See you Thursday.”'],
    ],
  },
  {
    slug: 'typo-case',
    title: 'The typo case',
    date: '2026-10-18',
    starring: 'Pearl and Judy',
    deck: 'Pearl reads the bill from the last page first: $7.30 to fix “recieve”. Judy has a song about it.',
    inside: 'Inside: what made one typo cost $7.30.',
    alt: 'Four-panel comic. Pearl studies a cost chart through a magnifying glass: “Someone spent $7.30 fixing one typo.” She reads a long printout: “Always start at the last page.” On the desk lies a report titled “Fixing ‘recieve’”. Judy plays a sunburst guitar: “I wrote a song about it too.”',
    headline: 'The typo case: why one small fix cost $7.30 in Claude Code',
    description:
      'A four-panel comic about a Claude Code session that spent $7.30 fixing one typo, and why a small task gets expensive at the end of a long conversation.',
    lead: 'Pearl reads a long session from the last page first. The total: $7.30. The task: one typo.',
    panels: [
      ['1', 'Pearl studies a cost chart through a magnifying glass: “Someone spent $7.30 fixing one typo.”'],
      ['2', 'She reads a long printout, a pile of pages beside her: “Always start at the last page.”'],
      ['3', 'On the desk, the report’s cover: “Fixing ‘recieve’”.'],
      ['4', 'Judy, with a sunburst guitar: “I wrote a song about it too.”'],
    ],
  },
  {
    slug: 'explore',
    title: 'Explore',
    date: '2026-10-18',
    starring: 'Sunny and Faye',
    deck: 'Sunny asks Faye, the Explore agent, for the login button. 214 tool uses later, it is in the file he has open.',
    inside: 'Inside: how to hand Claude Code the right file.',
    alt: 'Four-panel comic. Sunny asks: “Faye, where’s the login button?” Faye walks a desert of printouts, tagged “Explore · 214 tool uses”. She comes back dusty, carrying a stack of paper: “Found it.” Then: “ContentView.swift, line 12.” Sunny points at his screen: “That’s the file I have open.”',
    headline: 'Explore: Claude Code searches the repo for the file you have open',
    description:
      'A four-panel comic about the Explore sub-agent taking 214 tool uses to find a button in the file you already had open, and how to point Claude Code at the right file.',
    lead: 'Sunny asks where the login button is. Faye, the Explore sub-agent, searches the whole repository and comes back with the answer: the file Sunny has open.',
    panels: [
      ['1', 'Sunny at his desk: “Faye, where’s the login button?”'],
      ['2', 'Faye walks a desert of printouts. The tag reads “Explore · 214 tool uses”.'],
      ['3', 'She is back, dusty, carrying a stack of paper: “Found it.”'],
      ['4', 'Faye: “ContentView.swift, line 12.” Sunny points at his screen: “That’s the file I have open.”'],
    ],
  },
  {
    slug: 'plan-mode',
    title: 'Plan mode',
    date: '2026-10-18',
    starring: 'Sunny and Judy',
    deck: 'Sunny wants one button renamed. Judy, the Plan agent, brings a 38-step plan, and step 38 is the rename.',
    inside: 'Inside: when a plan pays off, and when to skip it.',
    alt: 'Four-panel comic. Sunny, at his terminal, to Judy: “Rename one button. Just do it.” Judy at a blank chalkboard, chalk raised: “First, a plan.” A chalk flowchart covers the whole wall, tagged “Plan · 38 steps”, while Judy adds a box from a stepladder. Sunny reads the last box: “Step 38: rename the button.” Judy holds out the chalk: “Approve?”',
    headline: 'Plan mode: a 38-step plan to rename one button in Claude Code',
    description:
      'A four-panel comic about Claude Code planning a one-button rename in 38 steps, and when plan mode is worth it and when to just ask for the change.',
    lead: 'Sunny asks for one renamed button. Judy, the Plan agent, wants a plan first, and the plan takes the whole wall.',
    panels: [
      ['1', 'Sunny, at his terminal, to Judy: “Rename one button. Just do it.”'],
      ['2', 'Judy at a blank chalkboard, chalk raised: “First, a plan.”'],
      ['3', 'A chalk flowchart covers the wall. The tag reads “Plan · 38 steps”. Judy adds one more box from a stepladder.'],
      ['4', 'Sunny reads the last box: “Step 38: rename the button.” Judy holds out the chalk: “Approve?”'],
    ],
  },
  {
    slug: 'compact',
    title: 'Compact',
    date: '2026-10-18',
    starring: 'Walt and Felix',
    deck: 'Context at 99 percent. Felix boxes the whole conversation into a summary, and the summary remembers a login button.',
    inside: 'Inside: what compaction keeps, and how to keep the rest.',
    alt: 'Four-panel comic. Walt points at a gauge in the red: “Context at 99 percent.” Felix pushes a mountain of printouts into one small box. The box sits taped shut on a desk, tagged “Compacted”, and Walt’s voice asks: “So, what were we building?” Felix reads a single card from the box while Walt scratches his head: “Something with a login button.”',
    headline: 'Compact: what Claude Code keeps when the context fills up',
    description:
      'A four-panel comic about a whole conversation compacted onto one card, and how to steer what Claude Code keeps when the context window fills up.',
    lead: 'The context is at 99 percent, so the whole conversation goes into one small box. Afterwards, nobody can quite say what they were building.',
    panels: [
      ['1', 'Walt points at a gauge in the red: “Context at 99 percent.”'],
      ['2', 'Felix pushes a mountain of printouts into one small box.'],
      ['3', 'The box sits taped shut on a desk. The tag reads “Compacted”. Walt, from outside the panel: “So, what were we building?”'],
      ['4', 'Felix reads a single card from the box while Walt scratches his head: “Something with a login button.”'],
    ],
  },
  {
    slug: 'tab-7',
    title: 'Tab 7',
    date: '2026-10-18',
    starring: 'Pearl and Walt',
    deck: 'Midnight, lights out. Pearl and Walt check the terminals, and one is still asking Sunny’s question from lunch on Tuesday.',
    inside: 'Inside: how to find the tab that asked, and how to get back to the rest.',
    alt: 'Four-panel comic. 11:58 PM, Pearl stands in a dark doorway with a flashlight: “Someone’s still in the building.” 11:59 PM, she walks past a row of dark terminals: “Tab 3, empty. Tab 5, empty.” 12:00 AM, one screen still glows beside a jack-o’-lantern, a dialog on it from Tuesday 12:01: “First, may I run npm install?” 12:00 AM, Walt, lit from below by his flashlight: “That’s Sunny’s, from lunch on Tuesday.” Pearl: “Poor thing. It’s still waiting.”',
    headline: 'Tab 7: a Claude Code session still waiting since Tuesday',
    description:
      'A four-panel comic about a Claude Code tab that has waited for permission since Tuesday lunch, and how to find the tab that asked and get back to the rest.',
    lead: 'Midnight in the office. Pearl and Walt walk the dark terminals with a flashlight, and one tab is still asking the question Sunny left at lunch on Tuesday.',
    panels: [
      ['11:58 PM', 'Pearl stands in a dark doorway with a flashlight: “Someone’s still in the building.”'],
      ['11:59 PM', 'She walks past a row of dark terminals: “Tab 3, empty. Tab 5, empty.”'],
      ['12:00 AM', 'One screen still glows beside a jack-o’-lantern, a dialog on it from Tuesday 12:01: “First, may I run npm install?”'],
      ['12:00 AM', 'Walt, lit from below by his flashlight: “That’s Sunny’s, from lunch on Tuesday.” Pearl: “Poor thing. It’s still waiting.”'],
    ],
  },
  {
    slug: 'just-watching',
    title: 'Just watching',
    date: '2026-10-23',
    starring: 'Sunny',
    deck: 'You put your own sketch off to watch Claude Code type. Sunny types no faster, and at six the sketch pad is still blank.',
    inside: 'Inside: the two moments it needs you, and how to hear about them.',
    alt: 'Four-panel comic. 2:00, Sunny types at his terminal, a blank sketch pad and a pencil beside him. From off the panel: “I’ll sketch the new screen later. Let me watch you first.” 3:30, his eyes slide toward the reader: “I don’t type faster when you watch.” 6:00, evening, he stretches, the sketch pad still blank: “Done. Same time tomorrow? You can watch again.” Next day, a Mac screen: Sunny’s pixel face at work in the notch, over a window with a wireframe sketch and a pencil: “Go sketch. I’ll wave when I need you.”',
    headline: 'Just watching: when you babysit Claude Code instead of working',
    description:
      'A four-panel comic about watching Claude Code work all afternoon while your own sketch waits, and how to hear when it needs you or finishes instead.',
    lead: 'You hand Claude Code a task and sit down to watch it, just for a minute. The minute lasts all afternoon, and your own work waits.',
    panels: [
      ['2:00', 'Sunny types at his terminal, a blank sketch pad and a pencil beside him. You, from off the panel: “I’ll sketch the new screen later. Let me watch you first.”'],
      ['3:30', 'Sunny keeps typing, his eyes sliding your way: “I don’t type faster when you watch.”'],
      ['6:00', 'Evening. Sunny stretches, the sketch pad still blank: “Done. Same time tomorrow? You can watch again.”'],
      ['Next day', 'Sunny works in the notch at the top of your screen while you sketch the new screen: “Go sketch. I’ll wave when I need you.”'],
    ],
  },
  {
    slug: 'both-on-main',
    title: 'Both on main',
    date: '2026-10-27',
    starring: 'Norm and Pearl',
    deck: 'Two tasks, two sessions, one folder. Norm and Pearl both need LoginView.swift, and both of them are on main.',
    inside: 'Inside: how to give each session a worktree of its own.',
    alt: 'Four-panel comic. 10:00, Norm and Pearl at their terminals, side by side. From off the panel: “Norm, fix the login. Pearl, add dark mode.” 10:40, the two pull one long printout between them. Norm: “I need LoginView.swift.” Pearl: “So do I.” Then the printout lies torn in half on a floor of crumpled paper and loose tape, tagged “CONFLICT”: “Which branch were you on?” Both: “main.” 11:30, the AgentValley panel shows two sessions, Fix the login and Add dark mode, both in shop-web on main, both on “Edit LoginView.swift”. Pearl: “It said so at ten.”',
    headline: 'Both on main: two Claude Code sessions in the same folder',
    description:
      'A four-panel comic about two Claude Code sessions editing the same file on the same branch, and how to give each session its own git worktree.',
    lead: 'Two tasks, two Claude Code sessions, one folder. They meet in the same file, on the same branch, before anyone looks.',
    panels: [
      ['10:00', 'Norm and Pearl at their terminals. You, from off the panel: “Norm, fix the login. Pearl, add dark mode.”'],
      ['10:40', 'The two pull one long printout between them. Norm: “I need LoginView.swift.” Pearl: “So do I.”'],
      ['Later', 'The printout lies torn in half on a floor of crumpled paper and loose tape. The tag reads “CONFLICT”. You: “Which branch were you on?” Norm and Pearl: “main.”'],
      ['11:30', 'The AgentValley panel: both sessions in shop-web, both on main, both on “Edit LoginView.swift”. Pearl: “It said so at ten.”'],
    ],
  },
];
