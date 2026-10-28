local render = require("markdown-table-wrap.render")

local M = {}

local namespace = vim.api.nvim_create_namespace("markdown-table-wrap")
-- saved_conceallevels[winid][bufnr]: the window's local conceallevel on the
-- buffer when the rendering started or raised it.
local saved_conceallevels = {}
-- Not active_buffers: a keep_window clear empties that while the windows keep
-- the raised conceallevel, which a later clear still has to hand back.
local raised_buffers = {}
local active_buffers = {}
local active_configs = {}
-- Buffers currently rendered by the row-anchored replace mode (see the block
-- comment above show_replace_aligned). Declared here because the window
-- option handling below has to know about it.
local aligned_tables = {}
-- renderings[bufnr]: { tick = the changedtick the rendering was made at,
-- tables = every table it rendered, in source order, groups = in replace mode
-- the runs of all those tables, each with the runs currently laid out from its
-- tables not shown raw }. See M.show_raw.
local renderings = {}

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

local function semantic_chunks(line, line_index, is_header)
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
      elseif is_header or line_index == 2 then
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
  local is_header = type(line_obj) == "table" and line_obj.is_header == true
  if type(line_obj) ~= "table" or not line_obj.chunks or #line_obj.chunks == 0 then
    return semantic_chunks(type(line_obj) == "table" and line_obj.text or line_obj, line_index, is_header)
  end

  local result = {}
  local cursor = 0
  local sorted = vim.deepcopy(line_obj.chunks)
  table.sort(sorted, function(a, b)
    return a.start_col < b.start_col
  end)

  for _, styled in ipairs(sorted) do
    if cursor < styled.start_col then
      vim.list_extend(result, semantic_chunks(line_obj.text:sub(cursor + 1, styled.start_col), line_index, is_header))
    end

    table.insert(result, {
      line_obj.text:sub(styled.start_col + 1, styled.end_col),
      styled.hl_group,
    })
    cursor = styled.end_col
  end

  if cursor < #line_obj.text then
    vim.list_extend(result, semantic_chunks(line_obj.text:sub(cursor + 1), line_index, is_header))
  end

  return result
end

-- Rendered lines of a quoted table carry the blockquote marker themselves:
-- the parser strips it from the source, and the source lines are hidden.
local function quoted(chunks, quote)
  if quote then
    table.insert(chunks, 1, { quote.text, quote.hl_group })
  end
  return chunks
end

local function virt_lines(lines, quote)
  local result = {}

  for index, line in ipairs(lines) do
    table.insert(result, quoted(chunks_from_line_object(line, index), quote))
  end

  return result
end

local function ensure_highlights(config)
  require("markdown-table-wrap.theme").apply(config)
end

local function window_conceallevel(winid, scope)
  return vim.api.nvim_get_option_value("conceallevel", { scope = scope, win = winid })
end

-- Never through vim.wo, which sets the window's global value as well: every
-- other buffer later shown in the window, and every window opened from it,
-- would start at the raised level.
local function set_window_conceallevel(winid, level)
  vim.api.nvim_set_option_value("conceallevel", level, { scope = "local", win = winid })
end

-- starting: the rendering starts, right after a clear handed every window its
-- level back, so the local level is the user's own and is saved even at 2 or
-- above. Not on a later attach, where a local 2 is the raised one. Not only
-- where it differs from the global value: a :setglobal during the rendering
-- leaves the local level alone in Neovim too.
local function set_render_window(winid, bufnr, starting)
  winid = winid or vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(winid) then
    return
  end

  local level = window_conceallevel(winid, "local")
  if level < 2 or starting then
    saved_conceallevels[winid] = saved_conceallevels[winid] or {}
    saved_conceallevels[winid][bufnr] = level
  end
  if level < 2 then
    set_window_conceallevel(winid, 2)
  end

  -- 'concealcursor' is left untouched: the cursor line keeps unconcealing
  -- itself, which is exactly how the revealed raw source row under the cursor
  -- works (and it keeps markdown delimiters visible while editing instead of
  -- flickering on mode changes). 'wrap' is left untouched too: the revealed
  -- row has to soft-wrap like any other line.
end

local function set_render_for_buffer(bufnr, starting)
  if starting then
    raised_buffers[bufnr] = true
    vim.b[bufnr].markdown_table_wrap_rendered = true
  end
  for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
    set_render_window(winid, bufnr, starting)
  end
