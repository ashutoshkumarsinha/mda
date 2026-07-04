# MDE — v2 Roadmap

> **Status:** v2 complete (2026-07-04)  
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

### v2.0 — Vault assets foundation *(complete)*

| Item | Status |
|------|--------|
| `vault_asset` + `note_asset` schema (`v3_vault_assets`) | ✅ |
| `VaultAssetStore` — read/write under `assets/` | ✅ |
| `![alt](assets/<id>.<ext>)` markdown convention | ✅ |
| `importImage(intoNoteID:)` API | ✅ |
| Image construct parsing + inline attachment rendering | ✅ |
| Toolbar / file picker image insert UI | ✅ |
| Asset sync (CloudKit) | ✅ |

**Exit:** Attach image to note in package vault; asset file on disk; markdown round-trips; unit tests pass.

### v2.1 — Obsidian import fidelity *(complete)*

- ✅ Resolve `![](relative/path.png)` to vault assets when importing a folder
- ✅ Skip `.obsidian` during recursive import
- WikiLink `[[Note]]` already supported

### v2.2 — Tables *(complete)*

- ✅ GFM pipe tables in parser + hybrid styled preview (header bold, faded pipes when caret outside)
- ✅ No cell editing UX — render-only while editing raw markdown

### v2.3 — Export packaging *(complete)*

- ✅ Zip export: `notes/*.md` + `assets/` + `meta.json` manifest
- ✅ Per-note folder / zip export (note markdown + linked assets)

### v2.4 — Asset sync *(complete)*

- ✅ Upload encrypted asset blobs alongside note payloads (`MDEAsset` CloudKit records)
- ✅ Skip re-upload when `content_checksum` matches sync base; replace local file when checksum changes

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

### Tables (v2.2)

GFM pipe tables; header row + separator `|---|`; no HTML. Hybrid editor shows header cells bold and fades pipe tokens when the caret is outside the table.

---

## Non-goals (unchanged)

Plugin marketplace · Third-party sync · Web/Windows clients · Real-time co-editing

---

## Revision history

| Date | Change |
|------|--------|
| 2026-07-04 | v2 kickoff: roadmap, assets schema, image import API, construct parsing |
