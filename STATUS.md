# Status of the `reveal-cursor-row` branch

This fork renders Markdown tables in place in the buffer being edited (row-anchored inline replace
mode with the cursor row revealed raw). It diverged from upstream on purpose and does not merge
upstream v1.0 (Reader-first); single upstream features are ported instead.

- Open questions for the owner: [QUESTIONS.md](QUESTIONS.md).
- Scope locks, builder/reviewer reports and probes of the review loops live in the git-ignored
  `tmp/` directory of the working copy (`tmp/scope-lock-*.md`, `tmp/followup-ledger.md`).

## Current work (2026-10-28)

| Task | State |
|---|---|
| Remove Reader (cc548c8), legacy overlay + Neovim 0.11 (6f516eb), test-prune pass, `below` fix (d37afbd), remove map_gx (a6d38da), tests for untested behaviour (69fdfde), docs (fd03807) | done |
| G1: adjacent tables drawn together, upper above lower (42c80dc) | done |
| F: conceallevel raised locally and handed back without leaks (437fafd) | done |
| G2: render_all = false drift after an edit that keeps the table text (changedtick in table_signature, 70f04b8) | done |
| I: the transient misdrawing between an edit and the debounced refresh (80 ms by default) — dropped by the owner (Q3 answer, 2026-10-28: too small to be worth the complexity). | dropped |
| J: the `Invalid 'line': out of range` error from CursorMoved/WinScrolled after `25G` `dgg` on a buffer ending with a table (tmp/manual/q3_dgg.md). Owner decision (Q4, 2026-10-28: option 1): when a recorded row lies outside the current buffer, skip re-anchoring and leave it to the next refresh; nothing else of the dropped Task I | next |
| H: in Visual mode, show only the tables inside the selection raw (2c22107) | done |

## On hold

One line per item: origin — content — disposition (empty while open) — date.

- Phase A review — `close_preview` has no test — fixed: 69fdfde — 2026-10-28
- Phase A review — Float chunk highlights untested — fixed: 69fdfde — 2026-10-28
- Phase A/B builders — extmark ids depended on string interning (`pairs()` in update_reveal) — fixed: 42c80dc — 2026-10-28
- Phase A review — PUBLISHING.md v0.2.x release-note drafts still mention Reader — dropped: historical drafts of upstream releases — 2026-10-27
- Removal feasibility — anchored replace breaks when the user's own 'concealcursor' contains the current mode (render-markdown sets it to '' so the owner is unaffected) — — 2026-10-27
- Phase B review — Neovim < 0.11: plugin loader + a user setup() give two ERROR notifications (one per call, as specified) — dropped: owner runs 0.12 — 2026-10-27
- Phase B review — CI on v0.11.0 not verified locally (only 0.12 installed) — — 2026-10-27
- test-prune audit — dead code: parser `\|` gsub (the ported inline parser handles escapes); export `setreg("0")` changes nothing — — 2026-10-27
- Task C/D feasibility — `parse_inline` still deep-copies every token per cell although nothing reads `tokens` since extract_links was removed — — 2026-10-27
- Task D review — nav.lua `iter_chars_with_pos` is unused — — 2026-10-27
- Task D review — link_icon iterates `link.custom` with pairs(); two patterns matching one URL can pick a different icon per run — — 2026-10-27
- Task D review — quarto/rmd buffers (no Tree-sitter by default) open a table link only from its URL text — dropped: owner works in markdown — 2026-10-27
- Task D re-review — README/help "with the cursor on the URL, it opens the URL" does not hold where gx falls back to <cfile> (URL with parentheses cut at '(') — — 2026-10-27
- Task C review — insert-mode dim marks drift after `ddP` — fixed: 70f04b8 — 2026-10-28
- Task C review — help/README default blocks showed wrong auto_preview_in_insert / clear_on_insert — fixed: fd03807 — 2026-10-28
- Task C review — inline_position is not part of the render signatures (only a direct M.config edit would leave a stale anchor) — dropped: setup() re-renders — 2026-10-28
- Task D review — the "leftover map_gx" test checks only buffers never shown in a window — dropped: no gx handling remains — 2026-10-27
- Task E builder — a split off a rendered window kept conceallevel 2 after clearing — fixed: 437fafd — 2026-10-28
- Task E builder — lifecycle_spec BufWipeout test asserts visual_buffers is cleared but never sets it (trivially true) — — 2026-10-28
- Task E review — :MarkdownTableClosePreview pause undocumented — fixed: fd03807 — 2026-10-28
- Task E review — tests/helpers.lua `screen_line` ignores 'winbar', reads blanks for floats, has no bound check — — 2026-10-28
- Task E review — the Visual-mode clear keeps window options (keep_window), documented only in code comments — fixed: 2c22107 (keep_window remains only in the fallback) — 2026-10-28
- Task E review / F review — flaky "BufLeave restores conceallevel": two existing tests ("a window that keeps its rendering on leave keeps its options", "repeated setup disposes the inline renderings") leave the origin window's global conceallevel at 1 and the flaky test's vsplit inherits it — — 2026-10-28
- Task E review — tests/README.md coverage map lacks the newer areas — — 2026-10-28
- Task E re-review — render_spec quoted-table test assumes an 80-column window only in a comment; mode_spec ClosePreview test restores conceallevel only on success; gutter test keeps looping after a failed precondition — — 2026-10-28
- G1 review — no test pinned the view repair — fixed: 42c80dc — 2026-10-28
- G1 review — Ctrl-Y with the topline just below a tall table jumps several lines (same before G1) — — 2026-10-28
- F review — `:noautocmd close` / `:noautocmd buffer` / noautocmd floats can keep a stored raised 2 (no event fires) — dropped: not observable — 2026-10-28
- F review — `:bdelete` of a rendered buffer leaves it marked active, so `:buffer A` raises conceallevel with nothing rendered (same before F) — — 2026-10-28
- F re-review — no test pins that the cursor-move repair saves a lowered level equal to the global value (mutant R02) — — 2026-10-28
- F re-review — CHANGELOG F entry omits the setlocal-2-before-first-render case and noautocmd pickups — — 2026-10-28
- G2 review — no test pins that render_all = false skips the re-render on a cursor move (a signature that changes on every call passes the suite; checked only by measurement: `jjkk` renders 0 times) — — 2026-10-28
- G2 review — render_all = false with clear_on_visual = false: an edit followed by `v` within the debounce leaves the drift after `<Esc>` until the next cursor move (the debounced refresh returns in Visual mode and ModeChanged returns early when clear_on_visual is false; same before G2) — — 2026-10-28
- G2 review — clear_on_cursor_leave = false: an edit made while another window is current (`win_execute`, an LSP edit) stays drawn wrongly until the user returns to the rendered window (refresh_auto refreshes only the current buffer; same before G2) — — 2026-10-28
- H review — restoring the 302-row table mid-selection costs 12-20 ms, about 1.5x a Normal-mode entry into it (H-AC2 asked for ≤ 6-14 ms; not a regression of Normal mode) — — 2026-10-28
- H builder — a write whose BufWritePre hook edits the text (a formatter) makes the next Visual session show every table raw until the refresh; selecting per table there would need rows re-read from marks (dropped Task I) — — 2026-10-28
- H review — Select mode has no suite test (probed correct: `gh` hides nothing, `v<C-g>` restores, `<C-g>` back hides) — — 2026-10-28
- F review — auto_preview = false: manual render, then Visual mode leaves the table gone and the window raised — fixed: 2c22107 — 2026-10-28
