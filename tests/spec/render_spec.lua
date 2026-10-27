local h = require("tests.helpers")

h.test("render emits styled chunks", function()
  local parser = require("markdown-table-wrap.parser")
  local render = require("markdown-table-wrap.render")

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| `code` | **bold** *italic* ~~strike~~ ==mark== [link](https://youtube.com) [[wiki]] ![alt](x.png) |",
  }, function(buf)
    local parsed = parser.parse_at_cursor(buf, 3)
    local rendered = render.render_table(parsed, {
      max_width_ratio = 0.9,
      min_col_width = 4,
      max_col_width = 80,
      use_unicode_border = true,
      table_border = "rounded",
      row_separator = true,
      link = {
        wiki = { icon = "W " },
        image = "I ",
        custom = {
          youtube = { pattern = "youtube", icon = "Y " },
        },
      },
    })

    local groups = {}
    for _, line in ipairs(rendered.line_objects) do
      for _, chunk in ipairs(line.chunks or {}) do
        groups[chunk.hl_group] = true
      end
    end

    h.assert_true("code chunk", groups.MarkdownTableWrapCode)
    h.assert_true("bold chunk", groups.MarkdownTableWrapBold)
    h.assert_true("italic chunk", groups.MarkdownTableWrapItalic)
    h.assert_true("strike chunk", groups.MarkdownTableWrapStrike)
    h.assert_true("mark chunk", groups.MarkdownTableWrapMark)
    h.assert_true("link chunk", groups.MarkdownTableWrapLink)
    h.assert_true("wiki link chunk", groups.MarkdownTableWrapWikiLink)
    h.assert_true("image chunk", groups.MarkdownTableWrapImage)

    local output = table.concat(rendered.lines, "\n")
    h.assert_true("custom link icon rendered", output:find("Y link", 1, true) ~= nil)
    h.assert_true("wiki icon rendered", output:find("W", 1, true) ~= nil and output:find("wiki", 1, true) ~= nil)
    h.assert_true("image icon rendered", output:find("I alt", 1, true) ~= nil)
  end)
end)

h.test("render keeps borders aligned for code-wrapped link labels", function()
  local parser = require("markdown-table-wrap.parser")
  local render = require("markdown-table-wrap.render")

  h.with_buffer({
    "| Week | Overview | Day 1 | Done |",
    "| --- | --- | --- | --- |",
    "| 1 | [overview](curriculum/week-01/overview.md) | [day-01](curriculum/week-01/day-01.md) | first |",
    "| 2 | [`overview`](curriculum/week-02/overview.md) | [`day-01`](curriculum/week-02/day-02.md) | second |",
  }, function(buf)
    vim.api.nvim_win_set_width(0, 100)
    local parsed = parser.parse_at_cursor(buf, 3)
    local rendered = render.render_table(parsed, {
      max_width_ratio = 1,
      min_col_width = 4,
      max_col_width = 40,
      fit_to_window = true,
      use_unicode_border = true,
      table_border = "rounded",
      row_separator = false,
    })

    local first_body = rendered.line_objects[4].text
    local second_body = rendered.line_objects[5].text
    h.assert_eq("code-wrapped link has no concealed delimiters", second_body:find("`", 1, true), nil)
    h.assert_eq(
      "code-wrapped and plain rows have equal width",
      vim.api.nvim_strwidth(first_body),
      vim.api.nvim_strwidth(second_body)
    )
    h.assert_eq("code-wrapped row keeps table width", vim.api.nvim_strwidth(second_body), rendered.width)
  end)
end)

