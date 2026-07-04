# MDE — v4 Roadmap

> **Status:** v4 complete (2026-07-04)  
> **Companion:** [spec.md](./spec.md) · [v3-roadmap.md](./v3-roadmap.md)

v4 focuses on smarter import, editor polish, capture UX, graph/backlink improvements, and reliability hardening.

---

## Phased delivery

### v4.0 — Smart package import *(complete)*

- ✅ Import modes: Add · Merge by note ID · Replace vault (with confirmation)
- ✅ ID preservation on merge/replace
- ✅ `note_asset` rebuild + sync enqueue after import
- ✅ Package import sheet in vault menu flow

### v4.1 — Editor markdown gaps *(complete)*

- ✅ Ordered list paragraph styling (`1. item`)
- ✅ Italic as hybrid construct (`*text*`)
- ✅ External link + WikiLink bracket-delete (whole token)
- ✅ Strikethrough `~~text~~` styling

### v4.2 — Capture & list UX *(complete)*

- ✅ Note templates (Meeting, Daily, Project)
- ✅ ⌘⇧N quick blank note
- ✅ Tag-scoped search (tag filter + FTS)
- ✅ List sort: Recently Updated / Title
- ⏭ iOS Share extension deferred (requires new Xcode target)

### v4.3 — Graph & link UX *(complete)*

- ✅ Graph node search/filter
- ✅ Tap graph node → select note (existing; retained)
- ✅ Backlink one-line snippet preview

### v4.4 — Sync & import hardening *(complete)*

- ✅ Import-without-package banner
- ✅ Post-import sync enqueue
- ✅ Sync conflict log (last 10 per vault)
- ✅ Zip central-directory reader fallback
- ✅ `phase0SyncRoundTripInMemory` already serialized

### v4.5 — Performance *(complete)*

- ✅ Image attachment LRU cache (48 entries)
- ✅ Existing incremental style path retained for tables/images

---

## Non-goals (unchanged)

Web/Windows clients · Real-time co-editing · Third-party sync · Plugin marketplace

---

## Revision history

| Date | Change |
|------|--------|
| 2026-07-04 | Draft v4 roadmap |
| 2026-07-04 | v4 shipped (Share extension deferred) |
