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
| `markdown_style` | `MarkdownStyler.apply()` |
| `sync_perform` | `SyncCoordinator.performSync()` |

### Automated budgets (`PerformanceBudgets.swift`)

| Budget | Value | Maps to |
|--------|-------|---------|
| `markdownStylePassMS` | 100 ms | NFR-01 (interim; target 16 ms in Phase 3) |
| `markdownParseMS` | 300 ms | NFR-01 |
| `coldVaultOpenMS` | 2,000 ms | NFR-02 (in-process proxy) |
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

## Revision history

| Date | Change |
|------|--------|
| 2026-07-03 | Phase 2: WAL/pragmas, list index, pagination, lifecycle flush, migration backup policy |
| 2026-07-03 | Phase 1: incremental vault cache, list summaries, debounced search, coalesced persist |
| 2026-07-03 | Phase 0: signposts, budgets, baseline tests, memory probe |
