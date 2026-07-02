local render = require("markdown-table-wrap.render")

local M = {}

local namespace = vim.api.nvim_create_namespace("markdown-table-wrap")
local saved_conceallevels = {}
local saved_concealcursors = {}
local saved_wraps = {}
local active_buffers = {}
local active_tables = {}
local active_configs = {}
local view_offsets = {}

local function normalize_bufnr(bufnr)
  if not bufnr or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

local border_chars = {
  ["╭"] = true,
  ["╮"] = true,
  ["╰"] = true,
  ["╯"] = true,
  ["┌"] = true,
  ["┐"] = true,
  ["└"] = true,
  ["┘"] = true,
  ["┬"] = true,
  ["┴"] = true,
  ["├"] = true,
  ["┤"] = true,
  ["┼"] = true,
  ["│"] = true,
  ["─"] = true,
  ["+"] = true,
  ["|"] = true,
  ["-"] = true,
}

local function iter_chars(text)
  return (text or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*")
end

local function append_chunk(chunks, text, hl_group)
  if text == "" then
    return
  end

  local last = chunks[#chunks]
  if last and last[2] == hl_group then
    last[1] = last[1] .. text
  else
    table.insert(chunks, { text, hl_group })
  end
end

local function semantic_chunks(line, line_index)
  local chunks = {}
  local index = 1

  while index <= #line do
    local code_start = line:find("`", index, true)
    local link_start = line:find("%[.-%]%(.-%)", index)
    local special_start = nil
    local special_end = nil
    local special_hl = nil

    if code_start and (not link_start or code_start < link_start) then
      local code_end = line:find("`", code_start + 1, true)
      if code_end then
        special_start = code_start
        special_end = code_end
        special_hl = "MarkdownTableWrapCode"
      end
    elseif link_start then
      local start_col, end_col = line:find("%[.-%]%(.-%)", index)
      special_start = start_col
      special_end = end_col
      special_hl = "MarkdownTableWrapLink"
    end

    local plain_end = special_start and special_start - 1 or #line
    local plain = line:sub(index, plain_end)
    local buffer = ""
    for ch in iter_chars(plain) do
      local hl_group
      if border_chars[ch] then
        hl_group = "MarkdownTableWrapBorder"
      elseif line_index == 2 then
        hl_group = "MarkdownTableWrapHeader"
      else
        hl_group = "MarkdownTableWrapInline"
      end
      append_chunk(chunks, ch, hl_group)
      buffer = ""
    end

    if not special_start then
      break
    end

    append_chunk(chunks, line:sub(special_start, special_end), special_hl)
    index = special_end + 1
  end

  return chunks
end

local function chunks_from_line_object(line_obj, line_index)
  if type(line_obj) ~= "table" or not line_obj.chunks or #line_obj.chunks == 0 then
    return semantic_chunks(type(line_obj) == "table" and line_obj.text or line_obj, line_index)
  end

  local result = {}
  local cursor = 0
  local sorted = vim.deepcopy(line_obj.chunks)
  table.sort(sorted, function(a, b)
    return a.start_col < b.start_col
  end)

  for _, styled in ipairs(sorted) do
    if cursor < styled.start_col then
      vim.list_extend(result, semantic_chunks(line_obj.text:sub(cursor + 1, styled.start_col), line_index))
    end

    table.insert(result, {
      line_obj.text:sub(styled.start_col + 1, styled.end_col),
      styled.hl_group,
    })
    cursor = styled.end_col
  end

  if cursor < #line_obj.text then
    vim.list_extend(result, semantic_chunks(line_obj.text:sub(cursor + 1), line_index))
  end

  return result
end

local function padded_chunks(line_obj, line_index, target_width)
  local line = type(line_obj) == "table" and line_obj.text or line_obj
  local chunks = chunks_from_line_object(line_obj, line_index)
  local missing = math.max(0, target_width - vim.api.nvim_strwidth(line))

  if missing > 0 then
    append_chunk(chunks, string.rep(" ", missing), "MarkdownTableWrapBlank")
  end

  return chunks
end

local function virt_lines(lines, start_index)
  local result = {}
  start_index = start_index or 1

  for index, line in ipairs(lines) do
    table.insert(result, chunks_from_line_object(line, start_index + index - 1))
  end

  return result
end

local function ensure_highlights(config)
  require("markdown-table-wrap.theme").apply(config)
end

local function set_render_window(winid, config)
  winid = winid or vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(winid) then
    return
  end

  local current = vim.wo[winid].conceallevel
  if current < 2 then
    if saved_conceallevels[winid] == nil then
      saved_conceallevels[winid] = current
    end
    vim.wo[winid].conceallevel = 2
  end

  if saved_concealcursors[winid] == nil then
    saved_concealcursors[winid] = vim.wo[winid].concealcursor
  end
  vim.wo[winid].concealcursor = "nvc"

  if config.inline_disable_wrap ~= false then
    if saved_wraps[winid] == nil then
      saved_wraps[winid] = vim.wo[winid].wrap
    end
    vim.wo[winid].wrap = false
  end
end

local function set_render_for_buffer(bufnr, config)
  for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
    set_render_window(winid, config)
  end
end

local function restore_render_window(winid)
  local previous = saved_conceallevels[winid]
  if previous ~= nil and vim.api.nvim_win_is_valid(winid) then
    vim.wo[winid].conceallevel = previous
  end
  saved_conceallevels[winid] = nil

  local previous_cursor = saved_concealcursors[winid]
  if previous_cursor ~= nil and vim.api.nvim_win_is_valid(winid) then
    vim.wo[winid].concealcursor = previous_cursor
  end
  saved_concealcursors[winid] = nil

  local previous_wrap = saved_wraps[winid]
  if previous_wrap ~= nil and vim.api.nvim_win_is_valid(winid) then
    vim.wo[winid].wrap = previous_wrap
  end
  saved_wraps[winid] = nil
end

local function restore_render_for_buffer(bufnr)
  for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
    restore_render_window(winid)
  end
end

local function conceal_source_line(bufnr, row)
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
  if line == "" then
    return
  end

  vim.api.nvim_buf_set_extmark(bufnr, namespace, row, 0, {
    end_row = row,
    end_col = #line,
    conceal = "",
    priority = 9999,
  })
end

local function table_key(table_info)
  return tostring(table_info.start_lnum) .. ":" .. tostring(table_info.end_lnum)
end

local function view_offset(bufnr, table_info, source_count, rendered_count, config)
  if not config.inline_viewport_scrolling then
    return 0
  end

  view_offsets[bufnr] = view_offsets[bufnr] or {}
  local key = table_key(table_info)
  local max_offset = math.max(0, rendered_count - source_count)
  local offset = math.max(0, math.min(view_offsets[bufnr][key] or 0, max_offset))
  view_offsets[bufnr][key] = offset
  return offset
end

-- Row-anchored replace mode state: per buffer, per source row (0-based), the
-- rendered group and its extmark ids, so the virtual cursor can re-render a
-- single row without redrawing the whole table.
local aligned_rows = {}
local cursor_rows = {}

-- Copy a rendered line and overlay a cursor highlight on byte range [s, e),
-- splitting any existing styled chunks around it.
local function inject_cursor_chunk(line_obj, s, e)
  local text = type(line_obj) == "table" and line_obj.text or line_obj
  local copy = { text = text, chunks = {} }

  for _, chunk in ipairs(type(line_obj) == "table" and line_obj.chunks or {}) do
    if chunk.end_col <= s or chunk.start_col >= e then
      table.insert(copy.chunks, chunk)
    else
      if chunk.start_col < s then
        table.insert(copy.chunks, { start_col = chunk.start_col, end_col = s, hl_group = chunk.hl_group })
      end
      if chunk.end_col > e then
        table.insert(copy.chunks, { start_col = e, end_col = chunk.end_col, hl_group = chunk.hl_group })
      end
    end
  end

  table.insert(copy.chunks, { start_col = s, end_col = e, hl_group = "MarkdownTableWrapCursor" })
  return copy
end

-- (Re-)set the extmarks of one row-anchored source row. cursor_pos is nil or
-- { line = <index into group.lines>, start_col, end_col } for the virtual cursor.
local function set_aligned_row_marks(bufnr, row, entry, cursor_pos)
  for _, key in ipairs({ "leading_id", "overlay_id", "rest_id" }) do
    if entry[key] then
      vim.api.nvim_buf_del_extmark(bufnr, namespace, entry[key])
      entry[key] = nil
    end
  end

  local group = entry.group

  if group.leading and #group.leading > 0 then
    local leading = {}
    for index, line_obj in ipairs(group.leading) do
      table.insert(leading, chunks_from_line_object(line_obj, entry.leading_indexes[index]))
    end

    entry.leading_id = vim.api.nvim_buf_set_extmark(bufnr, namespace, row, 0, {
      virt_lines = leading,
      virt_lines_above = true,
      right_gravity = false,
      priority = entry.priority,
    })
  end

  local first = group.lines[1]
  if cursor_pos and cursor_pos.line == 1 then
    first = inject_cursor_chunk(first, cursor_pos.start_col, cursor_pos.end_col)
  end

  -- virt_text_win_col keeps the overlay window-fixed: Neovim horizontally
  -- scrolls based on the raw (unconcealed) cursor virtcol, which would drag a
  -- text-anchored overlay off screen whenever the cursor sits past the window
  -- width on a long source line.
  entry.overlay_id = vim.api.nvim_buf_set_extmark(bufnr, namespace, row, 0, {
    virt_text = padded_chunks(first, entry.line_indexes[1], entry.overlay_width),
    hl_mode = "replace",
    virt_text_win_col = 0,
    right_gravity = false,
    priority = entry.priority,
  })

  if #group.lines > 1 then
    local rest = {}
    for index = 2, #group.lines do
      local line_obj = group.lines[index]
      if cursor_pos and cursor_pos.line == index then
        line_obj = inject_cursor_chunk(line_obj, cursor_pos.start_col, cursor_pos.end_col)
      end
      table.insert(rest, chunks_from_line_object(line_obj, entry.line_indexes[index]))
    end

    entry.rest_id = vim.api.nvim_buf_set_extmark(bufnr, namespace, row, 0, {
      virt_lines = rest,
      virt_lines_above = false,
      right_gravity = false,
      priority = entry.priority,
    })
  end
end

local function iter_chars_with_bytes(text)
  local index = 1
  return function()
    if index > #text then
      return nil
    end

    local start_col, end_col = text:find("[%z\1-\127\194-\244][\128-\191]*", index)
    if not start_col then
      return nil
    end

    index = end_col + 1
    return text:sub(start_col, end_col), start_col - 1, end_col
  end
end

-- Byte range of the character covering display column target (0-based).
local function char_at_display_col(text, target)
  local acc = 0
  local last_s, last_e = nil, nil

  for ch, byte_s, byte_e in iter_chars_with_bytes(text) do
    last_s, last_e = byte_s, byte_e
    acc = acc + vim.api.nvim_strwidth(ch)
    if acc > target then
      return byte_s, byte_e
    end
  end

  return last_s, last_e
end

-- Map the real cursor (source row/byte col) to the rendered position:
-- which line of the group (wrapped rows push content down) and which byte
-- range inside that rendered line.
local function cursor_target(bufnr, row, col, entry)
  local group = entry.group
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""

  if group.cells then
    local nav = require("markdown-table-wrap.nav")
    local spans = nav.spans(line)
    local cell_index = nav.cell_index(spans, col)
    local span = cell_index and spans[cell_index] or nil
    local wrapped = span and group.cells[cell_index] or nil

    if wrapped then
      -- Cursor offset inside the source cell -> display-char index, mapped
      -- through the full-cell inline parse so concealed delimiters like **
      -- don't drift the position.
      local raw_cell = line:sub(span.start_col + 1, span.end_col)
      local offset = math.min(math.max(col - span.start_col, 0), #raw_cell)

      -- The renderer sees escaped pipes unescaped (split_pipe_row applies
      -- gsub("\\|", "|")); normalize the same way, shifting the offset by
      -- the number of dropped backslashes before the cursor.
      local _, escaped_before = raw_cell:sub(1, offset):gsub("\\|", "|")
      local normalized = raw_cell:gsub("\\|", "|")

      local md = require("markdown-table-wrap.markdown")
      local t = md.source_to_display(normalized, offset - escaped_before, entry.config)

      local k = #wrapped
      for index, cell_line in ipairs(wrapped) do
        if t < (cell_line.char_end or 0) then
          k = index
          break
        end
      end

      local cell_line = wrapped[k]
      local nchars = vim.fn.strchars(cell_line.text)
      local within = math.min(math.max(t - (cell_line.char_start or 0), 0), nchars)
      local byte_s = #vim.fn.strcharpart(cell_line.text, 0, within)
      -- within == nchars: cursor sits on the padding space after the text
      -- (the rendered line always has at least one space before the border).
      local byte_e = within < nchars and (byte_s + #vim.fn.strcharpart(cell_line.text, within, 1)) or (byte_s + 1)

      local layout = group.lines[k] and group.lines[k].cells and group.lines[k].cells[cell_index] or nil
      if layout then
        return { line = k, start_col = layout.byte_start + byte_s, end_col = layout.byte_start + byte_e }
      end
    end
  end

  -- Separator line (or fallback): map by display column onto the first
  -- rendered line, clamped to the table width.
  local first_text = type(group.lines[1]) == "table" and group.lines[1].text or group.lines[1]
  local target = vim.api.nvim_strwidth(line:sub(1, col))
  local byte_s, byte_e = char_at_display_col(first_text, target)
  if byte_s then
    return { line = 1, start_col = byte_s, end_col = byte_e }
  end

  return nil
end

-- The real cursor sits on the concealed source line, so its screen position
-- never matches the rendered table. While the virtual cursor is shown in
-- normal mode, hide the real one by blending it away (same guicursor trick
-- noice.nvim uses); restore it the moment the cursor leaves the table or the
-- mode changes.
local real_cursor_hidden = false
local saved_guicursor = nil

local function hide_real_cursor()
  if real_cursor_hidden then
    return
  end

  real_cursor_hidden = true
  vim.api.nvim_set_hl(0, "MarkdownTableWrapHiddenCursor", { blend = 100, nocombine = true })
  saved_guicursor = vim.o.guicursor
  local sep = saved_guicursor ~= "" and "," or ""
  vim.o.guicursor = saved_guicursor .. sep .. "a:MarkdownTableWrapHiddenCursor/MarkdownTableWrapHiddenCursor"
end

local function show_real_cursor()
  if not real_cursor_hidden then
    return
  end

  real_cursor_hidden = false
  if saved_guicursor ~= nil then
    vim.o.guicursor = saved_guicursor
    saved_guicursor = nil
  end
end

-- Update the virtual cursor after real cursor movement. Cheap: re-renders at
-- most two source rows (the one left and the one entered).
function M.update_cursor(bufnr)
  bufnr = normalize_bufnr(bufnr)
  local rows = aligned_rows[bufnr]
  if not rows or vim.api.nvim_get_current_buf() ~= bufnr then
    show_real_cursor()
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local entry = rows[row]
  local target = entry and cursor_target(bufnr, row, cursor[2], entry) or nil
  local key = target and string.format("%d:%d:%d:%d", row, target.line, target.start_col, target.end_col) or nil

  local config = entry and entry.config or {}
  local mode = vim.api.nvim_get_mode().mode
  if target and mode:match("^n") and config.inline_hide_cursor ~= false then
    hide_real_cursor()
  else
    show_real_cursor()
  end

  local previous = cursor_rows[bufnr]
  if previous and previous.key == key then
    return
  end

  if previous and previous.row ~= row and rows[previous.row] then
    set_aligned_row_marks(bufnr, previous.row, rows[previous.row], nil)
  end

  if entry then
    set_aligned_row_marks(bufnr, row, entry, target)
  end

  cursor_rows[bufnr] = key and { row = row, key = key } or nil
end

-- Row-anchored replace mode: each source line shows the first visible line of
-- its own rendered row, and that row's extra lines (wrapped continuations,
-- separators, borders) hang below it as virtual lines. This keeps the cursor
-- line and the rendered row visually in sync while editing.
local function show_replace_aligned(bufnr, table_info, config, rendered)
  set_render_for_buffer(bufnr, config)

  local start_row = table_info.start_lnum - 1
  local overlay_width = rendered.width
  if config.overlay_fill then
    overlay_width = vim.api.nvim_win_get_width(0)
  end
  local priority = config.overlay_priority or 10000
  local line_index = 0 -- running index over the flattened rendered lines

  aligned_rows[bufnr] = aligned_rows[bufnr] or {}

  for source_offset, group in ipairs(rendered.groups) do
    local row = start_row + source_offset - 1
    conceal_source_line(bufnr, row)

    local leading_indexes = {}
    for _ in ipairs(group.leading or {}) do
      line_index = line_index + 1
      table.insert(leading_indexes, line_index)
    end

    local line_indexes = {}
    for _ in ipairs(group.lines) do
      line_index = line_index + 1
      table.insert(line_indexes, line_index)
    end

    local entry = {
      group = group,
      config = config,
      overlay_width = overlay_width,
      priority = priority,
      leading_indexes = leading_indexes,
      line_indexes = line_indexes,
    }

    aligned_rows[bufnr][row] = entry
    set_aligned_row_marks(bufnr, row, entry, nil)
  end
end

local function show_replace(bufnr, table_info, config, rendered)
  local source_count = table_info.end_lnum - table_info.start_lnum + 1
  if rendered.groups and #rendered.groups == source_count and not config.inline_viewport_scrolling then
    return show_replace_aligned(bufnr, table_info, config, rendered)
  end

  set_render_for_buffer(bufnr, config)

  local source_count = table_info.end_lnum - table_info.start_lnum + 1
  local rendered_count = #rendered.lines
  local first_rendered = view_offset(bufnr, table_info, source_count, rendered_count, config)
  local overlay_count = math.min(source_count, rendered_count - first_rendered)
  local start_row = table_info.start_lnum - 1
  local overlay_width = rendered.width
  if config.overlay_fill then
    overlay_width = vim.api.nvim_win_get_width(0)
  end
  local priority = config.overlay_priority or 10000

  for source_offset = 0, source_count - 1 do
    conceal_source_line(bufnr, start_row + source_offset)
  end

  for source_offset = 0, overlay_count - 1 do
    local line_obj = (rendered.line_objects or rendered.lines)[first_rendered + source_offset + 1]
    local mark = {
      virt_text = padded_chunks(line_obj, first_rendered + source_offset + 1, overlay_width),
      hl_mode = "replace",
      right_gravity = false,
      priority = priority,
    }

    if config.inline_virtual_text == "win_col" then
      mark.virt_text_win_col = 0
    else
      mark.virt_text_pos = "overlay"
    end

    vim.api.nvim_buf_set_extmark(bufnr, namespace, start_row + source_offset, 0, mark)
  end

  if rendered_count > overlay_count and not config.inline_viewport_scrolling then
    local extra = {}
    for index = overlay_count + 1, rendered_count do
      table.insert(extra, (rendered.line_objects or rendered.lines)[index])
    end

    vim.api.nvim_buf_set_extmark(bufnr, namespace, table_info.end_lnum - 1, 0, {
      virt_lines = virt_lines(extra, overlay_count + 1),
      virt_lines_above = false,
      right_gravity = false,
      priority = priority,
    })
  end
end

local function show_insert(bufnr, table_info, config, rendered)
  local target_line = math.max(table_info.start_lnum - 1, 0)
  local above = config.inline_position ~= "below"

  vim.api.nvim_buf_set_extmark(bufnr, namespace, target_line, 0, {
    virt_lines = virt_lines(rendered.lines),
    virt_lines_above = above,
    right_gravity = false,
    priority = 200,
  })

  if config.dim_source ~= false then
    for line = table_info.start_lnum - 1, table_info.end_lnum - 1 do
      vim.api.nvim_buf_set_extmark(bufnr, namespace, line, 0, {
        line_hl_group = "MarkdownTableWrapSource",
        priority = 100,
      })
    end
  end
end

function M.clear(bufnr)
  bufnr = normalize_bufnr(bufnr)

  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
  end

  active_buffers[bufnr] = nil
  active_tables[bufnr] = nil
  active_configs[bufnr] = nil
  aligned_rows[bufnr] = nil
  cursor_rows[bufnr] = nil
  if vim.api.nvim_get_current_buf() == bufnr then
    show_real_cursor()
  end
  restore_render_for_buffer(bufnr)
end

function M.reset_view(bufnr)
  bufnr = normalize_bufnr(bufnr)
  view_offsets[bufnr] = nil
end

function M.is_active(bufnr)
  bufnr = normalize_bufnr(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  local marks = vim.api.nvim_buf_get_extmarks(bufnr, namespace, 0, -1, {})
  return #marks > 0
end

local function show_one(bufnr, table_info, config)
  local rendered = render.render_table(table_info, config)

  if config.inline_mode == "insert" then
    show_insert(bufnr, table_info, config, rendered)
  else
    show_replace(bufnr, table_info, config, rendered)
  end

  return rendered
end

function M.show(bufnr, table_info, config)
  ensure_highlights(config)
  M.clear(bufnr)

  local rendered = show_one(bufnr, table_info, config)
  active_buffers[bufnr] = true
  active_tables[bufnr] = { table_info }
  active_configs[bufnr] = config
  M.update_cursor(bufnr)
  return rendered
end

function M.show_many(bufnr, tables, config)
  ensure_highlights(config)
  M.clear(bufnr)

  local rendered = {}
  for _, table_info in ipairs(tables) do
    table.insert(rendered, show_one(bufnr, table_info, config))
  end

  active_buffers[bufnr] = #tables > 0
  active_tables[bufnr] = tables
  active_configs[bufnr] = config
  M.update_cursor(bufnr)
  return rendered
end

local function table_under_cursor(bufnr, tables)
  local cursor_lnum = vim.api.nvim_win_get_cursor(0)[1]
  for _, table_info in ipairs(tables) do
    if cursor_lnum >= table_info.start_lnum and cursor_lnum <= table_info.end_lnum then
      return table_info
    end
  end
  return nil
end

local function max_view_offset(table_info, config)
  local rendered = render.render_table(table_info, config)
  local source_count = table_info.end_lnum - table_info.start_lnum + 1
  return math.max(0, #rendered.lines - source_count)
end

function M.scroll(bufnr, delta)
  bufnr = normalize_bufnr(bufnr)
  local tables = active_tables[bufnr]
  local config = active_configs[bufnr]
  if not tables or not config or not config.inline_viewport_scrolling then
    return false
  end

  local target = table_under_cursor(bufnr, tables)
  if not target then
    return false
  end

  local max_offset = max_view_offset(target, config)
  if max_offset == 0 then
    return false
  end

  view_offsets[bufnr] = view_offsets[bufnr] or {}
  local key = table_key(target)
  local current = view_offsets[bufnr][key] or 0
  local next_offset = math.max(0, math.min(current + delta, max_offset))
  if next_offset == current then
    return true
  end

  view_offsets[bufnr][key] = next_offset
  M.show_many(bufnr, tables, config)
  return true
end

function M.scroll_to(bufnr, position)
  bufnr = normalize_bufnr(bufnr)
  local tables = active_tables[bufnr]
  local config = active_configs[bufnr]
  if not tables or not config or not config.inline_viewport_scrolling then
    return false
  end

  local target = table_under_cursor(bufnr, tables)
  if not target then
    return false
  end

  local max_offset = max_view_offset(target, config)
  view_offsets[bufnr] = view_offsets[bufnr] or {}
  view_offsets[bufnr][table_key(target)] = position == "bottom" and max_offset or 0
  M.show_many(bufnr, tables, config)
  return true
end

function M.attach_window(bufnr)
  bufnr = normalize_bufnr(bufnr)
  if active_buffers[bufnr] then
    set_render_for_buffer(bufnr, active_configs[bufnr] or {})
  end
end

function M.namespace()
  return namespace
end

return M
