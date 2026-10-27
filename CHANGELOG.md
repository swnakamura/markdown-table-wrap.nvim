# Changelog

All notable changes to `markdown-table-wrap.nvim` are documented here.

## Unreleased

### Added

- Render pipe tables inside blockquotes, including callouts and nested `>` levels. Quote markers are stripped before parsing and redrawn in front of every rendered line with the new `MarkdownTableWrapQuote` highlight, and the rendered table is narrowed by the marker width so it stays inside the quote block. The marker follows the callout kind of the enclosing quote, so `> [!done]` keeps its green bar (`MarkdownTableWrapCallout{Info,Success,Hint,Warn,Error}`, linked to the `Diagnostic*` groups by default).
- `quote_icon` option controlling that marker: `"auto"` (default) follows render-markdown.nvim's quote bar when that plugin is loaded and uses the raw `>` otherwise, any string fixes the marker, and `false` draws none.
- `inline_line_numbers` (default `true`) draws window line numbers into rendered Inline table rows, honouring `'number'` and `'relativenumber'` and updating as the cursor moves.
- `inline_stable_height` (default `true`) pads the revealed cursor row with blank virtual lines so an Inline table keeps a constant screen height while the cursor moves through it.
- `:MarkdownTableExport[!] [tsv|csv]` and `export_table()`, ported from upstream v0.5.0 (with its later register and formula fixes): copy the table under the cursor, or every table with `!`, as TSV or CSV into the unnamed and `"0` registers, and into `"+` / `"*` as `'clipboard'` asks. CSV prefixes formula-leading values with `'` unless `csv_formula_policy = "raw"`; a table with more body cells than header cells is refused instead of being exported without them.

### Changed

- `preview_mode` now defaults to `"inline"` again. The default render happens in place, inside the buffer being edited: it stays `modifiable`, the raw source row under the cursor is revealed so it can be edited while the rest of the table stays rendered, and no separate buffer is entered. Reader mode, the previous default, has been removed; see Removed below.
- `max_width_ratio` is now applied to the window's text area instead of its full width. The `'number'`, `'signcolumn'`, and `'foldcolumn'` widths are subtracted before the ratio, so a rendered table can no longer overflow into or past the gutter. With no gutter the result is unchanged. With one, tables are narrower than before: measured on an 80-column window with `'number'` on (a 4-column gutter), a four-column table that used to render 72 columns wide -- 76 including the gutter -- now renders 68 wide and wraps one row into an extra line; at 120 columns the same table goes from 108 to 104 columns wide with no change in line count.
- Inline replace mode no longer changes `'wrap'` or `'concealcursor'`; it only raises `'conceallevel'` while a table is rendered and hands the previous value back when the rendering is cleared. Rendered source rows are removed from the screen with `conceal_lines`, so they cannot soft-wrap underneath the rendered table, and `'wrap'` has to stay on for the raw source row revealed under the cursor. The options that used to change them are removed; see Removed below.
- Neovim 0.11 is now the minimum version. On older Neovim, `setup()` reports an error and sets nothing up (no autocommands, commands, or rendering), and `:checkhealth markdown-table-wrap` reports an error. CI tests Neovim 0.11.0 and stable.

### Removed

