local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(source, ":p:h:h")

package.path = table.concat({
  root .. "/?.lua",
  root .. "/?/init.lua",
  package.path,
}, ";")

local specs = {
  "tests.spec.markdown_spec",
  "tests.spec.parser_spec",
  "tests.spec.width_spec",
  "tests.spec.wrap_spec",
  "tests.spec.render_spec",
  "tests.spec.theme_spec",
  "tests.spec.config_spec",
  "tests.spec.inline_spec",
  "tests.spec.reader_spec",
  "tests.spec.nav_spec",
  "tests.spec.mode_spec",
  "tests.spec.system_spec",
  "tests.spec.lifecycle_spec",
  "tests.spec.defaults_spec",
}

-- A spec that throws while loading used to abort this file, which meant
-- finish() never ran, no PASS/FAIL line was printed, and the trailing -c
-- "qa!" exited 0 -- a red run that looked green. Load failures are recorded
-- as failures instead, and the harness always gets to finish.
--
-- After a load failure the reported test count is not a coverage indicator:
-- an error partway through a spec silently skips the rest of that file, and
-- the single failure counted for the spec itself can exactly offset the tests
-- that were lost, so a broken run can report the same total as a clean one.
-- The exit code and the FAILED line stay reliable -- judge a run by those.
local h = require("tests.helpers")

local ok, err = xpcall(function()
  for _, spec in ipairs(specs) do
    local loaded, load_err = pcall(require, spec)
    if not loaded then
      h.count = h.count + 1
      h.fail(spec, "failed to load: " .. tostring(load_err))
    end
  end

  h.finish()
end, debug.traceback)

if not ok then
  print("\nFAIL test harness error: " .. tostring(err))
  vim.cmd("cquit")
end
