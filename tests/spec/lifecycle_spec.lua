local h = require("tests.helpers")

local table_lines = {
  "| A | B |",
  "| --- | --- |",
  "| one | two |",
}

local function new_markdown_buffer(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "markdown"
  return buf
end

local function delete_buffer(buf)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
end

h.test("debounced refreshes are isolated by buffer and keep their scheduled target", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({
    auto_preview = false,
    preview_mode = "inline",
    render_all = true,
    debounce_ms = 1,
  })

  local win_a = vim.api.nvim_get_current_win()
  local buf_a = new_markdown_buffer(table_lines)
  vim.api.nvim_win_set_buf(win_a, buf_a)
  vim.cmd("vsplit")
  local win_b = vim.api.nvim_get_current_win()
  local buf_b = new_markdown_buffer({
    "| C | D |",
    "| --- | --- |",
    "| three | four |",
  })
  vim.api.nvim_win_set_buf(win_b, buf_b)

  inline.clear(buf_a)
  inline.clear(buf_b)
  vim.api.nvim_set_current_win(win_a)
  plugin.schedule_refresh({ bufnr = buf_a, winid = win_a, force = true })
  vim.api.nvim_set_current_win(win_b)
  plugin.schedule_refresh({ bufnr = buf_b, winid = win_b, force = true })

  local refreshed = vim.wait(500, function()
    return inline.is_active(buf_a) and inline.is_active(buf_b)
  end, 1)

  h.assert_true("both buffer refreshes run", refreshed)
  h.assert_true("first buffer receives its own render", inline.is_active(buf_a))
  h.assert_true("second buffer receives its own render", inline.is_active(buf_b))
  h.assert_eq("deferred callbacks preserve the current window", vim.api.nvim_get_current_win(), win_b)
  h.assert_eq("deferred callbacks preserve the current buffer", vim.api.nvim_get_current_buf(), buf_b)

  inline.dispose(buf_a)
  inline.dispose(buf_b)
  if vim.api.nvim_win_is_valid(win_b) then
    vim.api.nvim_win_close(win_b, true)
  end
  delete_buffer(buf_a)
  delete_buffer(buf_b)
end)

h.test("repeated setup invalidates refreshes from the previous setup epoch", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")
  local opts = { auto_preview = false, preview_mode = "inline", debounce_ms = 1 }
  plugin.setup(opts)

  h.with_buffer(table_lines, function(buf)
    vim.bo[buf].filetype = "markdown"
    local win = vim.api.nvim_get_current_win()

    -- Not a counting stub of refresh_auto, which would tie the test to today's
    -- call target: the stale refresh is forced, so it would render visibly,
    -- and the unforced one after setup renders nothing but reuses its token
    -- number, which leaves the epoch check as the only thing stopping it.
    plugin.schedule_refresh({ bufnr = buf, winid = win, force = true })
    plugin.setup(opts)
    plugin.schedule_refresh({ bufnr = buf, winid = win })
    h.drain_timers(1)

    h.assert_false("the refresh scheduled before setup never renders", inline.is_active(buf))
  end)
end)

-- ddP and ddkp put a deleted row back where it was: the table's text and line
-- numbers end up as before, but the deleted row's extmarks have moved onto
-- its neighbour by then (replace mode's conceal_lines, insert mode's dimming).
for _, inline_mode in ipairs({ "replace", "insert" }) do
  h.test("render_all = false redraws a table whose row was deleted and put back, " .. inline_mode, function()
    local plugin = require("markdown-table-wrap")
    local inline = require("markdown-table-wrap.inline")
    plugin.setup({ preview_mode = "inline", inline_mode = inline_mode, render_all = false, debounce_ms = 1 })

    local lines = {
      "intro",
      "",
      "| A | B |",
      "| --- | --- |",
      "| one | two |",
      "| three | four |",
      "| five | six |",
      "",
      "outro",
    }
    h.with_buffer(lines, function(buf)
      vim.bo[buf].filetype = "markdown"
      vim.api.nvim_win_set_cursor(0, { 6, 0 })
      plugin.refresh_auto()
      local before = h.extmarks(buf, inline.namespace())

      for _, keys in ipairs({ "ddP", "ddkp" }) do
        local label = inline_mode .. ", " .. keys .. ": "
        vim.cmd.normal({ keys, bang = true })
        h.assert_deep_eq(label .. "the edit puts the text back", vim.api.nvim_buf_get_lines(buf, 0, -1, false), lines)
        vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
        h.drain_timers(1)
        h.assert_deep_eq(
          label .. "the refresh after the edit draws what was drawn before it",
          h.extmarks(buf, inline.namespace()),
          before
        )
      end

      inline.clear(buf)
    end)
  end)
end

h.test("deleting a table that ends the buffer moves the cursor without errors before the refresh", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")
  plugin.setup({ preview_mode = "inline", debounce_ms = 1 })

  local lines = {}
  for i = 1, 20 do
    table.insert(lines, "p" .. i)
  end
  vim.list_extend(lines, { "| A | B |", "| --- | --- |", "| one | two |" })
  h.with_buffer(lines, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 22, 0 })
    plugin.refresh_auto()
    h.assert_true("the table is rendered", inline.is_active(buf))

    vim.cmd.normal({ "dgg", bang = true })
    h.assert_deep_eq("dgg leaves one line", vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "| one | two |" })
    -- An autocmd callback's error is reported as a message, not raised.
    vim.v.errmsg = ""
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
    vim.api.nvim_exec_autocmds("WinScrolled", { buffer = buf })
    h.assert_eq("the cursor move and the scroll report no error", vim.v.errmsg, "")

    vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
    h.drain_timers(1)
    h.assert_true("the refresh clears the deleted table", not inline.is_active(buf))
  end)
