local h = require("tests.helpers")

h.test("floating preview gx opens the rendered link under the cursor", function()
  local parser = require("markdown-table-wrap.parser")
  local render = require("markdown-table-wrap.render")
  local opened = nil
  local original_open = vim.ui.open
  vim.ui.open = function(url)
    opened = url
  end

  h.with_buffer({
    "| Name | Link |",
    "| --- | --- |",
    "| Video | [youtube](https://www.youtube.com) |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    local parsed = parser.parse_at_cursor(buf, 3)
    local rendered = render.render_table(parsed, {
      max_width_ratio = 0.9,
      min_col_width = 4,
      max_col_width = 80,
      use_unicode_border = true,
      table_border = "rounded",
      row_separator = true,
      border = "rounded",
    })
    local _, win = render.open_float(rendered, { border = "rounded" })
    local target = nil

    for row, line_object in ipairs(rendered.line_objects) do
      for _, chunk in ipairs(line_object.chunks or {}) do
        if chunk.kind == "link" and chunk.url then
          target = { row, chunk.start_col }
          break
        end
      end
      if target then
        break
      end
    end

    h.assert_true("floating link target", target ~= nil)
    vim.api.nvim_win_set_cursor(win, target)
    vim.cmd("normal gx")
    h.assert_eq("opened floating URL", opened, "https://www.youtube.com")
    vim.api.nvim_win_close(win, true)
  end)

  vim.ui.open = original_open
end)

h.test("floating preview preserves inline rendering in render_all mode", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({
    preview_mode = "inline",
    debounce_ms = 0,
    render_all = true,
    auto_preview = true,
    max_col_width = 80,
  })

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| 1 | 2 |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    plugin.refresh_auto({ force = true })
    h.assert_true("inline active before float", inline.is_active(buf))

    plugin.float_preview()
    h.assert_true("inline active after float", inline.is_active(buf))

    if plugin.state.win and vim.api.nvim_win_is_valid(plugin.state.win) then
      vim.api.nvim_win_close(plugin.state.win, true)
    end
    inline.clear(buf)
  end)
end)

h.test("inline replace refuses a rendering without one row group per source line", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")
  local parser = require("markdown-table-wrap.parser")
  local render = require("markdown-table-wrap.render")

  plugin.setup({ auto_preview = false })

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| one | two |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    local original = render.render_table
    render.render_table = function(...)
      local rendered = original(...)
      table.remove(rendered.groups)
      return rendered
    end
    local ok, err = pcall(inline.show, buf, parser.parse_at_cursor(buf, 1), plugin.get_buffer_config(buf))
    render.render_table = original

    h.assert_false("show raises instead of rendering", ok)
    h.assert_true(
      "the error names the mismatch: " .. tostring(err),
      tostring(err):find("2 row groups for 3 source lines", 1, true) ~= nil
    )
    h.assert_false("nothing is left rendered", inline.is_active(buf))
    inline.clear(buf)
  end)
end)

h.test("row-anchored replace shows relative numbers with 'relativenumber'", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| 1 | 2 |",
    "",
    "after",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.wo.relativenumber = true

    plugin.setup({
      preview_mode = "inline",
      debounce_ms = 0,
      render_all = true,
      auto_preview = true,
    })

    local function rendered_numbers()
      local numbers = {}
      for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, inline.namespace(), 0, -1, { details = true })) do
        for _, line in ipairs((mark[4] or {}).virt_lines or {}) do
          local first = line[1]
          if first and first[2] == "LineNr" then
            local digits = first[1]:match("^%s*(%d+)%s$")
            if digits then
              table.insert(numbers, tonumber(digits))
            end
          end
        end
      end
      return numbers
    end

    vim.api.nvim_win_set_cursor(0, { 4, 0 }) -- outside the table
    plugin.refresh_auto({ force = true })

    h.assert_eq("distances from cursor row 4", table.concat(rendered_numbers(), ","), "3,2,1")

    vim.api.nvim_win_set_cursor(0, { 1, 0 }) -- header row inside the table
    inline.update_reveal(buf)

    -- Row 1 is revealed natively; rows 2 and 3 render at distances 1 and 2.
    h.assert_eq("distances from cursor row 1", table.concat(rendered_numbers(), ","), "1,2")

    vim.wo.relativenumber = false
    inline.clear(buf)
  end)
end)

