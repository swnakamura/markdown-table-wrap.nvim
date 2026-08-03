# Changelog

All notable changes to `markdown-table-wrap.nvim` are documented here.

## Unreleased

### Added

- Render pipe tables inside blockquotes, including callouts and nested `>` levels. Quote markers are stripped before parsing and redrawn in front of every rendered line with the new `MarkdownTableWrapQuote` highlight, and the rendered table is narrowed by the marker width so it stays inside the quote block. The marker follows the callout kind of the enclosing quote, so `> [!done]` keeps its green bar (`MarkdownTableWrapCallout{Info,Success,Hint,Warn,Error}`, linked to the `Diagnostic*` groups by default).
- `quote_icon` option controlling that marker: `"auto"` (default) follows render-markdown.nvim's quote bar when that plugin is loaded and uses the raw `>` otherwise, any string fixes the marker, and `false` draws none.
- `inline_line_numbers` (default `true`) draws window line numbers into rendered Inline table rows, honouring `'number'` and `'relativenumber'` and updating as the cursor moves.
- `inline_stable_height` (default `true`) pads the revealed cursor row with blank virtual lines so an Inline table keeps a constant screen height while the cursor moves through it.

### Changed

- `preview_mode` now defaults to `"inline"` again. The default render happens in place, inside the buffer being edited: it stays `modifiable`, the raw source row under the cursor is revealed so it can be edited while the rest of the table stays rendered, and no separate buffer is entered. Reader mode is unchanged and still available with `preview_mode = "reader"`, `:MarkdownTableReader`, or `:MarkdownTableToggleReader`; `reader.auto_open` keeps applying once Reader is the selected mode.
- `max_width_ratio` is now applied to the window's text area instead of its full width. The `'number'`, `'signcolumn'`, and `'foldcolumn'` widths are subtracted before the ratio, so a rendered table can no longer overflow into or past the gutter. With no gutter the result is unchanged. With one, tables are narrower than before: measured on an 80-column window with `'number'` on (a 4-column gutter), a four-column table that used to render 72 columns wide -- 76 including the gutter -- now renders 68 wide and wraps one row into an extra line; at 120 columns the same table goes from 108 to 104 columns wide with no change in line count.
- `inline_disable_wrap` now defaults to `false`. Rendered source rows are removed from the screen with `conceal_lines` on Neovim 0.11 or newer, so they cannot soft-wrap underneath the rendered table, and `'wrap'` has to stay on for the raw source row revealed under the cursor. Setting it to `true` still opts into the previous hard-replace behaviour, which also sets `'concealcursor'` so no row is revealed. `inline_wrap_scope` is only consulted when it is `true`.

### Fixed

- Table cell navigation now skips the blockquote markers instead of treating them as a leading cell.

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
