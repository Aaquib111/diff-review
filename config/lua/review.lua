local M = {}
local ns = vim.api.nvim_create_namespace("review")

local state = {
  vcs = os.getenv("REVIEW_VCS") or "git",
  ref = os.getenv("REVIEW_REF"),
  out = os.getenv("REVIEW_OUT"),
  root = os.getenv("REVIEW_ROOT") or vim.fn.getcwd(),
  files = {}, -- list of changed paths (new-file paths, renames included)
  annotations = {}, -- path -> { added=<set>, deleted=<map> }
  idx = 1, -- current file index
  comments = {}, -- { {path, start_line, end_line, body, snippet}, ... }
  left_win = nil,
  right_win = nil,
  left_buf = nil,
  right_buf = nil,
  path = nil,
}
state.ref = state.ref or (state.vcs == "jj" and "@" or "HEAD")

-- ── vcs diff ───────────────────────────────────────────────────────────────
-- Both backends emit a git-format unified diff with zero context, so a single
-- parser handles file discovery, binary detection, and per-line annotations.
local function diff_cmd()
  if state.vcs == "jj" then
    -- No --ignore-working-copy here: we want jj to snapshot disk into @ so the
    -- diff's "+" side matches the on-disk file the left pane clones.
    return {
      "jj",
      "-R",
      state.root,
      "diff",
      "-r",
      state.ref,
      "--git",
      "--context",
      "0",
    }
  end
  return { "git", "-C", state.root, "diff", "--no-color", "-U0", "-M", state.ref }
end

