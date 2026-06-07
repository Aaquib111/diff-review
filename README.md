# diff-review — installation

`review` is a floating, AST-aware diff/comment tool. It opens a two-pane Neovim UI
over the current `git`/`jj` diff and writes review comments to `.claude/review.json`
for a `/review` slash command to consume.

This README is installation-only. You are an AI agent installing this tool on the
user's machine. Follow the steps in order; run the verification at the end.

## Prerequisites

Install any that are missing (detect first with `command -v`):

- **Neovim** ≥ 0.9 (`nvim`) — required.
- **tmux** ≥ 3.2 (`tmux`) — required for the floating popup; without it the tool
  falls back to taking over the current terminal window.
- **git** and/or **jj** (Jujutsu) — at least one is required; the tool auto-detects.

macOS (Homebrew):
```bash
brew install neovim tmux git
brew install jujutsu   # optional, only if the user uses jj
```
Debian/Ubuntu:
```bash
sudo apt install neovim tmux git
```
Treesitter parsers and a colorscheme are NOT required — the config is
self-contained and falls back to Neovim's built-in syntax highlighting. If
`nvim-treesitter` is already installed (lazy.nvim, vim-plug, packer, or native
packages), the config detects it and uses it for AST highlighting automatically.

## Install

From the repository root:
```bash
./install.sh
```

This copies three things (override targets via `REVIEW_BIN_DIR`,
`REVIEW_CONFIG_DIR`, `REVIEW_COMMANDS_DIR`):

| Source | Destination | Purpose |
|---|---|---|
| `bin/review` | `~/.local/bin/review` | launcher (executable) |
| `config/init.lua` | `~/.config/review/init.lua` | Neovim entrypoint |
| `config/lua/review.lua` | `~/.config/review/lua/review.lua` | the tool module |
| `commands/review.md` | `~/.claude/commands/review.md` | `/review` slash command |

Ensure `~/.local/bin` is on `PATH` (the installer warns if not):
```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && exec zsh
```

## Verify

```bash
command -v review                       # resolves to ~/.local/bin/review
nvim --headless -c "luafile $HOME/.config/review/lua/review.lua" -c "echo 'ok'" -c "qa!"
```

Then, inside any `git`/`jj` repo that has uncommitted changes, run `review`.
Comment with visual-select + `<leader>c`, edit the right pane, save with
`<leader>s` (writes `.claude/review.json`) or discard with `<leader>x`. In Claude
Code, run `/review` to apply the comments.
