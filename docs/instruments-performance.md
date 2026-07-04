# MDE — Instruments performance profiling

Use Instruments to validate NFR-01–03 beyond the in-process `mdeTests` baselines.

## Signposts

Subsystem: `name.aks.mde`  
Category: `Performance`

| Signpost | When it fires |
|----------|----------------|
| `cold_launch_to_editor` | `ColdLaunchBenchmark` → editor note loaded (NFR-02) |
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

## Stored trace template

Repo assets live in [instruments/](./instruments/):

| Asset | Description |
|-------|-------------|
| `MDE Performance.tracetemplate` | Trace template for **Time Profiler** + **os_signpost** |
| `record-mde-profile.sh` | Build, record, and open a trace from the CLI |
| `benchmark-cold-launch.sh` | True cold-launch benchmark (NFR-02, median of N traces) |
| `parse-cold-launch-trace.py` | Extract `cold_launch_to_editor` duration from a `.trace` |
| `install-mde-instruments-template.sh` | Install template into Instruments (shows as **MDE Performance**) |
| `MDEPerformance.instrpkg` | Optional Instruments Package source for per-signpost duration lanes |

### CLI recording

```bash
./docs/instruments/install-mde-instruments-template.sh   # once per machine
./docs/instruments/record-mde-profile.sh ~/Desktop/mde.trace
```

`TIME_LIMIT=60s` overrides the default 30s capture window.

### True cold launch (NFR-02)

Out-of-process benchmark (not the in-test `VaultStore()` proxy):

```bash
./docs/instruments/benchmark-cold-launch.sh
```

The script quits any running **mde**, starts an **xctrace** recording (`Time Profiler` + **os_signpost**, all processes), cold-launches a fresh instance via `open -n` with `-benchmarkColdLaunch` and a prepared `.mde` vault, then reads the `cold_launch_to_editor` duration from the app-written result file (`.ms`). Traces are saved under `OUTPUT_DIR` for optional inspection. The script exits non-zero when the **median** duration exceeds `coldVaultOpenMS` × 1.10.

| Variable | Default | Meaning |
|----------|---------|---------|
| `ITERATIONS` | `3` | Recorded cold launches |
| `BUDGET_MS` | `2000` | NFR-02 budget |
| `TIME_LIMIT` | `15s` | Max Instruments capture per iteration |
| `VAULT_PATH` | — | Optional `.mde` package (default: generated under `OUTPUT_DIR`) |
| `OUTPUT_DIR` | `build/cold-launch` | Traces, `.ms` results, `cold-launch-results.json` |

### Manual profile (macOS)

1. Open `mde.xcodeproj` and select the **mde** scheme.
2. **Product → Profile** (⌘I), or run `install-mde-instruments-template.sh` and choose **MDE Performance**.
3. Ensure **Time Profiler** and **os_signpost** are in the template.
4. In **os_signpost**, filter subsystem `name.aks.mde`, category `Performance`.
5. Reproduce: cold open, type in editor, search 10k notes, sync.

## Quick profile (legacy steps)

If you prefer Apple's built-in templates instead of the stored file:

1. **Product → Profile** (⌘I).
2. Choose **os_signpost** (or **Time Profiler** + signpost detail).
3. Filter subsystem to `name.aks.mde`.

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

## Regression tolerance

`PerformanceRegressionGate` allows metrics up to **max(budget, recorded baseline) × 1.10** (10% headroom). Recorded values live in `mde/Performance/performance-baselines.json` and are updated when intentional perf work lands. `CompletionTests` and CI enforce this alongside fixed budgets in `PerformanceBudgets.swift`.

## macOS multi-window

`DocumentGroup` supports **Window → New Window** for a second view of the same vault (platform default). No extra code required.

## Budget reference

See [optimization-plan.md](./optimization-plan.md) and `mde/Performance/PerformanceBudgets.swift`.
