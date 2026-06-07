# diff-review — installation

`review` is a floating, AST-aware diff/comment tool. It opens a two-pane Neovim UI
over the current `git`/`jj` diff and writes review comments to `.claude/review.json`
for a `/review` slash command to consume.

<img width="3024" height="1930" alt="demo" src="https://github.com/user-attachments/assets/b200aea1-a8c9-4221-9dc5-68a294f016b3" />

The image shows the floating pane:

1. The green boxes highlight multi-line comments you can make by making a visual selection in vim, then pressing `<leader>c`.
2. The cyan box highlights all the files that have been edited, and you may move between them.
3. The orange box is an editable vim buffer to directly apply edits instead of suggesting as a comment.

## Usage

1. Run `review` as a bash command either within claude (via `!review` in chat) or in a separate pane.
2. Review the files and add comments as necessary. Use `<leader>s` to save. This saves the comments to `.claude/` as a JSON.
3. In the claude chat, run the `/review` skill. This prompts the model to look at the JSON comments and address them.

## Prerequisites

Install any that are missing (detect first with `command -v`):

- **Neovim** ≥ 0.9 (`nvim`) — required.
- **tmux** ≥ 3.2 (`tmux`) — required for the floating popup; without it the tool
  falls back to taking over the current terminal window.
- **git** and/or **jj** (Jujutsu) — at least one is required; the tool auto-detects.

macOS (Homebrew):

```bash
brew install neovim tmux git
brew install jujutsu   # OPTIONAL, only if the user uses jj
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
