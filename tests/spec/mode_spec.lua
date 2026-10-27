local h = require("tests.helpers")

h.test("toggle inline switches between source and inline rendering", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({ auto_preview = false, preview_mode = "float", debounce_ms = 0 })

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| one | two |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"

    h.assert_true("inline mode enabled", plugin.toggle_inline())
    h.assert_true("inline rendering is active", inline.is_active(buf))
    h.assert_eq("mode switches to inline", plugin.get_preview_mode(buf), "inline")

    h.assert_false("inline mode disabled", plugin.toggle_inline())
    h.assert_false("inline rendering is cleared", inline.is_active(buf))
    plugin.refresh_auto()
    h.assert_false("an automatic refresh does not bring the rendering back", inline.is_active(buf))
  end)
end)

h.test(":MarkdownTableClosePreview closes the float, restores conceallevel and stays cleared", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  -- Not auto_preview = false, under which an edit re-renders nothing anyway.
  plugin.setup({ debounce_ms = 1 })

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| one | two |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    local saved_conceallevel = vim.wo.conceallevel
    vim.wo.conceallevel = 0
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    plugin.refresh_auto()
    h.assert_true("inline rendering is active", inline.is_active(buf))
    h.assert_eq("rendering raises conceallevel", vim.wo.conceallevel, 2)

    local source_win = vim.api.nvim_get_current_win()
    vim.cmd("MarkdownTableFloatPreview")
    local float_win = vim.api.nvim_get_current_win()
    h.assert_true("a float preview is open", vim.api.nvim_win_get_config(float_win).relative ~= "")
    vim.api.nvim_set_current_win(source_win)

    vim.cmd("MarkdownTableClosePreview")
    h.assert_false("the float preview is closed", vim.api.nvim_win_is_valid(float_win))
    h.assert_false("the inline rendering is cleared", inline.is_active(buf))
    h.assert_eq("closing hands back the conceallevel from before the rendering", vim.wo.conceallevel, 0)

    vim.api.nvim_buf_set_lines(buf, 2, 3, false, { "| one | edited |" })
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
    h.drain_timers(1)
    h.assert_false("the automatic refresh after an edit does not render it again", inline.is_active(buf))

    if float_win ~= source_win and vim.api.nvim_win_is_valid(float_win) then
      vim.api.nvim_win_close(float_win, true)
    end
    vim.wo.conceallevel = saved_conceallevel
  end)
end)