end)

h.test("interactive mode and auto choices stay buffer local", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({
    auto_preview = false,
    preview_mode = "float",
    render_all = true,
    debounce_ms = 0,
  })

  local buf_a = new_markdown_buffer(table_lines)
  local buf_b = new_markdown_buffer(table_lines)
  vim.api.nvim_set_current_buf(buf_a)

  h.assert_true("inline can be enabled in first buffer", plugin.toggle_inline())
  h.assert_eq("first buffer switches to inline", plugin.get_preview_mode(buf_a), "inline")
  h.assert_eq("second buffer keeps float default", plugin.get_preview_mode(buf_b), "float")
  h.assert_eq("global preview mode stays immutable", plugin.config.preview_mode, "float")
  h.assert_false("global auto default stays immutable", plugin.config.auto_preview)

  plugin.disable_auto_preview()
  vim.api.nvim_set_current_buf(buf_b)
  h.assert_true("inline can be enabled independently in second buffer", plugin.toggle_inline())
  plugin.disable_auto_preview()
  plugin.enable_auto_preview()

  h.assert_true("second buffer auto preview is enabled", plugin.get_buffer_config(buf_b).auto_preview)
  h.assert_false("first buffer auto preview remains disabled", plugin.get_buffer_config(buf_a).auto_preview)
  h.assert_eq("first buffer keeps its inline mode", plugin.get_preview_mode(buf_a), "inline")
  h.assert_false("global auto default is still immutable", plugin.config.auto_preview)

  inline.dispose(buf_a)
  inline.dispose(buf_b)
  delete_buffer(buf_a)
  delete_buffer(buf_b)
end)

h.test("leaving an inline window or buffer restores its local options", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({
    auto_preview = false,
    preview_mode = "inline",
    -- Leaving the window hands its options back only when the rendering is
    -- released with it, which is render_all = false plus the default
    -- clear_on_cursor_leave. While the rendered blocks stay attached -- under
    -- render_all, or with clear_on_cursor_leave = false -- the window has to
    -- keep the options they depend on; that is covered by
    -- "an unfocused window keeps the options its rendering depends on" and
    -- "a window that keeps its rendering on leave keeps its options".
    render_all = false,
    debounce_ms = 0,
  })

  local win_a = vim.api.nvim_get_current_win()
  local buf_a = new_markdown_buffer(table_lines)
  vim.api.nvim_win_set_buf(win_a, buf_a)
  vim.cmd("vsplit")
  local win_b = vim.api.nvim_get_current_win()
  local buf_b = new_markdown_buffer({ "plain text" })
  vim.api.nvim_win_set_buf(win_b, buf_b)

  vim.wo[win_a].conceallevel = 0
  vim.api.nvim_set_current_win(win_a)
  plugin.refresh_auto({ bufnr = buf_a, winid = win_a, force = true })
  h.assert_eq("inline raises conceallevel", vim.wo[win_a].conceallevel, 2)

  vim.api.nvim_set_current_win(win_b)
  h.assert_false("WinLeave releases the rendering", inline.is_active(buf_a))
  h.assert_eq("WinLeave restores conceallevel", vim.wo[win_a].conceallevel, 0)

  -- Render again before switching buffers, so the BufLeave half has
  -- something to hand back rather than passing on the WinLeave result.
  vim.api.nvim_set_current_win(win_a)
  plugin.refresh_auto({ bufnr = buf_a, winid = win_a, force = true })
  h.assert_eq("re-rendering raises conceallevel again", vim.wo[win_a].conceallevel, 2)
  vim.api.nvim_win_set_buf(win_a, buf_b)
  h.assert_false("BufLeave releases the rendering", inline.is_active(buf_a))
  h.assert_eq("BufLeave restores conceallevel", vim.wo[win_a].conceallevel, 0)

  inline.dispose(buf_a)
  if vim.api.nvim_win_is_valid(win_b) then
    vim.api.nvim_win_close(win_b, true)
  end
  delete_buffer(buf_a)
  delete_buffer(buf_b)
end)

