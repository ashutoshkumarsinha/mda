# MDE — v5 Roadmap

> **Status:** v5 complete (2026-07-04)  
> **Companion:** [spec.md](./spec.md) · [v4-roadmap.md](./v4-roadmap.md)

v5 adds capture workflows (daily notes), system discoverability (Spotlight), print-friendly export (PDF), and Notion folder import.

---

## Phased delivery

### v5.0 — Daily notes *(complete)*

- ✅ ISO date titles (`yyyy-MM-dd`) with open-or-create **Today's Note**
- ✅ Daily template content on first create
- ✅ WikiLink `[[2026-07-04]]` creates daily note when unresolved

### v5.1 — Spotlight indexing *(complete)*

- ✅ Index active notes in Core Spotlight (`CSSearchableItem`)
- ✅ Reindex on edit; remove on soft-delete / purge
- ✅ Full vault reindex on package attach

### v5.2 — PDF export *(complete)*

- ✅ Export single note as `.pdf` from editor menu
- ✅ Plain-text layout (title + body)

### v5.3 — Notion import *(complete)*

- ✅ Recursive Notion markdown folder import
- ✅ URL-decoded embedded image paths (`%20`, etc.)
- ✅ Vault menu **Import Notion Export…**

---

## Backlog (v6+)

Notion HTML export · iOS Share extension · Widget glance · CRDT diff UI · Watch app

---

## Revision history

| Date | Change |
|------|--------|
| 2026-07-04 | v5: daily notes, Spotlight, PDF export, Notion import |
