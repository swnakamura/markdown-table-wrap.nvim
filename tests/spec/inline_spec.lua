local h = require("tests.helpers")

h.test("inline whole-buffer render uses extmarks and conceal options", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({
    preview_mode = "inline",
    debounce_ms = 0,
    render_all = true,
    auto_preview = true,
    max_col_width = 80,
  })

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| **bold** | [link](url) |",
    "",
    "| C | D |",
    "| --- | --- |",
    "| `code` | ~~strike~~ |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.wo.conceallevel = 0
    vim.wo.concealcursor = ""
    vim.wo.wrap = true
    plugin.refresh_auto({ force = true })

    local marks = vim.api.nvim_buf_get_extmarks(buf, inline.namespace(), 0, -1, { details = true })
    h.assert_true("inline marks", #marks > 0)
    h.assert_eq("conceallevel set", vim.wo.conceallevel, 2)
    -- concealcursor and wrap are left alone: the revealed cursor row must
    -- show (and soft-wrap) the raw source in every mode.
    h.assert_eq("concealcursor untouched", vim.wo.concealcursor, "")
    h.assert_true("wrap untouched while inline replace is active", vim.wo.wrap)

    inline.clear(buf)
    h.assert_eq("conceallevel restored", vim.wo.conceallevel, 0)
  end)
end)

h.test("cursor wrap scope preserves prose wrapping outside tables", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({
    preview_mode = "inline",
    debounce_ms = 0,
    render_all = true,
    auto_preview = true,
    -- Opt in: 'wrap' is left alone by default so the revealed cursor row can
    -- soft-wrap, and inline_wrap_scope is only consulted once this is true.
    inline_disable_wrap = true,
    inline_wrap_scope = "cursor",
  })

  h.with_buffer({
    "A long Markdown paragraph should wrap normally.",
    "",
    "| A | B |",
    "| --- | --- |",
    "| one | two |",
    "",
    "Another long Markdown paragraph should also wrap normally.",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.wo.wrap = true

    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    plugin.refresh_auto({ force = true })
    h.assert_true("wrap is kept outside the table", vim.wo.wrap)

    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    inline.update_wrap_for_cursor(buf)
    h.assert_false("wrap is disabled inside the table", vim.wo.wrap)

    vim.api.nvim_win_set_cursor(0, { 7, 0 })
    inline.update_wrap_for_cursor(buf)
    h.assert_true("wrap is restored after leaving the table", vim.wo.wrap)

    inline.clear(buf)
    h.assert_true("wrap remains enabled after clearing", vim.wo.wrap)
  end)
end)

h.test("floating preview includes highlight extmarks", function()
  local parser = require("markdown-table-wrap.parser")
  local render = require("markdown-table-wrap.render")

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| `code` | [link](url) |",
  }, function(buf)
    local parsed = parser.parse_at_cursor(buf, 3)
    local rendered = render.render_table(parsed, {
      max_width_ratio = 0.9,
      min_col_width = 4,
      max_col_width = 80,
      use_unicode_border = true,
      table_border = "rounded",
      row_separator = true,
      border = "rounded",
    })
    local float_buf, win = render.open_float(rendered, { border = "rounded" })
    local marks = vim.api.nvim_buf_get_extmarks(float_buf, -1, 0, -1, { details = true })
    h.assert_true("float highlight marks", #marks > 0)
    vim.api.nvim_win_close(win, true)
  end)
end)