- Reader mode, the separate non-modifiable buffer that mirrored the whole document with its tables rendered as real lines. Removed with it: `preview_mode = "reader"`, the `reader` option table, the commands `:MarkdownTableReader`, `:MarkdownTableToggleReader`, and `:MarkdownTableEditSource`, the Lua functions `reader_preview()`, `close_reader()`, `toggle_reader()`, `edit_source()`, and `pause_buffer()`, and the `reader=` field of `:MarkdownTableStatus`. A configuration that still sets `preview_mode = "reader"` falls back to the default `"inline"`, as any other invalid value does, and a leftover `reader` table is ignored like any unknown option. Use the inline default or `preview_mode = "float"` instead.
- The legacy Inline replace path that drew rendered rows as overlay virtual text over concealed source lines, which was used below Neovim 0.11 and for viewport scrolling. Removed with it: viewport scrolling (`inline_viewport_scrolling`, the commands `:MarkdownTableToggleInlineViewport`, `:MarkdownTableScrollDown`, `:MarkdownTableScrollUp`, `:MarkdownTableScrollTop`, and `:MarkdownTableScrollBottom`, and the Lua functions `scroll_view()`, `scroll_view_to()`, and `toggle_inline_viewport_scrolling()`); the options `inline_virtual_text`, `overlay_fill`, `inline_disable_wrap`, and `inline_wrap_scope`; the `MarkdownTableWrapBlank` highlight and its `blank` theme key; and the `/viewport` or `/full` suffix and the `wrap=` field of `:MarkdownTableStatus`. Leftover options and a leftover `blank` theme key are ignored like any unknown key.
- The `map_gx` option and the `:MarkdownTableOpenLink` command. The row under the cursor is revealed as raw Markdown, so Neovim's own `gx` opens a link there: from the label or the URL of `[label](url)` in `markdown` buffers, where Neovim starts Tree-sitter highlighting; only from the URL where Tree-sitter is not running (for example `quarto` and `rmd`, unless you start it); and for the non-standard `(text)[url]` form only from its URL part. A leftover `map_gx` key is ignored like any unknown key. The floating preview keeps its own `gx`.

### Fixed

- The configuration examples in the README and the help now show the real defaults, `auto_preview_in_insert = true` and `clear_on_insert = false`, and the help's example lists `inline_line_numbers` and `inline_stable_height`. `:MarkdownTableClosePreview` is documented as also stopping automatic rendering in the buffer until `:MarkdownTablePreview`, `:MarkdownTableToggleInline` or `:MarkdownTableEnableAutoPreview` turns it back on, which it has always done.
- Table cell navigation now skips the blockquote markers instead of treating them as a leading cell.
- Cell text follows CommonMark's inline rules, using the inline parser ported from upstream v1.0.0. Intraword underscores no longer start emphasis, so `snake_case_name`, file names, and URLs keep their `_`; backslash escapes such as `\*` and `\_` show the literal character; link destinations may contain balanced parentheses; `<https://...>` and `<user@host>` autolinks render as links; emphasis and links nest; double-backtick code may contain a backtick; and `[[note|alias]]` shows the alias. `:MarkdownTableExport` exports the same corrected text.
- A link inside emphasis (`**see [doc](url)**`) renders once, with its icon, instead of as raw Markdown. Upstream's parser has the same nesting and printed such a link twice; the link icons are now inserted without assuming that spans never overlap.
- Delimiter cells with one or two hyphens (`|-|-|`, `| :-- | --: |`, `-|-|-`) are accepted, as GFM allows. Such tables were left unrendered.
- Rendered rows no longer outgrow their column and push the borders out of line. Inline code wider than its column is wrapped, preferably after `:`, `.`, `/`, `_`, `-`, or `=`; code that fits still moves to the next line whole. A trailing space now counts when deciding whether the next character fits, so `word x` no longer lands on one line in a five-cell column. Tabs in a cell render as one space. A column holding a wide character is never narrowed below two cells. Ported from upstream v0.3.0 and v0.8.0.
- Wrapping also prefers to break after `。`, `！`, `？`, and `：`, as it already did after `、` and `，`, instead of splitting the next sentence mid-word.
- `inline_position = "below"` in Inline insert mode now draws the rendered table after the table's last row. It was drawn right after the header row, between the header and the delimiter row. `"above"` is unchanged.
- Tables with no line between them, such as a table inside a blockquote directly followed by one outside it, are now all drawn in Inline replace mode, in source order, wherever the cursor is. The upper table disappeared while the cursor was outside it, a lower table that ends the buffer disappeared while the cursor was in the upper one, and with the cursor on the lower table's first row its top border could, from one session to the next, be drawn above the whole upper table.

## 0.2.3 - Inline Rendering Corrections

### Fixed

- Keep linked semantic table highlights background-transparent so Inline replace
  mode does not render black or colorscheme-filled rectangles inside cells.
  Explicit `bg` values remain supported for intentional cell or token fills.
- Remove paired inline-code delimiters from link and image labels before width
  calculation so concealed backticks cannot shift Inline table separators.

## 0.2.2 - Stability And Editor Coexistence

