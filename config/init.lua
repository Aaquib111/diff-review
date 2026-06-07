-- Self-contained review-only Neovim config, loaded via `nvim -u`.
-- It bypasses the user's normal init.lua and depends on nothing beyond a stock
-- Neovim install (>= 0.9). Treesitter is an optional enhancement.
vim.opt.mouse = "a" -- clicks move the cursor -> fires CursorMoved
vim.opt.number = true
vim.opt.signcolumn = "yes"
vim.opt.termguicolors = true
vim.g.mapleader = " "

-- `nvim -u <init>` does NOT auto-enable filetype detection or syntax (unlike a
-- normal start), so buffers come up with an empty filetype and no highlighting.
-- `syntax enable` is the universal fallback: it highlights every language with
-- zero plugins, and is what shows when no Treesitter parser is available.
vim.cmd("filetype plugin indent on")
vim.cmd("syntax enable")

-- Stock colorscheme that ships with Neovim; no external theme required.
pcall(vim.cmd.colorscheme, "habamax")

-- Optional AST upgrade: if nvim-treesitter is installed anywhere common, put it
-- on the runtimepath so its parsers + highlight queries become available. If it
-- isn't found, the `syntax enable` above still gives full highlighting.
local data = vim.fn.stdpath("data")
local candidates = {
  data .. "/lazy/nvim-treesitter", -- lazy.nvim / LazyVim
  data .. "/plugged/nvim-treesitter", -- vim-plug
}
for _, glob in ipairs({
  data .. "/site/pack/*/start/nvim-treesitter", -- packer / native packages
  data .. "/site/pack/*/opt/nvim-treesitter",
}) do
  vim.list_extend(candidates, vim.fn.glob(glob, true, true))
end
for _, dir in ipairs(candidates) do
  if vim.fn.isdirectory(dir) == 1 then
    vim.opt.runtimepath:append(dir)
    break
  end
end

-- Make our module importable. stdpath("config") is ~/.config/nvim, so "/../review"
-- resolves to ~/.config/review, whose lua/ holds review.lua.
vim.opt.runtimepath:append(vim.fn.stdpath("config") .. "/../review")

require("review").start()