h.test("floating preview gx opens the rendered link under the cursor", function()
  local parser = require("markdown-table-wrap.parser")
  local render = require("markdown-table-wrap.render")
  local opened = nil
  local original_open = vim.ui.open
  vim.ui.open = function(url)
    opened = url
  end

  h.with_buffer({
    "| Name | Link |",
    "| --- | --- |",
    "| Video | [youtube](https://www.youtube.com) |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    local parsed = parser.parse_at_cursor(buf, 3)
    local rendered = render.render_table(parsed, {
      max_width_ratio = 0.9,
      min_col_width = 4,
      max_col_width = 80,
      use_unicode_border = true,
      table_border = "rounded",
      row_separator = true,
      border = "rounded",
    })
    local _, win = render.open_float(rendered, { border = "rounded" })
    local target = nil

    for row, line_object in ipairs(rendered.line_objects) do
      for _, chunk in ipairs(line_object.chunks or {}) do
        if chunk.kind == "link" and chunk.url then
          target = { row, chunk.start_col }
          break
        end
      end
      if target then
        break
      end
    end

    h.assert_true("floating link target", target ~= nil)
    vim.api.nvim_win_set_cursor(win, target)
    vim.cmd("normal gx")
    h.assert_eq("opened floating URL", opened, "https://www.youtube.com")
    vim.api.nvim_win_close(win, true)
  end)

  vim.ui.open = original_open
end)

h.test("floating preview preserves inline rendering in render_all mode", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({
    preview_mode = "inline",
    debounce_ms = 0,
    render_all = true,
    auto_preview = true,
    max_col_width = 80,
  })

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| 1 | 2 |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    plugin.refresh_auto({ force = true })
    h.assert_true("inline active before float", inline.is_active(buf))

    plugin.float_preview()
    h.assert_true("inline active after float", inline.is_active(buf))

    if plugin.state.win and vim.api.nvim_win_is_valid(plugin.state.win) then
      vim.api.nvim_win_close(plugin.state.win, true)
    end
    inline.clear(buf)
  end)
end)

h.test("inline viewport scroll changes rendered table slice", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({
    preview_mode = "inline",
    debounce_ms = 0,
    render_all = true,
    auto_preview = true,
    min_col_width = 4,
    max_col_width = 8,
    inline_viewport_scrolling = true,
  })

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| one | alpha beta gamma delta epsilon |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    plugin.refresh_auto({ force = true })

    local function first_overlay_text()
      local marks = vim.api.nvim_buf_get_extmarks(buf, inline.namespace(), 0, -1, { details = true })
      for _, mark in ipairs(marks) do
        if mark[2] == 0 and mark[4] and mark[4].virt_text then
          local parts = {}
          for _, chunk in ipairs(mark[4].virt_text) do
            table.insert(parts, chunk[1])
          end
          return table.concat(parts)
        end
      end
      return ""
    end

    local before = first_overlay_text()
    vim.cmd("MarkdownTableScrollDown")
    local after = first_overlay_text()
    vim.cmd("MarkdownTableScrollBottom")
    local bottom = first_overlay_text()
    vim.cmd("MarkdownTableScrollTop")
    local top = first_overlay_text()

    h.assert_true("before has top border", before:find("╭", 1, true) ~= nil)
    h.assert_true("after scroll advances viewport", after ~= before)
    h.assert_true("bottom changes viewport", bottom ~= before)
    h.assert_eq("top restores viewport", top, before)

    inline.clear(buf)
  end)
end)

h.test("row-anchored inline replace hides rows with conceal_lines, no overlays", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| 1 | 2 |",
    "",
    "after",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"

    plugin.setup({
      preview_mode = "inline",
      debounce_ms = 0,
      render_all = true,
      auto_preview = true,
    })
    vim.api.nvim_win_set_cursor(0, { 4, 0 }) -- outside the table
    plugin.refresh_auto({ force = true })

    local marks = vim.api.nvim_buf_get_extmarks(buf, inline.namespace(), 0, -1, { details = true })
    local concealed_lines = 0
    local has_virt_text = false
    local has_inline_conceal = false
    local virt_line_count = 0

    for _, mark in ipairs(marks) do
      local details = mark[4] or {}
      if details.conceal_lines == "" then
        concealed_lines = concealed_lines + 1
      end
      if details.conceal == "" then
        has_inline_conceal = true
      end
      if details.virt_text then
        has_virt_text = true
      end
      virt_line_count = virt_line_count + #(details.virt_lines or {})
    end

    h.assert_eq("every source row hidden via conceal_lines", concealed_lines, 3)
    -- Inline conceal keeps a wrapped long line's soft-wrap screen rows,
    -- which rendered as blank lines; conceal_lines collapses them entirely.
    h.assert_false("no inline conceal used", has_inline_conceal)
    h.assert_false("no virt_text overlays used", has_virt_text)
    h.assert_true("whole rendered table present as virtual lines", virt_line_count >= 5)

    inline.clear(buf)
  end)
end)