h.test("render output golden snapshot", function()
  local parser = require("markdown-table-wrap.parser")
  local render = require("markdown-table-wrap.render")

  h.with_buffer({
    "| 名称 | 说明 |",
    "| --- | --- |",
    "| Rc | `Rc<RefCell<T>>` 中文说明很长很长 |",
  }, function(buf)
    vim.api.nvim_win_set_width(0, 80)
    local parsed = parser.parse_at_cursor(buf, 3)
    local rendered = render.render_table(parsed, {
      max_width_ratio = 1,
      min_col_width = 4,
      max_col_width = 16,
      use_unicode_border = true,
      table_border = "rounded",
      row_separator = true,
    })

    h.assert_eq(
      "golden top",
      rendered.lines[1],
      "╭──────┬──────────────────╮"
    )
    h.assert_eq("golden header", rendered.lines[2], "│ 名称 │ 说明             │")
    h.assert_true("golden has bottom", rendered.lines[#rendered.lines]:match("^╰") ~= nil)
  end)
end)

h.test("render alignment golden snapshot", function()
  local parser = require("markdown-table-wrap.parser")
  local render = require("markdown-table-wrap.render")

  h.with_buffer({
    "| L | C | R |",
    "| :--- | :---: | ---: |",
    "| x | y | z |",
  }, function(buf)
    vim.api.nvim_win_set_width(0, 80)
    local parsed = parser.parse_at_cursor(buf, 3)
    local rendered = render.render_table(parsed, {
      max_width_ratio = 1,
      min_col_width = 3,
      max_col_width = 3,
      use_unicode_border = true,
      table_border = "single",
      row_separator = false,
    })

    h.assert_eq("alignment header", rendered.lines[2], "│ L   │  C  │   R │")
    h.assert_eq("alignment row", rendered.lines[4], "│ x   │  y  │   z │")
  end)
end)

h.test("render ascii border and no row separator", function()
  local parser = require("markdown-table-wrap.parser")
  local render = require("markdown-table-wrap.render")

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| 1 | 2 |",
    "| 3 | 4 |",
  }, function(buf)
    local parsed = parser.parse_at_cursor(buf, 3)
    local rendered = render.render_table(parsed, {
      max_width_ratio = 1,
      min_col_width = 3,
      max_col_width = 3,
      use_unicode_border = false,
      table_border = "single",
      row_separator = false,
    })

    h.assert_eq("ascii top", rendered.lines[1], "+-----+-----+")
    h.assert_eq("ascii no row separator line count", #rendered.lines, 6)
  end)
end)

h.test("render can shrink below preferred column width to fit the window", function()
  local parser = require("markdown-table-wrap.parser")
  local render = require("markdown-table-wrap.render")

  h.with_buffer({
    "| A | B | C | D | E | F | G | H |",
    "| --- | --- | --- | --- | --- | --- | --- | --- |",
    "| alpha beta gamma | one two three | 中文内容很长 | final content | fifth column | sixth column | seventh column | eighth column |",
  }, function(buf)
    vim.api.nvim_win_set_width(0, 80)
    local parsed = parser.parse_at_cursor(buf, 3)
    local rendered = render.render_table(parsed, {
      max_width_ratio = 0.9,
      min_col_width = 8,
      max_col_width = 50,
      fit_to_window = true,
      use_unicode_border = true,
      table_border = "rounded",
      row_separator = true,
    })

    for index, line in ipairs(rendered.lines) do
      h.assert_true("fit-to-window rendered line " .. index, vim.api.nvim_strwidth(line) <= 72)
    end
  end)
end)

h.test("render keeps every source row mapped when cells wrap", function()
  local parser = require("markdown-table-wrap.parser")
  local render = require("markdown-table-wrap.render")

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| alpha beta gamma delta | one |",
    "| two | three |",
  }, function(buf)
    vim.api.nvim_win_set_width(0, 36)
    local parsed = parser.parse_at_cursor(buf, 3)
    local rendered = render.render_table(parsed, {
      max_width_ratio = 1,
      min_col_width = 4,
      max_col_width = 8,
      use_unicode_border = true,
      table_border = "rounded",
      row_separator = true,
    })

    local first_row_lines = #rendered.groups[3].lines
    h.assert_true("wrapped source row maps to multiple rendered lines", first_row_lines > 1)
    local final_row = rendered.groups[4]
    h.assert_true(
      "final border maps to final source row",
      final_row.trailing[#final_row.trailing] == rendered.line_objects[#rendered.line_objects]
    )
  end)
end)

