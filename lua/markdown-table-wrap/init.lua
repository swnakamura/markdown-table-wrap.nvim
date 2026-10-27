local M = {}

M.version = "0.2.3"

local defaults = {
  max_width_ratio = 0.9,
  min_col_width = 8,
  max_col_width = 50,
  fit_to_window = true,
  border = "rounded",
  use_unicode_border = true,
  table_border = "rounded",
  row_separator = true,
  -- Render in place, inside the user's own buffer: the source stays editable
  -- and the row under the cursor is revealed as raw markdown.
  preview_mode = "inline",
  inline_mode = "replace",
  inline_position = "above",
  dim_source = true,
  auto_preview = true,
  render_all = true,
  -- Keep tables rendered in insert mode: only the cursor row is revealed
  -- (raw source), so entering insert no longer rewrites the whole screen.
  auto_preview_in_insert = true,
  clear_on_cursor_leave = true,
  clear_on_insert = false,
  -- Clear in visual mode so the selection is visible on raw source lines
  -- (rows hidden behind virtual lines cannot show the selection highlight).
  -- The clear keeps window options so conceal appearance doesn't flicker
  -- buffer-wide.
  clear_on_visual = true,
  debounce_ms = 80,
  overlay_priority = 10000,
  -- Draw the window's line numbers into the rendered rows (virtual lines
  -- cannot receive native line numbers). Follows 'number' and
  -- 'relativenumber'; relative numbers track the cursor row.
  inline_line_numbers = true,
  -- Pad the revealed cursor row with blank virtual lines so the table keeps
  -- a constant total screen height while the cursor moves between its rows.
  -- Without this, every move swaps a rendered row for the raw soft-wrapped
  -- source line (different heights), reflowing everything below the table.
  inline_stable_height = true,
  -- Blockquote (">") tables are rendered inside their quote block; this is
  -- the marker drawn in front of every rendered line, once per quote level.
  -- "auto" uses render-markdown.nvim's quote bar when that plugin is loaded
  -- and the raw ">" otherwise; set to false to draw no marker.
  quote_icon = "auto",
  highlight_preset = "default",
  theme_dir = nil,
  themes = {},
  extra_filetypes = {},
  highlights = {},
  link = {
    icon = "",
    wiki = { icon = " ", highlight = "MarkdownTableWrapWikiLink", scope_highlight = "MarkdownTableWrapWikiLink" },
    image = " ",
    custom = {
      github = { pattern = "github", icon = " " },
      gitlab = { pattern = "gitlab", icon = "󰮠 " },
      youtube = { pattern = "youtube", icon = " " },
      bilibili = { pattern = "bilibili", icon = "󰟴 " },
      cern = { pattern = "cern.ch", icon = " " },
    },
  },
}

M.config = vim.deepcopy(defaults)
M.state = {
  win = nil,
  buf = nil,
  inline_buf = nil,
  augroup = nil,
  refresh_epoch = 0,
  refresh_tokens = {},
  paused_buffers = {},
  auto_buffers = {},
  buffer_modes = {},
  last_signature = {},
  did_setup = false,
  visual_buffers = {},
}

local function configured_filetypes()
  local filetypes = { "markdown", "md", "quarto", "rmd", "rmarkdown" }
  vim.list_extend(filetypes, M.config.extra_filetypes or {})
  return filetypes
end

local function is_supported_filetype(filetype)
  return vim.tbl_contains(configured_filetypes(), filetype)
end

local function normalize_bufnr(bufnr)
  if not bufnr or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