h.test("a window that newly shows a rendered buffer picks up its options", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({
    auto_preview = false,
    preview_mode = "inline",
    render_all = true,
    debounce_ms = 0,
  })

  local win_a = vim.api.nvim_get_current_win()
  local buf_a = new_markdown_buffer(table_lines)
  vim.api.nvim_win_set_buf(win_a, buf_a)
  vim.cmd("vsplit")
  local win_b = vim.api.nvim_get_current_win()
  local buf_b = new_markdown_buffer({ "plain text" })
  vim.api.nvim_win_set_buf(win_b, buf_b)

  vim.wo[win_a].conceallevel = 0
  vim.api.nvim_set_current_win(win_a)
  plugin.refresh_auto({ bufnr = buf_a, winid = win_a, force = true })
  h.assert_eq("the rendering applies to the window it was made in", vim.wo[win_a].conceallevel, 2)

  -- A second window that had none of the inline options now shows the
  -- rendered buffer: displaying it there has to apply them too. This is the
  -- BufWinEnter half of the attach autocommand; the WinEnter half is covered
  -- by the focus-change test below.
  vim.api.nvim_set_current_win(win_b)
  vim.wo[win_b].conceallevel = 0
  vim.api.nvim_win_set_buf(win_b, buf_a)

  h.assert_eq("BufWinEnter reapplies inline conceallevel", vim.wo[win_b].conceallevel, 2)

  inline.dispose(buf_a)
  if vim.api.nvim_win_is_valid(win_b) then
    vim.api.nvim_win_close(win_b, true)
  end
  delete_buffer(buf_a)
  delete_buffer(buf_b)
end)

h.test("focusing a window back onto its rendering reapplies its options", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({
    auto_preview = false,
    preview_mode = "inline",
    render_all = true,
    debounce_ms = 0,
  })

  local win_a = vim.api.nvim_get_current_win()
  local buf_a = new_markdown_buffer(table_lines)
  vim.api.nvim_win_set_buf(win_a, buf_a)
  -- Both windows already hold the rendered buffer, so nothing below changes
  -- which buffer a window shows: the only trigger left is the focus change,
  -- which is WinEnter and never BufWinEnter.
  vim.cmd("vsplit")
  local win_b = vim.api.nvim_get_current_win()

  vim.api.nvim_set_current_win(win_a)
  plugin.refresh_auto({ bufnr = buf_a, winid = win_a, force = true })
  h.assert_true("both windows show the rendered buffer", vim.api.nvim_win_get_buf(win_b) == buf_a)
  h.assert_true("the rendering is active", inline.is_active(buf_a))

  -- Something else took the options off the unfocused window: a :set, an
  -- ftplugin, another plugin. Focusing it has to put them back.
  vim.wo[win_b].conceallevel = 0

  vim.api.nvim_set_current_win(win_b)
  h.assert_eq("focus alone did not change the displayed buffer", vim.api.nvim_win_get_buf(win_b), buf_a)
  h.assert_eq("WinEnter reapplies inline conceallevel", vim.wo[win_b].conceallevel, 2)

  inline.dispose(buf_a)
  if vim.api.nvim_win_is_valid(win_b) then
    vim.api.nvim_win_close(win_b, true)
  end
  delete_buffer(buf_a)
end)

h.test("a cursor move puts back a conceallevel taken off the rendered window", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  -- Under render_all a cursor move schedules no refresh, so the CursorMoved
  -- handler itself is what repairs the window.
  plugin.setup({
    auto_preview = false,
    preview_mode = "inline",
    render_all = true,
    debounce_ms = 0,
  })

  h.with_buffer(table_lines, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.wo.conceallevel = 0
    plugin.refresh_auto({ force = true })
    h.assert_true("the table is rendered", inline.is_active(buf))
    h.assert_eq("rendering raises conceallevel", vim.wo.conceallevel, 2)

    vim.wo.conceallevel = 0
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
    h.assert_eq("CursorMoved reapplies conceallevel", vim.wo.conceallevel, 2)

    inline.clear(buf)
    h.assert_eq("clearing hands back the original conceallevel", vim.wo.conceallevel, 0)
  end)
end)

