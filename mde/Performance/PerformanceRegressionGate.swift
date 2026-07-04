//
//  PerformanceRegressionGate.swift
//  MDE
//

import Foundation

/// CI gate: fail when a metric exceeds max(budget, recorded baseline) × tolerance (default 10%).
enum PerformanceRegressionGate {
    static let toleranceMultiplier: Double = 1.10

    struct Baselines: Codable {
        var metrics: [String: Double]
    }

    private static let recordedBaselines: Baselines? = {
        guard let url = Bundle.main.url(forResource: "performance-baselines", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(Baselines.self, from: data)
    }()

    static func ceiling(metric: String, budget: Double) -> Double {
        let fromBudget = budget * toleranceMultiplier
        guard let baseline = recordedBaselines?.metrics[metric] else { return fromBudget }
        return max(fromBudget, baseline * toleranceMultiplier)
    }

    static func withinTolerance(actual: Double, budget: Double) -> Bool {
        actual <= budget * toleranceMultiplier
    }

    static func withinTolerance(metric: String, actual: Double, budget: Double) -> Bool {
        actual <= ceiling(metric: metric, budget: budget)
    }

    static func message(metric: String, actual: Double, budget: Double) -> String {
        let limit = ceiling(metric: metric, budget: budget)
        return "\(metric): \(String(format: "%.2f", actual)) ms exceeds \(String(format: "%.2f", limit)) ms ceiling"
    }
}