h.test("row-anchored replace draws line numbers into rendered rows", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| 1 | 2 |",
    "",
    "after",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.wo.number = true

    plugin.setup({
      preview_mode = "inline",
      debounce_ms = 0,
      render_all = true,
      auto_preview = true,
    })
    vim.api.nvim_win_set_cursor(0, { 4, 0 }) -- outside the table
    plugin.refresh_auto({ force = true })

    local marks = vim.api.nvim_buf_get_extmarks(buf, inline.namespace(), 0, -1, { details = true })
    local numbers = {}
    local leftcol = false

    for _, mark in ipairs(marks) do
      local details = mark[4] or {}
      if details.virt_lines then
        leftcol = leftcol or details.virt_lines_leftcol == true
        for _, line in ipairs(details.virt_lines) do
          local first = line[1]
          if first and first[2] == "LineNr" then
            local digits = first[1]:match("^%s*(%d+)%s$")
            if digits then
              table.insert(numbers, tonumber(digits))
            end
          end
        end
      end
    end

    h.assert_true("virtual lines start at window leftcol", leftcol)
    h.assert_eq("one line number per source row", #numbers, 3)
    h.assert_eq("first source line number", numbers[1], 1)
    h.assert_eq("second source line number", numbers[2], 2)
    h.assert_eq("third source line number", numbers[3], 3)

    vim.wo.number = false
    inline.clear(buf)
  end)
end)

h.test("row-anchored replace shows relative numbers with 'relativenumber'", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| 1 | 2 |",
    "",
    "after",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.wo.relativenumber = true

    plugin.setup({
      preview_mode = "inline",
      debounce_ms = 0,
      render_all = true,
      auto_preview = true,
    })

    local function rendered_numbers()
      local numbers = {}
      for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, inline.namespace(), 0, -1, { details = true })) do
        for _, line in ipairs((mark[4] or {}).virt_lines or {}) do
          local first = line[1]
          if first and first[2] == "LineNr" then
            local digits = first[1]:match("^%s*(%d+)%s$")
            if digits then
              table.insert(numbers, tonumber(digits))
            end
          end
        end
      end
      return numbers
    end

    vim.api.nvim_win_set_cursor(0, { 4, 0 }) -- outside the table
    plugin.refresh_auto({ force = true })

    h.assert_eq("distances from cursor row 4", table.concat(rendered_numbers(), ","), "3,2,1")

    vim.api.nvim_win_set_cursor(0, { 1, 0 }) -- header row inside the table
    inline.update_reveal(buf)

    -- Row 1 is revealed natively; rows 2 and 3 render at distances 1 and 2.
    h.assert_eq("distances from cursor row 1", table.concat(rendered_numbers(), ","), "1,2")

    vim.wo.relativenumber = false
    inline.clear(buf)
  end)
end)

h.test("off-screen tables skip relative-number re-attach until visible", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  local lines = {
    "| A | B |",
    "| --- | --- |",
    "| 1 | 2 |",
  }
  table.insert(lines, "")
  for i = 1, 200 do
    table.insert(lines, "filler " .. i)
  end

  h.with_buffer(lines, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.wo.relativenumber = true

    plugin.setup({
      preview_mode = "inline",
      debounce_ms = 0,
      render_all = true,
      auto_preview = true,
    })

    local function rendered_numbers()
      local numbers = {}
      for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, inline.namespace(), 0, -1, { details = true })) do
        for _, line in ipairs((mark[4] or {}).virt_lines or {}) do
          local first = line[1]
          if first and first[2] == "LineNr" then
            local digits = first[1]:match("^%s*(%d+)%s$")
            if digits then
              table.insert(numbers, tonumber(digits))
            end
          end
        end
      end
      return table.concat(numbers, ",")
    end

    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    plugin.refresh_auto({ force = true })
    h.assert_eq("initial distances from row 4", rendered_numbers(), "3,2,1")

    -- Scroll far below: the table leaves the viewport, so cursor moves must
    -- leave its (now stale) numbers untouched.
    vim.cmd("normal! G")
    inline.update_reveal(buf)
    h.assert_true("table is off screen", vim.fn.line("w0") > 4)
    local stale = rendered_numbers()
    vim.api.nvim_win_set_cursor(0, { 150, 0 })
    inline.update_reveal(buf)
    h.assert_eq("off-screen table numbers untouched", rendered_numbers(), stale)

    -- Back to the top: the table is visible again and must catch up.
    vim.cmd("normal! gg")
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    inline.update_reveal(buf)
    h.assert_eq("numbers catch up when visible again", rendered_numbers(), "3,2,1")

    vim.wo.relativenumber = false
    inline.clear(buf)
  end)
