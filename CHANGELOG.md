# Changelog

## 0.3.12 — 2026-10-27

- When a sub-agent asks for permission, only its own row says needs you now, with Allow and Deny under it. The lead's row used to say it too, with a second Go to button, and the bar counted one prompt as two.
- This needs the plugin that answers from the notch. Without it the notch can't tell which agent asked, so the lead says needs you as before.

## 0.3.11 — 2026-10-27

- The sub-agent rows in Claude Code's terminal wear the notch's own marks now: the same folder before the project and the same branch before the branch name, and a worktree shows the worktree mark, as in the panel. Before, they had a box and a fork that didn't say much.
- The marks come in a new version of our font. Reopen your terminal once after the update to see them; until then the rows keep the old ones.

## 0.3.10 — 2026-10-27

- Claude Code's list of sub-agents fits your terminal now. With three or more, each takes one line, and a finished one always does, so none drops off the bottom where you can't scroll to it.
- Each line says what that sub-agent is doing right now: Find the login code · Read login.ts, and Thinking between steps. When they all run on the same model, the lines leave the model out to make room.

## 0.3.9 — 2026-10-27

- When a sub-agent asks for something the notch can't show in full, the prompt now comes up in your terminal at once. Before, the notch told you to answer in the terminal while the terminal showed nothing for up to ten minutes.
- Hide a sub-agent's request in the notch and the terminal asks right away too.

## 0.3.8 — 2026-10-26

- Open the envelope of finished sub-agents and they sit inside it now: one step further in, each on a line from the envelope, not from the lead. The lead's line ends at the envelope.

## 0.3.7 — 2026-10-26

- Answering from the notch takes one press now. Settings › Claude Code has an Install the plugin button: it runs Claude Code's own `claude plugin` command, and the switch turns on once the plugin is in. Then start Claude Code again; sessions already open don't have it.
- Until then, a session that waits on you shows Answer here next time beside Go to its app, and it takes you to that button.
- Rather paste the command yourself? It's still there to copy, and we turn the switch on when we see the plugin arrive.
- We run `claude plugin` only when you press Install, never on our own.

## 0.3.6 — 2026-10-26

- Export PDF writes a plain statement of work now, one you can hand a client as it is: the project and the period at the top, the total at API prices beside them, a bar for each day, what each agent and each model cost, and a line for every session or project. Our mark sits small in the bottom-right corner. Our faces stay out of it.
- By agent names agents the way Claude Code does: Main sessions, general-purpose, Explore, Plan, and Other agents.
- However long the month, every page keeps its margins, and its foot says the amounts are what Anthropic's API would charge.

## 0.3.5 — 2026-10-25

- When ALL would run past the bottom of the panel, sessions fold to one line each instead, still showing the file we're on, so your second project stays in sight. Quiet sessions fold first, then working ones from the bottom up. One that needs you never folds, and one with sub-agents at work stays open longest.
- Inside a session, pixel lines run from the lead to each sub-agent. A white pixel runs down the line when a sub-agent starts and back up when it hands its work in. When one is waiting on you, its line turns red.
- Finished sub-agents fold into one line marked with a sealed envelope: work handed back. Folding into that line no longer shows the words on top of each other for a moment.

## 0.3.4 — 2026-10-25

- When a session needs you, a red badge beside "needs you" counts how long it has waited, and the bar shows the longest wait once it passes a minute. Grouped by status, the longest wait comes first. Thanks to Leo Heo for asking.
- When we've all stopped but something we started is still running, a dev server or a watch on CI, a small green terminal sits beside the mug. Open the panel to see what runs and for how long. After half an hour it holds still and dims. The done sound waits for those jobs to finish.
- A new version shows as a green dot on the gear and on the About tab. About says which version came in, and one click opens it.
- Turn sounds on with the speaker button and whoever leads says so. Turn them off and they stop mid-word.

## 0.3.3 — 2026-10-24

- If your MacBook sits beside a bigger screen, we can sit on that one instead. Settings › General › Display lists the displays you have connected. Automatic keeps us at the notch, or on your main display when there is no notch. Unplug the one you picked and we come back to Automatic, then move over again when you plug it back in. Thanks to DJ Sipe for asking.

