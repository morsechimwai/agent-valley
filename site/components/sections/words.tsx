// The words a reader may not know, explained at the back as a 1969 manual did; the crew's photo
// still ends the page. Each is [id, word, meaning]; links elsewhere point at #w-<id>.
const WORDS: [string, string, string][] = [
  ["notch", "notch", "The black cutout at the top of a MacBook screen, around the camera."],
  ["panel", "panel, card, row", "The panel is the black box that opens under the notch. Each session is a card in it, and each agent is a row on a card."],
  ["session", "session", "One conversation with Claude Code in a terminal."],
  ["agent", "agent", "Claude at work on a task. Each session has one, and it can start more."],
  ["sub-agent", "sub-agent", "An agent that a session starts for one task, such as Explore or Plan."],
  ["main", "main", "In History, a session's own agent, apart from its sub-agents."],
  ["types", "Explore, Plan, General-purpose", "The types of sub-agent that come with Claude Code."],
  ["model", "model: Opus, Sonnet, Haiku", "The versions of Claude that do the work, from the most capable to the quickest."],
  ["step", "step", "One thing an agent does, such as reading a file or running a command."],
  ["quiet", "quiet", "An agent that has written nothing for two minutes. It may be waiting for you in its terminal, or stuck."],
  ["crew", "crew", "The little programmers, one for each agent."],
  ["regular", "regular", "Someone who always comes back to the same place, like a regular at a cafe. Here: the one of us who takes every session in your project."],
  ["valley", "valley", "The ground the crew stands on. \"Put the valley in your notch\" means install AgentValley."],
  ["terminal", "terminal", "The app where you type commands and where Claude Code runs. Terminal, iTerm2 and Ghostty are three."],
  ["status-line", "status line, prompt", "The prompt is where you type to Claude Code. The status line is the strip under it, which Claude Code lets an app fill in."],
  ["process", "process", "A program while it is running."],
  ["git", ".git, branch", "A project's .git folder holds its history. A branch is one line of work in it."],
  ["worktree", "worktree", "A second folder of the same project, on a branch of its own. Superset and Claude Code make them so agents can work side by side."],
  ["jump", "jump, Return", "Jump: bring the agent's app to the front, at its window or tab. Return: the Return key, also called Enter."],
  ["tokens", "tokens", "The small pieces of text a model reads and writes. Use and cost are counted in them."],
  ["api", "API prices", "What Anthropic charges for each token you use without a Claude plan. API stands for application programming interface."],
  ["history", "History", "The panel's page of past costs, and the record of them it keeps on your Mac."],
  ["pdf", "PDF", "A file that looks the same on every screen and printer. PDF stands for Portable Document Format."],
  ["statement", "statement of work", "A summary of the work done in a stretch of time and what it cost, to keep or to send to whoever pays."],
  ["limits", "Plan limits", "How much of your Claude plan you may use in 5 hours and in a week."],
  ["homebrew", "Homebrew", "A free tool that installs apps on a Mac from the terminal. Its command is brew."],
  ["open", "open source", "The code is public. Anyone may read it, change it and share it."],
  ["keychain", "Keychain", "Where your Mac keeps passwords and logins, locked."],
  ["hook", "hook", "A small program that Claude Code runs at set moments, such as before it uses a tool."],
  ["plugin", "plugin", "An add-on for Claude Code. Ours comes with the app and goes in when you press Install the plugin."],
  ["glance", "at a glance", "With one quick look."],
  ["end-up", "end up", "To find in the end that you are doing something."],
  ["check-on", "check on", "To look at how something is going."],
  ["nerve", "have the nerve to", "To be brave enough to do something."],
  ["ship", "ship", "To put something out for people to use."],
];

export function Words() {
  return (
    <section className="wrap section more words py-[clamp(56px,10vw,88px)]" id="words">
      <h2 className="mb-7">Words on this page.</h2>
      {/* An index, as at the back of a manual: the word in bold, its meaning running on after it,
          two columns with a rule between. */}
      <dl className="border-t pt-5 min-[760px]:columns-2 min-[760px]:gap-x-14 min-[760px]:[column-rule:1px_solid_var(--border)]">
        {WORDS.map(([id, word, meaning]) => (
          <div key={id} id={`w-${id}`} className="mb-3.5 break-inside-avoid">
            <dt className="mr-2 inline font-mono font-semibold">{word}</dt>
            <dd className="inline text-[.9375rem] text-muted-foreground">{meaning}</dd>
          </div>
        ))}
      </dl>
    </section>
  );
}
