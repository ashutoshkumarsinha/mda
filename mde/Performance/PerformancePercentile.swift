//
//  PerformancePercentile.swift
//  MDE
//

import Foundation

enum PerformancePercentile {
    /// Linear-interpolation percentile (0…1) over sorted samples.
    static func value(_ samples: [Double], percentile p: Double) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sorted = samples.sorted()
        let clamped = min(max(p, 0), 1)
        let rank = clamped * Double(sorted.count - 1)
        let lower = Int(floor(rank))
        let upper = Int(ceil(rank))
        if lower == upper { return sorted[lower] }
        let weight = rank - Double(lower)
        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }
}