## 0.3.2 — 2026-10-24

- Sounds are on from the start now, so the first time a session needs you, you hear which of us it is. If you never touched the Sounds switch, that goes for you too after this update. Settings › Sounds turns us quiet again, and we still keep quiet while the screen is locked.

## 0.3.1 — 2026-10-24

- On each card, what we're doing right now reads first and the clock ticking beside it steps back a shade. The session's name is the one bold line; its agents' names are set plain.
- When a question you can answer from the notch sits further down the list, the line at the bottom says so, "1 to answer here", and its red count jumps once when the question arrives.
- The red count now swells from its number alone, so it no longer runs over the words beside it.
- The small grey words in History and Settings are a touch darker and easier to read.

## 0.3.0 — 2026-10-24

- We talk now. When a session needs you, its regular plays a few notes on their own instrument and says what it's about: a command to run, a file to edit, a question, a plan. Judy brings the plans herself. When the work is done you hear that too, with a different line after a long session, late at night, or for the first one of the morning.
- When a plan limit runs out, one of us tells you we've gone fishing, or taken the van for the weekly one, and the same one tells you when we're back. Only once the reset has really passed.
- Settings › Sounds has a Voice choice: Crew talks, Crew, no talking (just the instruments), or Chimes, the Glass and Pop you had before. Sounds stay off until you turn them on, and quiet while the screen is locked. Lock it mid-sentence and we stop mid-sentence.
- In the status line, an agent's time keeps its seconds past ten minutes, the way Claude Code writes it.

## 0.2.12 — 2026-10-23

- A click anywhere on a session's row, or on one of its agents' rows, takes you to its terminal, not just a click on the name. Allow and Deny stay out of the clickable part, so a near miss keeps you here.

## 0.2.11 — 2026-10-23

- History and the PDF report keep one line per project too. A worktree, or a folder inside the project, counts toward the project it came from, even after Superset has tidied the worktree away. Your old history joins up as well, as far as we can still tell where it came from.

## 0.2.10 — 2026-10-23

- The ALL tab sorts us by project now. Each project gets its own line over its cards, and a worktree from Superset or Claude Code sits with the repository it came from, so you can tell at a glance which of us is on which branch.
- Under its project's line, a card no longer repeats the folder name when it's just the project's name again.
- A worktree is part of its project now, regular included. A new Superset workspace no longer means a new face at the desk.

## 0.2.9 — 2026-10-23

- Each of your projects has a regular now: the same one of us every session, even after you quit and reopen the app. Open a second session in the same project while the first is still going, and a colleague takes it, since nobody is in two places at once. Nobody switches seats while a session runs, and /clear keeps whoever was sitting there. A new worktree is a new project, with a regular of its own.
- We all get seated fresh once after this update, so a familiar face may change one last time.

## 0.2.8 — 2026-10-23

- A new session in Claude Code's terminal no longer shows Sunny and then someone else. Until your first prompt a coffee waits in the status line, On standby, and whoever takes the session sits down with your first message. The coffee waits there while the app is closed, too.
- When a limit runs out, the status line goes fishing as well, or takes the van for the weekly one.
- The coffee, the fish and the van come in a new version of our font. Reopen your terminal once after the update to see them.

## 0.2.7 — 2026-10-23

- Run /clear while Claude is still answering, and the old session hung around on the bar for ten minutes, still at work, with a different one of us than the face in your terminal. Now when Claude Code clears a session, quits, or switches to another, that session clocks out right away.

## 0.2.6 — 2026-10-21

- Every button on the About page has a small picture in front of it now. Report a bug got a ladybug, the only kind of bug we're happy to see.

## 0.2.5 — 2026-10-21

- Settings had grown into one long scroll, and we kept losing Quit at the bottom of it. Now there are five pages: General, Sounds, Shortcuts, Claude Code and About, and their names stay at the top while you scroll. Quit lives on About.
- A setting's name is bold now, with what it does in smaller grey underneath. Rows that only matter when another switch is on stay on the page greyed out, instead of disappearing.

## 0.2.4 — 2026-10-21

- When the weekly limit runs out we don't go fishing, we take the van. The bar shows it on the road, and the sign over the list says On vacation.
- The signs are painted boards on a real rope now, lettered in the same square pixels as us.

