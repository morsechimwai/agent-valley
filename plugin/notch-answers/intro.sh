#!/bin/sh
# Asks the AgentValley notch app who this new session, or this sub-agent, is drawn as, and prints
# the note it answers so Claude Code adds it to the agent's context.
#
# Prints nothing and always exits 0 unless the app answers: with no app, its switch off, or a
# scripted run, the session starts exactly as it would without this plugin.
# `claude -p` and other scripted runs (entrypoint sdk-…) get no names: scripts read their output.
case "$CLAUDE_CODE_ENTRYPOINT" in ""|sdk-*) exit 0 ;; esac
SOCK="$HOME/Library/Application Support/AgentValley/answers.sock"
[ -S "$SOCK" ] || exit 0
# -q first: the person's own ~/.curlrc must not add anything to what is printed here.
# CLAUDE_PID lets the app tell, after /clear, which session this terminal ran until now;
# TERM_PROGRAM, whether this terminal's config lets it draw the crew's name tags.
/usr/bin/curl -q --silent --fail --max-time 2 --unix-socket "$SOCK" \
  --header 'Content-Type: application/json' --header "X-Claude-Pid: ${CLAUDE_PID:-}" \
  --header "X-Term-Program: ${TERM_PROGRAM:-}" --data-binary @- \
  http://notch/crew-intro 2>/dev/null
exit 0