end

local function restore_render_window(winid, bufnr)
  local saved = saved_conceallevels[winid]
  local level = saved and saved[bufnr]
  if saved then
    saved[bufnr] = nil
  end
  -- Not any other level, which was set after the raise and is the user's. Not
  -- a level from before the rendering for a window without a saved one: a
  -- split or a float copied the raised level and never had one of its own.
  if vim.api.nvim_win_is_valid(winid) and window_conceallevel(winid, "local") == 2 then
    set_window_conceallevel(winid, level or window_conceallevel(winid, "global"))
  end
end

local function restore_render_for_buffer(bufnr)
  for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
    restore_render_window(winid, bufnr)
  end
end

-- Row-anchored replace mode, built on conceal_lines (nvim 0.11+).
--
-- Inline conceal cannot be used for table source lines: with 'wrap' on, a
-- concealed line still occupies all of its soft-wrap screen rows, which
-- showed up as mysterious blank lines under rendered rows. Instead every
-- table source line is hidden entirely with conceal_lines (zero screen
-- rows), and the rendered table hangs as virtual-line blocks:
--
--   - cursor inside the table: Neovim auto-reveals the raw cursor line (it
--     soft-wraps naturally and carries the real cursor); the rendered rows
--     above it are attached to it as virt_lines_above, the rows below as
--     virt_lines below. The cursor row's own rendered lines are not drawn.
--   - cursor outside the table: the whole rendered table is attached above
--     the first line after the table (or below the line before it when the
--     table ends the buffer).
--
-- virt_lines attached to a conceal_lines-hidden line are not displayed, so
-- the blocks always anchor to a visible line.
--
-- Tables with no line between them (possible across a change of quote depth)
-- are laid out together as one run, as if they were one table. Anchored one
-- by one, a table's outside anchor would be a hidden row of its neighbour,
-- and two tables' blocks hanging on one row would be stacked in mark-tree
-- order, which follows neither creation order nor priority.
--
-- The per-buffer state lives in `aligned_tables`, declared at the top of this
-- file: the runs of the buffer in source order.

-- A window currently showing bufnr (preferring the current window), or nil.
local function find_window(bufnr)
  local winid = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(winid) ~= bufnr then
    winid = vim.fn.win_findbuf(bufnr)[1]
  end
  return winid
end

-- Describes the number column of winid, or nil when no number column is
-- displayed. Virtual lines cannot receive native line numbers, so the
-- column is drawn into the lines themselves via virt_lines_leftcol.
local function number_column(winid, entry)
  if not entry.show_numbers or not winid then
    return nil
  end

  if not (vim.wo[winid].number or vim.wo[winid].relativenumber) then
    return nil
  end

  local textoff = vim.fn.getwininfo(winid)[1].textoff
  if textoff <= 1 then
    return nil
  end

  return {
    textoff = textoff,
    relative = vim.wo[winid].relativenumber,
    cursor_row = vim.api.nvim_win_get_cursor(winid)[1] - 1,
  }
end

-- Number of blank virtual lines drawn directly under the revealed cursor
-- row so that every other rendered line keeps its exact screen row while
-- the cursor moves between table rows. Revealing row i swaps that row's
-- rendered lines (group_lines[i]) for the raw source line's soft-wrapped
-- height; the filler tops the swap region up to a constant
--   E = max over rows of (estimated raw height - group lines)
-- extra rows (filler_i = E - (raw height_i - group_lines_i)), which makes
-- the position of everything after the revealed row invariant across moves
-- and pins the total table height to #flat + E.
local function stable_filler(winid, entry, split)
  if not entry.stable_height or not winid or not split then
    return 0
  end

  local info = vim.fn.getwininfo(winid)[1]
  local usable = math.max(1, info.width - info.textoff)

  local function estimate(index)
    return math.max(1, math.ceil(math.max(entry.row_widths[index] or 1, 1) / usable))
  end

  local extra = 0
  for index = 1, #entry.row_widths do
    extra = math.max(extra, estimate(index) - entry.group_lines[index])
  end
  extra = math.max(0, extra)

  -- The revealed row is on screen (the cursor is on it), so its real
  -- soft-wrapped height is measurable; fall back to the estimate. `all`
  -- includes virtual lines attached to the row, `fill` is their count, so
  -- the raw text height is the difference.
  local height
  local row = entry.start_row + split - 1
  local ok, measured = pcall(vim.api.nvim_win_text_height, winid, { start_row = row, end_row = row })
  if ok and measured.all and measured.all - (measured.fill or 0) > 0 then
    height = measured.all - (measured.fill or 0)
  else
    height = estimate(split)
  end

  return math.max(0, extra - (height - entry.group_lines[split]))
