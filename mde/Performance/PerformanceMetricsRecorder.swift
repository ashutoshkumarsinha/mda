//
//  PerformanceMetricsRecorder.swift
//  MDE
//

import Foundation
import Observation

#if DEBUG
@Observable
@MainActor
final class PerformanceMetricsRecorder {
    static let shared = PerformanceMetricsRecorder()

    struct Interval: Identifiable, Equatable {
        let name: String
        var lastMS: Double
        var count: Int
        var totalMS: Double

        var id: String { name }
        var averageMS: Double { count > 0 ? totalMS / Double(count) : 0 }
    }

    private(set) var intervals: [Interval] = []

    private var index: [String: Int] = [:]

    func record(signpost: PerformanceSignpost, milliseconds: Double) {
        let name = signpost.label
        if let slot = index[name] {
            var interval = intervals[slot]
            interval.lastMS = milliseconds
            interval.count += 1
            interval.totalMS += milliseconds
            intervals[slot] = interval
        } else {
            index[name] = intervals.count
            intervals.append(
                Interval(name: name, lastMS: milliseconds, count: 1, totalMS: milliseconds)
            )
        }
    }

    func reset() {
        intervals = []
        index = [:]
    }
}
#endif
