local width = require("markdown-table-wrap.width")
local utf8 = require("markdown-table-wrap.utf8")

local M = {}

local break_chars = {
  [" "] = true,
  ["\t"] = true,
  ["　"] = true,
  [","] = true,
  [";"] = true,
  ["/"] = true,
}

-- Wide (CJK) text breaks between any two characters, as Japanese and Chinese
-- typesetting does, instead of only after punctuation; these keep a closing
-- mark off the start of a line and an opening one off the end.
local function char_set(text)
  local set = {}
  for ch in utf8.iter(text) do
    set[ch] = true
  end
  return set
end

local no_line_start = char_set("、。，．！？：；）」』】〕〉》］｝ー〜…・,.;:!?)]}")
local no_line_end = char_set("（「『【〔〈《［｛([{")

-- Inside inline code, a token too long for its column is split after one of
-- these rather than at an arbitrary character.
local code_break_chars = {
  [":"] = true,
  ["."] = true,
  ["/"] = true,
  ["_"] = true,
  ["-"] = true,
  ["="] = true,
}

local whitespace_chars = {
  [" "] = true,
  ["\t"] = true,
  ["　"] = true,
}

-- Spans nest (a link inside bold); a character takes its innermost span.
local function span_kind_at(spans, start_col)
  local found = nil
  for _, span in ipairs(spans or {}) do
    if
      start_col >= span.start_col
      and start_col < span.end_col
      and (not found or span.end_col - span.start_col < found.end_col - found.start_col)
    then
      found = span
    end
  end
  return found or "text"
end

local function styled_chars(cell)
  if type(cell) ~= "table" then
    cell = { text = tostring(cell or ""), spans = {} }
  end

  local result = {}
  for ch, start_col in utf8.iter(cell.text or "") do
    -- nvim_strwidth, which sizes the columns, counts a tab as one cell, but a
    -- tab is drawn up to the next tabstop, so it cannot be kept as is.
    if ch == "\t" then
      ch = " "
    end
    local span = span_kind_at(cell.spans, start_col)
    if type(span) == "table" then
      table.insert(result, { text = ch, kind = span.kind, url = span.url })
    else
      table.insert(result, { text = ch, kind = span })
    end
  end

  local coalesced = {}
  for _, item in ipairs(result) do
    local last = coalesced[#coalesced]
    if item.kind == "code" and last and last.kind == "code" then
      last.text = last.text .. item.text
    else
      table.insert(coalesced, item)
    end
  end

  return coalesced
end

local function line_from_chars(chars)
  local text = {}
  local spans = {}
  local offset = 0
  local current_kind = nil
  local current_url = nil
  local current_start = nil

  local function close_span()
    if current_kind and current_kind ~= "text" and current_start and current_start < offset then
      table.insert(spans, {
        start_col = current_start,
        end_col = offset,
        kind = current_kind,
        url = current_url,
      })
    end
    current_kind = nil
    current_url = nil
    current_start = nil
  end

  for _, item in ipairs(chars) do
    table.insert(text, item.text)

    if item.kind ~= current_kind or item.url ~= current_url then
      close_span()
      current_kind = item.kind
      current_url = item.url
      current_start = offset
    end

    offset = offset + #item.text
  end

  close_span()

  return {
    text = table.concat(text):gsub("%s+$", ""),
    spans = spans,
  }
end

local function chars_text(chars)
  local parts = {}
  for index, item in ipairs(chars) do
    parts[index] = item.text
  end
  return table.concat(parts)
end

local function slice_chars(chars, start_index, end_index)
  local result = {}
  for index = start_index, end_index do
    table.insert(result, chars[index])
  end
  return result
end

-- Drop leading whitespace so a continuation line never starts with the
-- space we broke at (which would otherwise trim down to a blank line).
local function drop_leading_whitespace(chars)
  while chars[1] and whitespace_chars[chars[1].text] do
    table.remove(chars, 1)
  end
  return chars
end

local function append_line(lines, chars)
  -- Trim trailing whitespace char-wise (covers the ideographic space U+3000,
  -- which the byte-wise %s trim in line_from_chars cannot touch) and skip
  -- lines that would render blank.
  while chars[#chars] and whitespace_chars[chars[#chars].text] do
    table.remove(chars, #chars)
  end

  if #chars == 0 then
    return
  end

  table.insert(lines, line_from_chars(chars))
end

-- Inline code is kept as one unbreakable item while it fits its column; one
-- wider than the column is split into characters so it can wrap.
local function expand_oversized_item(item, limit)
  if item.kind ~= "code" or width.strwidth(item.text) <= limit then
    return { item }
  end

  local pieces = {}
  for ch in utf8.iter(item.text) do
    table.insert(pieces, { text = ch, kind = item.kind, url = item.url })
  end
  return pieces
end

local function is_wide(item)
  return item.kind ~= "code" and width.strwidth(item.text) > 1
end

-- Breaks are decided between two neighbours so a CJK pair can veto a break
-- that the character on either side would otherwise allow.
local function breaks_between(prev, item)
  if no_line_start[item.text] or no_line_end[prev.text] then
    return whitespace_chars[prev.text] == true
  end
  return break_chars[prev.text]
    or (prev.kind == "code" and code_break_chars[prev.text])
    or is_wide(prev)
    or is_wide(item)
end

local function wrap_segment(chars, limit, lines)
  local current = {}
  local last_break = nil

  for _, source_item in ipairs(chars) do
    for _, item in ipairs(expand_oversized_item(source_item, limit)) do
      if #current == 0 and whitespace_chars[item.text] then
        -- Never start a line with whitespace
        goto continue
      end

      if #current > 0 and breaks_between(current[#current], item) then
        last_break = #current
      end

      -- Measured untrimmed: "word " is five cells wide even though a line
      -- broken there renders as "word". Breaking at last_break can leave a
      -- tail that still does not fit with the item, hence the loop.
      while #current > 0 and width.strwidth(chars_text(current) .. item.text) > limit do
        if last_break and last_break < #current then
          append_line(lines, slice_chars(current, 1, last_break))
          current = drop_leading_whitespace(slice_chars(current, last_break + 1, #current))
        else
          append_line(lines, current)
          current = {}
        end
        last_break = nil
        if #current > 0 and breaks_between(current[#current], item) then
          last_break = #current
        end
      end

      if #current == 0 and whitespace_chars[item.text] then
        goto continue
      end

      table.insert(current, item)

      ::continue::
    end
  end

  if #current > 0 then
    append_line(lines, current)
  end
end

function M.wrap_cell(cell, limit)
  if limit <= 0 or width.strwidth(cell) == 0 then
    return { { text = "", spans = {} } }
  end

  local lines = {}
  local segment = {}

  for _, item in ipairs(styled_chars(cell)) do
    if item.text == "\n" then
      wrap_segment(segment, limit, lines)
      segment = {}
    else
      table.insert(segment, item)
    end
  end

  wrap_segment(segment, limit, lines)

  if #lines == 0 then
    return { { text = "", spans = {} } }
  end

  return lines
end

return M
