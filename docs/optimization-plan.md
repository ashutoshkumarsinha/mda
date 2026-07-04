# MDE — Optimization Plan

> **Phase 0:** Baseline measurement & instrumentation (complete)  
> **Companion:** [spec.md](./spec.md) NFR-01–03

---

## Phase 0 — Baseline & instrumentation ✅

Establish budgets before changing behavior. View signposts in **Instruments → os_signpost** (subsystem `name.aks.mde`, category `Performance`).

### Signposts

| Signpost | Location |
|----------|----------|
| `vault_refresh_all` | `VaultStore.refreshAll()` |
| `vault_reload_notes` | `VaultStore.reloadNotes()` |
| `vault_reload_tag_tree` | `VaultStore.reloadTagTree()` |
| `vault_resolve_links` | `VaultStore.resolvePendingLinks()` |
| `vault_update_note` | (via `measureUpdateNote`) |
| `vault_persist_package` | `VaultStore.persistToPackageIfNeeded()` |
| `vault_list_page` | `VaultStore.fetchNoteSummariesPage` |
| `vault_export_database` | `VaultStore.exportDatabase()` |
| `markdown_parse` | `MarkdownParseActor.parse()` |
| `markdown_style` | `MarkdownStyler.apply()` (full document) |
| `markdown_style_incremental` | `MarkdownStyler.apply(styleRange:)` |
| `sync_perform` | `SyncCoordinator.performSync()` |

### Automated budgets (`PerformanceBudgets.swift`)

| Budget | Value | Maps to |
|--------|-------|---------|
| `markdownStylePassMS` | 100 ms | NFR-01 (full pass / reduce motion) |
| `incrementalMarkdownStyleMS` | 16 ms | NFR-01 (caret neighborhood) |
| `markdownParseMS` | 300 ms | NFR-01 |
| `coldVaultOpenMS` | 2,000 ms | NFR-02 (in-process proxy in `mdeTests`; true launch via `benchmark-cold-launch.sh`) |
| `memoryDelta1kNotesMB` | 120 MB | NFR-03 (test-host delta) |
| `refreshAll1kNotesMS` | 2,000 ms | Phase 0 capture |
| `updateNote1kVaultMS` | 1,000 ms | Autosave path |
| `persistPackage1kNotesMS` | 5,000 ms | Disk I/O |
| `search10kNotesMS` | 100 ms | FR-S04 |
| `syncRoundTripInMemoryMS` | 1,000 ms | Sync stack |

### Tests (`Phase0BaselineTests`)

Run: `xcodebuild -only-testing:mdeTests/Phase0BaselineTests test`

CI runs all `mdeTests` including Phase 0 gates.

---

## Phase 1 — Quick wins ✅

1. **Incremental `VaultStore` updates** — `applyNoteChanged` updates one list row + tag/link indexes instead of `refreshAll` on autosave.
2. **Lightweight list rows** — `NoteListItem` + SQL snippet projection; editor loads body via `fetchNote(id:)`.
3. **Debounced FTS search** — 200 ms debounce in `NoteListView`.
4. **Title / WikiLink caches** — in-memory `titleIndex` rebuilt on list changes.
5. **Coalesced package persist** — `markPackageDirty()` + 3 s debounced `persistToPackageIfNeeded()`; `flushPackageIfNeeded()` on explicit save.

### Tests (`Phase1OptimizationTests`)

Run: `xcodebuild -only-testing:mdeTests/Phase1OptimizationTests test`

---

## Phase 2 — Data layer & disk ✅

1. **SQL list projection** — completed in Phase 1 (`VaultStore+ListQuery`); Phase 2 adds `LIMIT`/`OFFSET` paging.
2. **WAL + pragma tuning** — `DatabaseConfiguration` sets WAL, `cache_size`, `mmap_size`, `temp_store`.
3. **List-order index** — migration `v2_list_query_index` on `(is_deleted, is_pinned, updated_at)`.
4. **Migration backup policy** — backup only when pending schema migrations exist (not every open).
5. **Package lifecycle flush** — `vaultPackageLifecycle` flushes on iOS background / macOS terminate; 5 min periodic persist if dirty.
6. **Windowed note list** — `noteSummariesPage` + infinite scroll in `NoteListView` (100 rows/page).