h.test("relative numbers follow the cursor whenever the table is visible", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  local lines = {
    "| A | B |",
    "| --- | --- |",
    "| 1 | 2 |",
  }
  table.insert(lines, "")
  for i = 1, 200 do
    table.insert(lines, "filler " .. i)
  end

  h.with_buffer(lines, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.wo.relativenumber = true

    plugin.setup({
      preview_mode = "inline",
      debounce_ms = 0,
      render_all = true,
      auto_preview = true,
    })

    local function rendered_numbers()
      local numbers = {}
      for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, inline.namespace(), 0, -1, { details = true })) do
        for _, line in ipairs((mark[4] or {}).virt_lines or {}) do
          local first = line[1]
          if first and first[2] == "LineNr" then
            local digits = first[1]:match("^%s*(%d+)%s$")
            if digits then
              table.insert(numbers, tonumber(digits))
            end
          end
        end
      end
      return table.concat(numbers, ",")
    end

    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    plugin.refresh_auto({ force = true })
    h.assert_eq("distances from row 4", rendered_numbers(), "3,2,1")

    -- Row 6, not a row inside the table: the blocks keep their split, so only
    -- the relative-number update can change the numbers.
    vim.api.nvim_win_set_cursor(0, { 6, 0 })
    inline.update_reveal(buf)
    h.assert_eq("a cursor move below the table updates the distances", rendered_numbers(), "5,4,3")

    -- Nothing is asserted while the table is off screen, where skipping the
    -- update is allowed; back in view the numbers must follow the cursor row.
    vim.cmd("normal! G")
    inline.update_reveal(buf)
    h.assert_true("table is off screen", vim.fn.line("w0") > 4)
    vim.fn.winrestview({ topline = 1, lnum = 15, col = 0 })
    inline.update_reveal(buf)
    h.assert_eq("back in view, distances are measured from row 15", rendered_numbers(), "14,13,12")

    vim.wo.relativenumber = false
    inline.clear(buf)
  end)
end)

h.test("row-anchored replace omits number column when 'number' is off", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| 1 | 2 |",
    "",
    "after",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.wo.number = false
    vim.wo.relativenumber = false

    plugin.setup({
      preview_mode = "inline",
      debounce_ms = 0,
      render_all = true,
      auto_preview = true,
    })
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    plugin.refresh_auto({ force = true })

    local seen = false
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, inline.namespace(), 0, -1, { details = true })) do
      local details = mark[4] or {}
      if details.virt_lines then
        seen = true
        h.assert_false("no leftcol without a number column", details.virt_lines_leftcol == true)
        for _, line in ipairs(details.virt_lines) do
          h.assert_false("no LineNr prefix without a number column", line[1] and line[1][2] == "LineNr")
        end
      end
    end
    h.assert_true("rendered virtual lines exist", seen)

    inline.clear(buf)
  end)
end)

h.test("a table on line 1 keeps its top border on screen while its first row is revealed", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({
    preview_mode = "inline",
    debounce_ms = 0,
    render_all = true,
    auto_preview = true,
  })

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| 1 | 2 |",
    "",
    "after",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 5, 0 })
    plugin.refresh_auto({ force = true })

    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
    vim.cmd("redraw")

    h.assert_true(
      "the top border is the first screen line: " .. h.screen_line(1),
      h.screen_line(1):match("^╭") ~= nil
    )
    h.assert_eq("the revealed header row follows it", h.screen_line(2), "| A | B |")

    inline.clear(buf)
  end)
end)

-- Renders `lines` with the cursor on cursors[1], then moves the cursor through
-- `cursors` and compares the top screen lines with screen_for(cursor line).
-- `numbers` turns on 'number' and 'relativenumber' and reads the number column
-- as part of each screen line.
local function walk_screens(name, lines, cursors, screen_for, numbers)
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({
    preview_mode = "inline",
    debounce_ms = 0,
    render_all = true,
    auto_preview = true,
  })

  h.with_buffer(lines, function(buf)
    vim.bo[buf].filetype = "markdown"
    local saved = { number = vim.wo.number, relativenumber = vim.wo.relativenumber, wrap = vim.wo.wrap }
    local ok, err = pcall(function()
      vim.wo.number = numbers
      vim.wo.relativenumber = numbers
      vim.wo.wrap = true
      vim.api.nvim_win_set_cursor(0, { cursors[1], 0 })
      plugin.refresh_auto({ force = true })

      for _, lnum in ipairs(cursors) do
        vim.api.nvim_win_set_cursor(0, { lnum, 0 })
        vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
        vim.cmd("redraw")

        local expected = screen_for(lnum)
        local screen = {}
        for row = 1, #expected do
          screen[row] = h.screen_line(row, numbers)
        end
        h.assert_deep_eq(string.format("%s, cursor on line %d", name, lnum), screen, expected)
      end
    end)

    for option, value in pairs(saved) do
      vim.wo[option] = value
    end
    inline.clear(buf)
    if not ok then
      error(err, 0)
    end
  end)
end

-- Runs fn(win) in a new split of `height` rows showing the current buffer and
-- closes the split afterwards, also when fn fails; window options set on win
-- go away with it.
local function in_split(height, fn)
  vim.cmd("split")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_height(win, height)
  local ok, err = pcall(fn, win)
  vim.api.nvim_win_close(win, true)
  if not ok then
    error(err, 0)
  end
end

-- screen_for for walk_screens: `rendered` is the screen while the cursor is
-- outside the tables; with the cursor on line lnum, the line at screen row
-- reveal[lnum][1] gives way to the lines reveal[lnum][2].
local function revealed_screens(rendered, reveal)
  return function(lnum)
    local screen = vim.deepcopy(rendered)
    if reveal[lnum] then
      local row, replacement = unpack(reveal[lnum])
      table.remove(screen, row)
      for offset, line in ipairs(replacement) do
        table.insert(screen, row + offset - 1, line)
      end
    end
    return screen
  end
