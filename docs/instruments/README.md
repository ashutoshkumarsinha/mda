# MDE Instruments profiling assets

Stored trace template and helpers for validating NFR-01–03 beyond `mdeTests`.

| File | Purpose |
|------|---------|
| [MDE Performance.tracetemplate](./MDE%20Performance.tracetemplate) | Blank Instruments trace template (repo copy). Used with **Time Profiler** + **os_signpost**. |
| [MDEPerformance.instrpkg](./MDEPerformance.instrpkg) | Optional Instruments Package source — per-signpost duration lanes for `name.aks.mde` / `Performance`. Build with an Xcode **Instruments Package** target to install. |
| [install-mde-instruments-template.sh](./install-mde-instruments-template.sh) | Copies the trace template into `~/Library/Application Support/Instruments/Templates/` so **MDE Performance** appears in Instruments and `xctrace list templates`. |
| [record-mde-profile.sh](./record-mde-profile.sh) | Builds **mde**, records a timed trace, and opens it in Instruments. |
| [benchmark-cold-launch.sh](./benchmark-cold-launch.sh) | True cold-launch benchmark (NFR-02). |
| [parse-cold-launch-trace.py](./parse-cold-launch-trace.py) | Parses `cold_launch_to_editor` ms from a `.trace`. |

## Quick start (CLI)

```bash
# Optional: show template in Instruments picker
./docs/instruments/install-mde-instruments-template.sh

# Record 30s (default) — pass output path as first argument
./docs/instruments/record-mde-profile.sh ~/Desktop/mde-profile.trace

# True cold launch benchmark (NFR-02, 3 iterations, exits non-zero on regression)
./docs/instruments/benchmark-cold-launch.sh
```

## Quick start (Instruments UI)

1. Run `install-mde-instruments-template.sh` (or open the `.tracetemplate` from this folder).
2. **Product → Profile** (⌘I) in Xcode, or open Instruments and choose **MDE Performance**.
3. Add **Time Profiler** and **os_signpost** if not already present (the record script adds both automatically).
4. In **os_signpost**, filter **Subsystem** to `name.aks.mde` and **Category** to `Performance`.
5. Record while reproducing: cold open, typing, search, sync.

## Signposts

Subsystem `name.aks.mde`, category `Performance`. See [instruments-performance.md](../instruments-performance.md) for the full signpost table and CI budgets.

## Optional custom package

`MDEPerformance.instrpkg` defines an **MDE Signposts** instrument with duration lanes for each app signpost. To install:

1. In Xcode: **File → New → Project → macOS → Instruments Package**.
2. Replace the generated `.instrpkg` with this file (or merge schemas).
3. Build the package target and open the product `.instrdst` to install.

Raw `.instrpkg` files are not loaded by `xctrace --package` until built into an `.instrdst` bundle.
