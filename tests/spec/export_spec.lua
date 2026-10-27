local h = require("tests.helpers")

local function table_lines()
  return {
    "| Name | Link | Note |",
    "| --- | --- | --- |",
    '| Docs | [GitHub](https://github.com) | hello, "world" |',
  }
end

h.test("CSV export escapes delimiters and quotes", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({ auto_preview = false })

  h.with_buffer(table_lines(), function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 3, 2 })
    local ok, value = plugin.export_table({ format = "csv", silent = true })
    h.assert_true("CSV export succeeds", ok)
    h.assert_eq("CSV has RFC-style escaping", value, 'Name,Link,Note\nDocs,GitHub,"hello, ""world"""')
    h.assert_eq("CSV is copied to unnamed register", vim.fn.getreg('"'), value)
    h.assert_eq("CSV is copied to yank register", vim.fn.getreg("0"), value)
  end)
end)

h.test("CSV export prevents spreadsheet formulas by default with an explicit raw opt-out", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({ auto_preview = false })

  h.with_buffer({
    "| Value |",
    "| --- |",
    "| =SUM(A1:A2) |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 3, 2 })
    local ok, safe = plugin.export_table({ format = "csv", silent = true })
    h.assert_true("safe CSV export succeeds", ok)
    h.assert_eq("formula-leading CSV cell is neutralized", safe, "Value\n'=SUM(A1:A2)")

    local raw_ok, raw = plugin.export_table({ format = "csv", csv_formula_policy = "raw", silent = true })
    h.assert_true("raw CSV opt-out succeeds", raw_ok)
    h.assert_eq("raw CSV retains the original formula", raw, "Value\n=SUM(A1:A2)")

    local tsv_ok, tsv = plugin.export_table({ format = "tsv", silent = true })
    h.assert_true("TSV export succeeds", tsv_ok)
    h.assert_eq("TSV remains exact for formula-leading data", tsv, "Value\n=SUM(A1:A2)")
  end)
end)

h.test("TSV export escapes control characters without changing table shape", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({ auto_preview = false })

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| one | `two\tthree` |",
    "| four<br>five | six |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 3, 2 })
    local ok, value = plugin.export_table({ format = "tsv", silent = true })
    h.assert_true("TSV export succeeds", ok)
    h.assert_eq("TSV escapes tabs and line breaks inside fields", value, "A\tB\none\ttwo\\tthree\nfour\\nfive\tsix")
  end)
end)

h.test("bang export includes every table while default export stays contextual", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({ auto_preview = false })

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| one | two |",
    "",
    "| C | D |",
    "| --- | --- |",
    "| three | four |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 6, 2 })
    local _, one = plugin.export_table({ format = "tsv", silent = true })
    local _, all = plugin.export_table({ format = "tsv", all = true, silent = true })
    h.assert_eq("contextual export takes the table under the cursor", one, "C\tD\nthree\tfour")
    h.assert_eq("bang-style export separates tables by a blank line", all, "A\tB\none\ttwo\n\nC\tD\nthree\tfour")
  end)
end)

h.test("export outside a table leaves registers untouched", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({ auto_preview = false })

  h.with_buffer({ "plain text", "", "| A |", "| --- |", "| one |" }, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.fn.setreg('"', "sentinel", "v")
    h.assert_false("export outside a table fails", plugin.export_table({ silent = true }))
    h.assert_false("unknown format fails", plugin.export_table({ format = "json", all = true, silent = true }))
    h.assert_eq("failed export preserves registers", vim.fn.getreg('"'), "sentinel")
  end)
end)

h.test("structured export refuses excess cells instead of dropping data", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({ auto_preview = false })

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| one | two | excess |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 3, 2 })
    vim.fn.setreg('"', "sentinel", "v")
    h.assert_false("overflow export is rejected", plugin.export_table({ format = "tsv", silent = true }))
    h.assert_eq("overflow refusal preserves registers", vim.fn.getreg('"'), "sentinel")
  end)
end)

h.test("export follows the clipboard option like a yank", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({ auto_preview = false })
  local original_clipboard = vim.o.clipboard
  local original_setreg = vim.fn.setreg
  local system_registers = {}
  vim.fn.setreg = function(register, value, kind)
    if register == "+" or register == "*" then
      system_registers[register] = { value = value, kind = kind }
      return 0
    end
    return original_setreg(register, value, kind)
  end

  local ok, err = pcall(function()
    h.with_buffer(table_lines(), function(buf)
      vim.bo[buf].filetype = "markdown"
      vim.api.nvim_win_set_cursor(0, { 3, 2 })

      vim.o.clipboard = ""
      h.assert_true("export without clipboard integration succeeds", plugin.export_table({ silent = true }))
      h.assert_deep_eq("empty clipboard option leaves system registers alone", system_registers, {})

      vim.o.clipboard = "unnamedplus"
      local _, csv = plugin.export_table({ format = "csv", silent = true })
      h.assert_deep_eq("unnamedplus receives a characterwise copy", system_registers, {
        ["+"] = { value = csv, kind = "v" },
      })

      system_registers = {}
      vim.o.clipboard = "unnamed,unnamedplus"
      local _, tsv = plugin.export_table({ format = "tsv", silent = true })
      h.assert_deep_eq("unnamed with unnamedplus writes both, like a yank", system_registers, {
        ["+"] = { value = tsv, kind = "v" },
        ["*"] = { value = tsv, kind = "v" },
      })
    end)
  end)
  vim.fn.setreg = original_setreg
  vim.o.clipboard = original_clipboard
  if not ok then
    error(err, 0)
  end
end)

h.test("MarkdownTableExport command exports TSV by default, CSV on request, and all tables with bang", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({ auto_preview = false })

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| one | two |",
    "",
    "| C |",
    "| --- |",
    "| x, y |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 3, 2 })
    vim.cmd("silent MarkdownTableExport")
    h.assert_eq("bare command exports TSV", vim.fn.getreg('"'), "A\tB\none\ttwo")
    vim.cmd("silent MarkdownTableExport! csv")
    h.assert_eq("bang command exports every table as CSV", vim.fn.getreg('"'), 'A,B\none,two\n\nC\n"x, y"')
  end)
end)
