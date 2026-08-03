-- Out-of-the-box behaviour, asserted through a bare `setup({})`.
--
-- Every test here deliberately passes no `preview_mode` (and no other
-- rendering option) so that a change to the shipped defaults shows up as a
-- failure. The rest of the suite mostly configures `preview_mode = "inline"`
-- explicitly, which is how a default flip to reader mode -- a separate,
-- non-modifiable scratch buffer with no cursor-row reveal -- went unnoticed.
local h = require("tests.helpers")

local table_lines = {
  "intro paragraph",
  "",
  "| Name | Note |",
  "| --- | --- |",
  "| alpha | first |",
  "| beta | second |",
  "",
  "outro",
}

-- Every extmark of the plugin namespace, split into the source lines hidden by
-- conceal_lines and the virtual-line blocks with the row they hang off.
local function marks(bufnr)
  local inline = require("markdown-table-wrap.inline")
  local concealed, blocks = {}, {}
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, inline.namespace(), 0, -1, { details = true })) do
    local details = mark[4] or {}
    if details.conceal_lines == "" then
      concealed[mark[2] + 1] = true
    end
    if details.virt_lines then
      local texts = {}
      for _, virt_line in ipairs(details.virt_lines) do
        local text = ""
        for _, chunk in ipairs(virt_line) do
          text = text .. chunk[1]
        end
        table.insert(texts, text)
      end
      table.insert(blocks, {
        lnum = mark[2] + 1,
        above = details.virt_lines_above == true,
        leftcol = details.virt_lines_leftcol == true,
        texts = texts,
      })
    end
  end
  return concealed, blocks
end

-- Screen rows occupied by one buffer line, virtual lines excluded. A line
-- hidden by conceal_lines occupies none; the revealed cursor row occupies at
-- least one.
local function raw_height(lnum)
  local measured = vim.api.nvim_win_text_height(0, { start_row = lnum - 1, end_row = lnum - 1 })
  return measured.all - (measured.fill or 0)
end

-- Type keys for real, so mode changes and the InsertEnter / CursorMovedI /
-- TextChangedI autocommands fire the way they do for a user. "x" runs the
-- keys immediately with :normal! semantics, which also means insert mode ends
-- once the fed keys run out -- state that has to be observed *during* insert
-- is captured from an autocommand instead (see insert_snapshot).
local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "x", false)
end

-- Feed `keys` and return whatever `capture` collects the last time `event`
-- fires while they are being typed. Under :normal! semantics CursorMovedI and
-- TextChangedI are deferred past the insert session, so InsertCharPre is the
-- event that actually runs with mode == "i".
local function capture_during(bufnr, event, keys, capture)
  local snapshot
  local group = vim.api.nvim_create_augroup("MarkdownTableWrapDefaultsSpec", { clear = true })
  vim.api.nvim_create_autocmd(event, {
    group = group,
    buffer = bufnr,
    callback = function()
      snapshot = capture()
    end,
  })
  feed(keys)
  vim.api.nvim_del_augroup_by_id(group)
  return snapshot
end

local function move_cursor(bufnr, lnum)
  vim.api.nvim_win_set_cursor(0, { lnum, 0 })
  vim.api.nvim_exec_autocmds("CursorMoved", { buffer = bufnr })
end

h.test("default setup renders in the user's own buffer and keeps it editable", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")
  local reader = require("markdown-table-wrap.reader")

  h.with_buffer(table_lines, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 5, 0 })

    -- Bare setup in a Markdown buffer that already holds a table: exactly the
    -- situation a user lands in, including the debounced automatic refresh.
    plugin.setup({})
    vim.wait(400, function()
      return require("markdown-table-wrap.inline").is_active(buf)
    end)

    h.assert_eq("default preview mode is inline", plugin.config.preview_mode, "inline")
    h.assert_eq("no separate buffer is entered", vim.api.nvim_get_current_buf(), buf)
    h.assert_false("no reader buffer is opened", reader.is_reader(vim.api.nvim_get_current_buf()))
    h.assert_eq("the reader marker is absent", vim.b[buf].markdown_table_wrap_reader, nil)
    h.assert_true("the buffer stays modifiable", vim.bo[buf].modifiable)
    h.assert_eq("the buffer keeps its normal buftype", vim.bo[buf].buftype, "nofile")
    h.assert_true("inline rendering is active in the source buffer", inline.is_active(buf))

    -- The table can actually be edited.
    vim.api.nvim_buf_set_lines(buf, 5, 6, false, { "| beta | edited |" })
    h.assert_eq("the table row is editable", vim.api.nvim_buf_get_lines(buf, 5, 6, false)[1], "| beta | edited |")

    inline.clear(buf)
    plugin.state.inline_buf = nil
  end)
