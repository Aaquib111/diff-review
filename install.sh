#!/usr/bin/env bash
# install.sh — install the `review` tool into the standard user locations.
# Idempotent; safe to re-run. Override targets with the env vars shown below.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BIN_DIR="${REVIEW_BIN_DIR:-$HOME/.local/bin}"
CONFIG_DIR="${REVIEW_CONFIG_DIR:-$HOME/.config/review}"
COMMANDS_DIR="${REVIEW_COMMANDS_DIR:-$HOME/.claude/commands}"

echo "Installing review:"

# 1. Launcher
mkdir -p "$BIN_DIR"
install -m 0755 "$SRC/bin/review" "$BIN_DIR/review"
echo "  launcher    -> $BIN_DIR/review"

# 2. Neovim config + module
mkdir -p "$CONFIG_DIR/lua"
install -m 0644 "$SRC/config/init.lua" "$CONFIG_DIR/init.lua"
install -m 0644 "$SRC/config/lua/review.lua" "$CONFIG_DIR/lua/review.lua"
echo "  nvim config -> $CONFIG_DIR/{init.lua,lua/review.lua}"

# 3. Claude Code slash command
mkdir -p "$COMMANDS_DIR"
install -m 0644 "$SRC/commands/review.md" "$COMMANDS_DIR/review.md"
echo "  /review cmd -> $COMMANDS_DIR/review.md"

# Dependency check (warn only).
echo
missing=0
for dep in nvim tmux; do
  command -v "$dep" >/dev/null 2>&1 || { echo "WARNING: '$dep' not found on PATH"; missing=1; }
done
command -v git >/dev/null 2>&1 || command -v jj >/dev/null 2>&1 \
  || { echo "WARNING: neither 'git' nor 'jj' found on PATH"; missing=1; }

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "WARNING: $BIN_DIR is not on your PATH — add it, e.g.:"; \
     echo "         echo 'export PATH=\"$BIN_DIR:\$PATH\"' >> ~/.zshrc" ;;
esac

[ "$missing" -eq 0 ] && echo "Done. Run 'review' inside a git or jj repo with changes."