### Tests (`Phase2OptimizationTests`)

Run: `xcodebuild -only-testing:mdeTests/Phase2OptimizationTests test`

---

## Phase 3 — Editor optimization ✅

1. **Incremental styling** — `MarkdownStyler.apply` accepts `styleRange`; styles caret neighborhood (±1 line) only during typing.
2. **Parse cache** — `MarkdownParseActor` reuses constructs when `text.hashValue` unchanged; skips swift-markdown `Document` parse.
3. **Shared controller** — `MarkdownEditorStyleController` coordinates debounced parse + apply for macOS/iOS.
4. **iOS textStorage path** — `MarkdownUITextView` mutates `textStorage` in place (no `attributedText` reassignment).
5. **Signpost** — `markdown_style_incremental` for neighborhood passes.

### Budgets

| Budget | Value | Maps to |
|--------|-------|---------|
| `incrementalMarkdownStyleMS` | 16 ms | NFR-01 keystroke styling |
| `markdownStylePassMS` | 100 ms | Full-document / reduce-motion |

### Tests (`Phase3OptimizationTests`)

Run: `xcodebuild -only-testing:mdeTests/Phase3OptimizationTests test`

---

## Phase 4 — Sync & network ✅

1. **Smarter scheduling** — debounced push uses `SyncPolicy.editDebounceSeconds`; bootstrap skips pull when token is fresh and `lastSyncedAt` is within 5 minutes with no pending uploads.
2. **Delta uploads** — skip upload when `syncBase.checksum` matches current payload; per-note dequeue.
3. **Persisted change token** — `VaultMeta.cloudChangeToken` survives relaunch for incremental CloudKit fetch.
4. **Background / network** — `SyncLifecycle` pauses auto-sync on iOS background; `SyncNetworkMonitor` drives offline state via `NWPathMonitor`.
5. **Record size guard** — reject encrypted payloads over 1 MB before upload.

### Tests (`Phase4OptimizationTests`)

Run: `xcodebuild -only-testing:mdeTests/Phase4OptimizationTests test`

---

## Phase 5 — SwiftUI & platform UI ✅

1. **Granular observation** — `VaultListState` (list revision, tag tree) and `VaultEditorState` (content epoch, links, save errors) limit view invalidation; list/editor views bind to the narrow state surfaces.
2. **Equatable list rows** — `NoteListRow` precomputes display strings; `NoteRowView` is `Equatable` with `.id(rowIdentity)` keyed on `updatedAt`.
3. **Deferred sync bootstrap** — `ContentView` waits for `isPackageBound` (set after `attachToPackage`) before creating `SyncCoordinator`.
4. **iOS compact layout** — `ZStack` keeps tags, notes, and editor layers mounted; navigating back preserves editor state.
5. **Lazy detail column** — split layout builds `NoteEditorView` only when a note is selected.
6. **Dynamic Type cap** — editor font size capped at `.accessibility3` (29 pt) for layout stability.

### Tests (`Phase5OptimizationTests`)

Run: `xcodebuild -only-testing:mdeTests/Phase5OptimizationTests test`

---

## Phase 6 — Observability & budgets ✅

### 6.1 Benchmark suite (`Phase6ObservabilityTests`)

| Test | Budget |
|------|--------|
| Cold launch (simulated store open) | &lt; 2 s (`coldVaultOpenMS`) |
| Memory after 1k lightweight notes | &lt; 150 MB (`memory1kNotesNFR03MB`) |
| Keystroke styling p95 (40 samples) | &lt; 16 ms (`incrementalMarkdownStyleMS`) |
| FTS 10k | &lt; 100 ms (`search10kNotesMS`) |
| Package persist time + DB size | &lt; 5 s, &lt; 20 MB |

