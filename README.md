# markdown-table-wrap.nvim

A Neovim/LazyVim plugin for rendering Markdown pipe tables with wrapped cell content.

It does not modify the Markdown source buffer and does not fork or patch `render-markdown.nvim`. It provides two display modes: source-position-preserving inline rendering and a floating preview.

## Why

`render-markdown.nvim` makes normal Markdown tables pleasant to read, but very long cell content can still overflow the terminal width. Neovim's normal line wrapping breaks the whole source line, so table borders and columns no longer line up visually.

`markdown-table-wrap.nvim` parses pipe tables, calculates display widths with `vim.api.nvim_strwidth`, allocates columns to fit the current text area, and wraps long content inside each cell.

## Screenshots

Inline rendering in a Tokyo Night themed Markdown buffer:

![Inline table rendering](docs/01-inline-tokyonight.png)

Floating preview for long table reading:

![Floating long table preview](docs/03-floating-long-table.png)

## Features

- Automatic Markdown-only rendering; commands are optional controls.
- Detects supported top-level GFM pipe tables in the current Markdown document.
- Renders pipe tables inside blockquotes (including callouts and nested `>` levels) in place, with the quote marker redrawn in front of every rendered row and colored by the callout kind (`> [!done]` keeps its green bar).
- Parses header, separator, alignment, and body rows.
- Computes available width from the current window.
- Accounts for number, sign, and fold columns when fitting the table.
- Can shrink below the preferred column width when many columns must fit on screen.
- Wraps long cell content inside each column.
- Supports mixed Chinese, English, and Japanese display widths through `vim.api.nvim_strwidth`.
- Keeps Markdown inline code spans such as `` `Rc<RefCell<T>>` `` and `` `notes/01-smart-pointers.md` `` intact.
- Keeps pipes from splitting table cells when they occur inside matching code spans with arbitrary backtick-run lengths.
- Prefers wrapping at spaces, `、`, `，`, `,`, `；`, `;`, and `/`.
- Renders a Unicode table inline in a replace-like mode.
- Renders every table of a supported buffer inline by default, in place and without cursor focus.
- Debounces cursor movement and text changes.
- Reveals the Markdown source while typing in Insert mode, then restores the rendered table on `InsertLeave`.
- Skips redraws when the active table content, width, and render options have not changed.
- Avoids re-render scheduling on normal cursor movement when whole-buffer rendering is active.
- Restores window-local `conceallevel` after clearing Inline replace mode, and never changes `wrap` or `concealcursor`.
- Highlights rendered borders, headers, inline code spans, and Markdown links separately.
- Renders common inline Markdown inside cells to plain display text, including inline code, emphasis, strikethrough, links, autolinks, and backslash escapes. Emphasis follows CommonMark, so intraword underscores such as `snake_case_name` stay literal.
- Keeps code-wrapped link labels aligned when Markdown conceal hides their backticks.
- Supports `==highlight==`, wiki links, image alt text, and URL-pattern-based link icons.
- Theme presets for Tokyo Night, Catppuccin, a neutral default, and a render-markdown-inspired palette.
- Supports inline custom themes and loading custom theme files from a theme directory.
- Provides source-aware table cell navigation commands.
- Can also render the same table in a floating window.
- Provides `:MarkdownTableToggleInline` for quickly switching between source and inline rendering.
- Leaves the existing `gx` mapping untouched by default; table-aware source-buffer link handling is opt-in.
- Does not edit the source buffer.
- No external binaries.
- Neovim 0.11+.

## Installation

### GitHub (lazy.nvim / LazyVim)

```lua
return {
  {
    "ice345/markdown-table-wrap.nvim",
    ft = { "markdown", "quarto", "rmd" },
    opts = {},
  },
}
```

