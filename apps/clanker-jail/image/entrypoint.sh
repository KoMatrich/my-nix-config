#!/usr/bin/env bash
# Container main process (tini from `docker run --init` is PID 1 above it).
set -euo pipefail

# Claude Code and T3 Code live in the home volume, not the image: both update
# themselves, and those updates (plus the Claude login and T3 Code's threads)
# survive `clanker reset` and image rebuilds.
if ! command -v claude >/dev/null; then
  echo "clankerjail: installing Claude Code..."
  curl -fsSL https://claude.ai/install.sh | bash
fi
if ! command -v t3 >/dev/null; then
  echo "clankerjail: installing T3 Code..."
  curl -fsSL https://t3.codes/install.sh | sh
fi

# Seed the agent's global instructions and settings once; later edits stay.
mkdir -p "$HOME/.claude"
[ -e "$HOME/.claude/CLAUDE.md" ] || cp /etc/clankerjail/CLAUDE.md "$HOME/.claude/CLAUDE.md"
[ -e "$HOME/.claude/settings.json" ] || cp /etc/clankerjail/settings.json "$HOME/.claude/settings.json"

# 0.0.0.0 inside the container's own network namespace; the host publishes it
# on 127.0.0.1 only. Clients other than in-container ones must pair first.
echo "clankerjail: starting T3 Code server"
exec t3 serve --host 0.0.0.0 --port 3773 --no-browser /work