h.test("a window that keeps its rendering on leave keeps its options", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  -- The combination that releases nothing on leave: only the table under the
  -- cursor is rendered, and leaving does not clear it.
  plugin.setup({
    auto_preview = false,
    preview_mode = "inline",
    render_all = false,
    clear_on_cursor_leave = false,
    debounce_ms = 0,
  })

  local win_a = vim.api.nvim_get_current_win()
  local buf_a = new_markdown_buffer(table_lines)
  vim.api.nvim_win_set_buf(win_a, buf_a)
  vim.cmd("vsplit")
  local win_b = vim.api.nvim_get_current_win()
  local buf_b = new_markdown_buffer({ "plain text" })
  vim.api.nvim_win_set_buf(win_b, buf_b)

  vim.wo[win_a].conceallevel = 1
  vim.api.nvim_set_current_win(win_a)
  vim.api.nvim_win_set_cursor(win_a, { 1, 0 })
  plugin.refresh_auto({ bufnr = buf_a, winid = win_a, force = true })

  local function extmarks()
    return #vim.api.nvim_buf_get_extmarks(buf_a, inline.namespace(), 0, -1, {})
  end
  local function height()
    return vim.api.nvim_win_call(win_a, function()
      return vim.api.nvim_win_text_height(win_a, {}).all
    end)
  end

  h.assert_true("the table is rendered", inline.is_active(buf_a))
  h.assert_eq("rendering raises conceallevel", vim.wo[win_a].conceallevel, 2)
  local rendered_extmarks = extmarks()
  local rendered_height = height()
  h.assert_true("the rendering left extmarks", rendered_extmarks > 0)

  vim.api.nvim_set_current_win(win_b)
  h.assert_true("leaving keeps the rendering attached", inline.is_active(buf_a))
  h.assert_eq("leaving keeps the extmarks", extmarks(), rendered_extmarks)
  h.assert_eq("leaving keeps conceallevel", vim.wo[win_a].conceallevel, 2)
  h.assert_eq("leaving keeps the buffer screen height", height(), rendered_height)

  inline.dispose(buf_a)
  if vim.api.nvim_win_is_valid(win_b) then
    vim.api.nvim_win_close(win_b, true)
  end
  delete_buffer(buf_a)
  delete_buffer(buf_b)
end)

h.test("closing a rendered window hands its conceallevel back before Neovim stores it with the buffer", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({
    auto_preview = false,
    preview_mode = "inline",
    render_all = true,
    debounce_ms = 0,
  })

  local win_a = vim.api.nvim_get_current_win()
  local buf_plain = new_markdown_buffer({ "plain text" })
  vim.api.nvim_win_set_buf(win_a, buf_plain)
  vim.cmd("vsplit")
  local win_rendered = vim.api.nvim_get_current_win()
  local buf_a = new_markdown_buffer(table_lines)
  vim.api.nvim_win_set_buf(win_rendered, buf_a)

  vim.wo[win_a].conceallevel = 0
  vim.wo[win_rendered].conceallevel = 0
  plugin.refresh_auto({ bufnr = buf_a, winid = win_rendered, force = true })
  h.assert_eq("rendering raises conceallevel", vim.wo[win_rendered].conceallevel, 2)

  -- Not a check on the closed window, whose options go with it: Neovim gives
  -- a closing window's options to the next window that shows its buffer
  -- (:help local-options), and a leaked conceallevel surfaces there.
  vim.api.nvim_set_current_win(win_a)
  vim.api.nvim_win_close(win_rendered, true)
  vim.api.nvim_win_set_buf(win_a, buf_a)
  h.assert_eq("the rendering raises conceallevel in its new window", vim.wo[win_a].conceallevel, 2)

  plugin.disable_auto_preview()
  h.assert_false("the rendering is cleared", inline.is_active(buf_a))
  h.assert_eq("clearing hands back the conceallevel from before the rendering", vim.wo[win_a].conceallevel, 0)

  inline.dispose(buf_a)
  if vim.api.nvim_win_is_valid(win_rendered) then
    vim.api.nvim_win_close(win_rendered, true)
  end
  delete_buffer(buf_a)
  delete_buffer(buf_plain)
end)

-- A window's conceallevel as { :setlocal conceallevel?, :setglobal
-- conceallevel? } show it in that window.
local function conceallevels(win)
  return {
    vim.api.nvim_get_option_value("conceallevel", { scope = "local", win = win }),
    vim.api.nvim_get_option_value("conceallevel", { scope = "global", win = win }),
  }
end

-- Runs fn(win, buf) with a table rendered in a new window whose conceallevels
-- were set to `levels` before the rendering, with :setlocal and :setglobal.
-- `config` is merged into the setup options; `lines`, if given, replaces the
-- table as the buffer's text. Every window and buffer the test opens is closed
-- again, also when it fails.
local function with_rendered_window(levels, fn, config, lines)
  local plugin = require("markdown-table-wrap")
  plugin.setup(vim.tbl_extend("force", {
    auto_preview = false,
    preview_mode = "inline",
    render_all = true,
    debounce_ms = 0,
  }, config or {}))

  local origin = vim.api.nvim_get_current_win()
  local wins_before = vim.api.nvim_list_wins()
  local bufs_before = vim.api.nvim_list_bufs()
  local ok, err = pcall(function()
    vim.cmd("split")
    local win = vim.api.nvim_get_current_win()
    local buf = new_markdown_buffer(lines or table_lines)
    vim.api.nvim_win_set_buf(win, buf)
    vim.cmd("setglobal conceallevel=" .. levels[2])
    vim.cmd("setlocal conceallevel=" .. levels[1])
    plugin.refresh_auto({ bufnr = buf, winid = win, force = true })
    h.assert_true("the table is rendered", require("markdown-table-wrap.inline").is_active(buf))
    fn(win, buf)
  end)

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if not vim.tbl_contains(wins_before, win) and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  vim.api.nvim_set_current_win(origin)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if not vim.tbl_contains(bufs_before, buf) then
      delete_buffer(buf)
    end
  end
  if not ok then
    error(err, 0)
  end
