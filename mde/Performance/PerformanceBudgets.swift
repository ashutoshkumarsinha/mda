//
//  PerformanceBudgets.swift
//  MDE
//
//  Phase 0 — NFR-aligned budgets for automated regression gates.
//  Tighten in later optimization phases; loosen only with spec change.
//

import Foundation

enum PerformanceBudgets {
    // NFR-01 — full-document pass (reduce motion / initial load)
    static let markdownStylePassMS: Double = 100
    // NFR-01 — incremental caret-neighborhood pass (Phase 3 target)
    static let incrementalMarkdownStyleMS: Double = 16
    static let markdownParseMS: Double = 300

    // NFR-02 — in-process proxy in unit tests; true process launch via docs/instruments/benchmark-cold-launch.sh
    static let coldVaultOpenMS: Double = 2_000

    // NFR-03 (resident memory delta in test host after 1k-note cache load)
    static let memoryDelta1kNotesMB: Double = 120
    /// NFR-03 spec ceiling (Phase 6 gate).
    static let memory1kNotesNFR03MB: Double = 150

    // Store / I/O baselines (Phase 0 capture)
    static let refreshAll1kNotesMS: Double = 2_000
    static let updateNote1kVaultMS: Double = 1_000
    static let persistPackage1kNotesMS: Double = 5_000
    /// On-disk SQLite size after persisting 1k lightweight notes (regression guard).
    static let persistPackage1kNotesMaxBytes: UInt64 = 20_000_000
    static let search10kNotesMS: Double = 100

    // Phase 6 — synthetic keystroke styling sample count for p95 gate
    static let keystrokeStyleSampleCount: Int = 40

    // Sync
    static let syncRoundTripInMemoryMS: Double = 1_000
}