### Added

- Add `reader.auto_open = "has_table" | "always"`. The default enters Reader
  automatically only when a supported buffer contains a table; `"always"`
  preserves the previous all-document Reader behavior.
- Add `rmd` to the built-in filetypes so standard Neovim R Markdown detection
  works without `extra_filetypes`.
- Add `get_buffer_config(bufnr)` and `get_preview_mode(bufnr)` for inspecting
  effective per-buffer view configuration.
- Reapply semantic table highlights after `ColorScheme` events.
- Add regression coverage for large invalid pipe candidates, buffer-local
  scheduling/modes, mapping preservation, lifecycle cleanup, and compact border
  highlight spans.

### Changed

- Default `map_gx` to `false`, leaving existing Source-buffer `gx` mappings
  untouched. Table-aware link opening remains available in Reader, through
  `:MarkdownTableOpenLink`, or by explicitly setting `map_gx = true`.
- Keep runtime view, auto-preview, inline viewport, and deferred refresh state
  per buffer instead of mutating global setup values.
- Scan buffer lines and fenced blocks in one parsing pass, avoiding the previous
  quadratic worst case on long runs of pipe-like text.
- Accept top-level tables indented by up to three spaces, normalize body rows
  with missing cells (including eligible rows without a literal pipe), and stop
  before blockquote/list/other Markdown block starts.
- Track arbitrary-length backtick runs while splitting table rows so matching
  code spans can safely contain pipes.
- Merge continuous border highlights into ranges instead of creating an extmark
  for every border character.
- Automatically keep table-free Markdown in Source under the new default Reader
  policy.

### Fixed

- Preserve, invoke, and restore existing callback, string, and expression `gx`
  mappings outside table cells when the table-aware mapping is explicitly
  enabled.
- Prevent delayed refresh work in one buffer from being cancelled by or applied
  to another buffer.
- Restore Inline window-local wrap and conceal options when leaving or clearing
  a rendered buffer, and dispose retained buffer state on wipeout.
- Keep all wrapped header rows on the Header highlight path in Inline replace
  and insert modes.
- Dispose stale Inline viewport offsets during repeated `setup()` calls.
- Cancel delayed refreshes belonging to a previous `setup()` instance and
  reconfigure open Reader windows with the new Reader options while closing
  stale Float previews.
- Apply `:MarkdownTableDisableAutoPreview` from Reader to its backing source
  buffer instead of the protected Reader scratch buffer.
- Validate nested Reader options before applying them to a window.
- Preserve custom theme presets supplied through setup instead of replacing them
  during validation.
- Let direct custom highlight specs replace a preset's linked base highlight,
  and replay those overrides correctly after a colorscheme change.

## 0.2.1 - Reader Workflow And Regression Coverage

### Added

- Add coverage for Reader refresh and save forwarding, configuration validation,
  navigation, fitting behavior, wrapping metadata, and lazy-loading timing.
- Test the supported Neovim 0.10 baseline and stable Neovim in GitHub Actions.
- Add `tests/README.md` with the automated coverage map and release-only manual
  checks for terminal, compositor, and extmark interactions.
- Add `:MarkdownTableToggleInline` for switching from Reader or Source to an
  editable inline rendering layer.

### Fixed

- Ignore table-shaped text inside backtick- and tilde-fenced code blocks.
- Keep cell navigation correct when double-backtick inline code contains pipes.
- Install the table-aware `gx` mapping when a supported buffer existed before
  plugin setup, including filetype-based lazy-loading flows.
- Validate malformed nested configuration values before they reach rendering.

## 0.2.0 - Full-Document Reader

### Added

- Add a full-document reader mode with `preview_mode = "reader"`.
- Replace pipe tables with real Unicode buffer lines in reader mode while leaving the source Markdown buffer unchanged.
- Add `:MarkdownTableReader`, `:MarkdownTableToggleReader`, and `:MarkdownTableEditSource`.
- Preserve native wrapping for non-table Markdown in reader mode.
- Support direct source editing, Visual selection, and rendered-link `gx` navigation from the reader.
- Add `fit_to_window = true` so many-column tables may shrink below the preferred column width when required to fit the text area.

### Changed

