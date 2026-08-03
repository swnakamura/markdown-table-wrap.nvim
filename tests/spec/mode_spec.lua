local h = require("tests.helpers")

h.test("toggle inline switches between source and inline rendering", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({ auto_preview = false, preview_mode = "reader", debounce_ms = 0 })

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

h.test("closing the reader returns a buffer to its own preview mode override", function()
  local plugin = require("markdown-table-wrap")
  local reader = require("markdown-table-wrap.reader")
  local inline = require("markdown-table-wrap.inline")

  -- Global mode is Reader, so falling back to the global mode instead of the
  -- buffer's own override would strand the buffer exactly as it did before
  -- the round trip was fixed.
  plugin.setup({ preview_mode = "reader", debounce_ms = 0 })

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| one | two |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"

    h.assert_true("the buffer opts into inline", plugin.toggle_inline())
    h.assert_eq("the buffer overrides the global mode", plugin.get_preview_mode(buf), "inline")
    h.assert_true("inline rendering is active", inline.is_active(buf))

    local reader_bufnr = plugin.toggle_reader()
    h.assert_true("the reader opens over the override", reader.is_reader(reader_bufnr))

    h.assert_true("the reader closes again", plugin.toggle_reader())
    h.assert_eq("the source buffer is current", vim.api.nvim_get_current_buf(), buf)
    h.assert_eq("the buffer keeps its own override", plugin.get_preview_mode(buf), "inline")
    h.assert_false("the source is not left paused", plugin.state.paused_buffers[buf] == true)

    vim.wait(400, function()
      return inline.is_active(buf)
    end)
    h.assert_true("the round trip re-renders the buffer", inline.is_active(buf))

    inline.clear(buf)
    plugin.refresh_auto()
    h.assert_true("an ordinary refresh still renders the buffer", inline.is_active(buf))

    inline.clear(buf)
    plugin.state.inline_buf = nil
    plugin.state.paused_buffers[buf] = nil
  end)
end)

h.test("deleting the reader buffer leaves the source as closing it would", function()
  local plugin = require("markdown-table-wrap")
  local reader = require("markdown-table-wrap.reader")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({ preview_mode = "reader", debounce_ms = 0 })

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| one | two |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    local win = vim.api.nvim_get_current_win()
    -- Pin the options the window is entitled to get back, instead of reading
    -- whatever an earlier spec happened to leave behind.
    vim.wo[win].concealcursor = ""
    vim.wo[win].conceallevel = 0
    local saved_concealcursor = vim.wo[win].concealcursor
    local saved_conceallevel = vim.wo[win].conceallevel

    h.assert_true("the buffer opts into inline", plugin.toggle_inline())
    local reader_bufnr = plugin.toggle_reader()
    h.assert_true("the reader opens", reader.is_reader(reader_bufnr))
    -- Assert the precondition rather than assume it: if the Reader ever stops
    -- putting its own options on the window, the restore assertions below
    -- would start comparing a value to itself and pass vacuously.
    h.assert_eq("the reader puts its concealcursor on the window", vim.wo[win].concealcursor, "nvc")
    h.assert_eq("the reader puts its conceallevel on the window", vim.wo[win].conceallevel, 2)

    -- The Reader goes away without close_reader() ever running.
    vim.api.nvim_buf_delete(reader_bufnr, { force = true })

    h.assert_eq("the buffer keeps its own override", plugin.get_preview_mode(buf), "inline")
    h.assert_false("the source is not left paused", plugin.state.paused_buffers[buf] == true)
    h.assert_eq("no reader bookkeeping is left behind", plugin.state.pre_reader_modes[buf], nil)

    -- Reading the window right here would prove nothing. It fell back to a
    -- buffer it had already displayed, and Neovim keeps window-local options
    -- per (window, buffer) pair, so it restores that buffer's remembered
    -- values and masks whatever the plugin did or did not restore. A buffer
    -- this window has never shown inherits the window's current values
    -- instead -- which is also the symptom itself: the Reader's options
    -- following the window into whatever it displays next.
    local fresh_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(win, fresh_bufnr)
    h.assert_eq("the window does not keep the reader's concealcursor", vim.wo[win].concealcursor, saved_concealcursor)
    h.assert_eq("the window does not keep the reader's conceallevel", vim.wo[win].conceallevel, saved_conceallevel)

    -- A leaked "reader" override would make the automatic refresh open a
    -- fresh Reader instead of rendering the source.
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_delete(fresh_bufnr, { force = true })
    vim.wait(400, function()
      return inline.is_active(buf)
    end)
    h.assert_false("no replacement reader is opened", reader.is_reader(vim.api.nvim_get_current_buf()))
    h.assert_true("the source renders again", inline.is_active(buf))

    inline.clear(buf)
    plugin.state.inline_buf = nil
    plugin.state.paused_buffers[buf] = nil
  end)
end)

h.test("toggle inline leaves Reader and renders the source buffer", function()
  local plugin = require("markdown-table-wrap")
  local reader = require("markdown-table-wrap.reader")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({ auto_preview = false, preview_mode = "reader", debounce_ms = 0 })

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| one | two |",
  }, function(source_bufnr)
    vim.bo[source_bufnr].filetype = "markdown"
    local reader_bufnr = plugin.reader_preview()
    h.assert_true("reader opens first", reader.is_reader(reader_bufnr))

    h.assert_true("inline toggle succeeds from Reader", plugin.toggle_inline())
    h.assert_eq("source buffer becomes current", vim.api.nvim_get_current_buf(), source_bufnr)
    h.assert_true("inline rendering replaces Reader", inline.is_active(source_bufnr))
    h.assert_false("Reader is closed", reader.is_reader(vim.api.nvim_get_current_buf()))

    inline.clear(source_bufnr)
    plugin.state.inline_buf = nil
    plugin.state.paused_buffers[source_bufnr] = nil
  end)
end)
