local parser = require("markdown-table-wrap.parser")

local M = {}

local function notify(message, level, opts)
  if not opts.silent then
    vim.notify("MarkdownTableWrap: " .. message, level)
  end
end

local function selected_tables(opts)
  local tables = parser.parse_all(vim.api.nvim_get_current_buf())
  if opts.all then
    return tables
  end

  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  for _, table_info in ipairs(tables) do
    if lnum >= table_info.start_lnum and lnum <= table_info.end_lnum then
      return { table_info }
    end
  end
  return {}
end

local function export_value(value, format, opts)
  if format == "csv" then
    -- Spreadsheet applications evaluate formula-leading CSV fields. Make CSV
    -- safe by default while keeping a deliberate API opt-out for workflows
    -- that need byte-for-byte formula fields.
    if opts.csv_formula_policy ~= "raw" and value:find("^[=+%@%-\t\r]") then
      value = "'" .. value
    end
    if value:find('[,"\r\n]') then
      return '"' .. value:gsub('"', '""') .. '"'
    end
    return value
  end
  -- TSV has no universal quoting convention. Use the conventional C-style
  -- escapes so tabs/newlines cannot change the row/column structure.
  return (value:gsub("\\", "\\\\"):gsub("\t", "\\t"):gsub("\r", "\\r"):gsub("\n", "\\n"))
end

local function set_register(value)
  vim.fn.setreg('"', value, "v")
  vim.fn.setreg("0", value, "v")
  -- Unlike a real yank, setreg('"') never reaches the system clipboard, so
  -- 'clipboard' has to be honoured by hand.
  local clipboard = vim.split(vim.o.clipboard, ",")
  if vim.tbl_contains(clipboard, "unnamedplus") then
    vim.fn.setreg("+", value, "v")
  end
  if vim.tbl_contains(clipboard, "unnamed") then
    vim.fn.setreg("*", value, "v")
  end
end

function M.export(opts)
  opts = opts or {}
  local format = tostring(opts.format or "tsv"):lower()
  if format ~= "tsv" and format ~= "csv" then
    notify("export format must be tsv or csv", vim.log.levels.ERROR, opts)
    return false
  end

  local tables = selected_tables(opts)
  if #tables == 0 then
    notify("no Markdown table is available at the current position", vim.log.levels.INFO, opts)
    return false
  end

  local table_outputs = {}
  for _, table_info in ipairs(tables) do
    -- The parser drops cells beyond the header width; exporting would lose
    -- them silently.
    if table_info.excess_cells > 0 then
      notify(
        string.format(
          "export was refused because the table at line %d contains %d excess cell%s beyond its header",
          table_info.start_lnum,
          table_info.excess_cells,
          table_info.excess_cells == 1 and "" or "s"
        ),
        vim.log.levels.ERROR,
        opts
      )
      return false
    end

    local rows = vim.list_extend({ table_info.header }, table_info.rows)
    local row_outputs = {}
    for _, row in ipairs(rows) do
      local values = {}
      for _, cell in ipairs(row) do
        table.insert(values, export_value(cell.text, format, opts))
      end
      table.insert(row_outputs, table.concat(values, format == "csv" and "," or "\t"))
    end
    table.insert(table_outputs, table.concat(row_outputs, "\n"))
  end

  local value = table.concat(table_outputs, "\n\n")
  set_register(value)
  notify(
    string.format("exported %d table%s as %s", #tables, #tables == 1 and "" or "s", format:upper()),
    vim.log.levels.INFO,
    opts
  )
  return true, value
end

return M