h.test("render respects preferred widths when fit-to-window is disabled", function()
  local parser = require("markdown-table-wrap.parser")
  local render = require("markdown-table-wrap.render")

  h.with_buffer({
    "| A | B | C |",
    "| --- | --- | --- |",
    "| one | two | three |",
  }, function(buf)
    local parsed = parser.parse_at_cursor(buf, 3)
    -- The budget is narrowed through max_width_ratio, not the window: resizing
    -- the only window of a headless run leaves it at full width.
    local function width(fit_to_window)
      return render.render_table(parsed, {
        max_width_ratio = 0.2,
        min_col_width = 10,
        max_col_width = 10,
        fit_to_window = fit_to_window,
        use_unicode_border = true,
        table_border = "single",
        row_separator = false,
      }).width
    end

    h.assert_eq("three 10-cell columns plus borders, past the 16-cell budget", width(false), 40)
    h.assert_eq("fitting shrinks the same table into its 20-cell minimum", width(true), 20)
  end)
end)

h.test("max_width_ratio applies to the text area left after the number, sign and fold columns", function()
  local parser = require("markdown-table-wrap.parser")
  local render = require("markdown-table-wrap.render")
  local sentence = "every word in this cell widens its column far past any budget the window offers"

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| " .. sentence .. " | " .. sentence .. " |",
  }, function(buf)
    local parsed = parser.parse_at_cursor(buf, 3)
    -- Not the only window, whose width is also 'columns': in a 60-column split
    -- the window's own width and the screen's differ.
    local original = vim.api.nvim_get_current_win()
    vim.cmd("vsplit")
    local win = vim.api.nvim_get_current_win()

    -- Gutter widths are Neovim's: 'numberwidth' 4 (three lines need fewer
    -- digits), signcolumn "yes" 2, foldcolumn "1" 1. Both cells are wider
    -- than any budget, so the table fills its budget.
    local ok, err = pcall(function()
      vim.api.nvim_win_set_width(win, 60)
      h.assert_deep_eq(
        "the window is a 60-column split of an 80-column screen",
        { vim.api.nvim_win_get_width(win), vim.o.columns },
        { 60, 80 }
      )
      for _, case in ipairs({
        { name = "no gutter", ratio = 1, number = false, signcolumn = "no", foldcolumn = "0", width = 60 },
        { name = "'number'", ratio = 1, number = true, signcolumn = "no", foldcolumn = "0", width = 56 },
        { name = "'signcolumn'", ratio = 1, number = false, signcolumn = "yes", foldcolumn = "0", width = 58 },
        { name = "'foldcolumn'", ratio = 1, number = false, signcolumn = "no", foldcolumn = "1", width = 59 },
        -- Half of the 53-column text area; half of 60 minus the gutter is 23.
        { name = "all three, 0.5", ratio = 0.5, number = true, signcolumn = "yes", foldcolumn = "1", width = 26 },
      }) do
        vim.wo[win].number = case.number
        vim.wo[win].signcolumn = case.signcolumn
        vim.wo[win].foldcolumn = case.foldcolumn
        local rendered = render.render_table(parsed, {
          max_width_ratio = case.ratio,
          min_col_width = 1,
          max_col_width = 50,
          use_unicode_border = true,
          table_border = "rounded",
          row_separator = false,
        })
        h.assert_eq(case.name .. " table width", vim.fn.strdisplaywidth(rendered.lines[1]), case.width)
      end
    end)

    -- The gutter options were set in the split only, so closing it is the
    -- whole cleanup.
    if win ~= original and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if not ok then
      error(err, 0)
    end
  end)
end)

h.test("a quoted table is narrowed by its quote marker so both fit the text area", function()
  local parser = require("markdown-table-wrap.parser")
  local render = require("markdown-table-wrap.render")
  local sentence = "every word in this cell widens its column far past any budget the window offers"

  -- The default marker is the raw ">" and a space, two columns per level, in
  -- an 80-column window with no gutter.
  for depth, width in pairs({ [0] = 80, [1] = 78, [2] = 76 }) do
    local prefix = string.rep("> ", depth)
    h.with_buffer({
      prefix .. "| A | B |",
      prefix .. "| --- | --- |",
      prefix .. "| " .. sentence .. " | " .. sentence .. " |",
    }, function(buf)
      local rendered = render.render_table(parser.parse_at_cursor(buf, 3), {
        max_width_ratio = 1,
        min_col_width = 1,
        max_col_width = 50,
        use_unicode_border = true,
        table_border = "rounded",
        row_separator = false,
        quote_icon = "auto",
      })
      h.assert_eq("depth " .. depth .. " marker", rendered.quote and rendered.quote.text or "", prefix)
      local table_widths = {}
      for _, line in ipairs(rendered.lines) do
        table_widths[vim.fn.strdisplaywidth(line)] = true
      end
      h.assert_deep_eq(
        "depth " .. depth .. ": every table line is " .. width .. " wide",
        table_widths,
        { [width] = true }
      )
    end)
  end
end)

