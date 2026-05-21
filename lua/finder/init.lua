-- finder.nvim — a vertico-style file picker for nvim.
-- Single floating window, single nvim process, no fzf, no flicker on dir change.
--
-- Open with require("finder").open() or require("finder").open({ cwd = ... }).

local M = {}

-- ============================================================================
-- Config
-- ============================================================================
local cfg = {
  height_ratio    = 0.7,
  width_ratio     = 0.7,
  border          = "rounded",
  show_hidden     = true,
  ignore_patterns = { "^%.git$", "^%.DS_Store$" },
}

function M.setup(user)
  cfg = vim.tbl_deep_extend("force", cfg, user or {})
end

-- ============================================================================
-- State (one picker instance at a time)
-- ============================================================================
local state, ui = nil, { buf = nil, win = nil }
local ns = vim.api.nvim_create_namespace("finder")
local saved_guicursor = nil

local function reset_state(cwd)
  state = {
    cwd      = cwd,    -- absolute, no trailing slash
    filter   = "",
    entries  = {},     -- { {name, type}, ... } sorted, dirs first
    filtered = {},     -- after fuzzy match against filter
    cursor   = 1,      -- 1-based index into filtered
    view_top = 0,      -- 0-based; index 1 of view shows filtered[view_top+1]
  }
end

