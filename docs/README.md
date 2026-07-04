# MDE Documentation

Documentation for **MDE** — a local-first, minimalist note-taking app for macOS and iOS inspired by [Caliu](https://caliuapp.com/).

## Documents

| Document | Read this when you need… |
|----------|--------------------------|
| [**spec.md**](./spec.md) | Requirements, syntax rules, UX behavior, test scenarios, delivery phases |
| [**hld.md**](./hld.md) | Architecture, data flows, database schema, SQL recipes, GUI wireframes |
| [**optimization-plan.md**](./optimization-plan.md) | Performance phases, NFR budgets, signposts, Phase 0 baselines |
| [**v2-roadmap.md**](./v2-roadmap.md) | v2 phases: images, tables, Obsidian import, zip export |
| [**instruments/**](./instruments/) | Stored **MDE Performance** trace template + `record-mde-profile.sh` |

```
spec.md  ──  WHAT   (requirements, syntax, tests, milestones)
    └──►  hld.md  ──  HOW   (architecture, schema, pipelines)
```

## Code signing

**Debug (local runs):** Uses `mde.debug.entitlements` (sandbox only, no CloudKit) and ad-hoc signing (`Sign to Run Locally`). No Apple Developer team required — open and run in Xcode normally.

**Release / iCloud sync:** Uses `mde.entitlements` with CloudKit. Requires an Apple Developer team:

1. Copy `mde/Config/Local.xcconfig.example` → `mde/Config/Local.xcconfig`
2. Set `DEVELOPMENT_TEAM` to your [Team ID](https://developer.apple.com/account)
3. In Xcode: **mde** target → **Signing & Capabilities** → select your team for **Release**
4. Enable the **iCloud** capability with container `iCloud.name.aks.mde`

CI builds with `CODE_SIGNING_ALLOWED=NO` and do not need a team.

## Project status

**v1 + v1.1 + v2 complete** — see [v2-roadmap.md](./v2-roadmap.md) and [spec §13](./spec.md#13-delivery-phases).

**First-time setup:** run `./scripts/setup-grdb-cipher.sh` (vendors GRDB into `Packages/GRDBCipher/` for SQLCipher).

Open **`mde.xcodeproj`** — the app sources live in **`mde/`**.

## Quick reference

| Topic | Section |
|-------|---------|
| Markdown & tag syntax | [spec §5](./spec.md#5-syntax--content-model) |
| `.mde` vault format | [spec §6](./spec.md#6-document--vault-model) |
| Functional requirements | [spec §7](./spec.md#7-functional-requirements) |
| Design tokens & UI | [spec §10](./spec.md#10-user-interface) |
| Test scenarios (TC-*) | [spec §15](./spec.md#15-test-scenarios) |
| Traceability (UC → FR → TC) | [spec §14](./spec.md#14-traceability-matrix) |
| GRDB schema | [hld §6](./hld.md#6-database-schema) |
| Architecture diagram | [hld §1](./hld.md#1-system-architecture-overview) |
| Open questions | [spec §17](./spec.md#17-open-questions) |

## Design inspiration

- [Caliu](https://caliuapp.com/)