h.test("render highlights every wrapped header line as a header", function()
  local parser = require("markdown-table-wrap.parser")
  local render = require("markdown-table-wrap.render")

  h.with_buffer({
    "| a header that wraps | B |",
    "| --- | --- |",
    "| value | other |",
  }, function(source_buf)
    local parsed = parser.parse_at_cursor(source_buf, 3)
    local rendered = render.render_table(parsed, {
      max_width_ratio = 1,
      min_col_width = 4,
      max_col_width = 6,
      use_unicode_border = true,
      table_border = "rounded",
      row_separator = true,
    })

    local header_lines = 0
    for _, line_obj in ipairs(rendered.line_objects) do
      if line_obj.is_header then
        header_lines = header_lines + 1
      end
    end
    h.assert_true("header wraps across multiple rendered lines", header_lines > 1)

    local float_buf, float_win = render.open_float(rendered, { border = "rounded" })
    local marks = vim.api.nvim_buf_get_extmarks(float_buf, -1, 0, -1, { details = true })
    vim.api.nvim_win_close(float_win, true)

    local highlighted_header_lines = 0
    for _, mark in ipairs(marks) do
      local details = mark[4]
      if details.hl_group == "MarkdownTableWrapHeader" then
        highlighted_header_lines = highlighted_header_lines + 1
      end
    end

    h.assert_eq("every wrapped header line uses header highlight", highlighted_header_lines, header_lines)
  end)
end)

h.test("the floating preview colours code, bold and link text inside cells", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({ auto_preview = false })

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| `snippet` | **heavy** [site](https://example.com) |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    vim.cmd("MarkdownTableFloatPreview")
    local float_win = vim.api.nvim_get_current_win()
    local float_buf = vim.api.nvim_win_get_buf(float_win)
    -- Top border, header, delimiter, then the body row.
    local row = 3
    local line = vim.api.nvim_buf_get_lines(float_buf, row, row + 1, false)[1] or ""

    for _, case in ipairs({
      { word = "snippet", group = "MarkdownTableWrapCode" },
      { word = "heavy", group = "MarkdownTableWrapBold" },
      { word = "site", group = "MarkdownTableWrapLink" },
    }) do
      local first, last = line:find(case.word, 1, true)
      h.assert_true(case.word .. " is shown on the body row: " .. line, first ~= nil)
      -- Not merely present: the colour shown is the highest-priority
      -- highlight, and of equal priorities the later one in traversal order
      -- (start position, then creation), which is the one drawn on top.
      local top = nil
      local info = vim.inspect_pos(float_buf, row, (first or 1) - 1, {
        extmarks = true,
        syntax = false,
        treesitter = false,
        semantic_tokens = false,
      })
      for _, mark in ipairs(info.extmarks) do
        if not top or mark.opts.priority >= top.opts.priority then
          top = mark
        end
      end
      h.assert_deep_eq(
        case.word .. " is coloured " .. case.group .. " from its first to its last byte",
        top and { top.opts.hl_group, top.col, top.end_col },
        { case.group, (first or 0) - 1, last }
      )
    end

    if vim.api.nvim_win_get_config(float_win).relative ~= "" then
      vim.api.nvim_win_close(float_win, true)
    end
  end)
end)

