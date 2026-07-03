# MDE — Instruments performance profiling

Use Instruments to validate NFR-01–03 beyond the in-process `mdeTests` baselines.

## Signposts

Subsystem: `name.aks.mde`  
Category: `Performance`

| Signpost | When it fires |
|----------|----------------|
| `vault_refresh_all` | Full vault cache reload |
| `vault_reload_notes` | Note summary reload |
| `vault_reload_tag_tree` | Tag tree rebuild |
| `vault_resolve_links` | Pending wiki-link resolution |
| `vault_update_note` | Note write path |
| `vault_persist_package` | `.mde` package flush to disk |
| `vault_export_database` | SQLite export |
| `vault_list_page` | Paginated list SQL |
| `markdown_parse` | `MarkdownParseActor.parse` |
| `markdown_style` | Full-document `MarkdownStyler.apply` |
| `markdown_style_incremental` | Caret-neighborhood styling |
| `sync_perform` | `SyncCoordinator.performSync` |

## Quick profile (macOS)

1. Open `mde.xcodeproj` and select the **mde** scheme.
2. **Product → Profile** (⌘I) to launch Instruments.
3. Choose **os_signpost** (or **Time Profiler** + signpost detail).
4. Filter subsystem to `name.aks.mde`.
5. Reproduce: cold open, type in editor, search 10k notes, sync.

## DEBUG in-app overlay

In **DEBUG** builds, use **Developer** in the toolbar to see:

- Live resident memory (MB)
- Last / average duration per recorded signpost interval

Intervals are populated as signposted code paths run during the session.

## Automated gates (CI)

`mdeTests` enforces budgets in `PerformanceBudgets.swift`:

| Suite | Gate |
|-------|------|
| `Phase0BaselineTests` | Cold open, 1k refresh, persist, parse, style, sync |
| `Phase3OptimizationTests` | Incremental style under 16 ms |
| `Phase6ObservabilityTests` | p95 keystroke style, NFR-03 memory, persist size/time, FTS 10k |

Run locally:

```bash
xcodebuild -scheme mde -destination 'platform=macOS' -only-testing:mdeTests test CODE_SIGNING_ALLOWED=NO
```

Run only Phase 6 gates:

```bash
xcodebuild -scheme mde -destination 'platform=macOS' \
  -only-testing:mdeTests/Phase6ObservabilityTests test CODE_SIGNING_ALLOWED=NO
```

## Budget reference

See [optimization-plan.md](./optimization-plan.md) and `mde/Performance/PerformanceBudgets.swift`.
