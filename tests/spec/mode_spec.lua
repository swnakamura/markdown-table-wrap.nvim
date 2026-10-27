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
    h.assert_true("source mode pauses automatic rendering", plugin.state.paused_buffers[buf])
  end)
end)