end

local float_config = { relative = "editor", row = 1, col = 1, width = 20, height = 3 }

-- Each open(buf) returns a window that shows buf at the level it copied from
-- the rendered window, without the rendering having raised it there.
for _, case in ipairs({
  {
    name = "a window opened with :split",
    levels = { 1, 1 },
    copied = { 2, 1 },
    cleared = { 1, 1 },
    open = function()
      vim.cmd("split")
      return vim.api.nvim_get_current_win()
    end,
  },
  {
    name = "a window opened with :vsplit",
    levels = { 1, 1 },
    copied = { 2, 1 },
    cleared = { 1, 1 },
    open = function()
      vim.cmd("vsplit")
      return vim.api.nvim_get_current_win()
    end,
  },
  {
    name = "a window opened with :tab split",
    levels = { 1, 1 },
    copied = { 2, 1 },
    cleared = { 1, 1 },
    open = function()
      vim.cmd("tab split")
      return vim.api.nvim_get_current_win()
    end,
  },
  {
    name = "a float of the rendered buffer",
    levels = { 1, 1 },
    copied = { 2, 1 },
    cleared = { 1, 1 },
    open = function(buf)
      return vim.api.nvim_open_win(buf, false, float_config)
    end,
  },
  {
    -- 3 is above the raised level, so the split copies the user's own 3.
    name = "a window split off a window at a local 3",
    levels = { 3, 0 },
    copied = { 3, 0 },
    cleared = { 3, 0 },
    open = function()
      vim.cmd("split")
      return vim.api.nvim_get_current_win()
    end,
  },
  {
    -- As a vimrc sets it: 2 everywhere, which the clear must not lower.
    name = "a window split off a window at a global 2",
    levels = { 2, 2 },
    copied = { 2, 2 },
    cleared = { 2, 2 },
    open = function()
      vim.cmd("split")
      return vim.api.nvim_get_current_win()
    end,
  },
}) do
  h.test("clearing leaves the window's own conceallevel to " .. case.name, function()
    with_rendered_window(case.levels, function(_, buf)
      local label = case.name .. ": "
      local opened = case.open(buf)
      h.assert_deep_eq(label .. "the window runs at the copied level", conceallevels(opened), case.copied)

      require("markdown-table-wrap").close_preview()
      h.assert_false(label .. "the rendering is cleared", require("markdown-table-wrap.inline").is_active(buf))
      h.assert_deep_eq(label .. "clearing leaves the window at its own level", conceallevels(opened), case.cleared)
    end)
  end)
end

h.test("clearing sets a copied window to its own global conceallevel, not the clearing window's", function()
  with_rendered_window({ 0, 0 }, function(win)
    vim.cmd("split")
    local copied = vim.api.nvim_get_current_win()
    vim.cmd("setglobal conceallevel=1")
    h.assert_deep_eq("the split runs at the raised level over its own global 1", conceallevels(copied), { 2, 1 })

    vim.api.nvim_set_current_win(win)
    require("markdown-table-wrap").close_preview()
    h.assert_deep_eq("the split goes to its own global level", conceallevels(copied), { 1, 1 })
    h.assert_deep_eq("the clearing window gets its level back", conceallevels(win), { 0, 0 })
  end)
end)

-- Each open(win) returns a window showing another buffer, in or opened from
-- the rendered window while the table stays rendered.
for _, case in ipairs({
  {
    name = "another file edited in the rendered window",
    open = function(win)
      vim.cmd.edit(vim.fn.tempname())
      return win
    end,
  },
  {
    name = "a :new window opened from the rendered window",
    open = function()
      vim.cmd("new")
      return vim.api.nvim_get_current_win()
    end,
  },
  {
    name = "a float of another buffer entered from the rendered window",
    open = function()
      return vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), true, float_config)
    end,
  },
  {
    name = "a float of another buffer opened from the rendered window without entering it",
    open = function()
      return vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), false, float_config)
    end,
  },
}) do
  h.test(case.name .. " runs at the user's conceallevel", function()
    with_rendered_window({ 1, 1 }, function(win, buf)
      local label = case.name .. ": "
      local other = case.open(win)
      h.assert_true(label .. "the table stays rendered", require("markdown-table-wrap.inline").is_active(buf))
      h.assert_true(label .. "the window shows another buffer", vim.api.nvim_win_get_buf(other) ~= buf)
      h.assert_deep_eq(label .. "the other buffer runs at the user's level", conceallevels(other), { 1, 1 })
      h.assert_eq(label .. "the rendered window's global level is untouched", conceallevels(win)[2], 1)
    end)
  end)
