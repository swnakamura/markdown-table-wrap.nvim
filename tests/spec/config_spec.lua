local h = require("tests.helpers")

h.test("setup normalizes invalid configuration without breaking rendering", function()
  local plugin = require("markdown-table-wrap")

  plugin.setup({
    max_width_ratio = 9,
    min_col_width = 0,
    max_col_width = -1,
    debounce_ms = -1,
    overlay_priority = 0,
    preview_mode = "unknown",
    inline_mode = "unknown",
    inline_position = "sideways",
    table_border = "double",
    highlight_preset = "not-a-preset",
    extra_filetypes = { "text", 1 },
    link = false,
    themes = false,
    highlights = false,
    theme_dir = false,
  })

  h.assert_eq("ratio is capped to window width", plugin.config.max_width_ratio, 1)
  h.assert_eq("minimum width is positive", plugin.config.min_col_width, 1)
  h.assert_eq("maximum width follows minimum", plugin.config.max_col_width, 1)
  h.assert_eq("negative debounce is clamped", plugin.config.debounce_ms, 0)
  h.assert_eq("overlay priority is positive", plugin.config.overlay_priority, 1)
  h.assert_eq("invalid preview mode falls back", plugin.config.preview_mode, "inline")
  h.assert_eq("invalid inline mode falls back", plugin.config.inline_mode, "replace")
  h.assert_eq("invalid inline position falls back", plugin.config.inline_position, "above")
  h.assert_eq("invalid table border falls back", plugin.config.table_border, "rounded")
  h.assert_eq("invalid preset falls back", plugin.config.highlight_preset, "default")
  h.assert_deep_eq("invalid filetypes are ignored", plugin.config.extra_filetypes, {})
  h.assert_true("link config is restored", type(plugin.config.link) == "table")
  h.assert_deep_eq("invalid themes are ignored", plugin.config.themes, {})
  h.assert_deep_eq("invalid highlights are ignored", plugin.config.highlights, {})
  h.assert_eq("invalid theme directory is ignored", plugin.config.theme_dir, nil)
end)

h.test("setup with a leftover map_gx = true leaves buffer-local gx alone", function()
  local plugin = require("markdown-table-wrap")

  -- Not maparg alone: it falls back to Neovim's global gx, present even under -u NONE.
  local function buffer_gx(buf)
    return vim.api.nvim_buf_call(buf, function()
      local mapping = vim.fn.maparg("gx", "n", false, true)
      return mapping.buffer == 1 and mapping or nil
    end)
  end

  for _, filetype_first in ipairs({ true, false }) do
    local label = filetype_first and "filetype set before setup: " or "filetype set after setup: "
    local bare = vim.api.nvim_create_buf(false, true)
    local mapped = vim.api.nvim_create_buf(false, true)
    vim.keymap.set("n", "gx", "<Cmd>let g:markdown_table_wrap_test_gx = 1<CR>", {
      buffer = mapped,
      silent = true,
      desc = "Config test user gx",
    })
    local user_gx = buffer_gx(mapped)
    h.assert_true(label .. "the user's gx is buffer-local before setup", user_gx ~= nil)

    if filetype_first then
      vim.bo[bare].filetype = "markdown"
      vim.bo[mapped].filetype = "markdown"
      plugin.setup({ auto_preview = false, map_gx = true })
    else
      plugin.setup({ auto_preview = false, map_gx = true })
      vim.bo[bare].filetype = "markdown"
      vim.bo[mapped].filetype = "markdown"
    end

    h.assert_eq(label .. "no buffer-local gx is installed", buffer_gx(bare), nil)
    h.assert_deep_eq(label .. "the user's buffer-local gx is unchanged", buffer_gx(mapped), user_gx)
    vim.api.nvim_buf_delete(bare, { force = true })
    vim.api.nvim_buf_delete(mapped, { force = true })
  end
end)

h.test("ColorScheme reapplies configured highlights", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({
    auto_preview = false,
    highlights = { border = { fg = "#123456" } },
  })

  vim.api.nvim_set_hl(0, "MarkdownTableWrapBorder", { fg = "#ffffff" })
  vim.api.nvim_exec_autocmds("ColorScheme", {})
  local highlight = vim.api.nvim_get_hl(0, { name = "MarkdownTableWrapBorder", link = false })
  h.assert_eq("configured border color is restored", highlight.fg, 0x123456)
end)