end)

h.test("stable height: table keeps constant screen height while cursor moves inside", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| 1 | 2 |",
    "",
    "after",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"

    plugin.setup({
      preview_mode = "inline",
      debounce_ms = 0,
      render_all = true,
      auto_preview = true,
    })
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    plugin.refresh_auto({ force = true })

    -- Screen rows the table occupies: all attached virtual lines plus the
    -- revealed raw cursor row (when inside).
    local function virt_total()
      local total = 0
      for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, inline.namespace(), 0, -1, { details = true })) do
        total = total + #((mark[4] or {}).virt_lines or {})
      end
      return total
    end

    local outside = virt_total()

    local totals = {}
    for row = 1, 3 do
      vim.api.nvim_win_set_cursor(0, { row, 0 })
      inline.update_reveal(buf)
      -- raw line height is 1 here (short lines, no wrap)
      table.insert(totals, virt_total() + 1)
    end

    h.assert_eq("row 1 and row 2 equal height", totals[1], totals[2])
    h.assert_eq("row 2 and row 3 equal height", totals[2], totals[3])
    -- Whole table rendered outside == flat count; inside it stays at that
    -- height too because the filler absorbs the reveal swap.
    h.assert_eq("inside height matches outside height", totals[1], outside)

    inline.clear(buf)
  end)
end)

h.test("row-anchored replace omits number column when 'number' is off", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| 1 | 2 |",
    "",
    "after",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.wo.number = false
    vim.wo.relativenumber = false

    plugin.setup({
      preview_mode = "inline",
      debounce_ms = 0,
      render_all = true,
      auto_preview = true,
    })
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    plugin.refresh_auto({ force = true })

    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, inline.namespace(), 0, -1, { details = true })) do
      local details = mark[4] or {}
      if details.virt_lines then
        h.assert_false("no leftcol without a number column", details.virt_lines_leftcol == true)
        for _, line in ipairs(details.virt_lines) do
          h.assert_false("no LineNr prefix without a number column", line[1] and line[1][2] == "LineNr")
        end
      end
    end

    inline.clear(buf)
  end)
end)

h.test("inline viewport toggle switches between sliced and full rendering", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({
    preview_mode = "inline",
    debounce_ms = 0,
    render_all = true,
    auto_preview = true,
    min_col_width = 4,
    max_col_width = 8,
    inline_viewport_scrolling = true,
  })

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| one | alpha beta gamma delta epsilon |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    plugin.refresh_auto({ force = true })

    local function has_virt_lines()
      local marks = vim.api.nvim_buf_get_extmarks(buf, inline.namespace(), 0, -1, { details = true })
      for _, mark in ipairs(marks) do
        if mark[4] and mark[4].virt_lines then
          return true
        end
      end
      return false
    end

    h.assert_false("viewport mode avoids extra virt_lines", has_virt_lines())
    vim.cmd("MarkdownTableToggleInlineViewport")
    h.assert_false("viewport disabled", plugin.get_buffer_config(buf).inline_viewport_scrolling)
    h.assert_true("full mode uses virt_lines", has_virt_lines())

    vim.cmd("MarkdownTableToggleInlineViewport")
    h.assert_true("viewport enabled", plugin.get_buffer_config(buf).inline_viewport_scrolling)
    h.assert_false("viewport mode restored", has_virt_lines())

    inline.clear(buf)
  end)
end)