end

-- The rendered window leaves the buffer while it stays rendered, a split of it
-- clears the rendering, and the rendered window comes back to the buffer.
local function come_back_after_a_clear_elsewhere(win, buf)
  vim.cmd("vsplit")
  local clearing = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(win)
  vim.cmd("buffer " .. vim.api.nvim_create_buf(false, true))
  vim.api.nvim_set_current_win(clearing)
  require("markdown-table-wrap").close_preview()
  vim.api.nvim_set_current_win(win)
  vim.cmd("buffer " .. buf)
  return win
end

-- Each arrange(win, buf) clears the rendering and returns a window that shows
-- buf afterwards, starting from the raised level a window left stored with buf
-- while it was rendered.
for _, case in ipairs({
  {
    -- The split stores its raised level with the buffer when it leaves it, and
    -- Neovim hands that to a window that never showed the buffer.
    name = "a new window after a split left the buffer and closed",
    levels = { 1, 1 },
    shown = { 1, 1 },
    arrange = function(_, buf)
      vim.cmd("split")
      vim.cmd("buffer " .. vim.api.nvim_create_buf(false, true))
      vim.cmd("close")
      require("markdown-table-wrap").close_preview()
      vim.cmd("new")
      vim.cmd("buffer " .. buf)
      return vim.api.nvim_get_current_win()
    end,
  },
  {
    name = "the rendered window coming back after another window cleared the buffer",
    levels = { 1, 1 },
    shown = { 1, 1 },
    arrange = come_back_after_a_clear_elsewhere,
  },
  {
    name = "the rendered window at a local 1 coming back after another window cleared the buffer",
    levels = { 1, 0 },
    shown = { 1, 0 },
    arrange = come_back_after_a_clear_elsewhere,
  },
  {
    name = "the rendered window at a local 1 under a global 2 coming back after another window cleared the buffer",
    levels = { 1, 2 },
    shown = { 1, 2 },
    arrange = come_back_after_a_clear_elsewhere,
  },
}) do
  h.test("a window showing a cleared buffer runs at the user's conceallevel: " .. case.name, function()
    with_rendered_window(case.levels, function(win, buf)
      local label = case.name .. ": "
      local shown = case.arrange(win, buf)
      h.assert_false(label .. "the rendering is cleared", require("markdown-table-wrap.inline").is_active(buf))
      h.assert_eq(label .. "the window shows the buffer", vim.api.nvim_win_get_buf(shown), buf)
      h.assert_deep_eq(label .. "the window runs at the user's level", conceallevels(shown), case.shown)
    end)
  end)
end

-- Each change(win, buf), where given, runs while the table is rendered in win.
for _, case in ipairs({
  {
    name = "a local level set before the rendering",
    levels = { 1, 0 },
    cleared = { 1, 0 },
  },
  {
    -- 2 needs no raise, but it is still the user's own, unlike the 2 a
    -- window copies from a rendered one.
    name = "a local 2 set before the rendering",
    levels = { 2, 0 },
    cleared = { 2, 0 },
  },
  {
    name = "a local 1 set before the rendering under a global 2",
    levels = { 1, 2 },
    cleared = { 1, 2 },
  },
  {
    name = "a global level set during the rendering",
    levels = { 1, 0 },
    cleared = { 1, 3 },
    change = function()
      vim.cmd("setglobal conceallevel=3")
    end,
  },
  {
    -- :setglobal leaves the local level alone, also where it was equal.
    name = "a global level set during the rendering over an equal local level",
    levels = { 0, 0 },
    cleared = { 0, 3 },
    change = function()
      vim.cmd("setglobal conceallevel=3")
    end,
  },
  {
    name = "a local level above 2 set during the rendering",
    levels = { 1, 1 },
    cleared = { 3, 1 },
    change = function()
      vim.cmd("setlocal conceallevel=3")
    end,
  },
  {
    -- The cursor move raises it again; the lowered level is the user's latest
    -- choice, not the level from before the rendering.
    name = "a local level below 2 set during the rendering",
    levels = { 1, 0 },
    cleared = { 0, 0 },
    change = function(win, buf)
      vim.cmd("setlocal conceallevel=0")
      vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
      h.assert_deep_eq("the cursor move raises the local level again", conceallevels(win), { 2, 0 })
    end,
  },
}) do
  h.test("clearing hands the rendered window back " .. case.name, function()
    with_rendered_window(case.levels, function(win, buf)
      if case.change then
        case.change(win, buf)
      end
      require("markdown-table-wrap").close_preview()
      h.assert_deep_eq(case.name .. ": clearing leaves the user's levels", conceallevels(win), case.cleared)
    end)
  end)