- Make Reader the default preview mode so every table is rendered without cursor focus.
- Keep Visual selection inside Reader so copying uses real rendered lines and remains in Reader after yank.

### Fixed

- Avoid raw source pipes leaking from soft-wrapped Markdown table rows by using real rendered lines in reader mode.
- Account for the window text offset, including number, sign, and fold columns, when calculating rendered table width.

### Notes

- Inline mode remains available for source-position-preserving overlays. Reader mode is recommended when native prose wrapping and stable always-visible tables are both required.

## 0.1.5 - Cursor-Scoped Inline Wrapping

### Added

- Add cursor-scoped inline wrapping through `inline_wrap_scope = "cursor"`.
- Restore ordinary Markdown paragraph wrapping when the cursor leaves an inline table.

### Fixed

- Avoid disabling `wrap` for the entire Markdown window when inline tables are rendered with the default cursor-scoped policy.

## 0.1.4 - Floating Link Navigation

### Fixed

- Add buffer-local `gx` support inside floating table previews.
- Open the original URL instead of the rendered link label.
- Preserve link URL metadata through wrapping and rendering.
- Support links spanning multiple rendered lines.
- Prevent native `gx` from opening labels such as `youtube` or `Details`.

## 0.1.3 - Inline Selection And Extra-Line Highlights

### Added

- Add `clear_on_visual` so Inline reveals source Markdown during Visual,
  Visual-Line, and Visual-Block selection, then renders again after selection.

### Fixed

- Use the correct rendered-row index when styling extra Inline virtual lines.

## 0.1.2 - Setup And Defaults Cleanup

### Fixed

- Avoid overriding user configuration when `setup()` is called manually before `plugin/markdown-table-wrap.lua` is sourced, which affects package managers such as `vim.pack`.

### Changed

- `inline_viewport_scrolling` now defaults to `false` so the full rendered table is visible inline on first use.
- `highlight_preset` now defaults to `default`, which links into standard Neovim highlight groups and fits arbitrary colorschemes more naturally.
- Documentation now explains inline viewport behavior near the top of the help text instead of only through commands and options.

## 0.1.1 - Inline Rendering Compatibility Fixes

### Changed

- Default inline replace rendering now uses `inline_virtual_text = "overlay"` for a more portable extmark rendering path.
- Inline replace mode now temporarily disables window-local `wrap` by default through `inline_disable_wrap = true`.

### Fixed

- Prevent source Markdown fragments from leaking below inline rendered tables when long concealed rows soft-wrap on some Linux terminal setups.
- Keep inline table rendering behavior aligned more closely between macOS and Linux in viewport mode.

## 0.1.0 - Initial Public Release

### Added

- Inline replacement renderer for Markdown pipe tables.
- Floating table preview fallback.
- Automatic whole-buffer table rendering in Markdown buffers.
- Source reveal in Insert mode and rendered table view in Normal mode.
- Inline viewport scrolling for rendered tables taller than the source table.
- Toggle command for switching between viewport-sliced and full inline rendering.
- Floating preview can be used for long-table reading without clearing inline rendering.
- Cell wrapping with CJK/English display width support through `vim.api.nvim_strwidth`.
- Escaped pipe support and inline-code-aware pipe splitting.
- Single-backtick and double-backtick inline code spans.
- Inline Markdown display for code, bold, italic, strikethrough, links, and `<br>` hard breaks.
- Inline highlight syntax with `==text==`.
- Link icon configuration for wiki links, images, and custom URL patterns such as GitHub, YouTube, and Bilibili.
- Tokyo Night, Catppuccin, default, render-markdown-inspired, and auto highlight presets.
- Inline custom themes and theme-directory loading.
- Source-aware table cell navigation commands.
- Viewport top/bottom jump commands for long inline tables.
- Headless Neovim regression suite and GitHub Actions CI.
- `:checkhealth markdown-table-wrap`.
- LazyVim/lazy.nvim installation documentation.

### Known Limitations

- Inline replacement uses virtual text and optional virtual lines, which are visual rows rather than real buffer lines.
- Treesitter-aware table discovery is not implemented yet.
- This release is table-focused and intentionally does not replace general Markdown rendering.
