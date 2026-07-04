# MDE — v2 Roadmap

> **Status:** Kickoff (2026-07-04)  
> **Companion:** [spec.md](./spec.md) §4.2 · [optimization-plan.md](./optimization-plan.md)

v1 and v1.1 are complete. v2 expands the content model (images, tables), import fidelity, and export packaging — without plugins or a marketplace (still non-goals).

---

## Themes

| Theme | Goal |
|-------|------|
| **Rich content** | Images and tables in notes; assets live in vault `assets/` |
| **Interoperability** | Obsidian folder import with linked media; zip vault export |
| **Sync (later)** | Asset blobs in CloudKit or CKAsset references — after local model is stable |

---

## Phased delivery

### v2.0 — Vault assets foundation *(in progress)*

| Item | Status |
|------|--------|
| `vault_asset` + `note_asset` schema (`v3_vault_assets`) | ✅ |
| `VaultAssetStore` — read/write under `assets/` | ✅ |
| `![alt](assets/<id>.<ext>)` markdown convention | ✅ |
| `importImage(intoNoteID:)` API | ✅ |
| Image construct parsing + editor placeholder styling | ✅ |
| Toolbar / file picker image insert UI | — |
| Inline `NSTextAttachment` / `UIImage` rendering | — |

**Exit:** Attach image to note in package vault; asset file on disk; markdown round-trips; unit tests pass.

### v2.1 — Obsidian import fidelity

- Resolve `![](relative/path.png)` to vault assets when importing a folder
- Optional `attachments/` and `.obsidian/` skip rules
- WikiLink `[[Note]]` already supported; preserve folder note order

### v2.2 — Tables

- GFM pipe tables in parser + read-only styled preview (hybrid tokens)
- No cell editing UX in first slice — render-only, then edit

### v2.3 — Export packaging

- Zip export: `notes/*.md` + `assets/` + `meta.json` manifest
- Per-note folder export (single note + its assets)

### v2.4 — Asset sync

- Upload asset blobs with encrypted note payloads
- Conflict: asset immutable by `asset_id`; re-upload on content change only

---

## Markdown conventions (v2)

### Images

```markdown
![Diagram of flow](assets/a1b2c3d4-uuid.png)
```

| Rule | Specification |
|------|---------------|
| Path | Vault-relative `assets/<filename>` only (no `..`, no absolute paths) |
| Filename | `{uuid}.{ext}` — stable `vault_asset.id` + extension |
| Alt text | Optional; used for accessibility and export |
| Storage | Binary in `MyVault.mde/assets/`; metadata in `vault_asset` / `note_asset` |
| In-memory vault | Image import requires attached package |

### Tables (v2.2, planned)

GFM pipe tables; header row + separator `|---|`; no HTML.

---

## Non-goals (unchanged)

Plugin marketplace · Third-party sync · Web/Windows clients · Real-time co-editing

---

## Revision history

| Date | Change |
|------|--------|
| 2026-07-04 | v2 kickoff: roadmap, assets schema, image import API, construct parsing |