-- Parse the whole-repo git-format diff once. Fills state.files (encounter order,
-- excluding binary and deleted files) and state.annotations[path].
local function compute()
  local raw = vim.fn.systemlist(diff_cmd())
  local order, seen = {}, {}
  local binary, deleted_file = {}, {}
  local path, newlnum = nil, 0

  local function record(p)
    if p and not seen[p] then
      seen[p] = true
      order[#order + 1] = p
    end
  end

  for _, line in ipairs(raw) do
    if line:match("^diff %-%-git ") then
      -- New file record; the authoritative new path comes from the +++ header.
      path = line:match("^diff %-%-git a/.* b/(.+)$")
      newlnum = 0
    elseif line:sub(1, 4) == "+++ " then
      local p = line:match("^%+%+%+ b/(.+)$")
      if p then
        path = p
        record(path)
      elseif line:match("^%+%+%+ /dev/null$") and path then
        deleted_file[path] = true -- file removed; nothing on disk to review
      end
    elseif line:match("^Binary files ") or line:match("^GIT binary patch") then
      if path then
        binary[path] = true
      end
    elseif path then
      local start = line:match("^@@ %-%d+,?%d* %+(%d+)")
      if start then
        newlnum = tonumber(start)
      elseif line:sub(1, 1) == "+" and line:sub(1, 3) ~= "+++" then
        local a = state.annotations[path] or { added = {}, deleted = {} }
        a.added[newlnum] = true
        state.annotations[path] = a
        newlnum = newlnum + 1
      elseif line:sub(1, 1) == "-" and line:sub(1, 3) ~= "---" then
        local a = state.annotations[path] or { added = {}, deleted = {} }
        a.deleted[newlnum] = a.deleted[newlnum] or {}
        table.insert(a.deleted[newlnum], line:sub(2)) -- the removed text
        state.annotations[path] = a
      end
    end
  end

  state.files = {}
  for _, p in ipairs(order) do
    if not binary[p] and not deleted_file[p] then
      state.files[#state.files + 1] = p
    end
  end
end

-- ── layout ─────────────────────────────────────────────────────────────────
local function open_file(path)
  state.path = path
  -- Wipe the previous read-only clone so scratch buffers (and their names) don't
  -- pile up across file switches.
  if state.left_buf and vim.api.nvim_buf_is_valid(state.left_buf) then
    pcall(vim.api.nvim_buf_delete, state.left_buf, { force = true })
  end
  vim.cmd("silent! only") -- reset window layout

  -- RIGHT: editable real file
  vim.cmd("edit " .. vim.fn.fnameescape(state.root .. "/" .. path))
  state.right_win = vim.api.nvim_get_current_win()
  state.right_buf = vim.api.nvim_get_current_buf()

  -- LEFT: read-only clone of the same content
  vim.cmd("leftabove vsplit")
  state.left_win = vim.api.nvim_get_current_win()
  local content = vim.api.nvim_buf_get_lines(state.right_buf, 0, -1, false)
  local lbuf = vim.api.nvim_create_buf(false, true) -- listed=false, scratch=true
  vim.api.nvim_buf_set_lines(lbuf, 0, -1, false, content)
  local ft = vim.bo[state.right_buf].filetype
  vim.bo[lbuf].filetype = ft
  vim.bo[lbuf].modifiable = false
  vim.bo[lbuf].readonly = true
  vim.api.nvim_win_set_buf(state.left_win, lbuf)
  state.left_buf = lbuf

  -- AST-aware highlight. Resolve filetype -> language first; for filetypes whose
  -- parser name differs (e.g. typescriptreact -> tsx) ft alone won't resolve.
  -- pcall: if no parser is installed, syntax-enable highlighting still applies.
  local lang = vim.treesitter.language.get_lang(ft) or ft
  pcall(vim.treesitter.start, lbuf, lang)

  -- Unique buffer name (avoids clashes) + a visible winbar with file position.
  pcall(vim.api.nvim_buf_set_name, lbuf, ("review://%s"):format(path))
  vim.wo[state.left_win].winbar = (" [%d/%d] %s  │  ]f next  [f prev  <leader>f list  <leader>c comment  <leader>s save  <leader>x quit"):format(
    state.idx,
    #state.files,
    path
  )

  M.decorate(path)
  -- Re-draw any comments already attached to this file (markers live on the
  -- left buffer, which is rebuilt on every visit).
  for _, c in ipairs(state.comments) do
    if c.path == path then
      M.draw_comment(c)
    end
  end
  M.wire(path)
  vim.api.nvim_set_current_win(state.left_win) -- start focused on the diff
end

-- ── diff decoration on the left buffer ──────────────────────────────────────
function M.decorate(path)
  local ann = state.annotations[path] or { added = {}, deleted = {} }
  local added, deleted = ann.added, ann.deleted
  vim.api.nvim_buf_clear_namespace(state.left_buf, ns, 0, -1)

  local last = vim.api.nvim_buf_line_count(state.left_buf)
  for lnum in pairs(added) do
    if lnum >= 1 and lnum <= last then
      vim.api.nvim_buf_set_extmark(
        state.left_buf,
        ns,
        lnum - 1,
        0,
        { line_hl_group = "DiffAdd" }
      )
    end
  end

  for lnum, removed in pairs(deleted) do
    local virt = {}
    for _, text in ipairs(removed) do
      virt[#virt + 1] = { { "- " .. text, "DiffDelete" } }
    end
    -- Deletions can sit one past the final line (trailing removals); clamp to
    -- the last valid row and render the removed text above it.
    local row = math.min(math.max(lnum - 1, 0), math.max(last - 1, 0))
    vim.api.nvim_buf_set_extmark(state.left_buf, ns, row, 0, {
      virt_lines = virt,
      virt_lines_above = true,
    })
  end
end

-- ── interactions ────────────────────────────────────────────────────────────
function M.wire(path)
  -- click / any cursor move on the left -> mirror line in the right pane.
  -- Left line N == right line N because the left pane clones the new file.
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = state.left_buf,
    callback = function()
      local lnum = vim.api.nvim_win_get_cursor(state.left_win)[1]
      pcall(vim.api.nvim_win_set_cursor, state.right_win, { lnum, 0 })
    end,
  })

  vim.keymap.set("v", "<leader>c", function()
    M.add_comment(path)
  end, { buffer = state.left_buf, desc = "review: comment on selection" })

  vim.keymap.set(
    "n",
    "<leader>s",
    M.save,
    { buffer = state.left_buf, desc = "review: save + quit" }
  )
  vim.keymap.set("n", "<leader>x", function()
    vim.cmd("qa!")
  end, { buffer = state.left_buf, desc = "review: discard + quit" })
  vim.keymap.set("n", "]f", M.next_file, { buffer = state.left_buf, desc = "review: next file" })
  vim.keymap.set("n", "[f", M.prev_file, { buffer = state.left_buf, desc = "review: prev file" })
  vim.keymap.set("n", "<leader>f", M.pick_file, { buffer = state.left_buf, desc = "review: pick file" })
end

-- List every changed file and jump to the chosen one. Marks the current file and
-- any file that already has comments, so you can see where you've been.
function M.pick_file()
  local items = {}
  for i, p in ipairs(state.files) do
    items[i] = i
  end
  local commented = {}
  for _, c in ipairs(state.comments) do
    commented[c.path] = (commented[c.path] or 0) + 1
  end
  vim.ui.select(items, {
    prompt = "review: jump to file",
    format_item = function(i)
      local p = state.files[i]
      local mark = (i == state.idx) and "● " or "  "
      local n = commented[p]
      return ("%s%s%s"):format(mark, p, n and (" (" .. n .. " ✎)") or "")
    end,
  }, function(choice)
    if choice and choice ~= state.idx then
      state.idx = choice
      open_file(state.files[choice])
    end
  end)
end

function M.add_comment(path)
  local s, e = vim.fn.line("v"), vim.fn.line(".")
  if s > e then
    s, e = e, s
  end
  vim.cmd("normal! \27") -- leave visual mode
  vim.ui.input(
    { prompt = ("Comment %s:%d-%d -> "):format(path, s, e) },
    function(body)
      if not body or body == "" then
        return
      end
      local snippet = table.concat(
        vim.api.nvim_buf_get_lines(state.left_buf, s - 1, e, false),
        "\n"
      )
      local c = {
        path = path,
        start_line = s,
        end_line = e,
        body = body,
        snippet = snippet,
      }
      table.insert(state.comments, c)
      M.draw_comment(c)
    end
  )
end

-- Render a comment's gutter signs and inline echo on the current left buffer.
function M.draw_comment(c)
  for l = c.start_line, c.end_line do
    vim.api.nvim_buf_set_extmark(state.left_buf, ns, l - 1, 0, {
      sign_text = "»",
      sign_hl_group = "DiagnosticInfo",
    })
  end
  vim.api.nvim_buf_set_extmark(state.left_buf, ns, c.end_line - 1, 0, {
    virt_text = { { "  ✎ " .. c.body, "Comment" } },
  })
end

-- ── multi-file navigation ────────────────────────────────────────────────────
function M.next_file()
  if state.idx < #state.files then
    state.idx = state.idx + 1
    open_file(state.files[state.idx])
  end
end

function M.prev_file()
  if state.idx > 1 then
    state.idx = state.idx - 1
    open_file(state.files[state.idx])
  end
end

-- ── save ─────────────────────────────────────────────────────────────────────
function M.save()
  vim.cmd("silent! wa") -- flush manual edits in the right pane(s); scratch left is skipped
  local payload = {
    generated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    vcs = state.vcs,
    base = state.ref,
    comments = state.comments,
  }
  local f = assert(io.open(state.out, "w"))
  f:write(vim.json.encode(payload))
  f:close()
  vim.cmd("qa")
end

-- ── entry ────────────────────────────────────────────────────────────────────
function M.start()
  compute()
  if #state.files == 0 then
    vim.notify("review: no changes vs " .. state.ref, vim.log.levels.WARN)
    return
  end
  state.idx = 1
  open_file(state.files[1])
end

return M