If you also use `render-markdown.nvim`, disable its pipe-table renderer as
shown in [Coexisting With render-markdown.nvim](#coexisting-with-render-markdownnvim).

### Local Development And Complete Configuration

Clone or place this directory somewhere on disk, then add:

```lua
-- ~/.config/nvim/lua/plugins/markdown-table-wrap.lua
return {
  {
    dir = "~/Code/lazyvim-table/markdown-table-wrap.nvim",
    ft = { "markdown", "quarto", "rmd" },
    opts = {
      max_width_ratio = 0.9,
      min_col_width = 8,
      max_col_width = 50,
      fit_to_window = true,
      border = "rounded",
      use_unicode_border = true,
      table_border = "rounded",
      row_separator = true,
      preview_mode = "inline",
      inline_mode = "replace",
      inline_position = "above",
      dim_source = true,
      auto_preview = true,
      render_all = true,
      auto_preview_in_insert = false,
      clear_on_cursor_leave = true,
      clear_on_insert = true,
      clear_on_visual = true,
      debounce_ms = 80,
      overlay_priority = 10000,
      inline_line_numbers = true,
      inline_stable_height = true,
      quote_icon = "auto",
      highlight_preset = "default",
      theme_dir = nil,
      themes = {},
      extra_filetypes = {},
      highlights = {},
      map_gx = false,
      link = {
        icon = "",
        wiki = { icon = " ", highlight = "MarkdownTableWrapWikiLink", scope_highlight = "MarkdownTableWrapWikiLink" },
        image = " ",
        custom = {
          github = { pattern = "github", icon = " " },
          gitlab = { pattern = "gitlab", icon = "󰮠 " },
          youtube = { pattern = "youtube", icon = " " },
          bilibili = { pattern = "bilibili", icon = "󰟴 " },
          cern = { pattern = "cern.ch", icon = " " },
        },
      },
    },
    keys = {
      { "<leader>mt", "<cmd>MarkdownTableTogglePreview<cr>", desc = "Toggle Markdown table preview" },
      { "<leader>mp", "<cmd>MarkdownTablePreview<cr>", desc = "Preview Markdown tables" },
      { "<leader>mf", "<cmd>MarkdownTableFloatPreview<cr>", desc = "Float Markdown table preview" },
      { "<leader>mi", "<cmd>MarkdownTableToggleInline<cr>", desc = "Toggle Markdown table inline view" },
      { "<leader>mc", "<cmd>MarkdownTableClosePreview<cr>", desc = "Close Markdown table preview" },
      { "<leader>mT", "<cmd>MarkdownTableToggleAutoPreview<cr>", desc = "Toggle auto Markdown table preview" },
      { "]c", "<cmd>MarkdownTableNextCell<cr>", desc = "Next table cell" },
      { "[c", "<cmd>MarkdownTablePrevCell<cr>", desc = "Previous table cell" },
      { "]r", "<cmd>MarkdownTableNextRow<cr>", desc = "Next table row" },
      { "[r", "<cmd>MarkdownTablePrevRow<cr>", desc = "Previous table row" },
    },
  },
}
```

See [PUBLISHING.md](PUBLISHING.md) for the release flow.

## Default Behavior

Inline mode is the default preview strategy. With `auto_preview = true`, every
table of a supported buffer is rendered in place inside the buffer you are
editing: the buffer stays modifiable, and the source row under the cursor is
revealed as raw Markdown so it can be edited while the rest of the table stays
rendered.

### Choosing A View

Use Source when editing Markdown structure. It is the safest view for `dd`,
Visual changes, moving rows, changing delimiters, and other operations where
you need every source line to be a real Markdown line.

Use Inline when you want to edit the original buffer while seeing rendered
tables. The source buffer remains active, but conceal and virtual text are
visual layers, so Source is preferable for large structural edits.

`<leader>mi` can be mapped to `:MarkdownTableToggleInline`:

```lua
{ "<leader>mi", "<cmd>MarkdownTableToggleInline<cr>", desc = "Toggle Markdown table inline view" }
```

The command enables Inline from Source. Pressing it again clears the Inline
layer and leaves Source visible.

`preview_mode = "inline"` is the default strategy; `MarkdownTableToggleInline`
selects Inline for the current editing session.

### Coexisting With render-markdown.nvim

Use `render-markdown.nvim` for the rest of Markdown, but disable its table renderer so this plugin owns pipe tables:

```lua
-- ~/.config/nvim/lua/plugins/render-markdown.lua
return {
  "MeanderingProgrammer/render-markdown.nvim",
  opts = {
    pipe_table = {
      enabled = false,
    },
  },
}
```

Blockquoted tables work with this setup as well. Callout bars keep their severity color: the marker uses `callout_info`, `callout_success`, `callout_hint`, `callout_warn`, or `callout_error` depending on the `[!kind]` of the enclosing quote, and plain quotes use `quote`. The default preset links those to the `Diagnostic*` groups, which is what `render-markdown.nvim` colors its own callouts with. The table's source lines are hidden entirely, so `render-markdown.nvim` never draws its quote bar on them; the rendered rows carry the marker themselves, and `quote_icon = "auto"` picks the same `▋` bar so the quote block stays visually continuous. The `render_markdown` highlight preset links the marker to `RenderMarkdownQuote`.

## Commands

You do not need commands for normal use. With `auto_preview = true`, every
supported table is rendered inline automatically. The commands below provide
manual control and access to the optional floating mode.

- `:MarkdownTablePreview` opens the configured preview mode. By default this is Inline.
- `:MarkdownTableInlinePreview` renders an inline preview for the table under the cursor.
- `:MarkdownTableFloatPreview` opens a floating preview for the table under the cursor.
- `:MarkdownTableToggleInline` switches between Source and Inline.
- `:MarkdownTableTogglePreview` toggles the active preview.
- `:MarkdownTableClosePreview` closes the preview.
- `:MarkdownTableRefresh` force refreshes rendered tables in the current Markdown buffer.
- `:MarkdownTableEnableAutoPreview` enables automatic preview in the current buffer.
- `:MarkdownTableDisableAutoPreview` disables automatic preview in the current Source buffer.
- `:MarkdownTableToggleAutoPreview` toggles automatic preview in the current buffer.
- `:MarkdownTableStatus` shows the current auto-preview state.
- `:MarkdownTableNextCell` moves to the next source cell in the current table row.
- `:MarkdownTablePrevCell` moves to the previous source cell in the current table row.
- `:MarkdownTableNextRow` moves to the same source cell in the next table row.
- `:MarkdownTablePrevRow` moves to the same source cell in the previous table row.
- `:MarkdownTableOpenLink` opens the first link in the current source table cell.
- `:MarkdownTableExport[!] [tsv|csv]` copies the table under the cursor as TSV (the default) or CSV; with `!` it copies every table in the buffer, separated by blank lines.

Press `q` inside the floating preview window to close the float.

`map_gx = false` by default, so the plugin does not replace your existing `gx`
mapping. Run `:MarkdownTableOpenLink` directly, add your own keymap, or set
`map_gx = true` to opt into the buffer-local table-aware mapping. The command
reads the current source table cell and opens the actual URL from
`[text](url)`, `(text)[url]`, or image links.

`:MarkdownTableExport` exports the text each cell displays: Markdown syntax is
removed, so `[GitHub](https://github.com)` becomes `GitHub`, and `<br>` becomes
a line break. The result goes to the unnamed and `"0` registers like a yank,
and to `"+` / `"*` when `'clipboard'` contains `unnamedplus` / `unnamed`. TSV
escapes tabs, carriage returns, line breaks, and backslashes as `\t`, `\r`,
`\n`, and `\\`. CSV quotes fields containing commas, quotes, or line breaks,
and prefixes values starting with `=`, `+`, `-`, `@`, a tab, or a carriage
return with `'` so spreadsheets do not evaluate them as formulas; note that
this includes negative numbers. A table with body rows holding more cells than
its header is refused rather than exported without the extra cells.

## Configuration

```lua
require("markdown-table-wrap").setup({
  max_width_ratio = 0.9,
  min_col_width = 8,
  max_col_width = 50,
  fit_to_window = true,
  border = "rounded",
  use_unicode_border = true,
  table_border = "rounded",
  row_separator = true,
  preview_mode = "inline",
  inline_mode = "replace",
  inline_position = "above",
  dim_source = true,
  auto_preview = true,
  render_all = true,
  auto_preview_in_insert = false,
  clear_on_cursor_leave = true,
  clear_on_insert = true,
  clear_on_visual = true,
  debounce_ms = 80,
  overlay_priority = 10000,
  inline_line_numbers = true,
  inline_stable_height = true,
  quote_icon = "auto",
  highlight_preset = "default",
  theme_dir = nil,
  themes = {},
  extra_filetypes = {},
  highlights = {},
  map_gx = false,
  link = {
    icon = "",
    wiki = { icon = " ", highlight = "MarkdownTableWrapWikiLink", scope_highlight = "MarkdownTableWrapWikiLink" },
    image = " ",
    custom = {
      github = { pattern = "github", icon = " " },
      gitlab = { pattern = "gitlab", icon = "󰮠 " },
      youtube = { pattern = "youtube", icon = " " },
      bilibili = { pattern = "bilibili", icon = "󰟴 " },
      cern = { pattern = "cern.ch", icon = " " },
    },
  },
})
```

Options:

- `max_width_ratio`: maximum preview table width as a ratio of the current window's **text area**, clamped to `0.1` through `1.0`. The number, sign, and fold columns are subtracted before the ratio applies, so a window with a visible gutter renders narrower tables than a bare one of the same total width.
- `min_col_width`: minimum content width for each column.
- `max_col_width`: maximum natural content width before wrapping.
- `fit_to_window`: prioritize fitting the complete table inside the current text area, even when this requires columns narrower than `min_col_width`.
- `border`: floating window border style.
- `use_unicode_border`: use Unicode table drawing characters. Set to `false` for ASCII.
- `table_border`: `"rounded"` or `"single"` for rendered table corners.
- `row_separator`: draw horizontal separators between body rows for clearer cell grouping.
- `preview_mode`: `"inline"` (default) or `"float"` for `:MarkdownTablePreview`. Inline renders in place inside your own buffer, which stays modifiable and reveals the raw source row under the cursor.
- `inline_mode`: `"replace"` or `"insert"`. Replace mode hides the source rows and draws the rendered table in their place.
- `inline_position`: `"above"` or `"below"` for insert mode.
- `dim_source`: dim the original Markdown table lines while insert mode is active.
- `auto_preview`: automatically render supported buffers.
- `render_all`: render all Markdown tables in the current buffer instead of only the cursor table.
- `auto_preview_in_insert`: keep replacement rendering active while typing in Insert mode.
- `clear_on_cursor_leave`: clear inline rendering when the cursor leaves a table or window.
- `clear_on_insert`: reveal source Markdown while editing, then re-render on `InsertLeave`.
- `clear_on_visual`: in inline mode, reveal source Markdown while selecting text, then re-render after leaving Visual mode.
- `debounce_ms`: delay before automatic refresh after movement or text changes.
- `overlay_priority`: priority of the extmarks that carry the rendered table rows in Inline replace mode.
- `inline_line_numbers`: draw the window's line numbers into the rendered table rows in row-anchored replace mode (virtual lines cannot receive native line numbers). Each source row's number appears on the first rendered line of that row, using the `LineNr` highlight. Shown only when the window has `'number'` or `'relativenumber'` set; with `'relativenumber'` the distance to the cursor row is shown and updates as the cursor moves. Default `true`.
- `inline_stable_height`: pad the revealed cursor row with blank virtual lines so the table keeps a constant total screen height while the cursor moves between its rows. Without it, every move swaps a rendered row for the raw soft-wrapped source line (usually a different height), reflowing the rest of the table and everything below it. Default `true`.
- `quote_icon`: marker drawn in front of every rendered line of a table inside a blockquote, once per quote level, using the `quote` highlight. `"auto"` (default) draws `render-markdown.nvim`'s quote bar `▋` when that plugin is loaded and the raw `>` otherwise; set it to any string to fix the marker, or to `false` to draw no marker. Rendered tables are narrowed by the marker width so they stay inside the quote block.
- `highlight_preset`: `"default"`, `"tokyonight"`, `"catppuccin"`, `"render_markdown"`, `"auto"`, or any custom key supplied through `themes`/`theme_dir`. The default preset follows standard Neovim highlight groups so it fits arbitrary colorschemes without extra theme tuning.
- `theme_dir`: optional directory containing custom theme files named `<preset>.lua`; the file name must match `highlight_preset`.
- `themes`: inline custom theme table keyed by `highlight_preset`.
- `highlights`: override highlight specs by semantic key.
- `map_gx`: opt into a buffer-local `gx` mapping for table links in Source buffers. It defaults to `false`, leaving the user's existing mapping untouched.
- `link`: icon configuration for links, wiki links, images, and URL pattern matches.
- `extra_filetypes`: list of additional filetypes to enable table rendering for. The default is `{}`, meaning the built-in `markdown`, `md`, `quarto`, `rmd`, and `rmarkdown` filetypes render tables.

```lua
require("markdown-table-wrap").setup({
  extra_filetypes = { "text" },
})
```

> **Note for LazyVim users:** If you add extra filetypes, you must also include them in the plugin's `ft` list to load the plugin for those filetypes:
>
> ```lua
> return {
>   {
>     "ice345/markdown-table-wrap.nvim",
>     ft = { "markdown", "quarto", "rmd", "text" },
>     opts = {
>       extra_filetypes = { "text" },
>     },
>   },
> }
> ```

Highlight override example:

Semantic highlight groups are reapplied after `:colorscheme` changes. A direct
spec such as `{ fg = "#7aa2f7" }` replaces the preset's linked base for that
semantic key.

```lua
require("markdown-table-wrap").setup({
  highlight_preset = "default",
  highlights = {
    border = { fg = "#7aa2f7" },
    code = { fg = "#9ece6a" },
    bold = { fg = "#e0af68", bold = true },
    italic = { fg = "#7aa2f7", italic = true },
    strike = { fg = "#f7768e", strikethrough = true },
    mark = { fg = "#1a1b26", bg = "#e0af68" },
    link = { fg = "#7dcfff", underline = true },
    quote = { fg = "#565f89" },
    callout_success = { fg = "#9ece6a" },
  },
})
```

Custom theme example:

```lua
require("markdown-table-wrap").setup({
  highlight_preset = "my_theme",
  themes = {
    my_theme = {
      border = { fg = "#89b4fa" },
      inline = { fg = "#cdd6f4" },
      source = { link = "Comment" },
      header = { fg = "#f9e2af", bold = true },
      code = { fg = "#a6e3a1" },
      link = { fg = "#89dceb", underline = true },
      wiki_link = { fg = "#cba6f7", underline = true },
      image = { fg = "#94e2d5" },
      bold = { fg = "#f9e2af", bold = true },
      italic = { fg = "#cba6f7", italic = true },
      strike = { fg = "#f38ba8", strikethrough = true },
      mark = { fg = "#1e1e2e", bg = "#f9e2af" },
    },
  },
})
```

Theme directory example:

```lua
require("markdown-table-wrap").setup({
  highlight_preset = "my_theme",
  theme_dir = vim.fn.stdpath("config") .. "/markdown-table-wrap-themes",
})
```

Then create `~/.config/nvim/markdown-table-wrap-themes/my_theme.lua` returning the same table shape.

Link icon example:

```lua
require("markdown-table-wrap").setup({
  link = {
    icon = "",
    wiki = { icon = " ", highlight = "MarkdownTableWrapWikiLink", scope_highlight = "MarkdownTableWrapWikiLink" },
    image = " ",
    custom = {
      github = { pattern = "github", icon = " " },
      gitlab = { pattern = "gitlab", icon = "󰮠 " },
      youtube = { pattern = "youtube", icon = " " },
      bilibili = { pattern = "bilibili", icon = "󰟴 " },
      cern = { pattern = "cern.ch", icon = " " },
    },
  },
})
```

Standard Markdown links use `[text](url)`. The plugin also accepts `(text)[url]` as a convenience form inside table cells.

Semantic highlight keys:

- `border`
- `inline`
- `source`
- `header`
- `code`
- `link`
- `wiki_link`
- `image`
- `bold`
- `italic`
- `strike`
- `mark`

Content highlight keys are background-transparent when they only link to an
existing highlight group. This prevents Inline replace mode from turning each
cell into a filled rectangle when `Normal`, `Title`, or another linked group
has a colorscheme background. Add an explicit `bg` to a semantic key when a
filled background is intentional.

## Lua API

The inspection helpers expose effective buffer-local state without changing it:

```lua
local table_wrap = require("markdown-table-wrap")

local config = table_wrap.get_buffer_config(0)
local mode = table_wrap.get_preview_mode(0)
```

- `get_buffer_config(bufnr?)` returns a deep-copied effective configuration for
  the buffer, including runtime view and auto-preview overrides. Omit `bufnr`
  or pass `0` for the current buffer.
- `get_preview_mode(bufnr?)` returns the buffer's effective `"inline"` or
  `"float"` mode without mutating global setup.

`export_table(opts?)` is the Lua entry point behind `:MarkdownTableExport`. It
returns `true` and the exported text, or `false` without touching any register.

- `format`: `"tsv"` (default) or `"csv"`.
- `all`: export every table in the buffer instead of the one under the cursor.
- `csv_formula_policy`: `"raw"` keeps formula-leading CSV values unprefixed.
- `silent`: suppress the notification.

## Example

With the default configuration, opening a Markdown file renders this table automatically. You can also run `:MarkdownTablePreview` manually:

| 名称 | 说明 | 路径 |
| --- | --- | --- |
| Rc | `Rc<RefCell<T>>` 常用于需要共享所有权并且在运行时检查可变借用的场景，尤其适合写解释器、树结构、图结构。 | `notes/01-smart-pointers.md` |
| render-markdown.nvim | 当表格某一列非常长，Neovim 原生 wrap 会把整行硬折断，导致边框和列对齐错乱。 | lua/plugins/render-markdown.lua |

## Current Scope

The current rendering model includes:

- Inline, in-place table rendering by default.
- Automatic rendering of every supported table without cursor focus.
- Command-free workflow: edit Source in Insert mode and view rendered content in Normal mode.
- Cached refreshes to avoid unnecessary redraw flicker.
- Window-local conceal handling with restoration on clear.
- Semantic highlights for borders, headers, inline code, and links.
- Background-transparent linked content highlights prevent filled Inline cells
  unless an explicit `bg` is configured.
- Code-wrapped link labels keep concealed delimiters out of width calculation
  so Inline separators remain aligned.
- Cell navigation commands that understand inline code pipes like `` `a|b` ``.
- Floating preview is retained for focused table-only inspection.
- Top-level GFM pipe-table parsing with conservative Markdown block boundaries.
- Inline code spans are treated as indivisible chunks.
- Escaped pipes are displayed as `|`.
- A headless Neovim regression suite exists in `tests/run.lua`.
- Tests are split by parser, inline Markdown, width, wrapping, rendering, theme, inline extmarks, lifecycle, navigation, configuration, and system render chain. See [tests/README.md](tests/README.md) for the coverage map and release-only manual checks.

## Testing

Run the current regression suite from the repository root:

```sh
nvim --headless -u NONE --cmd "set shadafile=NONE" --cmd "set noswapfile" \
  -c "set rtp+=." \
  -c "luafile tests/run.lua" \
  -c "qa!"
```

The suite currently covers:

- GFM-style pipe tables with optional outer pipes.
- Escaped pipes and pipes inside inline code.
- Multi-backtick inline code spans with internal pipes.
- Table-shaped text inside backtick- and tilde-fenced code blocks.
- Alignment rows and missing/extra cells.
- GFM Example 202-style body rows without literal pipes and top-level tables
  indented by up to three spaces.
- Conservative termination at headings, lists, blockquotes, thematic breaks,
  HTML blocks, link definitions, and other new block-level structures.
- Adjacent pipe-like prose that must not be concealed as part of a table.
- Single-read parser behavior for large runs of invalid pipe-shaped prose.
- Mixed CJK/English width and hard breaks.
- Width helpers and display-width-aware padding.
- Inline token highlighting through wrapping, floating preview, and inline replacement.
- Link icons, `==highlight==`, inline custom themes, and theme-directory loading.
- Whole-buffer automatic rendering through Neovim extmarks.
- Compact continuous-border highlight spans and colorscheme highlight replay.
- Source-aware cell navigation, configuration validation, and opt-in table-aware `gx` installation when a filetype pre-dates plugin setup.
- Buffer-local deferred refresh, view/auto state, option restoration, and
  wipeout cleanup.

When running from the parent development directory, use:

```sh
nvim --headless -u NONE --cmd "set shadafile=NONE" --cmd "set noswapfile" \
  -c "set rtp+=./markdown-table-wrap.nvim" \
  -c "luafile markdown-table-wrap.nvim/tests/run.lua" \
  -c "qa!"
```

## Healthcheck

```vim
:checkhealth markdown-table-wrap
```

## Help

```vim
:help markdown-table-wrap
```

The default inline mode hides source table text with extmark conceal and draws the rendered rows as virtual lines anchored to the original table rows. It does not edit the Markdown source.

## Platform Notes

Inline replacement is built on Neovim extmarks: the source rows are removed from the screen with `conceal_lines` (Neovim 0.11+) and the rendered rows are drawn as virtual lines. A long source row therefore cannot soft-wrap into extra screen lines underneath the rendered table, and the plugin leaves `'wrap'` alone, which is what lets the row under the cursor be revealed as raw soft-wrapping source.

## Project Structure

```text
markdown-table-wrap.nvim/
├── .github/
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.yml
│   │   └── feature_request.yml
│   ├── pull_request_template.md
│   └── workflows/
│       └── ci.yml
├── .gitignore
├── CHANGELOG.md
├── CONTRIBUTING.md
├── LICENSE
├── PUBLISHING.md
├── README.md
├── doc/
│   ├── markdown-table-wrap.txt
│   └── tags
├── docs/
│   ├── 01-inline-tokyonight.png
│   └── 03-floating-long-table.png
├── lua/
│   └── markdown-table-wrap/
│       ├── export.lua
│       ├── health.lua
│       ├── init.lua
│       ├── inline.lua
│       ├── markdown.lua
│       ├── nav.lua
│       ├── parser.lua
│       ├── render.lua
│       ├── theme.lua
│       ├── utf8.lua
│       ├── width.lua
│       └── wrap.lua
├── plugin/
│   └── markdown-table-wrap.lua
├── stylua.toml
└── tests/
    ├── README.md
    ├── helpers.lua
    ├── run.lua
    └── spec/
        ├── config_spec.lua
        ├── defaults_spec.lua
        ├── export_spec.lua
        ├── inline_spec.lua
        ├── lifecycle_spec.lua
        ├── markdown_spec.lua
        ├── mode_spec.lua
        ├── nav_spec.lua
        ├── parser_spec.lua
        ├── render_spec.lua
        ├── system_spec.lua
        ├── theme_spec.lua
        └── wrap_spec.lua
```

## License

MIT
