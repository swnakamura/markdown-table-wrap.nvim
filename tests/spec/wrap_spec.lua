local h = require("tests.helpers")

h.test("wrap preserves token spans", function()
  local markdown = require("markdown-table-wrap.markdown")
  local wrap = require("markdown-table-wrap.wrap")
  local lines = wrap.wrap_cell(markdown.parse_inline("before `code` after"), 80)
  local found_code = false

  for _, span in ipairs(lines[1].spans) do
    if span.kind == "code" and lines[1].text:sub(span.start_col + 1, span.end_col) == "code" then
      found_code = true
    end
  end

  h.assert_true("wrapped code span", found_code)
end)

h.test("wrap keeps fitting code spans intact and splits oversized ones within the column", function()
  local markdown = require("markdown-table-wrap.markdown")
  local wrap = require("markdown-table-wrap.wrap")
  local fitting = wrap.wrap_cell(markdown.parse_inline("before `code value/with/path` after"), 20)
  h.assert_deep_eq(
    "fitting code span moves whole to its own line",
    vim.tbl_map(function(line)
      return line.text
    end, fitting),
    { "before", "code value/with/path", "after" }
  )

  local lines = wrap.wrap_cell(markdown.parse_inline("`tracepoint:sched:sched_process_exec`"), 12)
  local pieces = {}
  h.assert_true("oversized code span wraps", #lines > 1)
  for index, line in ipairs(lines) do
    h.assert_true("oversized code line fits " .. index, vim.api.nvim_strwidth(line.text) <= 12)
    h.assert_eq("oversized code line keeps code styling " .. index, line.spans[1] and line.spans[1].kind, "code")
    table.insert(pieces, line.text)
  end
  h.assert_eq("oversized code span keeps its text", table.concat(pieces), "tracepoint:sched:sched_process_exec")
  h.assert_eq("oversized code breaks after its own punctuation", lines[1].text, "tracepoint:")
end)

h.test("wrap never emits a line wider than its limit", function()
  local markdown = require("markdown-table-wrap.markdown")
  local wrap = require("markdown-table-wrap.wrap")
  local function texts(text, limit)
    return vim.tbl_map(function(line)
      return line.text
    end, wrap.wrap_cell(markdown.parse_inline(text), limit))
  end

  h.assert_deep_eq("a trailing space counts toward the fit", texts("word x", 5), { "word", "x" })
  h.assert_deep_eq("a tab renders as one space", texts("a\tb", 5), { "a b" })
end)

h.test("wrap handles wide characters and hard breaks", function()
  local markdown = require("markdown-table-wrap.markdown")
  local wrap = require("markdown-table-wrap.wrap")
  local lines = wrap.wrap_cell(markdown.parse_inline("中文中文<br>日本語English"), 8)

  h.assert_true("multiple hard break lines", #lines >= 2)
  for index, line in ipairs(lines) do
    h.assert_true("line width " .. index, vim.api.nvim_strwidth(line.text) <= 8)
  end
end)

h.test("wrap prefers punctuation boundaries and preserves link metadata", function()
  local markdown = require("markdown-table-wrap.markdown")
  local wrap = require("markdown-table-wrap.wrap")
  local lines =
    wrap.wrap_cell(markdown.parse_inline("alpha, beta; [documentation](https://example.com/very/long/path)"), 12)
  local link_spans = 0

  h.assert_true("punctuation creates more than one display line", #lines > 1)
  for _, line in ipairs(lines) do
    for _, span in ipairs(line.spans) do
      if span.kind == "link" then
        link_spans = link_spans + 1
        h.assert_eq("wrapped link keeps URL", span.url, "https://example.com/very/long/path")
      end
    end
  end
  h.assert_true("wrapped link remains highlighted", link_spans > 0)
end)

h.test("wrap never emits blank lines", function()
  local markdown = require("markdown-table-wrap.markdown")
  local wrap = require("markdown-table-wrap.wrap")

  local cases = {
    "スペース 混じり　全角スペースも　ある テキスト",
    "   leading spaces word word",
    "word  double  spaces here",
    "trailing spaces   ",
  }

  for _, text in ipairs(cases) do
    for _, limit in ipairs({ 8, 10, 12 }) do
      local lines = wrap.wrap_cell(markdown.parse_inline(text), limit)
      for index, line in ipairs(lines) do
        h.assert_true(
          string.format("no blank line %d for %q limit=%d", index, text, limit),
          #lines == 1 or line.text:match("%S") ~= nil
        )
      end
    end
  end
end)

h.test("wrap breaks at ideographic spaces and trims them", function()
  local markdown = require("markdown-table-wrap.markdown")
  local wrap = require("markdown-table-wrap.wrap")
  local lines = wrap.wrap_cell(markdown.parse_inline("最初の句　次の句　最後の句"), 8)

  h.assert_true("wrapped into multiple lines", #lines >= 2)
  for index, line in ipairs(lines) do
    h.assert_true(
      "line " .. index .. " has no leading space",
      line.text:sub(1, 3) ~= "　" and line.text:sub(1, 1) ~= " "
    )
    h.assert_true("line " .. index .. " has no trailing ideographic space", line.text:sub(-3) ~= "　")
  end
end)

h.test("wrap gives a character nested in emphasis its innermost span", function()
  local markdown = require("markdown-table-wrap.markdown")
  local wrap = require("markdown-table-wrap.wrap")
  local lines = wrap.wrap_cell(markdown.parse_inline("**see [doc](https://x.io)**"), 80)
  local by_kind = {}
  for _, span in ipairs(lines[1].spans) do
    by_kind[span.kind] = lines[1].text:sub(span.start_col + 1, span.end_col)
  end

  h.assert_eq("wrapped text", lines[1].text, "see doc")
  h.assert_eq("emphasis outside the link stays bold", by_kind.bold, "see ")
  h.assert_eq("link text takes the link span", by_kind.link, "doc")
end)
