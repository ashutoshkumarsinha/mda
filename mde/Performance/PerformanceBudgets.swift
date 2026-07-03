//
//  PerformanceBudgets.swift
//  MDE
//
//  Phase 0 — NFR-aligned budgets for automated regression gates.
//  Tighten in later optimization phases; loosen only with spec change.
//

import Foundation

enum PerformanceBudgets {
    // NFR-01
    static let markdownStylePassMS: Double = 100
    static let markdownParseMS: Double = 300

    // NFR-02 (in-process proxy; full launch needs Instruments)
    static let coldVaultOpenMS: Double = 2_000

    // NFR-03 (resident memory delta in test host after 1k-note cache load)
    static let memoryDelta1kNotesMB: Double = 120

    // Store / I/O baselines (Phase 0 capture)
    static let refreshAll1kNotesMS: Double = 2_000
    static let updateNote1kVaultMS: Double = 1_000
    static let persistPackage1kNotesMS: Double = 5_000
    static let search10kNotesMS: Double = 100

    // Sync
    static let syncRoundTripInMemoryMS: Double = 1_000
}