end

h.test("a 2 set in a window showing a cleared buffer stays while the window keeps showing it", function()
  with_rendered_window({ 1, 1 }, function(win, buf)
    require("markdown-table-wrap").close_preview()
    vim.cmd("setlocal conceallevel=2")

    vim.cmd("new")
    vim.api.nvim_set_current_win(win)
    h.assert_deep_eq("WinEnter keeps the 2 set in the window", conceallevels(win), { 2, 1 })

    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
    h.assert_deep_eq("a cursor move keeps the 2 set in the window", conceallevels(win), { 2, 1 })

    vim.cmd("new")
    vim.cmd("buffer " .. buf)
    h.assert_deep_eq("another window showing the buffer keeps the 2 set in the window", conceallevels(win), { 2, 1 })
  end)
end)

h.test("closing a rendered window stores its own conceallevel with the buffer", function()
  with_rendered_window({ 1, 0 }, function(win, buf)
    vim.cmd("vnew")
    local other = vim.api.nvim_get_current_win()
    vim.api.nvim_win_close(win, true)
    require("markdown-table-wrap.inline").clear(buf)

    -- Not a check on the closed window, whose options go with it: Neovim
    -- hands them to the next window that shows its buffer.
    vim.cmd("buffer " .. buf)
    h.assert_deep_eq(
      "the next window shows the buffer at the closed window's own level",
      conceallevels(other),
      { 1, 0 }
    )
  end)
end)

h.test("closing a window on another buffer stores the 2 set for that buffer", function()
  with_rendered_window({ 1, 1 }, function()
    vim.cmd("new")
    local opened = vim.api.nvim_get_current_win()
    local buf_new = vim.api.nvim_get_current_buf()
    vim.cmd("setlocal conceallevel=2")
    vim.api.nvim_win_close(opened, true)

    vim.cmd("split")
    vim.cmd("buffer " .. buf_new)
    h.assert_deep_eq("the buffer comes back with the 2 set for it", conceallevels(0), { 2, 1 })
  end)
end)

h.test("a clear after a Visual mode clear still hands the conceallevel back", function()
  with_rendered_window({ 1, 1 }, function(win, buf)
    -- What ModeChanged runs on entering Visual mode.
    require("markdown-table-wrap.inline").clear(buf, { keep_window = true })
    h.assert_deep_eq("the Visual mode clear keeps the raised level", conceallevels(win), { 2, 1 })

    require("markdown-table-wrap").close_preview()
    h.assert_deep_eq("the clear after it hands the user's level back", conceallevels(win), { 1, 1 })
  end)
end)

local table_and_prose = { table_lines[1], table_lines[2], table_lines[3], "", "outro" }

h.test("Visual mode with auto_preview off ends rendered or at the user's conceallevel", function()
  with_rendered_window({ 0, 0 }, function(win, buf)
    local inline = require("markdown-table-wrap.inline")
    h.feed("V")
    h.feed("<Esc>")
    h.assert_true("leaving Visual mode renders the selected table again", inline.is_active(buf))
    h.assert_deep_eq("the rendered window keeps the raised level", conceallevels(win), { 2, 0 })

    -- Visual mode over an edit made since the rendering clears everything.
    h.feed("Gx")
    h.feed("ggV")
    h.feed("<Esc>")
    h.assert_false("nothing is rendered after Visual mode", inline.is_active(buf))
    h.assert_deep_eq("the window gets the user's level back", conceallevels(win), { 0, 0 })
  end, nil, table_and_prose)
end)

h.test("Visual mode out of a table kept on leave ends rendered or at the user's conceallevel", function()
  with_rendered_window({ 0, 0 }, function(win, buf)
    local inline = require("markdown-table-wrap.inline")
    h.feed("V3j")
    h.feed("<Esc>")
    h.drain_timers(1)
    h.assert_true("the table the cursor left is rendered again", inline.is_active(buf))
    h.assert_deep_eq("the rendered window keeps the raised level", conceallevels(win), { 2, 0 })

    -- Deleting the table leaves nothing that the refresh could render.
    h.feed("ggVjjd")
    h.drain_timers(1)
    h.assert_false("nothing is rendered after the table is deleted", inline.is_active(buf))
    h.assert_deep_eq("the window gets the user's level back", conceallevels(win), { 0, 0 })
  end, { auto_preview = true, render_all = false, clear_on_cursor_leave = false }, table_and_prose)
end)

