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
# Which login this session pays with, so the app shows plan limits or what today cost. Only the
# kind is sent, never a key or a token. Same order Claude Code picks a login in; nothing found
# means a /login, and the app reads which kind from the Keychain itself.
# ponytail: apiKeyHelper and ANTHROPIC_PROFILE are not looked at; such a session falls back to the
# Keychain's kind. Add them here if someone using them sees the wrong bar.
on() { case "$1" in 1|[Tt][Rr][Uu][Ee]|[Yy][Ee][Ss]|[Oo][Nn]) return 0 ;; esac; return 1; }
LOGIN=
if on "$CLAUDE_CODE_USE_BEDROCK"; then LOGIN=bedrock
elif on "$CLAUDE_CODE_USE_VERTEX"; then LOGIN=vertex
elif on "$CLAUDE_CODE_USE_FOUNDRY"; then LOGIN=foundry
elif [ -n "$ANTHROPIC_AUTH_TOKEN" ]; then LOGIN=gateway
elif [ -n "$ANTHROPIC_API_KEY" ]; then
  LOGIN=api
  # A key the person told Claude Code not to use: it is kept by its last 20 characters. The
  # match stays inside this shell, so no part of the key reaches another program's arguments.
  REJECTED=$(/usr/bin/plutil -extract customApiKeyResponses.rejected json -o - \
    "${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json" 2>/dev/null)
  END=${ANTHROPIC_API_KEY#"${ANTHROPIC_API_KEY%????????????????????}"}
  case "$REJECTED" in *"\"${END:-$ANTHROPIC_API_KEY}\""*) LOGIN= ;; esac
fi
if [ -z "$LOGIN" ] && [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then LOGIN=plan; fi
# -q first: the person's own ~/.curlrc must not add anything to what is printed here.
# CLAUDE_PID lets the app tell, after /clear, which session this terminal ran until now;
# TERM_PROGRAM, whether this terminal's config lets it draw the crew's name tags.
/usr/bin/curl -q --silent --fail --max-time 2 --unix-socket "$SOCK" \
  --header 'Content-Type: application/json' --header "X-Claude-Pid: ${CLAUDE_PID:-}" \
  --header "X-Term-Program: ${TERM_PROGRAM:-}" --header "X-Claude-Login: $LOGIN" --data-binary @- \
  http://notch/crew-intro 2>/dev/null
exit 0
