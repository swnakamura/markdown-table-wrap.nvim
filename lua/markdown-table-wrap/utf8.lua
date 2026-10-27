local M = {}

local function is_continuation(byte)
  return byte and byte >= 0x80 and byte <= 0xBF
end

local function sequence_length(text, index)
  local lead = text:byte(index)
  if not lead or lead < 0x80 then
    return 1
  end

  local length
  if lead >= 0xC2 and lead <= 0xDF then
    length = 2
  elseif lead >= 0xE0 and lead <= 0xEF then
    length = 3
  elseif lead >= 0xF0 and lead <= 0xF4 then
    length = 4
  else
    return 1
  end

  if index + length - 1 > #text then
    return 1
  end
  for offset = 1, length - 1 do
    if not is_continuation(text:byte(index + offset)) then
      return 1
    end
  end
  return length
end

-- The scanner is deliberately tolerant: an invalid byte is returned as a
-- one-byte character so later structural ASCII is never skipped.
function M.next(text, index)
  index = math.max(1, tonumber(index) or 1)
  if index > #text then
    return nil
  end
  local end_col = index + sequence_length(text, index) - 1
  return text:sub(index, end_col), index, end_col
end

-- Iteration columns follow Neovim's 0-based, end-exclusive byte convention.
function M.iter(text)
  local index = 1
  return function()
    local ch, start_col, end_col = M.next(text, index)
    if not ch then
      return nil
    end
    index = end_col + 1
    return ch, start_col - 1, end_col
  end
end

function M.prev(text, index)
  text = text or ""
  index = math.min(#text, math.max(0, (tonumber(index) or (#text + 1)) - 1))
  if index == 0 then
    return nil
  end
  while index > 0 and is_continuation(text:byte(index)) do
    index = index - 1
  end
  return M.next(text, index)
end

local function codepoint(ch)
  local first = ch:byte(1)
  if not first then
    return nil
  elseif first < 0x80 then
    return first
  elseif first < 0xE0 then
    return (first - 0xC0) * 0x40 + (ch:byte(2) - 0x80)
  elseif first < 0xF0 then
    return (first - 0xE0) * 0x1000 + (ch:byte(2) - 0x80) * 0x40 + (ch:byte(3) - 0x80)
  end
  return (first - 0xF0) * 0x40000 + (ch:byte(2) - 0x80) * 0x1000 + (ch:byte(3) - 0x80) * 0x40 + (ch:byte(4) - 0x80)
end

-- Lua patterns only recognise ASCII word bytes.  Markdown emphasis boundaries
-- must also avoid splitting accented, CJK, and other Unicode words.  Treat
-- non-ASCII letters/numbers as word-like while explicitly leaving common
-- Unicode punctuation and symbols as boundaries.
function M.is_word(ch)
  if not ch or ch == "" then
    return false
  end
  if #ch == 1 then
    return ch:match("[%w_]") ~= nil
  end
  local value = codepoint(ch)
  if not value then
    return false
  end
  if
    value == 0x00A0
    or value == 0x1680
    or (value >= 0x2000 and value <= 0x206F)
    or (value >= 0x3000 and value <= 0x303F)
    or (value >= 0xFE10 and value <= 0xFE1F)
    or (value >= 0xFE30 and value <= 0xFE6F)
    or (value >= 0xFF00 and value <= 0xFF0F)
    or (value >= 0xFF1A and value <= 0xFF20)
    or (value >= 0xFF3B and value <= 0xFF40)
    or (value >= 0xFF5B and value <= 0xFF65)
    or (value >= 0x1F000 and value <= 0x1FAFF)
  then
    return false
  end
  return true
end

return M
