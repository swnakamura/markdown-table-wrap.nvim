local h = require("tests.helpers")

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

h.test("wrap ends a line at a hard break and counts wide characters as two cells", function()
  local markdown = require("markdown-table-wrap.markdown")
  local wrap = require("markdown-table-wrap.wrap")
  local texts = vim.tbl_map(function(line)
    return line.text
  end, wrap.wrap_cell(markdown.parse_inline("中文中文<br>日本語English"), 8))

  h.assert_deep_eq(
    "hard break, then a break between CJK text and an English word",
    texts,
    { "中文中文", "日本語", "English" }
  )
end)

h.test("wrap prefers punctuation boundaries and preserves link metadata", function()
  local markdown = require("markdown-table-wrap.markdown")
  local wrap = require("markdown-table-wrap.wrap")
  -- No space after the marks: with one, breaking at the space gives the same
  -- lines and the punctuation preference goes unchecked.
  h.assert_deep_eq(
    "breaks after , and ;",
    vim.tbl_map(function(line)
      return line.text
    end, wrap.wrap_cell(markdown.parse_inline("alpha,beta;gamma"), 8)),
    { "alpha,", "beta;", "gamma" }
  )

  local lines =
    wrap.wrap_cell(markdown.parse_inline("alpha, beta; [documentation](https://example.com/very/long/path)"), 12)
  local link_spans = 0

  for _, line in ipairs(lines) do
    for _, span in ipairs(line.spans) do
      if span.kind == "link" then
        link_spans = link_spans + 1
        h.assert_eq("wrapped link keeps URL", span.url, "https://example.com/very/long/path")
      end
    end
  end
  h.assert_eq("both pieces of the wrapped link keep the link span", link_spans, 2)
end)

h.test("wrap breaks CJK text between any characters except before closing and after opening marks", function()
  local markdown = require("markdown-table-wrap.markdown")
  local wrap = require("markdown-table-wrap.wrap")
  local function texts(text, limit)
    return vim.tbl_map(function(line)
      return line.text
    end, wrap.wrap_cell(markdown.parse_inline(text), limit))
  end

  h.assert_deep_eq(
    "fills past punctuation",
    texts("短い文。とても長い次の文", 12),
    { "短い文。とて", "も長い次の文" }
  )
  h.assert_deep_eq(
    "keeps an English word whole",
    texts("Neovimのプラグインを書く", 10),
    { "Neovimのプ", "ラグインを", "書く" }
  )
  h.assert_deep_eq(
    "carries a character down with a closing mark",
    texts("あいうえおかきくけこ。", 10),
    { "あいうえお", "かきくけ", "こ。" }
  )
  h.assert_deep_eq(
    "carries an opening mark down",
    texts("あいうえ「かきく」", 10),
    { "あいうえ", "「かきく」" }
  )
  h.assert_deep_eq("breaks between an English word and CJK text", texts("Vimで。", 5), { "Vim", "で。" })
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