end

-- The rendered lines of one table, carrying the number column described by
-- column (see number_column) unless it is nil.
local function numbered_lines(entry, column)
  -- The first rendered line of each source row carries that row's line
  -- number, right-aligned like the native column; continuation and border
  -- lines get a blank column. With 'relativenumber' the distance to the
  -- cursor row is shown instead (the cursor row itself is always revealed
  -- natively, so no rendered line ever needs the hybrid absolute number).
  --
  -- The prefixed lines are cached on the entry; re-attaching (which happens
  -- per cursor line move under 'relativenumber') only rewrites the number
  -- text in place instead of rebuilding every chunk list.
  if not column then
    entry.numbered = nil
  else
    if not entry.numbered or entry.numbered_textoff ~= column.textoff then
      entry.numbered = {}
      entry.numbered_textoff = column.textoff
      local blank = string.rep(" ", column.textoff)
      for index, chunks in ipairs(entry.flat) do
        entry.numbered[index] = vim.list_extend({ { blank, "LineNr" } }, chunks)
      end
    end

    for index, lnum in pairs(entry.flat_lnums) do
      if lnum then
        local display = column.relative and math.abs(lnum - 1 - column.cursor_row) or lnum
        entry.numbered[index][1][1] = string.format("%" .. (column.textoff - 1) .. "d ", display)
      end
    end
  end

  return entry.numbered or entry.flat
end

local function delete_run_blocks(bufnr, run)
  for _, key in ipairs({ "above_id", "below_id" }) do
    if run[key] then
      vim.api.nvim_buf_del_extmark(bufnr, namespace, run[key])
      run[key] = nil
    end
  end
end

