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

h.test("render mixed width cells stay within configured width", function()
  local parser = require("markdown-table-wrap.parser")
  local render = require("markdown-table-wrap.render")

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| 中日English | 中文中文EnglishEnglish |",
  }, function(buf)
    local parsed = parser.parse_at_cursor(buf, 3)
    local rendered = render.render_table(parsed, {
      max_width_ratio = 1,
      min_col_width = 4,
      max_col_width = 8,
      use_unicode_border = true,
      table_border = "rounded",
      row_separator = true,
    })

    for index, line in ipairs(rendered.lines) do
      h.assert_true("mixed width rendered line " .. index, vim.api.nvim_strwidth(line) <= rendered.width)
    end
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
    vim.api.nvim_win_set_width(0, 30)
    local parsed = parser.parse_at_cursor(buf, 3)
    local rendered = render.render_table(parsed, {
      max_width_ratio = 0.5,
      min_col_width = 10,
      max_col_width = 10,
      fit_to_window = false,
      use_unicode_border = true,
      table_border = "single",
      row_separator = false,
    })

    h.assert_true("table can exceed requested viewport", rendered.width > 15)
    h.assert_eq("top border keeps stable width", vim.api.nvim_strwidth(rendered.lines[1]), rendered.width)
    h.assert_eq(
      "bottom border keeps stable width",
      vim.api.nvim_strwidth(rendered.lines[#rendered.lines]),
      rendered.width
    )
  end)
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
      if details.priority == 10 and details.hl_group == "MarkdownTableWrapHeader" then
        highlighted_header_lines = highlighted_header_lines + 1
      end
    end

    h.assert_eq("every wrapped header line uses header highlight", highlighted_header_lines, header_lines)
  end)
end)

h.test("render merges contiguous border highlights for large tables", function()
  local render = require("markdown-table-wrap.render")
  local line_count = 1000
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
      plugin.setup({
        auto_preview = false,
        min_col_width = 1,
        max_col_width = choose(12),
        max_width_ratio = 1,
        quote_icon = false,
      })
      local output = render.render_table(parser.parse_all(buf)[1], plugin.config)
      local expected = vim.fn.strdisplaywidth(output.lines[1])
      for _, line in ipairs(output.lines) do
        h.assert_eq(
          string.format("case %d, max_col_width %d, %s", case, plugin.config.max_col_width, source),
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
