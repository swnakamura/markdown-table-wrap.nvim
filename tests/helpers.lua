local M = {
  failures = {},
  count = 0,
}

function M.fail(name, message)
  table.insert(M.failures, string.format("%s: %s", name, message))
end

function M.assert_eq(name, actual, expected)
  if actual ~= expected then
    M.fail(name, string.format("expected %s, got %s", vim.inspect(expected), vim.inspect(actual)))
  end
end

function M.assert_deep_eq(name, actual, expected)
  if not vim.deep_equal(actual, expected) then
    M.fail(name, string.format("expected %s, got %s", vim.inspect(expected), vim.inspect(actual)))
  end
end

function M.assert_true(name, value)
  if not value then
    M.fail(name, "expected truthy value")
  end
end

function M.assert_false(name, value)
  if value then
    M.fail(name, "expected falsy value")
  end
end

function M.test(name, fn)
  M.count = M.count + 1
  local ok, err = pcall(fn)
  if not ok then
    M.fail(name, err)
  end
end

-- Waits until every timer started earlier with at most `ms` has fired: timers
-- with one timeout fire in start order, so a sentinel started last fires last.
-- A fixed vim.wait would have to guess the delay and sleep it out every run.
function M.drain_timers(ms)
  local fired = false
  vim.defer_fn(function()
    fired = true
  end, ms)
  vim.wait(1000, function()
    return fired
  end, 1)
end

-- Runs every callback queued with vim.schedule so far: the queue runs in
-- order, so a sentinel queued last runs last.
function M.drain_scheduled()
  local ran = false
  vim.schedule(function()
    ran = true
  end)
  vim.wait(1000, function()
    return ran
  end, 1)
end

-- Types keys for real, so mode changes and the InsertEnter / CursorMovedI /
-- TextChangedI autocommands fire the way they do for a user. "x" runs the
-- keys immediately with :normal! semantics, which also means insert mode ends
-- once the fed keys run out. CursorMoved does not fire for keys fed this way;
-- a test fires it itself where the main loop would.
function M.feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "x", false)
end

-- The text drawn on screen line `row` of the current window's text area
-- (number, sign and fold columns left out unless `gutter` is true), trailing
-- blanks trimmed. Reads the grid as last drawn, so call :redraw first.
function M.screen_line(row, gutter)
  local info = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]
  local cells = {}
  for col = info.wincol + (gutter and 0 or info.textoff), info.wincol + info.width - 1 do
    table.insert(cells, vim.fn.screenstring(info.winrow + row - 1, col))
  end
  return (table.concat(cells):gsub("%s+$", ""))
end

-- Every extmark of namespace `ns` in `bufnr` with its details, ids left out:
-- a re-render legitimately allocates new ids.
function M.extmarks(bufnr, ns)
  local result = {}
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })) do
    local details = mark[4] or {}
    details.ns_id = nil
    table.insert(result, { mark[2], mark[3], details })
  end
  return result
end

function M.with_buffer(lines, fn)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local ok, err = pcall(fn, buf)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
  if not ok then
    error(err, 0)
  end
end

-- Headless output from vim.notify, :write and friends arrives without a
-- trailing newline, so a bare print() lands on the same screen line as
-- whatever came before it and stops matching a "^FAIL" grep. Every result
-- line therefore opens its own line.
local function report(line)
  print("\n" .. line)
end

function M.finish()
  if #M.failures > 0 then
    for _, failure in ipairs(M.failures) do
      report("FAIL " .. failure)
    end
    report(string.format("FAILED %d assertions in %d tests", #M.failures, M.count))
    -- Non-zero exit, so the acceptance command and CI see a red run.
    vim.cmd("cquit")
  end

  report(string.format("PASS %d tests", M.count))
end

return M