h.test("render merges contiguous border highlights", function()
  local render = require("markdown-table-wrap.render")
  -- Ten lines, not a thousand: one mark per border character instead of one
  -- per range adds about fifty marks on every line, whatever the line count.
  local line_count = 10
  local lines = {}
  local line_objects = {}

  for _ = 1, line_count do
    local line =
      "├────────────────────────┼────────────────────────┤"
    table.insert(lines, line)
    table.insert(line_objects, { text = line, chunks = {} })
  end

  local float_buf, float_win = render.open_float({
    lines = lines,
    line_objects = line_objects,
    width = vim.api.nvim_strwidth(lines[1]),
    height = line_count,
  }, { border = "rounded" })
  local marks = vim.api.nvim_buf_get_extmarks(float_buf, -1, 0, -1, { details = true })
  vim.api.nvim_win_close(float_win, true)

  local border_marks = 0
  for _, mark in ipairs(marks) do
    if mark[4].hl_group == "MarkdownTableWrapBorder" then
      border_marks = border_marks + 1
    end
  end

  h.assert_eq("one merged border range per rendered line", border_marks, line_count)
  h.assert_true("extmark count stays linear with a small constant", #marks <= line_count * 2)
end)

-- Generated after upstream's generated_spec: every rendered line of a table
-- must have the same display width, or its borders do not line up.
h.test("generated tables render every line at one display width", function()
  local plugin = require("markdown-table-wrap")
  local parser = require("markdown-table-wrap.parser")
  local render = require("markdown-table-wrap.render")
  local values = {
    "",
    "界😀",
    "éclair",
    "a\\|b",
    "`a|b`",
    "**bold**",
    "[label](https://example.com)",
    "word  tail",
    "a\tb",
    "日本語の長い文章です。句点で終わる。",
    "`long_inline_code_token_here`",
    "全角　スペース",
    "x",
  }
  local seed = 1741
  local function choose(size)
    seed = (seed * 48271) % 2147483647
    return (seed % size) + 1
  end

  -- One setup for all cases: setup() rebuilds autocmds, commands and
  -- highlights, which took most of this test's time when run per case.
  plugin.setup({
    auto_preview = false,
    min_col_width = 1,
    max_width_ratio = 1,
    quote_icon = false,
  })

  h.with_buffer({}, function(buf)
    vim.api.nvim_win_set_width(0, 60)
    for case = 1, 200 do
      local row = {}
      for column = 1, 3 do
        row[column] = values[choose(#values)]
      end
      local prefix = string.rep("> ", choose(3) - 1)
      local source = prefix .. "| " .. table.concat(row, " | ") .. " |"
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { prefix .. "| A | B | C |", prefix .. "| - | :- | -: |", source })
      local config = vim.tbl_extend("force", plugin.config, { max_col_width = choose(12) })
      local output = render.render_table(parser.parse_all(buf)[1], config)
      local expected = vim.fn.strdisplaywidth(output.lines[1])
      for _, line in ipairs(output.lines) do
        h.assert_eq(
          string.format("case %d, max_col_width %d, %s", case, config.max_col_width, source),
          vim.fn.strdisplaywidth(line),
          expected
        )
      end
    end
  end)
end)

h.test("render emits one row group per source line", function()
  local parser = require("markdown-table-wrap.parser")
  local render = require("markdown-table-wrap.render")
  local config = {
    max_width_ratio = 0.9,
    min_col_width = 4,
    max_col_width = 8,
    use_unicode_border = true,
    table_border = "rounded",
    row_separator = true,
  }

  for _, case in ipairs({
    {
      name = "plain table",
      lines = { "| A | B |", "| --- | --- |", "| alpha beta gamma delta | one |", "| two | three |" },
    },
    {
      name = "blockquote table",
      lines = { "> | A | B |", "> | --- | --- |", "> | one | two |", "> | three | four |" },
    },
    {
      name = "table with a short row",
      lines = { "| A | B | C |", "| --- | --- | --- |", "| one |", "| two | three | four |" },
    },
    {
      name = "table with an excess cell",
      lines = { "| A | B |", "| --- | --- |", "| one | two | three |", "| four | five |" },
    },
  }) do
    h.with_buffer(case.lines, function(buf)
      local parsed = parser.parse_at_cursor(buf, 1)
      h.assert_true(case.name .. " parses", parsed ~= nil)
      local source_count = parsed.end_lnum - parsed.start_lnum + 1
      h.assert_eq(case.name .. " spans every buffer line", source_count, #case.lines)

      local rendered = render.render_table(parsed, config)
      h.assert_eq(case.name .. " has one row group per source line", #rendered.groups, source_count)
    end)
  end
end)
