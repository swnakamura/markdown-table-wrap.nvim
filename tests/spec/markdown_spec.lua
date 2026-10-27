local h = require("tests.helpers")

h.test("markdown inline token parsing", function()
  local markdown = require("markdown-table-wrap.markdown")
  local parsed = markdown.parse_inline("`code` **bold** *italic* ~~strike~~ ==mark== [link](url)")
  local kinds = {}

  for _, span in ipairs(parsed.spans) do
    kinds[span.kind] = true
  end

  h.assert_eq("inline text", parsed.text, "code bold italic strike mark link")
  h.assert_true("code span", kinds.code)
  h.assert_true("bold span", kinds.bold)
  h.assert_true("italic span", kinds.italic)
  h.assert_true("strike span", kinds.strike)
  h.assert_true("mark span", kinds.mark)
  h.assert_true("link span", kinds.link)
end)

h.test("markdown parses link variants and icons", function()
  local markdown = require("markdown-table-wrap.markdown")
  local parsed =
    markdown.parse_inline("[youtube](https://www.youtube.com) (bili)[https://bilibili.com] [[Wiki]] ![alt](image.png)")

  local kinds = {}
  local link_urls = {}
  for _, span in ipairs(parsed.spans) do
    kinds[span.kind] = span
    if span.kind == "link" then
      link_urls[span.url] = true
    end
  end

  h.assert_true("standard link", kinds.link ~= nil)
  h.assert_true("standard link url", link_urls["https://www.youtube.com"])
  h.assert_true("reversed link url", link_urls["https://bilibili.com"])
  h.assert_true("wiki link", kinds.wiki_link ~= nil)
  h.assert_true("image link", kinds.image ~= nil)
  h.assert_eq("image url", kinds.image and kinds.image.url, "image.png")

  local autolink = markdown.parse_inline("<https://example.com>").spans[1] or {}
  h.assert_eq("autolink kind", autolink.kind, "link")
  h.assert_eq("autolink url", autolink.url, "https://example.com")

  local with_icons = markdown.apply_link_icons(parsed, {
    link = {
      wiki = { icon = "W " },
      image = "I ",
      custom = {
        youtube = { pattern = "youtube", icon = "Y " },
        bilibili = { pattern = "bilibili", icon = "B " },
      },
    },
  })

  h.assert_true("youtube icon", with_icons.text:find("Y youtube", 1, true) ~= nil)
  h.assert_true("bilibili icon", with_icons.text:find("B bili", 1, true) ~= nil)
  h.assert_true("wiki icon", with_icons.text:find("W Wiki", 1, true) ~= nil)
  h.assert_true("image icon", with_icons.text:find("I alt", 1, true) ~= nil)
end)

h.test("markdown removes concealed code delimiters from link labels", function()
  local markdown = require("markdown-table-wrap.markdown")
  local parsed = markdown.parse_inline("[`overview`](curriculum/week-02/overview.md)")

  h.assert_eq("code-wrapped link display text", parsed.text, "overview")
  h.assert_eq("code-wrapped link span start", parsed.spans[1].start_col, 0)
  h.assert_eq("code-wrapped link span end", parsed.spans[1].end_col, #"overview")
  h.assert_eq("code-wrapped link URL", parsed.spans[1].url, "curriculum/week-02/overview.md")
end)

h.test("markdown display text follows CommonMark inline rules, <br> breaks and unmatched syntax", function()
  local markdown = require("markdown-table-wrap.markdown")
  local cases = {
    { "", "" },
    { "snake_case_name", "snake_case_name" },
    { "~/path/to_file_name", "~/path/to_file_name" },
    { "http://example.com/a_b_c", "http://example.com/a_b_c" },
    { "\\*not italic\\*", "*not italic*" },
    { "\\_x\\_", "_x_" },
    { "**bold _nested_ text**", "bold nested text" },
    { "[link with **bold**](u)", "link with bold" },
    { "[Foo](https://en.wikipedia.org/wiki/Foo_(bar)) tail", "Foo tail" },
    { "<https://example.com>", "https://example.com" },
    { "``code with ` tick``", "code with ` tick" },
    { "``a|b``", "a|b" },
    { "[[note|alias]]", "alias" },
    { "a<br>b", "a\nb" },
    { "a<br/>b", "a\nb" },
    { "before `unfinished", "before `unfinished" },
    { "[missing](", "[missing](" },
  }
  for _, case in ipairs(cases) do
    h.assert_eq("display text of " .. case[1], markdown.inline_to_text(case[1]), case[2])
  end
end)

h.test("markdown link icons do not duplicate a link nested in emphasis", function()
  local markdown = require("markdown-table-wrap.markdown")
  local parsed = markdown.parse_inline("**see [doc](https://youtube.com)** end")
  local with_icons = markdown.apply_link_icons(parsed, {
    link = { custom = { youtube = { pattern = "youtube", icon = "Y " } } },
  })

  h.assert_eq("icon is inserted once before the nested link", with_icons.text, "see Y doc end")
  local by_kind = {}
  for _, span in ipairs(with_icons.spans) do
    by_kind[span.kind] = with_icons.text:sub(span.start_col + 1, span.end_col)
  end
  h.assert_eq("bold span covers the icon and the link", by_kind.bold, "see Y doc")
  h.assert_eq("link span covers its icon", by_kind.link, "Y doc")
end)