end

-- Tables touch only across a change of quote depth: within one depth, the
-- line under a table is one of its rows.
h.test("two adjacent tables at the top of the buffer are both drawn in source order wherever the cursor is", function()
  local lines = {
    "> | A | B |",
    "> | --- | --- |",
    "> | one | two |",
    "| E | F |",
    "| --- | --- |",
    "| five | six |",
    "",
    "outro",
  }
  local rendered = {
    "> ╭──────────┬──────────╮",
    "> │ A        │ B        │",
    "> ├──────────┼──────────┤",
    "> │ one      │ two      │",
    "> ╰──────────┴──────────╯",
    "╭──────────┬──────────╮",
    "│ E        │ F        │",
    "├──────────┼──────────┤",
    "│ five     │ six      │",
    "╰──────────┴──────────╯",
    "",
    "outro",
    "~",
  }
  local reveal = {
    { 2, { "> | A | B |" } },
    { 3, { "> | --- | --- |" } },
    { 4, { "> | one | two |" } },
    { 7, { "| E | F |" } },
    { 8, { "| --- | --- |" } },
    { 9, { "| five | six |" } },
  }

  -- 1 -> 4 -> 1 keeps the row's index within its table and changes only the
  -- table.
  local cursors = { 8, 1, 4, 1 }
  for lnum = 2, 8 do
    table.insert(cursors, lnum)
  end
  for lnum = 7, 1, -1 do
    table.insert(cursors, lnum)
  end

  walk_screens("two-table run", lines, cursors, revealed_screens(rendered, reveal), false)
end)

h.test("three adjacent tables ending the buffer are all drawn in source order wherever the cursor is", function()
  local width = vim.api.nvim_win_get_width(0)
  local lines = {
    "intro",
    "",
    "| E | F |",
    "| --- | --- |",
    "| five | six |",
    "> | A | B |",
    "> | --- | --- |",
    -- Revealed, this row soft-wraps onto a second screen row (its last 14
    -- cells) while it renders as one, so the middle table gets a stable-height
    -- filler line under its other revealed rows.
    "> | one | two" .. string.rep(" ", width) .. "|",
    "> > | C | D |",
    "> > | --- | --- |",
    "> > | three | four |",
  }
  local rendered = {
    "intro",
    "",
    "╭──────────┬──────────╮",
    "│ E        │ F        │",
    "├──────────┼──────────┤",
    "│ five     │ six      │",
    "╰──────────┴──────────╯",
    "> ╭──────────┬──────────╮",
    "> │ A        │ B        │",
    "> ├──────────┼──────────┤",
    "> │ one      │ two      │",
    "> ╰──────────┴──────────╯",
    "> > ╭──────────┬──────────╮",
    "> > │ C        │ D        │",
    "> > ├──────────┼──────────┤",
    "> > │ three    │ four     │",
    "> > ╰──────────┴──────────╯",
    "~",
  }
  local reveal = {
    [3] = { 4, { "| E | F |" } },
    [4] = { 5, { "| --- | --- |" } },
    [5] = { 6, { "| five | six |" } },
    [6] = { 9, { "> | A | B |", ">" } },
    [7] = { 10, { "> | --- | --- |", ">" } },
    [8] = { 11, { "> | one | two", string.rep(" ", 13) .. "|" } },
    [9] = { 14, { "> > | C | D |" } },
    [10] = { 15, { "> > | --- | --- |" } },
    [11] = { 16, { "> > | three | four |" } },
  }

  local cursors = { 1, 3, 6, 9, 3 }
  for lnum = 2, 11 do
    table.insert(cursors, lnum)
  end
  for lnum = 10, 1, -1 do
    table.insert(cursors, lnum)
  end

  walk_screens("three-table run", lines, cursors, revealed_screens(rendered, reveal), false)
end)