end)

h.test("default setup renders the table in place with row-anchored blocks", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({})

  h.with_buffer(table_lines, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    plugin.refresh_auto()

    h.assert_true("inline rendering is active", inline.is_active(buf))
    local concealed, blocks = marks(buf)
    h.assert_false("prose above the table is untouched", concealed[1])
    h.assert_true("header row is hidden", concealed[3])
    h.assert_true("delimiter row is hidden", concealed[4])
    h.assert_true("body row is hidden", concealed[5])
    h.assert_true("last body row is hidden", concealed[6])
    h.assert_false("prose below the table is untouched", concealed[7])
    h.assert_true("the rendered table is drawn as virtual lines", #blocks > 0)

    local rendered = table.concat(blocks[1].texts, "\n")
    h.assert_true("the rendered table has a top border", rendered:find("╭", 1, true) ~= nil)
    h.assert_true("the rendered table carries the cell text", rendered:find("alpha", 1, true) ~= nil)

    inline.clear(buf)
    plugin.state.inline_buf = nil
  end)
end)

h.test("default setup reveals the source row under the cursor and follows it", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({})

  h.with_buffer(table_lines, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    plugin.refresh_auto()

    -- Cursor outside the table: nothing is revealed and the whole rendered
    -- table hangs off the first line after it.
    for _, lnum in ipairs({ 3, 4, 5, 6 }) do
      h.assert_eq("table row " .. lnum .. " is hidden while the cursor is outside", raw_height(lnum), 0)
    end
    local _, outside_blocks = marks(buf)
    h.assert_eq("one block while the cursor is outside", #outside_blocks, 1)
    h.assert_eq("the block anchors after the table", outside_blocks[1].lnum, 7)

    -- Cursor inside the table: exactly the cursor row shows raw source, and
    -- the rendered rows split into an above/below block around it.
    for _, cursor_lnum in ipairs({ 3, 4, 5, 6, 5, 3 }) do
      move_cursor(buf, cursor_lnum)

      h.assert_true("row " .. cursor_lnum .. " is revealed as raw source", raw_height(cursor_lnum) >= 1)
      for _, lnum in ipairs({ 3, 4, 5, 6 }) do
        if lnum ~= cursor_lnum then
          h.assert_eq(
            string.format("row %d stays rendered while the cursor is on %d", lnum, cursor_lnum),
            raw_height(lnum),
            0
          )
        end
      end

      local _, blocks = marks(buf)
      h.assert_true("blocks exist while the cursor is on " .. cursor_lnum, #blocks > 0)
      for _, block in ipairs(blocks) do
        h.assert_eq("block anchors on the cursor row " .. cursor_lnum, block.lnum, cursor_lnum)
      end

      -- The revealed row's own rendered content is not drawn twice.
      local drawn = table.concat(
        vim.tbl_map(function(block)
          return table.concat(block.texts, "\n")
        end, blocks),
        "\n"
      )
      local cell = vim.api.nvim_buf_get_lines(buf, cursor_lnum - 1, cursor_lnum, false)[1]:match("|%s*([%w]+)%s*|")
      if cell then
        h.assert_true(
          "cell " .. cell .. " is not drawn while its row is revealed",
          drawn:find("│ " .. cell, 1, true) == nil
        )
      end
    end

    -- Leaving the table hides every row again.
    move_cursor(buf, 8)
    for _, lnum in ipairs({ 3, 4, 5, 6 }) do
      h.assert_eq("row " .. lnum .. " is rendered again after leaving", raw_height(lnum), 0)
    end

    inline.clear(buf)
    plugin.state.inline_buf = nil
  end)
end)

h.test("default setup keeps the table rendered in insert mode", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({})
  h.assert_true("insert-mode rendering stays on by default", plugin.config.auto_preview_in_insert)
  h.assert_false("insert mode does not clear by default", plugin.config.clear_on_insert)

  h.with_buffer(table_lines, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 5, 0 })
    plugin.refresh_auto()
    h.assert_true("inline rendering is active before insert", inline.is_active(buf))

    vim.api.nvim_exec_autocmds("InsertEnter", { buffer = buf })
    h.assert_true("inline rendering survives InsertEnter", inline.is_active(buf))

    -- Really enter insert mode and type, so the InsertEnter handler and the
    -- CursorMovedI/TextChangedI wiring run the way they do for a user. The
    -- state is read from inside the insert session, not simulated.
    -- "AXY<Esc>": the snapshot is taken on the last InsertCharPre (the "Y"),
    -- by which point "X" is already in the buffer and the cursor row has been
    -- edited in a live insert session.
    local during = capture_during(buf, "InsertCharPre", "AXY<Esc>", function()
      local mode = vim.api.nvim_get_mode().mode
      local line = vim.api.nvim_get_current_line()
      local survived_insert_enter = inline.is_active(buf)

      -- The debounced TextChangedI refresh normally lands here, in insert
      -- mode, and it is the place that consults auto_preview_in_insert. Under
      -- :normal! semantics TextChangedI is deferred past the insert session,
      -- so the same entry point is called directly while the mode is provably
      -- "i" -- otherwise nothing in this test would ever reach that branch.
      plugin.refresh_auto()

      local concealed, blocks = marks(buf)
      return {
        mode = mode,
        line = line,
        survived_insert_enter = survived_insert_enter,
        active = inline.is_active(buf),
        concealed = concealed,
        blocks = blocks,
        cursor_row = raw_height(5),
        row_above = raw_height(3),
        row_below = raw_height(6),
      }
    end)

    h.assert_true("insert mode was actually entered", during ~= nil)
    h.assert_eq("the snapshot was taken in insert mode", during.mode:sub(1, 1), "i")
    h.assert_eq("the earlier keystroke is already in the buffer", during.line:sub(-1), "X")
    h.assert_eq("the pending keystroke is the second one", vim.api.nvim_get_current_line():sub(-2), "XY")
    h.assert_true("inline rendering survives entering insert for real", during.survived_insert_enter)
    h.assert_true("an automatic refresh performed in insert mode keeps the rendering", during.active)
    h.assert_true(
      "non-cursor rows stay hidden in insert mode",
      during.concealed[3] and during.concealed[4] and during.concealed[6]
    )
    h.assert_true("the cursor row is revealed while typing", during.cursor_row >= 1)
    h.assert_eq("a non-cursor row stays rendered while typing", during.row_above, 0)
    h.assert_eq("the last table row stays rendered while typing", during.row_below, 0)
    h.assert_true("the rendered blocks still exist in insert mode", #during.blocks > 0)
    for _, block in ipairs(during.blocks) do
      h.assert_eq("blocks stay anchored on the cursor row in insert mode", block.lnum, 5)
    end

    h.assert_eq("normal mode is restored", vim.api.nvim_get_mode().mode:sub(1, 1), "n")
    h.assert_true("inline rendering survives InsertLeave", inline.is_active(buf))

    inline.clear(buf)
    plugin.state.inline_buf = nil
  end)
end)

h.test("default setup draws line numbers into the rendered rows", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({})
  h.assert_true("line numbers are drawn by default", plugin.config.inline_line_numbers)

  h.with_buffer(table_lines, function(buf)
    vim.bo[buf].filetype = "markdown"
    local saved_number = vim.wo.number
    local saved_relative = vim.wo.relativenumber
    vim.wo.number = true
    vim.wo.relativenumber = false

    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    plugin.refresh_auto()

    local _, blocks = marks(buf)
    h.assert_eq("one block while the cursor is outside", #blocks, 1)
    local numbers = {}
    for _, text in ipairs(blocks[1].texts) do
      local number = text:match("^%s*(%d+)%s*[│╭├╰]")
      if number then
        numbers[tonumber(number)] = true
      end
    end
    h.assert_true("header row carries buffer line 3", numbers[3])
    h.assert_true("delimiter row carries buffer line 4", numbers[4])
    h.assert_true("first body row carries buffer line 5", numbers[5])
    h.assert_true("second body row carries buffer line 6", numbers[6])
    h.assert_true("the block is drawn from the left edge", blocks[1].leftcol)

    -- Relative numbers are measured from the cursor row.
    vim.wo.relativenumber = true
    move_cursor(buf, 3)
    local _, relative_blocks = marks(buf)
    local relative = {}
    for _, block in ipairs(relative_blocks) do
      for _, text in ipairs(block.texts) do
        local number = text:match("^%s*(%d+)%s*[│╭├╰]")
        if number then
          relative[tonumber(number)] = true
        end
      end
    end
    h.assert_true("row 5 is one line from the cursor row 4", relative[1])
    h.assert_true("row 6 is two lines from the cursor row 4", relative[2])
    h.assert_false("absolute buffer numbers are gone", relative[5])

    vim.wo.number = saved_number
    vim.wo.relativenumber = saved_relative
    inline.clear(buf)
    plugin.state.inline_buf = nil
  end)
end)

h.test("default setup keeps the table screen height constant across the cursor rows", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({})
  h.assert_true("stable height is on by default", plugin.config.inline_stable_height)

  h.with_buffer({
    "intro paragraph",
    "",
    "| Name | Note |",
    "| --- | --- |",
    -- Raw source far wider than what it renders to: the link collapses to its
    -- label, so revealing this row costs two screen rows where the rendered
    -- form costs one. That gap is what the stable-height filler absorbs.
    "| alpha | [docs](https://example.com/a/very/long/url/that/makes/this/raw/line/wrap) |",
    "| beta | second |",
    "",
    "outro",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    -- The whole point of the filler is what soft-wrapping costs, so the
    -- measurement needs 'wrap' (which the defaults leave alone).
    local saved_wrap = vim.wo.wrap
    vim.wo.wrap = true
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    plugin.refresh_auto()

    h.assert_true("inline rendering is active", inline.is_active(buf))

    local heights = {}
    for _, lnum in ipairs({ 3, 4, 5, 6 }) do
      move_cursor(buf, lnum)
      h.assert_true("row " .. lnum .. " is revealed", raw_height(lnum) >= 1)
      -- The whole buffer: the blocks re-anchor between rows, so only a range
      -- that contains every anchor is comparable across cursor positions.
      heights[lnum] = vim.api.nvim_win_text_height(0, {}).all
    end

    -- The long body row soft-wraps into more screen rows than the single
    -- rendered row it replaces, so the constant total below is only reachable
    -- through the stable-height filler.
    move_cursor(buf, 5)
    h.assert_true("the long body row really soft-wraps when revealed", raw_height(5) >= 2)

    for _, lnum in ipairs({ 4, 5, 6 }) do
      h.assert_eq(string.format("height on row %d matches row 3 (%d)", lnum, heights[3]), heights[lnum], heights[3])
    end

    vim.wo.wrap = saved_wrap
    inline.clear(buf)
    plugin.state.inline_buf = nil
  end)
end)

h.test("toggling the reader off returns to the default inline rendering", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")
  local reader = require("markdown-table-wrap.reader")

  plugin.setup({})

  h.with_buffer(table_lines, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 5, 0 })
    plugin.refresh_auto()
    h.assert_true("inline rendering is active to begin with", inline.is_active(buf))

    local reader_buf = plugin.toggle_reader()
    h.assert_true("the reader opens on the first toggle", reader.is_reader(reader_buf))

    h.assert_true("the reader closes on the second toggle", plugin.toggle_reader())
    h.assert_eq("the source buffer is current again", vim.api.nvim_get_current_buf(), buf)
    h.assert_false("the source is not left paused", plugin.state.paused_buffers[buf] == true)
    h.assert_eq("the buffer returns to the configured mode", plugin.get_preview_mode(buf), "inline")

    -- The round trip must actually restore the rendering, both by itself and
    -- through the ordinary refresh path that a cursor move, scroll, or edit
    -- goes through.
    vim.wait(400, function()
      return inline.is_active(buf)
    end)
    h.assert_true("the round trip re-renders the buffer", inline.is_active(buf))

    inline.clear(buf)
    plugin.refresh_auto()
    h.assert_true("an ordinary refresh still renders the buffer", inline.is_active(buf))

    inline.clear(buf)
    plugin.state.inline_buf = nil
  end)
end)

h.test("an unfocused window keeps the options its rendering depends on", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({})
  h.assert_true("whole-buffer rendering is on by default", plugin.config.render_all)

  local markdown_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[markdown_buf].buftype = "nofile"
  vim.bo[markdown_buf].swapfile = false
  vim.api.nvim_buf_set_lines(markdown_buf, 0, -1, false, table_lines)
  vim.bo[markdown_buf].filetype = "markdown"

  local plain_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[plain_buf].buftype = "nofile"
  vim.bo[plain_buf].swapfile = false
  vim.api.nvim_buf_set_lines(plain_buf, 0, -1, false, { "plain text" })

  local plain_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(plain_win, plain_buf)
  vim.cmd("vsplit")
  local markdown_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(markdown_win, markdown_buf)
  -- A conceallevel the user or an ftplugin already had in place: it is what
  -- gets handed back when the window is wrongly detached on leave.
  vim.wo[markdown_win].conceallevel = 1
  vim.api.nvim_win_set_cursor(markdown_win, { 1, 0 })
  plugin.refresh_auto({ force = true })

  local function height()
    return vim.api.nvim_win_call(markdown_win, function()
      return vim.api.nvim_win_text_height(markdown_win, {}).all
    end)
  end
  local function extmarks()
    return #vim.api.nvim_buf_get_extmarks(markdown_buf, inline.namespace(), 0, -1, {})
  end

  h.assert_true("the markdown window is rendered", inline.is_active(markdown_buf))
  local focused_conceallevel = vim.wo[markdown_win].conceallevel
  local focused_height = height()
  local focused_extmarks = extmarks()
  h.assert_eq("rendering raises conceallevel while focused", focused_conceallevel, 2)

  -- Focus away. The rendered blocks stay attached (render_all), so the window
  -- must keep the conceallevel that hides the source rows underneath them.
  vim.api.nvim_set_current_win(plain_win)
  h.assert_eq("the rendering stays attached after leaving", extmarks(), focused_extmarks)
  h.assert_eq("leaving keeps conceallevel", vim.wo[markdown_win].conceallevel, focused_conceallevel)
  h.assert_eq("leaving keeps the buffer screen height", height(), focused_height)

  -- And it never self-heals on its own, so a second round trip must be stable
  -- rather than merely repaired by refocusing.
  vim.api.nvim_set_current_win(markdown_win)
  h.assert_eq("refocusing keeps conceallevel", vim.wo[markdown_win].conceallevel, focused_conceallevel)
  h.assert_eq("refocusing keeps the buffer screen height", height(), focused_height)
  vim.api.nvim_set_current_win(plain_win)
  h.assert_eq("leaving again keeps conceallevel", vim.wo[markdown_win].conceallevel, focused_conceallevel)
  h.assert_eq("leaving again keeps the buffer screen height", height(), focused_height)

  inline.dispose(markdown_buf)
  if vim.api.nvim_win_is_valid(markdown_win) then
    vim.api.nvim_win_close(markdown_win, true)
  end
  vim.api.nvim_buf_delete(markdown_buf, { force = true })
  vim.api.nvim_buf_delete(plain_buf, { force = true })
end)

h.test("default setup leaves 'wrap' and 'concealcursor' alone", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({})
  h.assert_false("wrap is not disabled by default", plugin.config.inline_disable_wrap)

  h.with_buffer(table_lines, function(buf)
    vim.bo[buf].filetype = "markdown"
    local saved_wrap = vim.wo.wrap
    local saved_concealcursor = vim.wo.concealcursor
    vim.wo.wrap = true
    vim.wo.concealcursor = ""

    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    plugin.refresh_auto()
    h.assert_true("wrap survives rendering", vim.wo.wrap)
    h.assert_eq("concealcursor survives rendering", vim.wo.concealcursor, "")

    for _, lnum in ipairs({ 3, 5, 8 }) do
      move_cursor(buf, lnum)
      h.assert_true("wrap survives the cursor on line " .. lnum, vim.wo.wrap)
      h.assert_eq("concealcursor survives the cursor on line " .. lnum, vim.wo.concealcursor, "")
    end

    vim.wo.wrap = saved_wrap
    vim.wo.concealcursor = saved_concealcursor
    inline.clear(buf)
    plugin.state.inline_buf = nil
  end)
end)

h.test("default setup renders blockquote tables with their quote marker", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({})
  h.assert_eq("quote marker is drawn by default", plugin.config.quote_icon, "auto")

  h.with_buffer({
    "intro paragraph",
    "",
    "> | Name | Note |",
    "> | --- | --- |",
    "> | alpha | first |",
    "",
    "outro",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    plugin.refresh_auto()

    local concealed, blocks = marks(buf)
    h.assert_true("quoted header row is hidden", concealed[3])
    h.assert_true("quoted body row is hidden", concealed[5])
    h.assert_true("the quoted table is rendered", #blocks > 0)

    for _, text in ipairs(blocks[1].texts) do
      h.assert_true("rendered line keeps the quote marker: " .. text, text:find("^>%s") ~= nil)
    end

    inline.clear(buf)
    plugin.state.inline_buf = nil
  end)
end)