## 0.2.3 — 2026-10-21

- When your 5-hour or weekly limit hits 100%, we go fishing. The coffee on the bar turns into a fish on the line, and a sign over the list says when we're back. It needs Plan limits on in Settings.

## 0.2.2 — 2026-10-20

- We no longer bob up and down at work. It looked like waiting. Between things, and on a call we have no picture for, we think, chin in hand, the dots coming.

## 0.2.1 — 2026-10-20

- Homebrew leaves our 0.1 installed when you move to the cask, and it kept opening at login beside us. Now it steps out as soon as it opens, and the panel shows the one command that takes it out for good: `brew uninstall --formula agent-valley`.

## 0.2.0 — 2026-10-20

We moved house. AgentValley is now an app you download, signed with a Developer ID and checked by Apple.

- Download AgentValley.dmg and drag it into Applications. With Homebrew: `brew install --cask morsechimwai/tap/agent-valley`.
- We check GitHub for a new version once a day and ask before we install it. The switch, and Check now, are in Settings.
- Open us from the dmg or from Downloads and we'll offer to move ourselves to Applications.
- Only one of us runs at a time. Open another copy and the old one steps out.
- On 0.1 from Homebrew? Run `brew uninstall --formula agent-valley`, then download the dmg or install the cask. Homebrew won't move you over by itself.
- The plugin may still point at the old copy. The panel says so when it does; copy its command from Settings once more.
- Put the crew in Claude Code's terminal on 0.1? Its status line still calls the old copy and goes blank once that's gone. Copy the crew's install command from the Actions settings and run it once more.
- To macOS we're a new app, so it may ask again: to let us work your terminal when you jump to an agent, and, with Plan limits on, to read your Claude Code login from the Keychain.

## 0.1.4 — 2026-10-19

- At work, we hold what the agent is on: a printout while it reads, a keyboard while it edits, a terminal while it runs a command, a magnifier while it searches, a phone while a sub-agent works for it, and a chin in one hand while it thinks. Six seconds in hand, two to put it down. The faces in Claude Code's terminal hold the same things, standing still. Reopen your terminal once after updating to see them there.
- Report a bug, in Settings, opens a new GitHub issue with the app's version, macOS and Mac model filled in. Your browser sends it; the app still sends nothing.
- Long transcripts open faster and take far less memory. A 116 MB one used to take 0.96 s and 314 MB more memory, and now takes 0.41 s and 12 MB. History's first pass over a big folder of transcripts is about three times quicker.
- The status line's context meter says `context`, not `ctx`.
- The crew's font is a quarter of its old size.

## 0.1.3 — 2026-10-17

- History has its own button at the top of the panel, a chart beside the pin. The token line at the end of the list still opens it, but it never looked like something to press.

## 0.1.2 — 2026-10-17

- The crew comes to Claude Code's terminal too. The status line under the prompt gets the face of whoever runs the session, with the model, your plan and your limits, and each sub-agent row gets a face, its model and its current step. Set it up in the Actions settings, under Crew in the terminal. It keeps working with the app closed. Tried in Terminal, iTerm2, Ghostty and Cursor.
- Export PDF, at the top of History, makes an A4 report of the day, week or month on screen. Press it on All projects for every project, or on one project for its sessions alone, with no other project's name in it, to hand to a team or a client.
- If you remove the app, take the crew out of the terminal first, with the command under How to take it out in the Actions settings. Otherwise Claude Code's status line goes blank.

## 0.1.1 — 2026-10-16

- Open at login keeps working after `brew upgrade`. macOS remembers the app by its folder, and Homebrew gives each version a new one; the app now tells macOS where it is when it opens from a new folder. If you turned Open at login on in 0.1.0, quit the app and open it again after upgrading.

## 0.1.0 — 2026-10-16

The first public release.

- Every Claude Code session gets a card in the notch, and every agent and sub-agent a row with its task, model and latest step.
- A red count beside the notch when an agent asks a question or waits for permission.
- Jump to the agent's app in one click.
- Allow once or Deny from the notch, with a plugin you install yourself.
- History: what each project cost by day, week or month, at API prices.
- Plan limits, token use, and a keyboard shortcut (⌃⌥⌘A).