-- (Re-)attach the rendered virtual-line blocks of one run of tables. entry is
-- the table holding the cursor row and split the row's 1-based group index in
-- it, or both are nil when the cursor is outside the run.
local function set_run_blocks(bufnr, run, entry, split)
  delete_run_blocks(bufnr, run)

  local first, last = run.tables[1], run.tables[#run.tables]
  local winid = find_window(bufnr)
  local column = number_column(winid, first)
  run.numbers_relative = column ~= nil and column.relative or false
  run.number_cursor_row = column and column.cursor_row or nil

  -- A run spanning the entire buffer has no visible line outside itself to
  -- anchor to; the cursor is then necessarily inside it, so fall back to
  -- splitting at the first row.
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local has_outside_anchor = last.end_row + 1 < line_count or first.start_row > 0
  if not entry and not has_outside_anchor then
    entry, split = first, 1
  end

  local source, offset = {}, 0
  for _, member in ipairs(run.tables) do
    if member == entry then
      offset = #source
    end
    vim.list_extend(source, numbered_lines(member, column))
  end

  local function attach(row, from, to, above, filler)
    local lines = {}
    -- The filler leads the block: it sits directly under the revealed raw
    -- line, so the rendered lines that follow stay on fixed screen rows. It
    -- keeps the number column and the blockquote marker so neither breaks up.
    for _ = 1, filler or 0 do
      local blank = {}
      if column then
        table.insert(blank, { string.rep(" ", column.textoff), "LineNr" })
      end
      if entry.quote then
        table.insert(blank, { entry.quote.text, entry.quote.hl_group })
      end
      table.insert(lines, blank)
    end

    for index = math.max(from, 1), math.min(to, #source) do
      table.insert(lines, source[index])
    end

    if #lines == 0 then
      return nil
    end
    return vim.api.nvim_buf_set_extmark(bufnr, namespace, row, 0, {
      virt_lines = lines,
      virt_lines_above = above,
      virt_lines_leftcol = column ~= nil,
      right_gravity = false,
      priority = first.priority,
    })
  end

  if entry then
    local info = entry.group_index[split]
    local row = entry.start_row + split - 1
    run.above_id = attach(row, 1, offset + info.content_start - 1, true)
    run.below_id = attach(row, offset + info.content_last + 1, #source, false, stable_filler(winid, entry, split))
  elseif last.end_row + 1 < line_count then
    run.above_id = attach(last.end_row + 1, 1, #source, true)
  else
    run.below_id = attach(first.start_row - 1, 1, #source, false)
  end

  run.entry, run.split = entry, split
end

-- The table of run holding row and the row's 1-based group index in it, or
-- nil when row is outside the run.
local function find_split(run, row)
  for _, member in ipairs(run.tables) do
    if row >= member.start_row and row <= member.end_row then
      return member, row - member.start_row + 1
    end
  end
end

-- Brings the cursor back on screen after Neovim normalized a view whose
-- topline was concealed again. A plain view assignment: normal-mode scroll
-- commands are unusable here (they clamp or drag the off-screen cursor back
-- into the table). topline = cursor line yields a stable view with a few rows
-- of the table's tail auto-filled above the cursor.
local function repair_view(bufnr)
  vim.schedule(function()
    if vim.api.nvim_get_current_buf() ~= bufnr then
      return
    end

    if vim.fn.winline() > vim.api.nvim_win_get_height(0) then
      vim.fn.winrestview({ topline = vim.api.nvim_win_get_cursor(0)[1] })
    end
  end)
end

-- Re-split the virtual-line blocks around the cursor row. Neovim itself
-- reveals the raw source line under the cursor (conceal_lines is inactive on
-- the cursor line), so no per-row extmark juggling is needed here.
function M.update_reveal(bufnr)
  bufnr = normalize_bufnr(bufnr)
  local runs = aligned_tables[bufnr]
  if not runs or vim.api.nvim_get_current_buf() ~= bufnr then
    return
  end

  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local top = vim.fn.line("w0") - 1
  local bot = vim.fn.line("w$") - 1

  for _, run in ipairs(runs) do
    local entry, split = find_split(run, row)
    local first, last = run.tables[1], run.tables[#run.tables]

    -- Relative line numbers are measured from the cursor row, so the blocks
    -- also go stale whenever the cursor changes lines. Refreshing them only
    -- matters while some part of the run can be on screen: an off-screen
    -- run stays stale (number_cursor_row keeps the old row) and catches
    -- up here as soon as it scrolls back into view.
    local numbers_stale = run.numbers_relative and run.number_cursor_row ~= row
    local visible = last.end_row + 1 >= top - 1 and first.start_row - 1 <= bot + 1

    local split_changed = run.entry ~= entry or run.split ~= split

    if split_changed or (numbers_stale and visible) then
      set_run_blocks(bufnr, run, entry, split)
    end

    if split == 1 and entry.start_row == 0 then
      -- Neovim never draws virt_lines above the first buffer line on its
      -- own; they only appear as topfill rows when scrolled into view. With
      -- the cursor on line 1 the topline is pinned there, so the block
      -- above the revealed row (the table's top border) would silently
      -- vanish. Force the fill so it stays visible.
      local fill = entry.group_index[1].content_start - 1
      if fill > 0 and vim.fn.winsaveview().topfill < fill then
        vim.fn.winrestview({ topline = 1, topfill = fill })
      end
    end

    if not split and split_changed then
      -- While the cursor is inside the table the topline usually sits on
      -- the revealed source row (scrolled topfill rows into the virtual
      -- block above it). The moment the cursor leaves, that row is
      -- concealed again, the topline becomes invalid, and Neovim normalizes
      -- the view upward: the viewport visibly jumped above the table and
      -- the cursor sat off-screen for several hundred ms.
      repair_view(bufnr)
    end
  end
end

local conceal_row = { conceal_lines = "", right_gravity = false }

-- Row-anchored replace mode: each source line corresponds to its rendered
-- row; the line under the cursor shows (and edits) as plain soft-wrapped
-- markdown while every other row appears only in its rendered form.
local function show_replace_aligned(bufnr, table_info, config, rendered)
  local start_row = table_info.start_lnum - 1
  local end_row = table_info.end_lnum - 1
  local priority = config.overlay_priority or 10000

  -- Flatten the rendered lines, remembering where each group's content
  -- starts/ends so the blocks can be split around any source row. A group's
  -- leading border belongs to the block above its row and its trailing
  -- separators to the block below it. flat_lnums maps each
  -- flat line to its source line number (first content line of a group) or
  -- false (border/continuation lines).
  local flat = {}
  local flat_lnums = {}
  local group_index = {}
  local line_index = 0

  for group_number, group in ipairs(rendered.groups) do
    for _, line_obj in ipairs(group.leading or {}) do
      line_index = line_index + 1
      table.insert(flat, quoted(chunks_from_line_object(line_obj, line_index), rendered.quote))
      table.insert(flat_lnums, false)
    end

    local content_start = #flat + 1
    for offset, line_obj in ipairs(group.lines) do
      line_index = line_index + 1
      table.insert(flat, quoted(chunks_from_line_object(line_obj, line_index), rendered.quote))
      table.insert(flat_lnums, offset == 1 and (start_row + group_number) or false)
    end
    local content_last = #flat

    -- Trailing separators stay visible while this row is revealed, so they
    -- belong to the below block, not the hidden content range.
    for _, line_obj in ipairs(group.trailing or {}) do
      line_index = line_index + 1
      table.insert(flat, quoted(chunks_from_line_object(line_obj, line_index), rendered.quote))
      table.insert(flat_lnums, false)
    end

    table.insert(group_index, { content_start = content_start, content_last = content_last })
  end

  -- Per-row data for the stable-height filler: display width of each raw
  -- source line and the number of rendered content lines its group hides
  -- while revealed.
  local row_widths = {}
  local group_lines = {}
  local source_lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)
  for index, info in ipairs(group_index) do
    row_widths[index] = vim.fn.strdisplaywidth(source_lines[index] or "")
    group_lines[index] = info.content_last - info.content_start + 1
  end

  local marks = {}
  for row = start_row, end_row do
    table.insert(marks, { row, conceal_row })
  end

  local entry = {
    start_row = start_row,
    end_row = end_row,
    marks = marks,
    flat = flat,
    flat_lnums = flat_lnums,
    group_index = group_index,
    priority = priority,
    show_numbers = config.inline_line_numbers ~= false,
    stable_height = config.inline_stable_height ~= false,
    quote = rendered.quote,
    row_widths = row_widths,
    group_lines = group_lines,
  }

  return entry
end

-- Sets the marks of one table's entry outside its run's blocks, unless they
-- are set already.
local function draw_marks(bufnr, entry)
  if entry.ids then
    return
  end
  entry.ids = {}
  for _, mark in ipairs(entry.marks) do
    table.insert(entry.ids, vim.api.nvim_buf_set_extmark(bufnr, namespace, mark[1], 0, mark[2]))
  end
end

local function undraw_marks(bufnr, entry)
  for _, id in ipairs(entry.ids or {}) do
    vim.api.nvim_buf_del_extmark(bufnr, namespace, id)
  end
  entry.ids = nil
end

-- Groups the tables of bufnr shown in replace mode (entries, in source order)
-- into runs, hides their source rows and hangs each run's blocks, split around
-- row if given; returns the runs. Not done per table as it is shown: a run
-- would then be laid out again for every table that joins it.
local function lay_out_runs(bufnr, entries, row)
  local runs = {}
  for _, entry in ipairs(entries) do
    local run = runs[#runs]
    if not run or run.tables[#run.tables].end_row + 1 ~= entry.start_row then
      run = { tables = {} }
      table.insert(runs, run)
    end
    table.insert(run.tables, entry)
  end

  for _, run in ipairs(runs) do
    for _, entry in ipairs(run.tables) do
      draw_marks(bufnr, entry)
    end
    if row then
      set_run_blocks(bufnr, run, find_split(run, row))
    else
      set_run_blocks(bufnr, run, nil, nil)
    end
  end
  return runs
end

-- Keeps the tables of bufnr's new rendering (entries, in source order) for
-- M.show_raw and, in replace mode, lays out their runs.
local function keep_rendering(bufnr, entries, config)
  local rendering = { tick = vim.api.nvim_buf_get_changedtick(bufnr), tables = entries }
  if config.inline_mode ~= "insert" and #entries > 0 then
    local runs = lay_out_runs(bufnr, entries)
    aligned_tables[bufnr] = runs
    rendering.groups = {}
    for _, run in ipairs(runs) do
      table.insert(rendering.groups, { tables = run.tables, runs = { run } })
    end
  end
  renderings[bufnr] = rendering
end

local function show_replace(bufnr, table_info, config, rendered)
  local source_count = table_info.end_lnum - table_info.start_lnum + 1
  if #rendered.groups ~= source_count then
    error(
      string.format(
        "MarkdownTableWrap: table at lines %d-%d rendered %d row groups for %d source lines;"
          .. " inline replace needs exactly one per source line",
        table_info.start_lnum,
        table_info.end_lnum,
        #rendered.groups,
        source_count
      )
    )
  end

  return show_replace_aligned(bufnr, table_info, config, rendered)
end

local function show_insert(bufnr, table_info, config, rendered)
  local above = config.inline_position ~= "below"
  local target_line = above and math.max(table_info.start_lnum - 1, 0) or table_info.end_lnum - 1

  local marks = {
    {
      target_line,
      {
        virt_lines = virt_lines(rendered.line_objects or rendered.lines, rendered.quote),
        virt_lines_above = above,
        right_gravity = false,
        priority = 200,
      },
    },
  }

  if config.dim_source ~= false then
    local dim = { line_hl_group = "MarkdownTableWrapSource", priority = 100 }
    for line = table_info.start_lnum - 1, table_info.end_lnum - 1 do
      table.insert(marks, { line, dim })
    end
  end

  local entry = { start_row = table_info.start_lnum - 1, end_row = table_info.end_lnum - 1, marks = marks }
  draw_marks(bufnr, entry)
  return entry
end

-- opts.keep_window: skip restoring window options (conceallevel). Used for
-- transient clears (visual mode) so the buffer-wide conceal appearance does
-- not flicker between conceallevel values.
function M.clear(bufnr, opts)
  bufnr = normalize_bufnr(bufnr)
  opts = opts or {}

  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
  end

  active_buffers[bufnr] = nil
  active_configs[bufnr] = nil
  aligned_tables[bufnr] = nil
  renderings[bufnr] = nil
  if not opts.keep_window then
    if raised_buffers[bufnr] then
      restore_render_for_buffer(bufnr)
    end
    raised_buffers[bufnr] = nil
  end
end

function M.detach_window(winid)
  winid = winid or vim.api.nvim_get_current_win()
  if vim.api.nvim_win_is_valid(winid) then
    local bufnr = vim.api.nvim_win_get_buf(winid)
    if raised_buffers[bufnr] then
      restore_render_window(winid, bufnr)
    end
  end
  saved_conceallevels[winid] = nil
end

function M.dispose(bufnr)
  bufnr = normalize_bufnr(bufnr)
  M.clear(bufnr)
end

function M.is_active(bufnr)
  bufnr = normalize_bufnr(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  local marks = vim.api.nvim_buf_get_extmarks(bufnr, namespace, 0, -1, {})
  return #marks > 0
end

-- Returns the rendering and the table's entry for keep_rendering.
local function show_one(bufnr, table_info, config)
  local rendered = render.render_table(table_info, config)

  if config.inline_mode == "insert" then
    return rendered, show_insert(bufnr, table_info, config, rendered)
  end

  return rendered, show_replace(bufnr, table_info, config, rendered)
end

function M.show(bufnr, table_info, config)
  ensure_highlights(config)
  M.clear(bufnr)

  local rendered, entry = show_one(bufnr, table_info, config)
  keep_rendering(bufnr, { entry }, config)
  active_buffers[bufnr] = true
  active_configs[bufnr] = config
  if config.inline_mode == "replace" then
    set_render_for_buffer(bufnr, true)
  end
  M.update_reveal(bufnr)
  return rendered
end

function M.show_many(bufnr, tables, config)
  ensure_highlights(config)
  M.clear(bufnr)

  local rendered, entries = {}, {}
  for _, table_info in ipairs(tables) do
    local table_rendered, entry = show_one(bufnr, table_info, config)
    table.insert(rendered, table_rendered)
    table.insert(entries, entry)
  end
  keep_rendering(bufnr, entries, config)

  active_buffers[bufnr] = #tables > 0
  active_configs[bufnr] = config
  if config.inline_mode == "replace" then
    set_render_for_buffer(bufnr, true)
  end
  M.update_reveal(bufnr)
  return rendered
end

-- Shows raw every table of bufnr's rendering whose rows overlap first_row to
-- last_row (0-based) and every other table rendered; with no rows given, every
-- table rendered. Returns false, changing nothing, when there is no rendering
-- or the buffer has changed since it was made: its recorded rows are then no
-- longer where its marks are.
function M.show_raw(bufnr, first_row, last_row)
  bufnr = normalize_bufnr(bufnr)
  local rendering = renderings[bufnr]
  if not rendering or rendering.tick ~= vim.api.nvim_buf_get_changedtick(bufnr) then
    return false
  end

  local function raw(entry)
    return first_row ~= nil and entry.end_row >= first_row and entry.start_row <= last_row
  end

  if not rendering.groups then
    for _, entry in ipairs(rendering.tables) do
      if raw(entry) then
        undraw_marks(bufnr, entry)
      else
        draw_marks(bufnr, entry)
      end
    end
    return true
  end

  -- Not every run laid out again: a small table selected next to a long one
  -- would cost as much as rendering the long one. Not laid out unsplit for
  -- update_reveal to split around the cursor: a long table restored under
  -- the cursor would be laid out twice.
  local row = vim.api.nvim_get_current_buf() == bufnr and vim.api.nvim_win_get_cursor(0)[1] - 1 or nil
  local changed, runs = false, {}
  for _, group in ipairs(rendering.groups) do
    local stale = false
    for _, entry in ipairs(group.tables) do
      stale = stale or raw(entry) == (entry.ids ~= nil)
    end

    if stale then
      changed = true
      local shown = {}
      for _, run in ipairs(group.runs) do
        delete_run_blocks(bufnr, run)
      end
      for _, entry in ipairs(group.tables) do
        if raw(entry) then
          undraw_marks(bufnr, entry)
        else
          table.insert(shown, entry)
        end
      end
      group.runs = lay_out_runs(bufnr, shown, row)
    end
    vim.list_extend(runs, group.runs)
  end

  if changed then
    aligned_tables[bufnr] = runs
    M.update_reveal(bufnr)
    -- Raw rows under the topline are concealed again when their table is
    -- rendered again, as when the cursor leaves a table.
    repair_view(bufnr)
  end
  return true
end

-- A write that resets 'modified' moves the changedtick by one without
-- changing the text; the rendering's recorded rows still hold across it.
-- before_write and after_write run at BufWritePre and BufWritePost.
function M.before_write(bufnr)
  bufnr = normalize_bufnr(bufnr)
  local rendering = renderings[bufnr]
  if rendering then
    rendering.write_tick = vim.api.nvim_buf_get_changedtick(bufnr)
    rendering.write_modified = vim.bo[bufnr].modified
  end
end

function M.after_write(bufnr)
  bufnr = normalize_bufnr(bufnr)
  local rendering = renderings[bufnr]
  if not rendering or not rendering.write_tick then
    return
  end
  -- Not "moved by at most one": a write that keeps 'modified' (:w other.md)
  -- moves nothing itself, so one edit around it (a formatter on BufWritePre)
  -- would pass for the write.
  local reset = rendering.write_modified and not vim.bo[bufnr].modified
  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  if rendering.tick == rendering.write_tick and tick == rendering.write_tick + (reset and 1 or 0) then
    rendering.tick = tick
  end
  rendering.write_tick, rendering.write_modified = nil, nil
end

-- shown: bufnr has just been displayed in the current window (BufWinEnter).
function M.attach_window(bufnr, shown)
  bufnr = normalize_bufnr(bufnr)
  if active_buffers[bufnr] and (active_configs[bufnr] or {}).inline_mode == "replace" then
    set_render_for_buffer(bufnr)
  elseif shown and vim.b[bufnr].markdown_table_wrap_rendered then
    -- Not on WinEnter or a cursor move, where a 2 in the window is the user's.
    -- A 2 that comes with the buffer can be the raised level Neovim stored
    -- when a window left it or closed showing it; a 2 the user set is reset
    -- too when the buffer is displayed again or reloaded with :edit, since
    -- nothing tells the two apart.
    restore_render_window(vim.api.nvim_get_current_win(), bufnr)
  end
end

function M.namespace()
  return namespace
end

return M