h.test("all documented commands exist after setup", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({ auto_preview = false })

  for _, command in ipairs({
    "MarkdownTablePreview",
    "MarkdownTableFloatPreview",
    "MarkdownTableToggleAutoPreview",
    "MarkdownTableRefresh",
    "MarkdownTableToggleInline",
  }) do
    h.assert_eq("command exists: " .. command, vim.fn.exists(":" .. command), 2)
  end
end)

h.test("viewport scrolling commands are gone after setup", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({ auto_preview = false })

  for _, command in ipairs({
    "MarkdownTableToggleInlineViewport",
    "MarkdownTableScrollDown",
    "MarkdownTableScrollUp",
    "MarkdownTableScrollTop",
    "MarkdownTableScrollBottom",
  }) do
    h.assert_eq("removed command is absent: " .. command, vim.fn.exists(":" .. command), 0)
  end
end)

h.test("MarkdownTableOpenLink is gone after setup", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({ auto_preview = false })
  h.assert_eq("removed command is absent", vim.fn.exists(":MarkdownTableOpenLink"), 0)
end)

h.test("Reader mode is gone and inline stays the default preview mode", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({ auto_preview = false })
  h.assert_eq("default preview mode", plugin.config.preview_mode, "inline")

  for _, command in ipairs({
    "MarkdownTableReader",
    "MarkdownTableToggleReader",
    "MarkdownTableEditSource",
  }) do
    h.assert_eq("removed command is absent: " .. command, vim.fn.exists(":" .. command), 0)
  end

  plugin.setup({ auto_preview = false, preview_mode = "reader" })
  h.assert_eq("a leftover reader preview mode falls back to inline", plugin.get_preview_mode(0), "inline")
end)

h.test("repeated setup replaces plugin autocmds instead of accumulating them", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({ auto_preview = false })
  local first = #vim.api.nvim_get_autocmds({ group = "MarkdownTableWrap" })

  plugin.setup({ auto_preview = false, preview_mode = "inline" })
  local second = #vim.api.nvim_get_autocmds({ group = "MarkdownTableWrap" })

  h.assert_true("plugin registers autocmds", first > 0)
  h.assert_eq("second setup does not duplicate autocmds", second, first)
end)

h.test("setup below Neovim 0.11 reports an error and sets nothing up", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  -- Earlier setup() calls already created the augroup and the commands, so
  -- they are removed first: what is left afterwards is what this call made.
  plugin.setup({ auto_preview = false })
  vim.api.nvim_del_augroup_by_id(plugin.state.augroup)
  plugin.state.augroup = nil
  for name in pairs(vim.api.nvim_get_commands({})) do
    if name:match("^MarkdownTable") then
      vim.api.nvim_del_user_command(name)
    end
  end

  local original_has = vim.fn.has
  local original_notify = vim.notify
  local notifications = {}
  vim.fn.has = function(feature)
    if feature == "nvim-0.11" then
      return 0
    end
    return original_has(feature)
  end
  vim.notify = function(message, level)
    table.insert(notifications, { message = message, level = level })
  end

  local ok, err = pcall(h.with_buffer, {
    "| A | B |",
    "| --- | --- |",
    "| one | two |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    plugin.setup({ debounce_ms = 0 })
    -- A setup that went ahead would have scheduled its first refresh with no
    -- delay, so it has run by the time a 1 ms sentinel fires.
    h.drain_timers(1)
    h.assert_false("no table is rendered", inline.is_active(buf))
  end)

  vim.fn.has = original_has
  vim.notify = original_notify

  h.assert_true("setup does not throw: " .. tostring(err), ok)
  h.assert_eq("exactly one notification", #notifications, 1)
  local notification = notifications[1] or {}
  h.assert_eq("the notification is an error", notification.level, vim.log.levels.ERROR)
  h.assert_true("the notification names 0.11", tostring(notification.message):find("0.11", 1, true) ~= nil)
  h.assert_false("no plugin augroup exists", pcall(vim.api.nvim_get_autocmds, { group = "MarkdownTableWrap" }))
  local commands = {}
  for name in pairs(vim.api.nvim_get_commands({})) do
    if name:match("^MarkdownTable") then
      table.insert(commands, name)
    end
  end
  h.assert_deep_eq("no MarkdownTable commands exist", commands, {})

  plugin.setup({ auto_preview = false })
  h.assert_true(
    "a normal setup works again afterwards",
    #vim.api.nvim_get_autocmds({ group = "MarkdownTableWrap" }) > 0
  )
  h.assert_eq("its commands are back", vim.fn.exists(":MarkdownTablePreview"), 2)
end)