h.test("row-anchored lines keep their original rendered line index", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({
    preview_mode = "inline",
    debounce_ms = 0,
    render_all = true,
    auto_preview = true,
    inline_viewport_scrolling = false,
    row_separator = true,
  })

  h.with_buffer({
    "| 成员 | 分工 |",
    "| --- | --- |",
    "| 组长 | 项目规划 |",
    "| 成员 A | 数据集整理 |",
    "| 成员 B | Web 系统实现 |",
    "| 成员 C | 报告撰写 |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    plugin.refresh_auto({ force = true })

    local marks = vim.api.nvim_buf_get_extmarks(buf, inline.namespace(), 0, -1, { details = true })
    local member_b_chunks = nil
    local member_b_row = nil

    local function scan_chunks(chunks, row)
      local text = {}
      for _, chunk in ipairs(chunks) do
        table.insert(text, chunk[1])
      end

      if table.concat(text):find("成员 B", 1, true) then
        member_b_chunks = chunks
        member_b_row = row
      end
    end

    for _, mark in ipairs(marks) do
      local details = mark[4] or {}
      if details.virt_text then
        scan_chunks(details.virt_text, mark[2])
      end
      for _, virt_line in ipairs(details.virt_lines or {}) do
        scan_chunks(virt_line, mark[2])
      end
    end

    h.assert_true("member B is rendered", member_b_chunks ~= nil)
    h.assert_true("member B rendered as a virtual line", member_b_row ~= nil)

    local groups = {}
    for _, chunk in ipairs(member_b_chunks) do
      groups[chunk[2]] = true
    end

    h.assert_false("member B is not treated as table header", groups.MarkdownTableWrapHeader)
    h.assert_true("member B keeps normal inline highlight", groups.MarkdownTableWrapInline)

    inline.clear(buf)
  end)
end)

h.test("inline insert mode highlights every wrapped header line", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({
    preview_mode = "inline",
    inline_mode = "insert",
    auto_preview = false,
    render_all = true,
    min_col_width = 4,
    max_col_width = 6,
  })

  h.with_buffer({
    "| a header that wraps | B |",
    "| --- | --- |",
    "| value | other |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    plugin.refresh_auto({ force = true })

    local highlighted_header_lines = 0
    local marks = vim.api.nvim_buf_get_extmarks(buf, inline.namespace(), 0, -1, { details = true })
    for _, mark in ipairs(marks) do
      for _, virt_line in ipairs((mark[4] or {}).virt_lines or {}) do
        for _, chunk in ipairs(virt_line) do
          if chunk[2] == "MarkdownTableWrapHeader" then
            highlighted_header_lines = highlighted_header_lines + 1
            break
          end
        end
      end
    end

    h.assert_true("wrapped header spans multiple virtual lines", highlighted_header_lines > 1)
    inline.clear(buf)
  end)
end)

h.test("cursor row is revealed as raw source and restored on leave", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({
    preview_mode = "inline",
    debounce_ms = 0,
    render_all = true,
    auto_preview = true,
    row_separator = true,
  })

  local long_line = "| alpha | " .. string.rep("wrapping content ", 12) .. "|"

  h.with_buffer({
    "| Name | Description |",
    "| --- | --- |",
    long_line,
    "| beta | short |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"

    -- Per-row state: conceal_lines mark and attached virt_lines blocks
    local function row_state(row)
      local marks = vim.api.nvim_buf_get_extmarks(buf, inline.namespace(), { row, 0 }, { row, -1 }, { details = true })
      local state = { conceal_lines = false, blocks = 0, block_lines = 0 }
      for _, mark in ipairs(marks) do
        local details = mark[4] or {}
        if details.conceal_lines == "" then
          state.conceal_lines = true
        end
        if details.virt_lines then
          state.blocks = state.blocks + 1
          state.block_lines = state.block_lines + #details.virt_lines
        end
      end
      return state
    end

    -- Cursor on the long row (0-based row 2): the rendered blocks split
    -- around it. Neovim reveals the raw line itself (conceal_lines is
    -- inactive on the cursor line), soft-wrapping at the window width.
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    plugin.refresh_auto({ force = true })

    -- Own text height of a row: total minus filler (virt_lines below a
    -- previous row are counted as the next row's fill)
    local function text_rows(row)
      local height = vim.api.nvim_win_text_height(0, { start_row = row, end_row = row })
      return height.all - height.fill
    end

    local cursor_row = row_state(2)
    h.assert_true("cursor row still carries conceal_lines", cursor_row.conceal_lines)
    h.assert_eq("blocks split around the cursor row", cursor_row.blocks, 2)
    -- ...and Neovim auto-reveals it on screen:
    h.assert_true("cursor row is revealed and soft-wraps", text_rows(2) >= 2)

    local other = row_state(3)
    h.assert_eq("other rows have no blocks", other.blocks, 0)
    h.assert_eq("other row is fully hidden", text_rows(3), 0)

    -- The cursor row's own rendered lines are excluded from the blocks:
    -- blocks hold strictly fewer lines than the whole rendered table.
    local whole = 0
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, inline.namespace(), 0, -1, { details = true })) do
      whole = whole + #((mark[4] or {}).virt_lines or {})
    end
    h.assert_true("cursor row content not duplicated in blocks", whole == cursor_row.block_lines)

    -- Move to another row: blocks re-split there
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    inline.update_reveal(buf)

    h.assert_eq("blocks moved off the left row", row_state(2).blocks, 0)
    -- Last row: the below-block is empty, so only the above-block remains
    h.assert_true("blocks split around the new cursor row", row_state(3).blocks >= 1)
    h.assert_eq("left row hidden again", text_rows(2), 0)

    inline.clear(buf)
  end)
end)

h.test("insert mode keeps the table rendered with the cursor row revealed", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({
    preview_mode = "inline",
    debounce_ms = 0,
    render_all = true,
    auto_preview = true,
  })

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| 1 | 2 |",
    "| 3 | 4 |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 3, 2 })
    plugin.refresh_auto({ force = true })
    h.assert_true("rendered before insert", inline.is_active(buf))

    -- Insert mode: refresh no longer clears the rendering
    vim.cmd("startinsert")
    plugin.refresh_auto({ force = true })
    h.assert_true("still rendered in insert mode", inline.is_active(buf))
    vim.cmd("stopinsert")

    inline.clear(buf)
  end)
end)

h.test("table link opener uses source cell urls", function()
  local nav = require("markdown-table-wrap.nav")
  local opened = nil
  local original_open = vim.ui.open
  vim.ui.open = function(url)
    opened = url
  end

  h.with_buffer({
    "| Name | Link |",
    "| --- | --- |",
    "| Video | [YouTube](https://youtube.com/watch) |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 3, 12 })
    h.assert_true("open table link", nav.open_link())
    h.assert_eq("opened url", opened, "https://youtube.com/watch")
  end)

  vim.ui.open = original_open
end)

h.test("table link opener falls back to the only parsed table link", function()
  local nav = require("markdown-table-wrap.nav")
  local opened = nil
  local original_open = vim.ui.open
  vim.ui.open = function(url)
    opened = url
  end

  h.with_buffer({
    "| Name | Link |",
    "| --- | --- |",
    "| Video | [youtube](https://www.youtube.com) |",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 3, 2 })
    h.assert_true("open only parsed table link", nav.open_link())
    h.assert_eq("opened parsed table URL", opened, "https://www.youtube.com")
  end)

  vim.ui.open = original_open
end)

h.test("inline render draws the blockquote marker in front of rendered rows", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({
    preview_mode = "inline",
    debounce_ms = 0,
    render_all = true,
    auto_preview = true,
    max_col_width = 80,
    inline_line_numbers = false,
    quote_icon = ">",
  })

  h.with_buffer({
    "> | A | B |",
    "> | --- | --- |",
    "> | x | y |",
    "",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    plugin.refresh_auto({ force = true })

    local marks = vim.api.nvim_buf_get_extmarks(buf, inline.namespace(), 0, -1, { details = true })
    local seen = false

    for _, mark in ipairs(marks) do
      for _, line in ipairs(mark[4].virt_lines or {}) do
        seen = true
        h.assert_eq("quote marker text", line[1][1], "> ")
        h.assert_eq("quote marker highlight", line[1][2], "MarkdownTableWrapQuote")
      end
    end

    h.assert_true("rendered virtual lines exist", seen)
    inline.clear(buf)
  end)
end)

h.test("quoted table navigation skips the quote marker", function()
  local nav = require("markdown-table-wrap.nav")

  local spans = nav.spans("> | ab | cd |")
  h.assert_eq("quoted cell count", #spans, 2)
  h.assert_eq("first quoted cell", ("> | ab | cd |"):sub(spans[1].start_col + 1, spans[1].end_col), "ab")
  h.assert_eq("second quoted cell", ("> | ab | cd |"):sub(spans[2].start_col + 1, spans[2].end_col), "cd")
end)
