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
