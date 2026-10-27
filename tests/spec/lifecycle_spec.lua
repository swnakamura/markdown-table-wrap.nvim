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
    debounce_ms = 20,
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
  end, 10)

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
  plugin.setup({ auto_preview = false, preview_mode = "inline", debounce_ms = 20 })

  h.with_buffer(table_lines, function(buf)
    vim.bo[buf].filetype = "markdown"
    local original_refresh = plugin.refresh_auto
    local refresh_calls = 0
    plugin.refresh_auto = function()
      refresh_calls = refresh_calls + 1
    end

    plugin.schedule_refresh({ bufnr = buf, winid = vim.api.nvim_get_current_win() })
    plugin.setup({ auto_preview = false, preview_mode = "inline", debounce_ms = 20 })
    plugin.schedule_refresh({ bufnr = buf, winid = vim.api.nvim_get_current_win() })
    vim.wait(200, function()
      return refresh_calls >= 1
    end, 10)
    vim.wait(40)

    plugin.refresh_auto = original_refresh
    h.assert_eq("only the current setup epoch refreshes", refresh_calls, 1)
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
    debounce_ms = 30,
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
  vim.wait(80)

  for _, field in ipairs({
    "auto_buffers",
    "buffer_modes",
    "refresh_tokens",
    "paused_buffers",
    "last_signature",
    "visual_buffers",
    "gx_fallbacks",
    "gx_installed",
    "gx_callbacks",
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
    plugin.float_preview()
    local float_win = plugin.state.win
    local float_buf = plugin.state.buf
    h.assert_true("float opens before setup", vim.api.nvim_win_is_valid(float_win))

    plugin.setup({ auto_preview = false, preview_mode = "float" })
    h.assert_true("old float window is closed", not vim.api.nvim_win_is_valid(float_win))
    h.assert_true("old float buffer is deleted", not vim.api.nvim_buf_is_valid(float_buf))
    h.assert_eq("float window state is cleared", plugin.state.win, nil)
    h.assert_eq("float buffer state is cleared", plugin.state.buf, nil)
  end)
end)

h.test("gx delegates ordinary text to the previous buffer-local mapping", function()
  local plugin = require("markdown-table-wrap")
  local fallback_calls = 0

  h.with_buffer({ "ordinary Markdown prose" }, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.keymap.set("n", "gx", function()
      fallback_calls = fallback_calls + 1
    end, { buffer = buf, silent = true, desc = "Lifecycle test gx fallback" })

    plugin.setup({ auto_preview = false, map_gx = true })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd("normal gx")

    h.assert_eq("previous buffer-local gx mapping is called once", fallback_calls, 1)

    plugin.setup({ auto_preview = false, map_gx = false })
    vim.cmd("normal gx")
    h.assert_eq("disabling the proxy restores the previous mapping", fallback_calls, 2)
  end)
end)

h.test("gx proxy evaluates an existing string expression mapping", function()
  local plugin = require("markdown-table-wrap")
  local expression_calls = 0
  _G.__markdown_table_wrap_test_expr = function()
    expression_calls = expression_calls + 1
    return "<Ignore>"
  end

  h.with_buffer({ "ordinary Markdown prose" }, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.keymap.set("n", "gx", "v:lua.__markdown_table_wrap_test_expr()", {
      buffer = buf,
      expr = true,
      replace_keycodes = false,
      silent = true,
      desc = "Lifecycle string expr gx fallback",
    })

    plugin.setup({ auto_preview = false, map_gx = true })
    vim.cmd("normal gx")
    h.assert_eq("proxy evaluates the previous expression mapping", expression_calls, 1)

    plugin.setup({ auto_preview = false, map_gx = false })
    local restored = vim.api.nvim_buf_call(buf, function()
      return vim.fn.maparg("gx", "n", false, true)
    end)
    h.assert_true(
      "restored mapping preserves replace_keycodes when reported",
      restored.replace_keycodes == nil or restored.replace_keycodes == 0
    )
    vim.cmd("normal gx")
    h.assert_eq("restored expression mapping still evaluates", expression_calls, 2)
  end)

  _G.__markdown_table_wrap_test_expr = nil
end)

h.test("gx teardown preserves a later user mapping even with the same description", function()
  local plugin = require("markdown-table-wrap")
  local later_calls = 0

  h.with_buffer({ "ordinary Markdown prose" }, function(buf)
    vim.bo[buf].filetype = "markdown"
    plugin.setup({ auto_preview = false, map_gx = true })

    vim.keymap.set("n", "gx", function()
      later_calls = later_calls + 1
    end, { buffer = buf, desc = "Open Markdown table link" })

    plugin.setup({ auto_preview = false, map_gx = false })
    vim.cmd("normal gx")
    h.assert_eq("later user mapping is not mistaken for the proxy", later_calls, 1)
  end)
end)
