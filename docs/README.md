# MDE Documentation

Documentation for **MDE** — a local-first, minimalist note-taking app for macOS and iOS inspired by [Caliu](https://caliuapp.com/).

## Documents

| Document | Read this when you need… |
|----------|--------------------------|
| [**spec.md**](./spec.md) | Requirements, syntax rules, UX behavior, test scenarios, delivery phases |
| [**hld.md**](./hld.md) | Architecture, data flows, database schema, SQL recipes, GUI wireframes |

```
spec.md  ──  WHAT   (requirements, syntax, tests, milestones)
    └──►  hld.md  ──  HOW   (architecture, schema, pipelines)
```

## Project status

**Phase 0** — `mde.xcodeproj` scaffold (SwiftData placeholder). Next: GRDB vault package per [spec §6](./spec.md#6-document--vault-model). Roadmap: [spec §13](./spec.md#13-delivery-phases).

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
