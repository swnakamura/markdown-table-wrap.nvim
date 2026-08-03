local M = {}
local markdown = require("markdown-table-wrap.markdown")

local function trim(value)
  if type(value) == "table" then
    value = value.text or ""
  end
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function next_char_at(text, index)
  local start_col, end_col, ch = text:find("([%z\1-\127\194-\244][\128-\191]*)", index)
  if not start_col then
    return nil
  end
  return ch, start_col, end_col
end

local function backtick_run_at(text, index)
  local count = 0
  local cursor = index

  while cursor <= #text do
    local ch, _, end_col = next_char_at(text, cursor)
    if ch ~= "`" then
      break
    end
    count = count + 1
    cursor = end_col + 1
  end

  return count, cursor - 1
end

local function fence_parts(line)
  local indent, marker, tail = line:match("^( *)([`~]+)(.*)$")
  if not marker or #indent > 3 or #marker < 3 then
    return nil
  end

  local char = marker:sub(1, 1)
  if marker:match("^" .. char .. "+$") == nil then
    return nil
  end

  return char, #marker, tail
end

local function fence_opener(line)
  local char, length, tail = fence_parts(line)
  if not char or (char == "`" and tail:find("`", 1, true)) then
    return nil
  end

  return char, length
end

local function is_fence_closer(line, fence_char, fence_length)
  local char, length, tail = fence_parts(line)
  return char == fence_char and length >= fence_length and tail:match("^[ \t]*$") ~= nil
end

local function has_unescaped_pipe(line)
  local code_ticks = nil
  local escaped = false
  local index = 1

  while index <= #line do
    local ch, _, end_col = next_char_at(line, index)
    if not ch then
      break
    end

    if escaped then
      escaped = false
    elseif ch == "\\" then
      escaped = true
    elseif ch == "`" then
      local count, run_end = backtick_run_at(line, index)
      if not code_ticks then
        code_ticks = count
      elseif count == code_ticks then
        code_ticks = nil
      end
      index = run_end + 1
      goto continue
    elseif ch == "|" and not code_ticks then
      return true
    end

    index = end_col + 1
    ::continue::
  end

  return false
end

local function split_pipe_row(line)
  local cells = {}
  local current = {}
  local code_ticks = nil
  local escaped = false
  local trailing_separator = false
  local index = 1

  while index <= #line do
    local ch, _, end_col = next_char_at(line, index)
    if not ch then
      break
    end

    if escaped then
      table.insert(current, ch)
      escaped = false
      trailing_separator = false
    elseif ch == "\\" then
      escaped = true
      table.insert(current, ch)
      trailing_separator = false
    elseif ch == "`" then
      local count, run_end = backtick_run_at(line, index)
      table.insert(current, line:sub(index, run_end))
      trailing_separator = false
      if not code_ticks then
        code_ticks = count
      elseif count == code_ticks then
        code_ticks = nil
      end
      index = run_end + 1
      goto continue
    elseif ch == "|" and not code_ticks then
      table.insert(cells, trim(table.concat(current)))
      current = {}
      trailing_separator = true
    else
      table.insert(current, ch)
      if ch:match("%s") == nil then
        trailing_separator = false
      end
    end

    index = end_col + 1
    ::continue::
  end

  table.insert(cells, trim(table.concat(current)))

  local stripped = trim(line)

  if vim.startswith(stripped, "|") then
    table.remove(cells, 1)
  end

  if trailing_separator then
    table.remove(cells)
  end

  for index, cell in ipairs(cells) do
    cells[index] = markdown.parse_inline(cell:gsub("\\|", "|"))
  end

  return cells
end

local function is_separator_cell(cell)
  local value = trim(cell):gsub("%s+", "")
  value = value:gsub("^:", ""):gsub(":$", "")
  return #value >= 3 and value:match("^%-+$") ~= nil
end

local function parse_alignment(cell)
  local value = trim(cell):gsub("%s+", "")
  local starts = vim.startswith(value, ":")
  local ends = vim.endswith(value, ":")

  if starts and ends then
    return "center"
  elseif ends then
    return "right"
  elseif starts then
    return "left"
  end

  return "left"
end

local function is_separator_row(line)
  if not has_unescaped_pipe(line) then
    return false
  end

  local cells = split_pipe_row(line)
  if #cells == 0 then
    return false
  end

  for _, cell in ipairs(cells) do
    if not is_separator_cell(cell) then
      return false
    end
  end

  return true
end