h.test("Visual mode in a paused buffer ends at the user's conceallevel when nothing is left", function()
  with_rendered_window({ 0, 0 }, function(win, buf)
    local plugin = require("markdown-table-wrap")
    local inline = require("markdown-table-wrap.inline")
    plugin.close_preview()
    -- A forced refresh renders in the paused buffer; automatic ones do not.
    plugin.refresh_auto({ force = true })
    h.assert_true("the forced refresh renders the table", inline.is_active(buf))

    h.feed("ggVjjd")
    h.drain_timers(1)
    h.assert_false("nothing is rendered after the table is deleted", inline.is_active(buf))
    h.assert_deep_eq("the window gets the user's level back", conceallevels(win), { 0, 0 })
  end, { auto_preview = true }, table_and_prose)
end)

-- render_all both ways: one renders through show(), the other through
-- show_many().
for _, render_all in ipairs({ true, false }) do
  h.test(
    "an Inline insert mode rendering leaves the window's conceallevel alone, render_all = " .. tostring(render_all),
    function()
      with_rendered_window({ 2, 0 }, function(win, buf)
        local label = "render_all = " .. tostring(render_all) .. ": "
        require("markdown-table-wrap").close_preview()
        h.assert_deep_eq(label .. "the clear leaves the local 2", conceallevels(win), { 2, 0 })

        vim.cmd("buffer " .. vim.api.nvim_create_buf(false, true))
        vim.cmd("buffer " .. buf)
        h.assert_deep_eq(label .. "showing the buffer again leaves the local 2", conceallevels(win), { 2, 0 })
      end, { inline_mode = "insert", render_all = render_all })
    end
  )
end

h.test("BufWipeout disposes all per-buffer runtime state", function()
  local plugin = require("markdown-table-wrap")

  plugin.setup({
    auto_preview = false,
    render_all = true,
    debounce_ms = 1,
  })

  local buf = new_markdown_buffer(table_lines)
  vim.api.nvim_set_current_buf(buf)
  plugin.toggle_inline()
  plugin.state.paused_buffers[buf] = true
  plugin.schedule_refresh({ bufnr = buf, winid = vim.api.nvim_get_current_win(), force = true })
  -- Without these the cleanup assertions below would pass on state that was
  -- never there.
  h.assert_eq("buffer is the active inline buffer before the wipe", plugin.state.inline_buf, buf)
  h.assert_true("buffer is paused before the wipe", plugin.state.paused_buffers[buf] == true)
  h.assert_true("buffer has a render signature before the wipe", plugin.state.last_signature[buf] ~= nil)
  vim.api.nvim_buf_delete(buf, { force = true })
  -- Not skipped: the refresh scheduled above fires after the wipe and must
  -- not bring any of the state back.
  h.drain_timers(1)

  for _, field in ipairs({
    "auto_buffers",
    "buffer_modes",
    "refresh_tokens",
    "paused_buffers",
    "last_signature",
    "visual_buffers",
  }) do
    h.assert_eq(field .. " is cleared for wiped buffer", (plugin.state[field] or {})[buf], nil)
  end
  h.assert_true("wiped buffer is invalid", not vim.api.nvim_buf_is_valid(buf))
  h.assert_true("wiped buffer is no longer the active inline buffer", plugin.state.inline_buf ~= buf)
end)

h.test("repeated setup disposes the inline renderings of the previous setup", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")
  plugin.setup({ auto_preview = false, preview_mode = "inline", render_all = true })

  h.with_buffer(table_lines, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.wo.conceallevel = 1
    plugin.refresh_auto({ force = true })
    h.assert_true("the table is rendered before setup", inline.is_active(buf))
    h.assert_eq("rendering raises conceallevel", vim.wo.conceallevel, 2)

    plugin.setup({ auto_preview = false })
    h.assert_eq(
      "no inline extmarks are left after setup",
      #vim.api.nvim_buf_get_extmarks(buf, inline.namespace(), 0, -1, {}),
      0
    )
    h.assert_eq("setup hands back the conceallevel from before the rendering", vim.wo.conceallevel, 1)
  end)
end)

h.test("repeated setup closes an open floating preview", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({ auto_preview = false, preview_mode = "float" })

  h.with_buffer(table_lines, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    local source_win = vim.api.nvim_get_current_win()
    plugin.float_preview()
    -- Not plugin.state.win, which is private: the float takes focus.
    local float_win = vim.api.nvim_get_current_win()
    local float_buf = vim.api.nvim_win_get_buf(float_win)
    h.assert_true(
      "a float opens before setup",
      float_win ~= source_win and vim.api.nvim_win_get_config(float_win).relative ~= ""
    )

    plugin.setup({ auto_preview = false, preview_mode = "float" })
    h.assert_false("old float window is closed", vim.api.nvim_win_is_valid(float_win))
    h.assert_false("old float buffer is deleted", vim.api.nvim_buf_is_valid(float_buf))
  end)
end)