Helpers: `PerformancePercentile`, `VaultStore.measurePersistPackageRegression(at:)`.

### 6.2 DEBUG overlays

- `PerformanceMetricsRecorder` captures signpost interval last/avg/count.
- **Developer** toolbar sheet (`DeveloperSettingsView`): memory gauge + signpost table.
- Profile with Instruments — see [instruments-performance.md](./instruments-performance.md).

### 6.3 CI gates

- **macOS:** build + full `mdeTests` (Phase 0–6 baselines).
- **iOS Simulator:** build + `mdeTests` smoke (first available iPhone simulator).

### Tests (`Phase6ObservabilityTests`)

Run: `xcodebuild -only-testing:mdeTests/Phase6ObservabilityTests test`

---

## Phase 7 — Product enhancements ✅

Resource-aware UX improvements from the optimization roadmap:

| Enhancement | Resource benefit |
|-------------|------------------|
| **Trash UI + purge** | Smaller DB, faster FTS after `VACUUM` |
| **Export single note** | One `fetchNote` — no full vault export |
| **Pinned & Recent default filter** | Smaller list working set (30-day window) |
| **Empty trash** | Reclaim disk |
| **On-demand backlinks** | SQL only when disclosure expands |
| **Reduce Motion** | Already wired in editor (Phase 3) |

### Tests (`Phase7EnhancementTests`)

Run: `xcodebuild -only-testing:mdeTests/Phase7EnhancementTests test`

---

## Gap closure ✅

| Item | Status |
|------|--------|
| Trash note preview in editor | `fetchListItem` + read-only trash banner |
| List reload on body-only edit | `listRevision` skips when title/snippet/pin unchanged |
| Code fences & blockquotes | `MarkdownConstruct` + `MarkdownStyler` |
| Full vault export | `exportVaultAsCombinedMarkdown()` + single-file & folder Vault menu |
| Markdown import | `importMarkdownFile` / `importMarkdownDirectory` |
| Link graph UI | `WikiLinkGraphView` v2 — force-directed layout, pan/zoom, focus, unresolved nodes |
| `MarkdownTokenTextStorage` | macOS editor uses hybrid `NSTextStorage` path |
| Persisted perf baselines | `performance-baselines.json` + `PerformanceRegressionGate` |
| Instruments trace template | `docs/instruments/MDE Performance.tracetemplate` + `record-mde-profile.sh` |
| True cold-launch benchmark | `benchmark-cold-launch.sh` + `cold_launch_to_editor` signpost |
| 10% regression CI gate | `PerformanceRegressionGate` + `CompletionTests` |
| iOS UITests in CI | `mdeUITests` job on simulator (launch, scroll, vault menu) |

### Tests (`CompletionTests`)

Run: `xcodebuild -only-testing:mdeTests/CompletionTests test`

---

## Revision history

| Date | Change |
|------|--------|
| 2026-07-03 | Gap closure: import/export vault, graph, markdown constructs, trash preview, regression gate |
| 2026-07-03 | Phase 7: trash purge UI, note export, focused list filter, on-demand backlinks |
| 2026-07-03 | Phase 6: p95 style gate, NFR-03 memory ceiling, persist size regression, DEBUG developer overlay, iOS CI smoke |
| 2026-07-03 | Phase 5: granular observation, equatable rows, deferred sync, iOS compact ZStack, editor Dynamic Type cap |
| 2026-07-03 | Phase 2: WAL/pragmas, list index, pagination, lifecycle flush, migration backup policy |
| 2026-07-03 | Phase 1: incremental vault cache, list summaries, debounced search, coalesced persist |
| 2026-07-03 | Phase 0: signposts, budgets, baseline tests, memory probe |