h.test("adjacent tables number their rows by distance from the cursor row inside and outside them", function()
  local lines = {
    "> | A | B |",
    "> | --- | --- |",
    "> | one | two |",
    "| E | F |",
    "| --- | --- |",
    "| five | six |",
    "",
    "outro",
  }
  -- Native numbers on real lines, the plugin's on rendered ones; the cursor
  -- line shows its absolute number, left-aligned.
  local screens = {
    [8] = {
      "    > ╭──────────┬──────────╮",
      "  7 > │ A        │ B        │",
      "  6 > ├──────────┼──────────┤",
      "  5 > │ one      │ two      │",
      "    > ╰──────────┴──────────╯",
      "    ╭──────────┬──────────╮",
      "  4 │ E        │ F        │",
      "  3 ├──────────┼──────────┤",
      "  2 │ five     │ six      │",
      "    ╰──────────┴──────────╯",
      "  1",
      "8   outro",
    },
    [7] = {
      "    > ╭──────────┬──────────╮",
      "  6 > │ A        │ B        │",
      "  5 > ├──────────┼──────────┤",
      "  4 > │ one      │ two      │",
      "    > ╰──────────┴──────────╯",
      "    ╭──────────┬──────────╮",
      "  3 │ E        │ F        │",
      "  2 ├──────────┼──────────┤",
      "  1 │ five     │ six      │",
      "    ╰──────────┴──────────╯",
      "7",
      "  1 outro",
    },
    [2] = {
      "    > ╭──────────┬──────────╮",
      "  1 > │ A        │ B        │",
      "2   > | --- | --- |",
      "  1 > │ one      │ two      │",
      "    > ╰──────────┴──────────╯",
      "    ╭──────────┬──────────╮",
      "  2 │ E        │ F        │",
      "  3 ├──────────┼──────────┤",
      "  4 │ five     │ six      │",
      "    ╰──────────┴──────────╯",
      "  5",
      "  6 outro",
    },
    [5] = {
      "    > ╭──────────┬──────────╮",
      "  4 > │ A        │ B        │",
      "  3 > ├──────────┼──────────┤",
      "  2 > │ one      │ two      │",
      "    > ╰──────────┴──────────╯",
      "    ╭──────────┬──────────╮",
      "  1 │ E        │ F        │",
      "5   | --- | --- |",
      "  1 │ five     │ six      │",
      "    ╰──────────┴──────────╯",
      "  2",
      "  3 outro",
    },
  }

  walk_screens("numbered run", lines, { 8, 7, 2, 5 }, function(lnum)
    return screens[lnum]
  end, true)
end)

h.test("stepping down out of a table or a run that is taller than the window keeps the cursor in it", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({
    preview_mode = "inline",
    debounce_ms = 0,
    render_all = true,
    auto_preview = true,
  })

  local lines = { "p1", "p2", "p3", "p4", "p5", "p6", "" }
  -- Lines 8-14: a lone table rendering to 13 lines.
  vim.list_extend(lines, {
    "| A | B |",
    "| --- | --- |",
    "| a1 | a2 |",
    "| a3 | a4 |",
    "| a5 | a6 |",
    "| a7 | a8 |",
    "| a9 | a10 |",
  })
  vim.list_extend(lines, { "", "m1", "m2", "m3", "" })
  -- Lines 20-29: a run whose first table renders to 13 lines.
  vim.list_extend(lines, {
    "| L | M |",
    "| --- | --- |",
    "| l1 | m1 |",
    "| l2 | m2 |",
    "| l3 | m3 |",
    "| l4 | m4 |",
    "| l5 | m5 |",
    "> | X | Y |",
    "> | --- | --- |",
    "> | x1 | y1 |",
  })
  vim.list_extend(lines, { "", "q1", "q2", "q3", "q4", "q5", "q6", "q7", "q8" })

  h.with_buffer(lines, function(buf)
    vim.bo[buf].filetype = "markdown"
    in_split(11, function(win)
      vim.wo[win].scrolloff = 3
      vim.api.nvim_win_set_cursor(win, { 1, 0 })
      plugin.refresh_auto({ force = true })

      for lnum = 2, #lines do
        vim.cmd("normal! j")
        vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
        h.drain_scheduled()
        vim.cmd("redraw")
        local winline = vim.fn.winline()
        h.assert_true(
          string.format("cursor on line %d is on window row %d of 11", lnum, winline),
          winline >= 1 and winline <= 11
        )
      end
    end)
    inline.clear(buf)
  end)
end)

h.test("relative numbers catch up when only the tail of a run scrolls into view", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({
    preview_mode = "inline",
    debounce_ms = 0,
    render_all = true,
    auto_preview = true,
  })

  local lines = { "p1", "p2", "p3", "p4", "p5", "p6", "p7", "p8", "p9", "p10" }
  -- Lines 11-17: a run; e3 is line 17.
  vim.list_extend(lines, {
    "> | A | B |",
    "> | --- | --- |",
    "> | a1 | a2 |",
    "| E | F |",
    "| --- | --- |",
    "| e1 | e2 |",
    "| e3 | e4 |",
    "",
  })
  for lnum = 19, 40 do
    table.insert(lines, "q" .. lnum)
  end

  h.with_buffer(lines, function(buf)
    vim.bo[buf].filetype = "markdown"
    in_split(11, function(win)
      vim.wo[win].number = true
      vim.wo[win].relativenumber = true
      vim.wo[win].scrolloff = 0
      vim.api.nvim_win_set_cursor(win, { 1, 0 })
      plugin.refresh_auto({ force = true })

      -- Off screen the run keeps the distances from line 1.
      vim.fn.winrestview({ topline = 20, lnum = 25, col = 0 })
      inline.update_reveal(buf)

      -- Only the run's last three rendered lines show, as filler above line 18.
      vim.fn.winrestview({ topline = 18, topfill = 3 })
      inline.update_reveal(buf)
      vim.cmd("redraw")
      h.assert_deep_eq("e3 (line 17) is 8 lines from the cursor on 25", {
        h.screen_line(1, true),
        h.screen_line(2, true),
        h.screen_line(3, true),
        h.screen_line(4, true),
      }, {
        "    ├──────────┼──────────┤",
        "  8 │ e3       │ e4       │",
        "    ╰──────────┴──────────╯",
        "  7",
      })

      vim.cmd("normal! j")
      vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
      vim.cmd("redraw")
      h.assert_deep_eq("after j, e3 is 9 lines from the cursor on 26", {
        h.screen_line(1, true),
        h.screen_line(2, true),
      }, {
        "  9 │ e3       │ e4       │",
        "    ╰──────────┴──────────╯",
      })
    end)
    inline.clear(buf)
  end)
end)