local function is_markdown_buffer(bufnr)
  bufnr = normalize_bufnr(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  return is_supported_filetype(vim.bo[bufnr].filetype)
end

local function preview_mode_for(bufnr)
  return M.state.buffer_modes[bufnr] or M.config.preview_mode
end

local function auto_preview_for(bufnr)
  local override = M.state.auto_buffers[bufnr]
  if override ~= nil then
    return override
  end
  return M.config.auto_preview
end

local function config_for_buffer(bufnr)
  local config = vim.deepcopy(M.config)
  config.preview_mode = preview_mode_for(bufnr)
  config.auto_preview = auto_preview_for(bufnr)
  return config
end

function M.get_buffer_config(bufnr)
  bufnr = normalize_bufnr(bufnr)
  return config_for_buffer(bufnr)
end

function M.get_preview_mode(bufnr)
  bufnr = normalize_bufnr(bufnr)
  return preview_mode_for(bufnr)
end

local function validate_config()
  M.config.max_width_ratio = tonumber(M.config.max_width_ratio) or defaults.max_width_ratio
  M.config.min_col_width = math.max(1, tonumber(M.config.min_col_width) or defaults.min_col_width)
  M.config.max_col_width = math.max(M.config.min_col_width, tonumber(M.config.max_col_width) or defaults.max_col_width)
  M.config.debounce_ms = math.max(0, tonumber(M.config.debounce_ms) or defaults.debounce_ms)
  M.config.overlay_priority = math.max(1, tonumber(M.config.overlay_priority) or defaults.overlay_priority)
  M.config.max_width_ratio = math.max(0.1, math.min(1, M.config.max_width_ratio))
  M.config.render_all = M.config.render_all ~= false
  M.config.fit_to_window = M.config.fit_to_window ~= false
  M.config.clear_on_visual = M.config.clear_on_visual ~= false
  M.config.inline_line_numbers = M.config.inline_line_numbers ~= false
  M.config.inline_stable_height = M.config.inline_stable_height ~= false

  if type(M.config.extra_filetypes) ~= "table" or #M.config.extra_filetypes == 0 then
    M.config.extra_filetypes = {}
  else
    local valid = true
    for _, v in ipairs(M.config.extra_filetypes) do
      if type(v) ~= "string" then
        valid = false
        break
      end
    end
    if not valid then
      M.config.extra_filetypes = {}
    end
  end

  if type(M.config.themes) ~= "table" then
    M.config.themes = {}
  end
  if type(M.config.highlights) ~= "table" then
    M.config.highlights = {}
  end
  if type(M.config.theme_dir) ~= "string" then
    M.config.theme_dir = nil
  end

  if type(M.config.link) ~= "table" then
    M.config.link = vim.deepcopy(defaults.link)
  end
  M.config.link.icon = type(M.config.link.icon) == "string" and M.config.link.icon or defaults.link.icon
  M.config.link.image = type(M.config.link.image) == "string" and M.config.link.image or defaults.link.image
  if type(M.config.link.wiki) ~= "table" then
    M.config.link.wiki = vim.deepcopy(defaults.link.wiki)
  end
  if type(M.config.link.custom) ~= "table" then
    M.config.link.custom = vim.deepcopy(defaults.link.custom)
  end

  if M.config.quote_icon ~= false and type(M.config.quote_icon) ~= "string" then
    M.config.quote_icon = defaults.quote_icon
  end

  if M.config.preview_mode ~= "inline" and M.config.preview_mode ~= "float" then
    M.config.preview_mode = defaults.preview_mode
  end

  if M.config.inline_mode ~= "replace" and M.config.inline_mode ~= "insert" then
    M.config.inline_mode = defaults.inline_mode
  end

  if M.config.inline_position ~= "above" and M.config.inline_position ~= "below" then
    M.config.inline_position = defaults.inline_position
  end

  if M.config.table_border ~= "rounded" and M.config.table_border ~= "single" then
    M.config.table_border = defaults.table_border
  end

  local preset_name = M.config.highlight_preset
  local builtin_preset = false
  for _, preset in ipairs(require("markdown-table-wrap.theme").presets()) do
    if preset == preset_name then
      builtin_preset = true
      break
    end
  end
  local inline_custom = type(M.config.themes[preset_name]) == "table"
  local file_custom = type(M.config.theme_dir) == "string"
  if
    type(preset_name) ~= "string"
    or preset_name == ""
    or (not builtin_preset and not inline_custom and not file_custom)
  then
    M.config.highlight_preset = defaults.highlight_preset
  end
end

local function close_existing()
  if M.state.win and vim.api.nvim_win_is_valid(M.state.win) then
    vim.api.nvim_win_close(M.state.win, true)
  end

  if M.state.buf and vim.api.nvim_buf_is_valid(M.state.buf) then
    vim.api.nvim_buf_delete(M.state.buf, { force = true })
  end

  M.state.win = nil
  M.state.buf = nil
end

local function table_signature(bufnr, table_info, config)
  local lines = vim.api.nvim_buf_get_lines(bufnr, table_info.start_lnum - 1, table_info.end_lnum, false)
  return table.concat({
    tostring(table_info.start_lnum),
    tostring(table_info.end_lnum),
    tostring(vim.api.nvim_win_get_width(0)),
    tostring(config.max_width_ratio),
    tostring(config.min_col_width),
    tostring(config.max_col_width),
    config.use_unicode_border and "unicode" or "ascii",
    tostring(config.table_border),
    tostring(config.row_separator),
    tostring(config.inline_mode),
    tostring(config.clear_on_visual),
    tostring(config.inline_line_numbers),
    tostring(config.inline_stable_height),
    tostring(config.quote_icon),
    tostring(table_info.callout),
    table.concat(lines, "\n"),
  }, "\31")
end

local function all_tables_signature(bufnr, tables, config)
  local parts = {
    tostring(vim.api.nvim_buf_get_changedtick(bufnr)),
    tostring(vim.api.nvim_win_get_width(0)),
    tostring(config.max_width_ratio),
    tostring(config.min_col_width),
    tostring(config.max_col_width),
    config.use_unicode_border and "unicode" or "ascii",
    tostring(config.table_border),
    tostring(config.row_separator),
    tostring(config.inline_mode),
    tostring(config.clear_on_visual),
    tostring(config.inline_line_numbers),
    tostring(config.inline_stable_height),
    tostring(config.quote_icon),
  }

  for _, table_info in ipairs(tables) do
    table.insert(parts, tostring(table_info.start_lnum))
    table.insert(parts, tostring(table_info.end_lnum))
  end

  return table.concat(parts, "\31")
end

function M.close_preview()
  close_existing()
  local bufnr = vim.api.nvim_get_current_buf()
  require("markdown-table-wrap.inline").clear(bufnr)
  if M.state.inline_buf == bufnr then
    M.state.inline_buf = nil
  end
  M.state.paused_buffers[bufnr] = true
end

local function table_under_cursor(opts)
  opts = opts or {}

  if not is_markdown_buffer() then
    if not opts.silent then
      vim.notify(
        "MarkdownTableWrap: preview is only available in Markdown buffers or fts added to extra_filetypes in opts.",
        vim.log.levels.INFO
      )
    end
    return nil
  end

  local parser = require("markdown-table-wrap.parser")
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local table_info, err = parser.parse_at_cursor(bufnr, cursor[1])

  if not table_info then
    if not opts.silent then
      vim.notify(err or "MarkdownTableWrap: cursor is not inside a Markdown pipe table.", vim.log.levels.INFO)
    end
    return nil
  end

  return bufnr, table_info
end

function M.inline_preview()
  local bufnr, table_info = table_under_cursor()
  if not bufnr then
    return
  end

  close_existing()
  M.state.paused_buffers[bufnr] = nil
  local config = config_for_buffer(bufnr)
  require("markdown-table-wrap.inline").show(bufnr, table_info, config)
  M.state.last_signature[bufnr] = table_signature(bufnr, table_info, config)
  M.state.inline_buf = bufnr
end

function M.export_table(opts)
  return require("markdown-table-wrap.export").export(opts)
end

function M.float_preview()
  local bufnr, table_info = table_under_cursor()
  if not bufnr then
    return
  end

  close_existing()

  local config = config_for_buffer(bufnr)
  local render = require("markdown-table-wrap.render")
  local rendered = render.render_table(table_info, config)
  local buf, win = render.open_float(rendered, config)
  M.state.buf = buf
  M.state.win = win
end

function M.preview()
  local mode = preview_mode_for(vim.api.nvim_get_current_buf())
  if mode == "float" then
    M.float_preview()
    return
  end

  M.inline_preview()
end

function M.refresh_auto(opts)
  opts = opts or {}
  local bufnr = normalize_bufnr(opts.bufnr)
  local inline = require("markdown-table-wrap.inline")
  if not vim.api.nvim_buf_is_valid(bufnr) or vim.api.nvim_get_current_buf() ~= bufnr then
    return
  end
  local config = config_for_buffer(bufnr)

  if not config.auto_preview and not opts.force then
    return
  end

  if M.state.paused_buffers[bufnr] and not opts.force then
    return
  end

  if not is_markdown_buffer(bufnr) then
    inline.clear(bufnr)
    return
  end

  local mode = vim.api.nvim_get_mode().mode
  if not config.auto_preview_in_insert and mode:match("^i") then
    inline.clear(bufnr)
    M.state.inline_buf = nil
    M.state.last_signature[bufnr] = nil
    return
  end

  if mode:match("^[vV\22]") then
    return
  end

  local parser = require("markdown-table-wrap.parser")
  if config.render_all then
    local tables = parser.parse_all(bufnr)
    if #tables == 0 then
      inline.clear(bufnr)
      M.state.inline_buf = nil
      M.state.last_signature[bufnr] = nil
      return
    end

    local signature = all_tables_signature(bufnr, tables, config)
    if not opts.force and M.state.last_signature[bufnr] == signature and inline.is_active(bufnr) then
      inline.attach_window(bufnr)
      return
    end

    close_existing()
    inline.show_many(bufnr, tables, config)
    M.state.last_signature[bufnr] = signature
    M.state.inline_buf = bufnr
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local table_info = parser.parse_at_cursor(bufnr, cursor[1])

  if not table_info then
    if config.clear_on_cursor_leave ~= false then
      inline.clear(bufnr)
      if M.state.inline_buf == bufnr then
        M.state.inline_buf = nil
      end
      M.state.last_signature[bufnr] = nil
    end
    return
  end

  local signature = table_signature(bufnr, table_info, config)
  if not opts.force and M.state.last_signature[bufnr] == signature and inline.is_active(bufnr) then
    inline.attach_window(bufnr)
    return
  end

  close_existing()
  inline.show(bufnr, table_info, config)
  M.state.last_signature[bufnr] = signature
  M.state.inline_buf = bufnr
end

function M.schedule_refresh(opts)
  opts = vim.deepcopy(opts or {})
  local bufnr = normalize_bufnr(opts.bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local winid = opts.winid
  if not winid and vim.api.nvim_get_current_buf() == bufnr then
    winid = vim.api.nvim_get_current_win()
  end
  opts.bufnr = bufnr
  opts.winid = nil

  M.state.refresh_tokens[bufnr] = (M.state.refresh_tokens[bufnr] or 0) + 1
  local token = M.state.refresh_tokens[bufnr]
  local epoch = M.state.refresh_epoch
  local delay = opts.immediate and 0 or M.config.debounce_ms

  vim.defer_fn(function()
    if
      epoch ~= M.state.refresh_epoch
      or token ~= M.state.refresh_tokens[bufnr]
      or not vim.api.nvim_buf_is_valid(bufnr)
    then
      return
    end

    if not winid or not vim.api.nvim_win_is_valid(winid) or vim.api.nvim_win_get_buf(winid) ~= bufnr then
      winid = vim.fn.win_findbuf(bufnr)[1]
    end
    if not winid or not vim.api.nvim_win_is_valid(winid) then
      return
    end

    vim.api.nvim_win_call(winid, function()
      M.refresh_auto(opts)
    end)
  end, delay)
end

function M.toggle_preview()
  if M.state.win and vim.api.nvim_win_is_valid(M.state.win) then
    close_existing()
    return
  end

  local inline = require("markdown-table-wrap.inline")
  local bufnr = vim.api.nvim_get_current_buf()
  if inline.is_active(bufnr) then
    inline.clear(bufnr)
    M.state.inline_buf = nil
    M.state.last_signature[bufnr] = nil
    M.state.paused_buffers[bufnr] = true
    return
  end

  M.preview()
end

function M.toggle_inline()
  local inline = require("markdown-table-wrap.inline")
  local bufnr = vim.api.nvim_get_current_buf()

  if not is_markdown_buffer() then
    vim.notify("MarkdownTableWrap: inline rendering is only available in Markdown buffers.", vim.log.levels.INFO)
    return false
  end

  if inline.is_active(bufnr) then
    inline.clear(bufnr)
    M.state.inline_buf = nil
    M.state.last_signature[bufnr] = nil
    M.state.paused_buffers[bufnr] = true
    return false
  end

  M.state.buffer_modes[bufnr] = "inline"
  M.state.auto_buffers[bufnr] = true
  M.state.paused_buffers[bufnr] = nil
  M.refresh_auto({ force = true })
  return true
end

function M.enable_auto_preview()
  local bufnr = vim.api.nvim_get_current_buf()
  M.state.paused_buffers[bufnr] = nil
  M.state.auto_buffers[bufnr] = true
  M.refresh_auto({ force = true })
end

function M.disable_auto_preview()
  local bufnr = vim.api.nvim_get_current_buf()
  M.state.paused_buffers[bufnr] = true
  M.state.auto_buffers[bufnr] = false
  require("markdown-table-wrap.inline").clear(bufnr)
  if M.state.inline_buf == bufnr then
    M.state.inline_buf = nil
  end
  M.state.last_signature[bufnr] = nil
end

function M.toggle_auto_preview()
  local bufnr = vim.api.nvim_get_current_buf()
  if auto_preview_for(bufnr) and not M.state.paused_buffers[bufnr] then
    M.disable_auto_preview()
  else
    M.enable_auto_preview()
  end
end

local function create_autocmds()
  if M.state.augroup then
    vim.api.nvim_del_augroup_by_id(M.state.augroup)
  end

  M.state.augroup = vim.api.nvim_create_augroup("MarkdownTableWrap", { clear = true })

  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = M.state.augroup,
    callback = function(args)
      if not is_markdown_buffer(args.buf) then
        return
      end

      require("markdown-table-wrap.inline").attach_window(args.buf)
      -- Reveal the raw source line under the cursor, restore the row left
      require("markdown-table-wrap.inline").update_reveal(args.buf)

      if config_for_buffer(args.buf).render_all then
        return
      end

      M.schedule_refresh({ bufnr = args.buf, winid = vim.api.nvim_get_current_win(), silent = true })
    end,
  })

  vim.api.nvim_create_autocmd(
    { "TextChanged", "TextChangedI", "InsertLeave", "BufWinEnter", "WinScrolled", "WinResized", "VimResized" },
    {
      group = M.state.augroup,
      callback = function(args)
        local bufnr = args.buf
        if not bufnr or bufnr == 0 or not vim.api.nvim_buf_is_valid(bufnr) then
          bufnr = vim.api.nvim_get_current_buf()
        end

        if not is_markdown_buffer(bufnr) then
          return
        end
        local winid = vim.api.nvim_get_current_win()
        if vim.api.nvim_win_get_buf(winid) ~= bufnr then
          winid = nil
        end
        M.schedule_refresh({ bufnr = bufnr, winid = winid, silent = true })
      end,
    }
  )

  vim.api.nvim_create_autocmd("WinScrolled", {
    group = M.state.augroup,
    callback = function(args)
      if not is_markdown_buffer() then
        return
      end

      -- A table with stale relative line numbers (skipped while off-screen)
      -- can scroll into view without the cursor moving; catch up here.
      require("markdown-table-wrap.inline").update_reveal(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd("InsertEnter", {
    group = M.state.augroup,
    callback = function(args)
      local config = config_for_buffer(args.buf)
      if config.auto_preview_in_insert or not config.clear_on_insert then
        return
      end

      local bufnr = args.buf
      require("markdown-table-wrap.inline").clear(bufnr)
      if M.state.inline_buf == bufnr then
        M.state.inline_buf = nil
      end
      M.state.last_signature[bufnr] = nil
    end,
  })

  vim.api.nvim_create_autocmd("ModeChanged", {
    group = M.state.augroup,
    callback = function(args)
      local bufnr = args.buf
      if not is_markdown_buffer(bufnr) or config_for_buffer(bufnr).clear_on_visual == false then
        return
      end

      local mode = vim.api.nvim_get_mode().mode
      local visual = mode:match("^[vV\22]") ~= nil

      if visual then
        -- keep_window: leave conceallevel in place so concealed markup
        -- outside tables doesn't flicker while toggling visual mode
        require("markdown-table-wrap.inline").clear(bufnr, { keep_window = true })
        if M.state.inline_buf == bufnr then
          M.state.inline_buf = nil
        end
        M.state.last_signature[bufnr] = nil
        M.state.visual_buffers[bufnr] = true
      elseif M.state.visual_buffers[bufnr] then
        M.state.visual_buffers[bufnr] = nil
        M.schedule_refresh({ bufnr = bufnr, winid = vim.api.nvim_get_current_win(), silent = true })
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "WinEnter", "BufWinEnter" }, {
    group = M.state.augroup,
    callback = function(args)
      local inline = require("markdown-table-wrap.inline")
      inline.attach_window(args.buf)
      inline.update_reveal(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
    group = M.state.augroup,
    callback = function(args)
      local inline = require("markdown-table-wrap.inline")
      local config = config_for_buffer(args.buf)

      -- Leaving releases the rendering only in this configuration, and
      -- inline.clear() hands the window options back as part of that (it runs
      -- restore_render_for_buffer over every window showing the buffer). No
      -- separate detach belongs here: while the rendered blocks stay attached
      -- -- under render_all, or with clear_on_cursor_leave = false -- the
      -- window has to keep the options they depend on. conceallevel in
      -- particular is load-bearing, since the source rows are hidden with
      -- conceal_lines and handing back a lower conceallevel makes them
      -- reappear underneath the still-attached block, with nothing to repair
      -- it: WinEnter fires on the window being entered, whose buffer is
      -- usually not the rendered one.
      if not config.render_all and config.clear_on_cursor_leave ~= false then
        inline.clear(args.buf)
        if M.state.inline_buf == args.buf then
          M.state.inline_buf = nil
        end
        M.state.last_signature[args.buf] = nil
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    group = M.state.augroup,
    callback = function(args)
      require("markdown-table-wrap.inline").dispose(args.buf)
      M.state.refresh_tokens[args.buf] = nil
      M.state.paused_buffers[args.buf] = nil
      M.state.auto_buffers[args.buf] = nil
      M.state.buffer_modes[args.buf] = nil
      M.state.last_signature[args.buf] = nil
      M.state.visual_buffers[args.buf] = nil
      if M.state.inline_buf == args.buf then
        M.state.inline_buf = nil
      end
    end,
  })

  vim.api.nvim_create_autocmd("WinClosed", {
    group = M.state.augroup,
    callback = function(args)
      require("markdown-table-wrap.inline").detach_window(tonumber(args.match))
    end,
  })

  vim.api.nvim_create_autocmd("ColorScheme", {
    group = M.state.augroup,
    callback = function()
      require("markdown-table-wrap.theme").apply(M.config)
    end,
  })
end

function M.setup(opts)
  -- Rendering hides the source rows with conceal_lines, an extmark key older
  -- Neovim rejects; rather than failing on every refresh, nothing is set up.
  if vim.fn.has("nvim-0.11") ~= 1 then
    vim.notify("MarkdownTableWrap: Neovim 0.11 or newer is required; the plugin is not set up.", vim.log.levels.ERROR)
    return
  end

  if M.state.did_setup then
    close_existing()
    local inline = require("markdown-table-wrap.inline")
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        inline.dispose(bufnr)
      end
    end
  end

  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  validate_config()
  M.state.refresh_epoch = M.state.refresh_epoch + 1
  M.state.refresh_tokens = {}
  M.state.paused_buffers = {}
  M.state.auto_buffers = {}
  M.state.buffer_modes = {}
  M.state.last_signature = {}
  M.state.visual_buffers = {}
  M.state.inline_buf = nil
  create_autocmds()
  require("markdown-table-wrap.theme").apply(M.config)
  M.state.did_setup = true

  vim.api.nvim_create_user_command("MarkdownTablePreview", function()
    M.preview()
  end, { desc = "Preview the Markdown pipe table under the cursor with wrapped cells", force = true })

  vim.api.nvim_create_user_command("MarkdownTableInlinePreview", function()
    M.inline_preview()
  end, { desc = "Inline preview the Markdown pipe table under the cursor with wrapped cells", force = true })

  vim.api.nvim_create_user_command("MarkdownTableFloatPreview", function()
    M.float_preview()
  end, { desc = "Floating preview the Markdown pipe table under the cursor with wrapped cells", force = true })

  vim.api.nvim_create_user_command("MarkdownTableTogglePreview", function()
    M.toggle_preview()
  end, { desc = "Toggle wrapped Markdown table preview", force = true })

  vim.api.nvim_create_user_command("MarkdownTableToggleInline", function()
    M.toggle_inline()
  end, { desc = "Toggle inline Markdown table rendering", force = true })

  vim.api.nvim_create_user_command("MarkdownTableClosePreview", function()
    M.close_preview()
  end, { desc = "Close wrapped Markdown table preview", force = true })

  vim.api.nvim_create_user_command("MarkdownTableRefresh", function()
    M.refresh_auto({ force = true })
  end, { desc = "Force refresh Markdown table rendering", force = true })

  vim.api.nvim_create_user_command("MarkdownTableEnableAutoPreview", function()
    M.enable_auto_preview()
  end, { desc = "Enable automatic Markdown table preview in the current buffer", force = true })

  vim.api.nvim_create_user_command("MarkdownTableDisableAutoPreview", function()
    M.disable_auto_preview()
  end, { desc = "Disable automatic Markdown table preview in the current buffer", force = true })

  vim.api.nvim_create_user_command("MarkdownTableToggleAutoPreview", function()
    M.toggle_auto_preview()
  end, { desc = "Toggle automatic Markdown table preview in the current buffer", force = true })

  vim.api.nvim_create_user_command("MarkdownTableStatus", function()
    local bufnr = vim.api.nvim_get_current_buf()
    local active = require("markdown-table-wrap.inline").is_active(bufnr)
    local paused = M.state.paused_buffers[bufnr] == true
    local config = config_for_buffer(bufnr)
    vim.notify(
      string.format(
        "MarkdownTableWrap: auto=%s paused=%s active=%s mode=%s/%s",
        tostring(config.auto_preview),
        tostring(paused),
        tostring(active),
        config.preview_mode,
        config.inline_mode
      ),
      vim.log.levels.INFO
    )
  end, { desc = "Show Markdown table wrap status", force = true })

  vim.api.nvim_create_user_command("MarkdownTableNextCell", function()
    require("markdown-table-wrap.nav").move_horizontal(1)
  end, { desc = "Move to the next Markdown table cell", force = true })

  vim.api.nvim_create_user_command("MarkdownTablePrevCell", function()
    require("markdown-table-wrap.nav").move_horizontal(-1)
  end, { desc = "Move to the previous Markdown table cell", force = true })

  vim.api.nvim_create_user_command("MarkdownTableNextRow", function()
    require("markdown-table-wrap.nav").move_vertical(1)
  end, { desc = "Move to the same Markdown table cell in the next row", force = true })

  vim.api.nvim_create_user_command("MarkdownTablePrevRow", function()
    require("markdown-table-wrap.nav").move_vertical(-1)
  end, { desc = "Move to the same Markdown table cell in the previous row", force = true })

  vim.api.nvim_create_user_command("MarkdownTableExport", function(opts_cmd)
    local format = vim.trim(opts_cmd.args)
    M.export_table({ format = format ~= "" and format or "tsv", all = opts_cmd.bang })
  end, {
    desc = "Export the current Markdown table as TSV or CSV",
    bang = true,
    nargs = "?",
    complete = function()
      return { "tsv", "csv" }
    end,
    force = true,
  })

  if auto_preview_for(vim.api.nvim_get_current_buf()) and is_markdown_buffer() then
    M.schedule_refresh({
      bufnr = vim.api.nvim_get_current_buf(),
      winid = vim.api.nvim_get_current_win(),
      silent = true,
      immediate = true,
    })
  end
end

return M