-- ============================================================================
-- Filesystem
-- ============================================================================
local function read_dir(path)
  local out = {}
  local d = vim.uv.fs_scandir(path)
  if not d then return out end
  while true do
    local name, t = vim.uv.fs_scandir_next(d)
    if not name then break end
    if cfg.show_hidden or not name:match("^%.") then
      local skip = false
      for _, p in ipairs(cfg.ignore_patterns) do
        if name:match(p) then skip = true; break end
      end
      if not skip then
        -- Resolve symlinks: fs_stat follows links, so we get the target's
        -- type. Otherwise a symlink-to-directory would be treated as a file
        -- and Tab/Enter would try to vim.cmd("edit") it instead of descending.
        local is_link = (t == "link")
        if is_link then
          local sep = path:sub(-1) == "/" and "" or "/"
          local stat = vim.uv.fs_stat(path .. sep .. name)
          if stat and stat.type then t = stat.type end
        end
        out[#out + 1] = { name = name, type = t or "file", is_link = is_link }
      end
    end
  end
  return out
end

local function sort_entries(entries)
  table.sort(entries, function(a, b)
    local ad, bd = a.type == "directory", b.type == "directory"
    if ad ~= bd then return ad end
    return a.name:lower() < b.name:lower()
  end)
  return entries
end

local function apply_filter()
  if state.filter == "" then
    state.filtered = state.entries
  else
    local names, map = {}, {}
    for i, e in ipairs(state.entries) do
      names[i] = e.name
      map[e.name] = e
    end
    local matched = vim.fn.matchfuzzy(names, state.filter)
    state.filtered = {}
    for _, n in ipairs(matched) do
      state.filtered[#state.filtered + 1] = map[n]
    end
  end
  state.cursor = state.filtered[1] and 1 or 0
  state.view_top = 0
end

local function reload_entries()
  state.entries = sort_entries(read_dir(state.cwd))
  apply_filter()
end

-- ============================================================================
-- UI
-- ============================================================================
local function pretty_cwd()
  return vim.fn.fnamemodify(state.cwd, ":~")
end

local function entry_display(e)
  return e.type == "directory" and (e.name .. "/") or e.name
end

local function render()
  if not (ui.buf and vim.api.nvim_buf_is_valid(ui.buf)) then return end
  if not (ui.win and vim.api.nvim_win_is_valid(ui.win)) then return end

  local h = vim.api.nvim_win_get_height(ui.win)
  local list_h = h - 2  -- 1 line path bar, 1 line status

  -- clamp cursor
  if state.cursor > #state.filtered then state.cursor = #state.filtered end
  if state.cursor < 1 and #state.filtered > 0 then state.cursor = 1 end

  -- ensure cursor visible (virtual scroll)
  if state.cursor > 0 then
    if state.cursor - state.view_top > list_h then
      state.view_top = state.cursor - list_h
    elseif state.cursor <= state.view_top then
      state.view_top = state.cursor - 1
    end
  else
    state.view_top = 0
  end

  -- assemble lines
  local lines = {}
  local cwd_part = pretty_cwd()
  if not cwd_part:match("/$") then cwd_part = cwd_part .. "/" end
  local path_line = cwd_part .. state.filter
  lines[1] = path_line
  for i = 1, list_h do
    local idx = state.view_top + i
    local e = state.filtered[idx]
    lines[#lines + 1] = e and ("  " .. entry_display(e)) or ""
  end
  lines[#lines + 1] = string.format(" %d/%d%s",
    #state.filtered, #state.entries,
    cfg.show_hidden and "  hidden:on" or "  hidden:off")

  vim.bo[ui.buf].modifiable = true
  vim.api.nvim_buf_set_lines(ui.buf, 0, -1, false, lines)
  vim.bo[ui.buf].modifiable = false

  -- highlights
  vim.api.nvim_buf_clear_namespace(ui.buf, ns, 0, -1)

  -- path bar styling: dim the cwd, normal the filter, cursor indicator at end
  -- (cwd_part already computed above, reuse it for highlight range)
  vim.api.nvim_buf_add_highlight(ui.buf, ns, "Directory", 0, 0, #cwd_part)
  if state.filter ~= "" then
    vim.api.nvim_buf_add_highlight(ui.buf, ns, "Normal", 0, #cwd_part, -1)
  end

  -- highlight current entry
  if state.cursor > 0 and state.cursor > state.view_top
     and state.cursor <= state.view_top + list_h then
    local row = state.cursor - state.view_top  -- 0-indexed row in buf
    vim.api.nvim_buf_add_highlight(ui.buf, ns, "PmenuSel", row, 0, -1)
  end

  -- directory entries: dim with Directory hl
  for i = 1, list_h do
    local idx = state.view_top + i
    local e = state.filtered[idx]
    if e and e.type == "directory" then
      vim.api.nvim_buf_add_highlight(ui.buf, ns, "Directory", i, 0, -1)
    end
  end

  -- status line subtle
  vim.api.nvim_buf_add_highlight(ui.buf, ns, "Comment", #lines - 1, 0, -1)

  -- put nvim cursor at the end of the path bar (visual caret for the filter)
  pcall(vim.api.nvim_win_set_cursor, ui.win, { 1, #path_line })
end

-- ============================================================================
-- Actions
-- ============================================================================
local function close()
  if ui.win and vim.api.nvim_win_is_valid(ui.win) then
    vim.api.nvim_win_close(ui.win, true)
  end
  if saved_guicursor ~= nil then
    vim.o.guicursor = saved_guicursor
    saved_guicursor = nil
  end
  ui.buf, ui.win, state = nil, nil, nil
end

-- Join a directory `base` with a `name`, avoiding double slashes when base
-- already ends in '/' (e.g. when base is the filesystem root).
local function path_join(base, name)
  if base == "" or base:sub(-1) == "/" then return base .. name end
  return base .. "/" .. name
end

local function ascend()
  local parent = vim.fn.fnamemodify(state.cwd, ":h")
  if parent == state.cwd then return end
  state.cwd, state.filter = parent, ""
  reload_entries()
  render()
end

local function descend(entry)
  state.cwd    = path_join(state.cwd, entry.name)
  state.filter = ""
  reload_entries()
  render()
end

local function open_file(entry)
  local path = path_join(state.cwd, entry.name)
  close()
  vim.cmd("edit " .. vim.fn.fnameescape(path))
end

local function pick(entry)
  if not entry then return end
  if entry.type == "directory" then descend(entry)
  else open_file(entry) end
end

-- ============================================================================
-- Key dispatch
-- ============================================================================
local function on_char(c)
  state.filter = state.filter .. c
  apply_filter()
  render()
end

local function on_bs()
  if state.filter ~= "" then
    state.filter = state.filter:sub(1, -2)
    apply_filter()
    render()
  else
    ascend()
  end
end

local function on_first_match() pick(state.filtered[1]) end
local function on_enter()       pick(state.filtered[state.cursor]) end
local function on_down()  state.cursor = math.min(#state.filtered, state.cursor + 1); render() end
local function on_up()    state.cursor = math.max(1, state.cursor - 1); render() end
local function on_clear() state.filter = ""; apply_filter(); render() end
local function on_toggle_hidden()
  cfg.show_hidden = not cfg.show_hidden
  reload_entries()
  render()
end

local function jump_to(path)
  state.cwd    = (vim.fn.fnamemodify(path, ":p")):gsub("/+$", "")
  if state.cwd == "" then state.cwd = "/" end
  state.filter = ""
  reload_entries()
  render()
end

-- "/" with empty filter -> jump to root; otherwise pick first match
local function on_slash()
  if state.filter == "" then jump_to("/")
  else on_first_match() end
end

-- "~" with empty filter -> jump to home; otherwise append to filter
local function on_tilde()
  if state.filter == "" then jump_to(vim.fn.expand("~"))
  else on_char("~") end
end

local function setup_keymaps(buf)
  local function map(k, fn)
    vim.keymap.set("n", k, fn, { buffer = buf, nowait = true, silent = true })
  end

  -- every printable ASCII char (except '/' and '~') goes to filter.
  -- '/' and '~' are context-sensitive (see on_slash / on_tilde).
  for c = 32, 126 do
    local ch = string.char(c)
    if ch ~= "/" and ch ~= "~" then map(ch, function() on_char(ch) end) end
  end

  map("/",       on_slash)
  map("~",       on_tilde)
  map("<Tab>",   on_first_match)
  map("<BS>",    on_bs)
  map("<CR>",    on_enter)
  map("<C-j>",   on_down)
  map("<C-k>",   on_up)
  map("<Down>",  on_down)
  map("<Up>",    on_up)
  map("<C-u>",   on_clear)
  map("<C-h>",   on_toggle_hidden)
  map("<Esc>",   close)
  map("<C-c>",   close)
end

-- ============================================================================
-- Public API
-- ============================================================================
function M.open(opts)
  opts = opts or {}
  local cwd = opts.cwd
  if not cwd or cwd == "" then cwd = vim.fn.expand("%:p:h") end
  if cwd == "" or vim.fn.isdirectory(cwd) ~= 1 then cwd = vim.fn.getcwd() end
  cwd = (vim.fn.fnamemodify(cwd, ":p")):gsub("/+$", "")
  if cwd == "" then cwd = "/" end

  reset_state(cwd)
  reload_entries()

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype  = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "finder"
  vim.bo[buf].modifiable = false

  local h = math.floor(vim.o.lines * cfg.height_ratio)
  local w = math.floor(vim.o.columns * cfg.width_ratio)
  local win = vim.api.nvim_open_win(buf, true, {
    relative  = "editor",
    width     = w,
    height    = h,
    row       = math.floor((vim.o.lines - h) / 2),
    col       = math.floor((vim.o.columns - w) / 2),
    border    = cfg.border,
    title     = " Finder ",
    title_pos = "center",
    style     = "minimal",
  })

  ui.buf, ui.win = buf, win

  -- show a vertical-bar caret in the path bar instead of the normal-mode block.
  saved_guicursor = vim.o.guicursor
  vim.o.guicursor = "n-v-c:ver25-Cursor/lCursor,a:blinkon0"

  -- allow cursor to sit one cell past the end of the path line (insert-style).
  vim.wo[win].virtualedit = "all"
  vim.wo[win].cursorline  = false

  setup_keymaps(buf)

  -- close on focus loss to a different window
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = buf,
    once   = true,
    callback = close,
  })

  render()
end

function M.close() close() end

return M
