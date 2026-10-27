#!/bin/sh
# Hands Claude Code's permission request to the AgentValley notch app and prints its answer.
#
# Prints nothing unless the app answers, and always exits 0: with no output Claude Code asks in
# the terminal exactly as it would without this plugin. The terminal prompt stays usable while
# this waits, and whichever answer comes first is the one Claude Code uses. Not for a sub-agent:
# its prompt shows only once this is done, so the app lets go at once of what it cannot answer.
SOCK="$HOME/Library/Application Support/AgentValley/answers.sock"
[ -S "$SOCK" ] || exit 0
# -q first: the person's own ~/.curlrc must not add anything to what is printed here.
/usr/bin/curl -q --silent --fail --max-time 590 --unix-socket "$SOCK" \
  --header 'Content-Type: application/json' --data-binary @- \
  http://notch/permission-request 2>/dev/null
exit 0