local function is_tableish_line(line)
  return line and trim(line) ~= "" and has_unescaped_pipe(line)
end

-- Blockquote support: a table may sit inside one or more '>' levels. The
-- markers are stripped before parsing and drawn back by the renderer, so all
-- lines of one table must share the same quote depth. Returns the literal
-- marker prefix, the line body after it, and the quote depth.
local function split_quote(line)
  line = line or ""
  local prefix_end = 0
  local depth = 0
  local index = 1

  while true do
    local _, marker_end = line:find("^[ \t]*>[ \t]?", index)
    if not marker_end then
      break
    end
    depth = depth + 1
    prefix_end = marker_end
    index = marker_end + 1
  end

  return line:sub(1, prefix_end), line:sub(prefix_end + 1), depth
end

M.split_quote = split_quote

-- Every buffer line split once into quote prefix, body and depth, so the rest
-- of the parser works on the quoted bodies while the renderer can still redraw
-- the markers it stripped.
local function split_quote_lines(lines)
  local prefixes = {}
  local bodies = {}
  local depths = {}

  for index = 1, #lines do
    local prefix, body, depth = split_quote(lines[index])
    prefixes[index] = prefix
    bodies[index] = body
    depths[index] = depth
  end

  return { count = #lines, prefixes = prefixes, bodies = bodies, depths = depths }
end

local function starts_atx_heading(content)
  local hashes = content:match("^(#+)")
  if not hashes or #hashes > 6 then
    return false
  end

  local next_char = content:sub(#hashes + 1, #hashes + 1)
  return next_char == "" or next_char == " " or next_char == "\t"
end

local function starts_list(content)
  if content:match("^[-+*][ \t]+") then
    return true
  end

  local digits, suffix = content:match("^(%d+)([.)])")
  if not digits or #digits > 9 then
    return false
  end

  local next_char = content:sub(#digits + #suffix + 1, #digits + #suffix + 1)
  return next_char == " " or next_char == "\t"
end

local function is_thematic_break(content)
  local compact = content:gsub("[ \t]", "")
  return compact:match("^%*%*%*+$") ~= nil or compact:match("^___+$") ~= nil or compact:match("^%-%-%-+$") ~= nil
end

local html_block_tags = {
  address = true,
  article = true,
  aside = true,
  base = true,
  basefont = true,
  blockquote = true,
  body = true,
  caption = true,
  center = true,
  col = true,
  colgroup = true,
  dd = true,
  details = true,
  dialog = true,
  dir = true,
  div = true,
  dl = true,
  dt = true,
  fieldset = true,
  figcaption = true,
  figure = true,
  footer = true,
  form = true,
  frame = true,
  frameset = true,
  h1 = true,
  h2 = true,
  h3 = true,
  h4 = true,
  h5 = true,
  h6 = true,
  head = true,
  header = true,
  hr = true,
  html = true,
  iframe = true,
  legend = true,
  li = true,
  link = true,
  main = true,
  menu = true,
  menuitem = true,
  nav = true,
  noframes = true,
  ol = true,
  optgroup = true,
  option = true,
  p = true,
  param = true,
  pre = true,
  script = true,
  search = true,
  section = true,
  style = true,
  summary = true,
  table = true,
  tbody = true,
  td = true,
  tfoot = true,
  th = true,
  thead = true,
  title = true,
  tr = true,
  track = true,
  ul = true,
}

local function starts_html_block(content)
  if
    content:match("^<!%-%-")
    or content:match("^<%?")
    or content:match("^<![A-Z]")
    or content:match("^<!%[CDATA%[")
  then
    return true
  end

  local tag, tail = content:match("^</?([A-Za-z][A-Za-z0-9-]*)(.*)$")
  if not tag or not html_block_tags[tag:lower()] then
    return false
  end

  return tail == "" or tail:match("^[ \t/>]") ~= nil
end

local function starts_block(line)
  local indent, content = line:match("^( *)(.*)$")
  if #indent >= 4 then
    return true
  end

  if content:sub(1, 1) == ">" then
    return true
  end

  if fence_opener(line) then
    return true
  end

  if starts_atx_heading(content) or starts_list(content) or is_thematic_break(content) then
    return true
  end

  if starts_html_block(content) then
    return true
  end

  return content:match("^%[[^%]]+%]:[ \t]*%S") ~= nil
end

local function normalize_row(row, count)
  local normalized = {}

  for index = 1, count do
    normalized[index] = row[index] or markdown.parse_inline("")
  end

  return normalized
end

-- Callout kind ("done", "warning", ...) of the blockquote holding the table,
-- or nil for a plain quote. The marker sits on the first line of the quote
-- block at this depth, which is found by walking up from the table until the
-- quote ends (a shallower line, or no quote at all).
local function callout_kind(quote, start_lnum, depth)
  if depth == 0 then
    return nil
  end

  local first = nil
  for lnum = start_lnum - 1, 1, -1 do
    local line_depth = quote.depths[lnum]
    if line_depth < depth then
      break
    end
    if line_depth == depth then
      first = quote.bodies[lnum]
    end
  end

  local kind = first and first:match("^%s*%[!([%w_-]+)%]")
  return kind and kind:lower() or nil
end

local function parse_table_at(quote, start_lnum)
  local depth = quote.depths[start_lnum]
  local header_line = quote.bodies[start_lnum]
  local separator_line = quote.bodies[start_lnum + 1]

  if
    not separator_line
    or quote.depths[start_lnum + 1] ~= depth
    or not is_tableish_line(header_line)
    or starts_block(header_line)
    or starts_block(separator_line)
    or not is_separator_row(separator_line)
  then
    return nil
  end

  local header = split_pipe_row(header_line)
  local separator = split_pipe_row(separator_line)

  if #header == 0 then
    return nil
  end

  if #separator ~= #header then
    return nil
  end

  local align = {}
  for index = 1, #header do
    align[index] = parse_alignment(separator[index] or "---")
  end

  local rows = {}
  local end_lnum = start_lnum + 1
  local lnum = start_lnum + 2

  while lnum <= quote.count do
    local line = quote.bodies[lnum]
    if quote.depths[lnum] ~= depth or trim(line) == "" or starts_block(line) then
      break
    end

    table.insert(rows, normalize_row(split_pipe_row(line), #header))
    end_lnum = lnum
    lnum = lnum + 1
  end

  return {
    start_lnum = start_lnum,
    separator_lnum = start_lnum + 1,
    end_lnum = end_lnum,
    quote_depth = depth,
    quote_prefix = quote.prefixes[start_lnum],
    callout = callout_kind(quote, start_lnum, depth),
    header = normalize_row(header, #header),
    align = align,
    rows = rows,
  }
end

local function parse_lines(lines, stop_lnum)
  local quote = split_quote_lines(lines)
  local tables = {}
  local fenced_lines = {}
  local fence_char = nil
  local fence_length = nil
  local fence_depth = nil
  local lnum = 1

  while lnum <= quote.count and (not stop_lnum or lnum <= stop_lnum) do
    local line = quote.bodies[lnum]
    local depth = quote.depths[lnum]

    -- A fence lives inside one quote level; leaving that level ends it instead
    -- of swallowing the rest of the document.
    if fence_char and depth ~= fence_depth then
      fence_char = nil
      fence_length = nil
      fence_depth = nil
    end

    if fence_char then
      fenced_lines[lnum] = true
      if is_fence_closer(line, fence_char, fence_length) then
        fence_char = nil
        fence_length = nil
        fence_depth = nil
      end
      lnum = lnum + 1
    else
      local opener_char, opener_length = fence_opener(line)
      if opener_char then
        fenced_lines[lnum] = true
        fence_char = opener_char
        fence_length = opener_length
        fence_depth = depth
        lnum = lnum + 1
      else
        local table_info = parse_table_at(quote, lnum)
        if table_info then
          table.insert(tables, table_info)
          lnum = table_info.end_lnum + 1
        else
          lnum = lnum + 1
        end
      end
    end
  end

  return tables, fenced_lines
end

function M.parse_at_cursor(bufnr, cursor_lnum)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local tables, fenced_lines = parse_lines(lines, cursor_lnum)

  for _, table_info in ipairs(tables) do
    if cursor_lnum >= table_info.start_lnum and cursor_lnum <= table_info.end_lnum then
      return table_info
    end
  end

  if fenced_lines[cursor_lnum] then
    return nil, "MarkdownTableWrap: cursor is inside a fenced code block."
  end

  local _, current = split_quote(lines[cursor_lnum] or "")
  if not is_tableish_line(current) then
    return nil, "MarkdownTableWrap: cursor is not inside a Markdown pipe table."
  end

  return nil, "MarkdownTableWrap: no valid Markdown table separator row found."
end

function M.parse_all(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local tables = parse_lines(lines)
  return tables
end

return M