h.test("row-anchored lines keep their original rendered line index", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({
    preview_mode = "inline",
    debounce_ms = 0,
    render_all = true,
    auto_preview = true,
    row_separator = true,
  })

  h.with_buffer({
    "| 成员 | 分工 |",
    "| --- | --- |",
    "| 组长 | 项目规划 |",
    "| 成员 A | 数据集整理 |",
    "| 成员 B | Web 系统实现 |",
    "| 成员 C | 报告撰写 |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    plugin.refresh_auto({ force = true })

    local marks = vim.api.nvim_buf_get_extmarks(buf, inline.namespace(), 0, -1, { details = true })
    local member_b_chunks = nil
    local member_b_row = nil

    local function scan_chunks(chunks, row)
      local text = {}
      for _, chunk in ipairs(chunks) do
        table.insert(text, chunk[1])
      end

      if table.concat(text):find("成员 B", 1, true) then
        member_b_chunks = chunks
        member_b_row = row
      end
    end

    for _, mark in ipairs(marks) do
      local details = mark[4] or {}
      if details.virt_text then
        scan_chunks(details.virt_text, mark[2])
      end
      for _, virt_line in ipairs(details.virt_lines or {}) do
        scan_chunks(virt_line, mark[2])
      end
    end

    h.assert_true("member B is rendered", member_b_chunks ~= nil)
    h.assert_true("member B rendered as a virtual line", member_b_row ~= nil)

    local groups = {}
    for _, chunk in ipairs(member_b_chunks) do
      groups[chunk[2]] = true
    end

    h.assert_false("member B is not treated as table header", groups.MarkdownTableWrapHeader)
    h.assert_true("member B keeps normal inline highlight", groups.MarkdownTableWrapInline)

    inline.clear(buf)
  end)
end)

h.test("inline insert mode highlights every wrapped header line", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({
    preview_mode = "inline",
    inline_mode = "insert",
    auto_preview = false,
    render_all = true,
    min_col_width = 4,
    max_col_width = 6,
  })

  h.with_buffer({
    "| a header that wraps | B |",
    "| --- | --- |",
    "| value | other |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    plugin.refresh_auto({ force = true })

    local highlighted_header_lines = 0
    local marks = vim.api.nvim_buf_get_extmarks(buf, inline.namespace(), 0, -1, { details = true })
    for _, mark in ipairs(marks) do
      for _, virt_line in ipairs((mark[4] or {}).virt_lines or {}) do
        for _, chunk in ipairs(virt_line) do
          if chunk[2] == "MarkdownTableWrapHeader" then
            highlighted_header_lines = highlighted_header_lines + 1
            break
          end
        end
      end
    end

    h.assert_true("wrapped header spans multiple virtual lines", highlighted_header_lines > 1)
    inline.clear(buf)
  end)
end)

h.test("inline insert mode draws the table before its first row or after its last row", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  for _, case in ipairs({
    { position = "above", row = 2, above = true },
    { position = "below", row = 5, above = false },
  }) do
    plugin.setup({
      preview_mode = "inline",
      inline_mode = "insert",
      inline_position = case.position,
      auto_preview = false,
      render_all = true,
    })

    h.with_buffer({
      "intro",
      "",
      "| A | B |",
      "| --- | --- |",
      "| one | two |",
      "| three | four |",
      "",
      "outro",
    }, function(buf)
      vim.bo[buf].filetype = "markdown"
      plugin.refresh_auto({ force = true })

      local anchors = {}
      local marks = vim.api.nvim_buf_get_extmarks(buf, inline.namespace(), 0, -1, { details = true })
      for _, mark in ipairs(marks) do
        if mark[4].virt_lines then
          table.insert(anchors, { row = mark[2], above = mark[4].virt_lines_above == true })
        end
      end

      h.assert_deep_eq(case.position .. " anchor", anchors, { { row = case.row, above = case.above } })
      inline.clear(buf)
    end)
  end
end)

h.test("quoted table navigation skips the quote marker", function()
  local nav = require("markdown-table-wrap.nav")

  local spans = nav.spans("> | ab | cd |")
  h.assert_eq("quoted cell count", #spans, 2)
  h.assert_eq("first quoted cell", ("> | ab | cd |"):sub(spans[1].start_col + 1, spans[1].end_col), "ab")
  h.assert_eq("second quoted cell", ("> | ab | cd |"):sub(spans[2].start_col + 1, spans[2].end_col), "cd")
end)

-- Renders `lines` under setup(config) with the cursor on line `lnum`, runs
-- fn(buf) and clears the rendering again, leaving Visual mode first if fn
-- failed in it.
local function with_rendered(lines, lnum, config, fn)
  local plugin = require("markdown-table-wrap")
  plugin.setup(vim.tbl_extend("force", {
    preview_mode = "inline",
    debounce_ms = 0,
    render_all = true,
    auto_preview = true,
  }, config))

  h.with_buffer(lines, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { lnum, 0 })
    plugin.refresh_auto({ force = true })
    local ok, err = pcall(fn, buf)
    if vim.api.nvim_get_mode().mode ~= "n" then
      h.feed("<Esc>")
    end
    require("markdown-table-wrap.inline").clear(buf)
    if not ok then
      error(err, 0)
    end
  end)
end

-- Moves in Visual mode the way a user does: the main loop fires CursorMoved
-- after the move, which h.feed does not.
local function move(buf, keys)
  h.feed(keys)
  vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
end

-- The screen lines of the current window from the top, as many as `expected`
-- has, for comparing with it.
local function screen_like(expected)
  vim.cmd("redraw")
  local screen = {}
  for row = 1, #expected do
    screen[row] = h.screen_line(row)
  end
  return screen
end

local two_tables = {
  "intro",
  "",
  "| A | B |",
  "| --- | --- |",
  "| one | two |",
  "",
  "mid",
  "",
  "| C | D |",
  "| --- | --- |",
  "| three | four |",
  "",
  "outro",
}
local first_raw = { unpack(two_tables, 3, 5) }
local second_raw = { unpack(two_tables, 9, 11) }
local first_rendered = {
  "╭──────────┬──────────╮",
  "│ A        │ B        │",
  "├──────────┼──────────┤",
  "│ one      │ two      │",
  "╰──────────┴──────────╯",
}
local second_rendered = {
  "╭──────────┬──────────╮",
  "│ C        │ D        │",
  "├──────────┼──────────┤",
  "│ three    │ four     │",
  "╰──────────┴──────────╯",
}
-- The first table rendered with its last row, the cursor row, revealed.
local first_revealed = { first_rendered[1], first_rendered[2], first_rendered[3], "| one | two |", first_rendered[5] }

-- The screen of two_tables with each table drawn as the given lines.
local function two_table_screen(first, second, outro)
  local screen = { "intro", "" }
  vim.list_extend(screen, first)
  vim.list_extend(screen, { "", "mid", "" })
  vim.list_extend(screen, second)
  vim.list_extend(screen, { "", outro or "outro" })
  return screen
end

h.test("Visual mode shows raw only the tables its lines reach, following the selection", function()
  for _, keys in ipairs({ "v", "V", "<C-v>" }) do
    with_rendered(two_tables, 5, {}, function(buf)
      local label = keys .. ": "
      h.feed(keys)
      h.assert_deep_eq(
        label .. "the table under the cursor is raw, the other one rendered",
        screen_like(two_table_screen(first_raw, second_rendered)),
        two_table_screen(first_raw, second_rendered)
      )

      move(buf, "4j")
      h.assert_deep_eq(
        label .. "a selection reaching the first row of the second table shows all of it raw",
        screen_like(two_table_screen(first_raw, second_raw)),
        two_table_screen(first_raw, second_raw)
      )

      move(buf, "4k")
      h.assert_deep_eq(
        label .. "shrinking the selection renders the second table again",
        screen_like(two_table_screen(first_raw, second_rendered)),
        two_table_screen(first_raw, second_rendered)
      )

      -- No timers drained: a refresh would render everything anyway.
      h.feed("<Esc>")
      h.assert_deep_eq(
        label .. "leaving Visual mode renders both tables at once",
        screen_like(two_table_screen(first_revealed, second_rendered)),
        two_table_screen(first_revealed, second_rendered)
      )
    end)
  end
end)

h.test("Visual mode keeps the other tables of an adjacent run drawn around a selected one", function()
  local lines = {
    "intro",
    "",
    "| E | F |",
    "| --- | --- |",
    "| five | six |",
    "> | A | B |",
    "> | --- | --- |",
    "> | one | two |",
    "> > | C | D |",
    "> > | --- | --- |",
    "> > | three | four |",
  }
  local rendered = {
    {
      "╭──────────┬──────────╮",
      "│ E        │ F        │",
      "├──────────┼──────────┤",
      "│ five     │ six      │",
      "╰──────────┴──────────╯",
    },
    {
      "> ╭──────────┬──────────╮",
      "> │ A        │ B        │",
      "> ├──────────┼──────────┤",
      "> │ one      │ two      │",
      "> ╰──────────┴──────────╯",
    },
    {
      "> > ╭──────────┬──────────╮",
      "> > │ C        │ D        │",
      "> > ├──────────┼──────────┤",
      "> > │ three    │ four     │",
      "> > ╰──────────┴──────────╯",
    },
  }

  with_rendered(lines, 1, {}, function()
    -- The middle row of each table in turn: the upper, the middle and the
    -- lower member of the run.
    for selected, lnum in ipairs({ 4, 7, 10 }) do
      local expected = { "intro", "" }
      for member = 1, 3 do
        local first = 3 * member
        vim.list_extend(expected, member == selected and { unpack(lines, first, first + 2) } or rendered[member])
      end

      h.feed(lnum .. "GV")
      h.assert_deep_eq("line " .. lnum .. " selected", screen_like(expected), expected)
      h.feed("<Esc>")
    end
  end)
end)

h.test("Visual mode leaves every table rendered with clear_on_visual = false", function()
  with_rendered(two_tables, 1, { clear_on_visual = false }, function(buf)
    h.feed("V")
    move(buf, "4j")
    h.assert_deep_eq(
      "both tables stay rendered, the cursor row revealed",
      screen_like(two_table_screen(first_revealed, second_rendered)),
      two_table_screen(first_revealed, second_rendered)
    )
  end)
end)

h.test("Visual mode takes only the selected tables' rendering away in Inline insert mode", function()
  -- Inline insert mode draws the rendered table above its source rows.
  local function screen(first_shown, second_shown)
    local first, second = vim.list_extend({}, first_raw), vim.list_extend({}, second_raw)
    if first_shown then
      first = vim.list_extend(vim.list_extend({}, first_rendered), first_raw)
    end
    if second_shown then
      second = vim.list_extend(vim.list_extend({}, second_rendered), second_raw)
    end
    -- Not past the window's last line.
    return { unpack(two_table_screen(first, second), 1, 20) }
  end

  with_rendered(two_tables, 1, { inline_mode = "insert" }, function(buf)
    h.assert_deep_eq("both tables are rendered", screen_like(screen(true, true)), screen(true, true))

    h.feed("4GV")
    h.assert_deep_eq("the selected table loses its rendering", screen_like(screen(false, true)), screen(false, true))

    move(buf, "6j")
    h.assert_deep_eq("so does a table the selection reaches", screen_like(screen(false, false)), screen(false, false))

    move(buf, "6k")
    h.assert_deep_eq(
      "and gets it back when the selection leaves it",
      screen_like(screen(false, true)),
      screen(false, true)
    )

    h.feed("<Esc>")
    h.assert_deep_eq("leaving Visual mode renders both at once", screen_like(screen(true, true)), screen(true, true))
  end)
end)

h.test("leaving Visual mode with an edit leaves the edited table raw until the next refresh", function()
  local plugin = require("markdown-table-wrap")
  local first_edited = { "| A | B |", "| --- | --- |", "| ONE | TWO |" }
  local first_edited_revealed =
    { first_rendered[1], first_rendered[2], first_rendered[3], "| ONE | TWO |", first_rendered[5] }

  for _, auto_preview in ipairs({ true, false }) do
    with_rendered(two_tables, 5, { auto_preview = auto_preview }, function()
      local label = "auto_preview = " .. tostring(auto_preview) .. ": "
      h.feed("Vy")
      h.assert_deep_eq(
        label .. "a yank renders the table at once",
        screen_like(two_table_screen(first_revealed, second_rendered)),
        two_table_screen(first_revealed, second_rendered)
      )

      h.feed("VU")
      h.assert_deep_eq(
        label .. "an operator leaves the edited table raw and the other one rendered",
        screen_like(two_table_screen(first_edited, second_rendered)),
        two_table_screen(first_edited, second_rendered)
      )

      h.drain_timers(1)
      local refreshed = auto_preview and first_edited_revealed or first_edited
      h.assert_deep_eq(
        label .. (auto_preview and "the refresh renders it" or "no refresh comes"),
        screen_like(two_table_screen(refreshed, second_rendered)),
        two_table_screen(refreshed, second_rendered)
      )

      plugin.refresh_auto({ force = true })
      h.assert_deep_eq(
        label .. "a manual refresh renders it",
        screen_like(two_table_screen(first_edited_revealed, second_rendered)),
        two_table_screen(first_edited_revealed, second_rendered)
      )
    end)
  end
end)

h.test("Visual mode started over an edit not yet refreshed shows every table raw until the refresh", function()
  local all_raw = two_table_screen(first_raw, second_raw, "utro")
  local all_rendered = two_table_screen(first_rendered, second_rendered, "utro")

  with_rendered(two_tables, 1, {}, function()
    -- The refresh the edit schedules has not run yet.
    h.feed("Gxgg")
    h.feed("V")
    h.assert_deep_eq("every table is raw", screen_like(all_raw), all_raw)

    h.feed("<Esc>")
    h.drain_timers(1)
    h.assert_deep_eq("the refresh renders them", screen_like(all_rendered), all_rendered)

    h.feed("V")
    h.assert_deep_eq("after the refresh only the selected tables are raw", screen_like(all_rendered), all_rendered)
  end)
end)

h.test("leaving Visual mode keeps the cursor on screen when a tall table is rendered again", function()
  local lines = { "intro", "", "| A | B |", "| --- | --- |" }
  for row = 1, 40 do
    table.insert(lines, "| a" .. row .. " | b |")
  end
  vim.list_extend(lines, { "", "| C | D |", "| --- | --- |", "| c1 | d |", "| c2 | d |" })

  with_rendered(lines, 1, {}, function(buf)
    -- From the tall table to the delimiter row of the short one below it, so
    -- the window's top line is one of the tall table's raw rows. Not to the
    -- last row: Neovim then keeps the cursor on screen by itself.
    h.feed("10GV")
    move(buf, "47G")
    vim.cmd("redraw")
    h.assert_true("the top line is a raw row of the tall table", vim.fn.line("w0") > 10)

    h.feed("<Esc>")
    vim.cmd("redraw")
    h.drain_scheduled()
    vim.cmd("redraw")
    h.assert_true(
      string.format("the cursor is on screen: window line %d of %d", vim.fn.winline(), vim.api.nvim_win_get_height(0)),
      vim.fn.winline() <= vim.api.nvim_win_get_height(0)
    )
  end)
end)

-- Gives the scratch buffer a file to be written to; returns its path.
local function writable(buf)
  local path = vim.fn.tempname() .. ".md"
  vim.bo[buf].buftype = ""
  vim.api.nvim_buf_set_name(buf, path)
  return path
end

h.test("a write since the rendering does not make Visual mode show every table raw", function()
  local plugin = require("markdown-table-wrap")
  local function screen(first, second, outro)
    local lines = two_table_screen(first, second, outro)
    lines[1] = "ntro"
    return lines
  end

  with_rendered(two_tables, 1, {}, function(buf)
    local path = writable(buf)
    local ok, err = pcall(function()
      h.feed("x")
      plugin.refresh_auto()
      vim.cmd("silent write")
      h.feed("3GV")
      h.assert_deep_eq(
        "after the write only the selected table is raw",
        screen_like(screen(first_raw, second_rendered)),
        screen(first_raw, second_rendered)
      )
      h.feed("<Esc>")
      h.drain_timers(1)

      -- A change made while writing is a change like any other.
      vim.api.nvim_create_autocmd("BufWritePre", {
        buffer = buf,
        once = true,
        callback = function()
          vim.api.nvim_buf_set_lines(buf, -2, -1, false, { "outro!" })
        end,
      })
      vim.cmd("silent write")
      h.feed("gg3GV")
      h.assert_deep_eq(
        "after a write that changed the text every table is raw",
        screen_like(screen(first_raw, second_raw, "outro!")),
        screen(first_raw, second_raw, "outro!")
      )
    end)
    vim.fn.delete(path)
    if not ok then
      error(err, 0)
    end
  end)
end)

h.test("leaving Visual mode after a write keeps a manual rendering", function()
  local plugin = require("markdown-table-wrap")
  local header_revealed = { first_rendered[1], "| A | B |", first_rendered[3], first_rendered[4], first_rendered[5] }
  local expected = two_table_screen(header_revealed, second_rendered)
  expected[1] = "ntro"

  with_rendered(two_tables, 1, { auto_preview = false }, function(buf)
    local path = writable(buf)
    local ok, err = pcall(function()
      h.feed("x")
      plugin.refresh_auto({ force = true })
      vim.cmd("silent write")
      h.feed("3GV")
      h.feed("<Esc>")
      h.assert_deep_eq("both tables are rendered after Visual mode", screen_like(expected), expected)

      -- An edit the write follows is still not refreshed.
      h.feed("Gx")
      vim.cmd("silent write")
      h.feed("ggV")
      local all_raw = two_table_screen(first_raw, second_raw, "utro")
      all_raw[1] = "ntro"
      h.assert_deep_eq("after an unrefreshed edit and a write every table is raw", screen_like(all_raw), all_raw)
    end)
    vim.fn.delete(path)
    if not ok then
      error(err, 0)
    end
  end)
end)

h.test("a write to another file with an edit around it makes Visual mode show every table raw", function()
  local plugin = require("markdown-table-wrap")
  -- two_tables without its first line, which the edit deletes.
  local all_raw = { unpack(two_tables, 2) }

  for _, mode in ipairs({ "replace", "insert" }) do
    with_rendered(two_tables, 1, { auto_preview = false, inline_mode = mode }, function(buf)
      local path = writable(buf)
      local other = vim.fn.tempname() .. ".md"
      local ok, err = pcall(function()
        plugin.refresh_auto({ force = true })
        -- Created after setup, so it runs after the plugin's own BufWritePre.
        vim.api.nvim_create_autocmd("BufWritePre", {
          buffer = buf,
          once = true,
          callback = function()
            vim.api.nvim_buf_set_lines(buf, 0, 1, false, {})
          end,
        })
        -- Keeps 'modified', so the write itself moves no changedtick.
        vim.cmd("silent write! " .. vim.fn.fnameescape(other))
        h.assert_true(mode .. ": the buffer is still modified", vim.bo[buf].modified)
        h.feed("8GV")
        h.assert_deep_eq(mode .. ": every table is raw", screen_like(all_raw), all_raw)
      end)
      vim.fn.delete(path)
      vim.fn.delete(other)
      if not ok then
        error(err, 0)
      end
    end)
  end
end)
