# MDE — v4 Enhancement Roadmap (Draft)

> **Status:** Planning (2026-07-04)  
> **Companion:** [spec.md](./spec.md) · [v3-roadmap.md](./v3-roadmap.md) · [optimization-plan.md](./optimization-plan.md)

v1–v3 delivered a complete local-first wiki: hybrid editor, tags, sync, assets, tables, and full export/import round-trip. v4 focuses on **smarter import**, **editor polish**, **capture UX**, and **quality** — still without plugins, third-party sync, or non-Apple clients.

---

## Guiding principles

| Principle | Implication |
|-----------|-------------|
| Local-first | Every feature must work offline; sync is additive |
| Minimal surface | Prefer one great path over many half-finished options |
| Interop over lock-in | Import/export should preserve IDs and metadata where possible |
| Hybrid editor | Keep raw markdown as source of truth; preview stays caret-aware |

---

## Themes

| Theme | User value |
|-------|------------|
| **Import intelligence** | Merge package imports instead of always duplicating notes |
| **Editor completeness** | Ordered lists, italic constructs, link bracket editing |
| **Capture & navigation** | Faster note creation, better findability |
| **Reliability** | Flaky tests, import edge cases, sync after import |

---

## Phased delivery

### v4.0 — Smart package import *(recommended first)*

**Problem:** v3 import always creates new notes with new IDs. Re-importing an export duplicates the vault; asset refs work but links/backlinks/sync bases break.

| Item | Description |
|------|-------------|
| Import modes | **Add** (current) vs **Merge by manifest note id** vs **Replace vault** (destructive, confirmed) |
| ID preservation | Optional `createNote(id:content:)` path when manifest `note.id` is unused |
| Asset upsert | Already partial — ensure `note_asset` links rebuilt after merge |
| Sync hooks | Enqueue merged notes + referenced assets for sync push |
| UI | Import sheet: mode picker when export package detected |

**Exit:** Export → import merge → same note IDs, backlinks intact, sync queue populated. Tests: `VaultPackageImportMergeTests`.

---

### v4.1 — Editor markdown gaps

**Problem:** Spec lists constructs that are styled inline but lack hybrid token treatment or full construct coverage.

| Item | Priority | Notes |
|------|----------|-------|
| Ordered lists (`1. item`) | High | Parser + list paragraph style (unordered exists) |
| Italic as construct | Medium | `*text*` hybrid hide like bold; avoid `**` false positives |
| External link bracket editing | Medium | Deleting `[` removes whole link (parity with WikiLinks) |
| Strikethrough `~~text~~` | Low | Style-only; no construct required for v4 |
| Update spec §5.2 | — | Document `[[Note\|alias]]` (shipped v3.2) |

**Non-goals:** WYSIWYG table cell editor (remain raw markdown), HTML blocks, LaTeX.

**Exit:** Construct tests for ordered list + italic; manual bracket-delete behavior for links.

---

### v4.2 — Capture & list UX

**Problem:** Power users want faster entry and tighter list control without folders.

| Item | Description |
|------|-------------|
| Note templates | 3–5 built-in starters (Meeting, Daily, Project); stored as `.md` snippets in app bundle |
| Quick note | ⌘⇧N creates note with focus in editor; optional default tag in settings |
| Combined filter | Tag + FTS query (e.g. `#work` + "budget") |
| Sort options | Title A–Z / updated (pinned still first) — list scope already has pinned/recent |
| iOS Share extension | Append to inbox note or create from Share sheet (new target) |

**Exit:** Template picker on new note; combined search returns intersection; Share extension smoke test.

---

### v4.3 — Graph & link UX

**Problem:** Graph is useful but passive; unresolved links require manual create flow.

| Item | Description |
|------|-------------|
| Graph search / filter | Highlight node by title; dim unrelated edges |
| Open in editor from graph | Double-click / long-press → select note in list |
| Backlink preview | Hover or accessory shows one-line snippet (macOS) |
| Alias display in graph | Node label uses display text when edge originates from aliased link (optional) |
| Bulk link repair | After import merge, background job resolves titles that changed |

**Exit:** Graph focus + navigate; backlink snippet in panel.

---

### v4.4 — Sync & import hardening

**Problem:** Edge cases from v2.4/v3 remain possible in multi-device workflows.

| Item | Description |
|------|-------------|
| Import without package | Clear banner: assets skipped; offer Save to Package |
| Post-import sync bootstrap | One-shot `enqueueSync` for all imported notes |
| Conflict audit | Settings → last 10 sync conflicts with timestamps (read-only log) |
| Test stability | Serialize or isolate flaky `phase0SyncRoundTripInMemory` |
| Zip edge cases | Central directory reader fallback if sequential scan misses entries |

**Exit:** CI green without parallel sync flakes; import-asset banner test.

---

### v4.5 — Performance & observability (Phase 8)

**Problem:** Budgets exist; product growth (images, tables, larger vaults) needs re-baselining.

| Item | Target |
|------|--------|
| Style incremental path | Table + image constructs only re-style affected block |
| Large vault list | Virtualize or cap snippet work > 5k notes |
| Asset thumbnail cache | Memory-bounded LRU for inline images |
| Re-baseline | Update `performance-baselines.json` after v4 editor changes |
| Instruments | Document import + merge profile in `docs/instruments/` |

**Exit:** No regression vs Phase 6 gates; optional 5k-note list benchmark.

---

## Backlog (v5+ candidates)

Evaluate after v4 ships; not committed.

| Idea | Rationale |
|------|-----------|
| **Notion export import** | High demand; HTML-heavy, needs dedicated parser |
| **Daily notes / date titles** | `[[2026-07-04]]` auto-note pattern |
| **PDF export** | Print-friendly; separate from markdown zip |
| **Spotlight / Core Spotlight** | macOS/iOS system search into vault |
| **Watch / widget glance** | Read-only recent notes |
| **CRDT visual diff** | Show merge hunks on conflict (beyond LWW banner) |
| **Vault-level full-text in tags** | Search scoped to tag subtree only (partial today via filter) |

---

## Non-goals (unchanged)

Web/Windows/Linux clients · Real-time co-editing · Third-party sync (Dropbox, etc.) · Plugin marketplace · HTML/Mermaid blocks in editor

---

## Suggested implementation order

```
v4.0 Smart import  →  v4.1 Editor gaps  →  v4.4 Hardening
        ↓                                        ↑
v4.2 Capture UX  →  v4.3 Graph UX  →  v4.5 Perf (continuous)
```

**Rationale:** Merge import unlocks real round-trip workflows (biggest v3 gap). Editor gaps are small, shippable increments. Capture/graph UX builds on stable import. Hardening and perf run in parallel once features land.

---

## Success metrics

| Metric | Target |
|--------|--------|
| Export → merge import | 0 duplicate notes; IDs match manifest |
| New constructs | Unit tests per construct; no full-doc style regression |
| CI | 100% `mdeTests` pass on macOS + iOS smoke |
| Search | Still &lt; 100 ms P95 at 10k notes after v4.1 |

---

## Documentation updates (when v4 starts)

- [ ] Add v4 section to `spec.md` §13 delivery phases
- [ ] Update §5.1 syntax table (aliases, ordered lists, external links)
- [ ] Update `README.md` status line

---

## Revision history

| Date | Change |
|------|--------|
| 2026-07-04 | Draft v4 roadmap: import merge, editor, capture, graph, hardening, perf |
