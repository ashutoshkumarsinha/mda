# MDE — v3 Roadmap

> **Status:** v3 complete (2026-07-04)  
> **Companion:** [spec.md](./spec.md) · [v2-roadmap.md](./v2-roadmap.md)

v2 delivered rich content and export packaging. v3 completes the interoperability loop and extends the markdown subset.

---

## Themes

| Theme | Goal |
|-------|------|
| **Import fidelity** | Import v2.3 package / zip exports back into a vault |
| **Markdown completeness** | External `[text](url)` links; WikiLink `[[Note\|alias]]` |
| **Stability** | Preserve asset IDs on import so `assets/<uuid>.<ext>` refs resolve |

---

## Phased delivery

### v3.0 — Package / zip import *(complete)*

- ✅ Import folder export (`notes/`, `assets/`, export `meta.json`)
- ✅ Import `.zip` archives produced by v2.3 export
- ✅ Vault menu auto-detects export package vs Obsidian vs loose markdown

### v3.1 — External links *(complete)*

- ✅ Parse and hybrid-style `[label](https://…)` links (excluding images)
- ✅ Tap opens URL in browser

### v3.2 — WikiLink aliases *(complete)*

- ✅ `[[Target Note|Display Text]]` — link resolves to *Target Note*, shows *Display Text*
- ✅ Indexer and graph use target title only

---

## Non-goals (unchanged)

Plugin marketplace · Third-party sync · Web/Windows clients · Real-time co-editing · HTML blocks

---

## Revision history

| Date | Change |
|------|--------|
| 2026-07-04 | v3: package import, external links, WikiLink aliases |
