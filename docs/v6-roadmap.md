# MDE — v6 Roadmap

> **Status:** v6 complete (2026-07-04)  
> **Companion:** [spec.md](./spec.md) · [v5-roadmap.md](./v5-roadmap.md)

v6 closes v5 polish gaps and ships platform extensions: Spotlight deep links, Share extension, Widget glance, Watch companion, sync conflict diff UI, and Notion HTML import.

---

## Phased delivery

### v6.0 — Spotlight & daily note polish *(complete)*

- ✅ Open note from Spotlight search (`CSSearchableItemActionType`)
- ✅ Spotlight cleanup on empty trash + full reindex clears stale entries
- ✅ **⌘⇧D** opens today's note; Daily template uses ISO daily note flow

### v6.1 — Import & sync UX *(complete)*

- ✅ Notion **HTML** export import (basic tag → Markdown conversion)
- ✅ Import dedup skips notes with existing titles
- ✅ Sync conflict **Compare** sheet (local vs cloud side-by-side)

### v6.2 — Platform extensions *(complete)*

- ✅ **Save to MDE** iOS Share extension (`mdeShareExtension`)
- ✅ **Today's Note** Widget (`mdeWidgetExtension`) — small/medium families
- ✅ **Watch glance** app (`mdeWatchApp`) reads shared daily note snapshot
- ✅ App Group `group.name.aks.mde` + `VaultGlanceStore` (Release signing)

---

## Backlog (v7+)

Rich PDF markdown rendering · Notion block-level HTML · watchOS complications · macOS Share menu · App Intents for Siri shortcuts

---

## Revision history

| Date | Change |
|------|--------|
| 2026-07-04 | v6: Spotlight deep link, extensions, conflict diff, Notion HTML |
