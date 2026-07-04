//
//  LaunchArguments.swift
//  MDE
//

import Foundation

enum LaunchArguments {
    static var skipOnboarding: Bool {
        ProcessInfo.processInfo.arguments.contains("-skipOnboarding")
    }

    /// Enables deterministic cold-launch benchmarking (auto-select/create note, skip onboarding).
    static var benchmarkColdLaunch: Bool {
        ProcessInfo.processInfo.arguments.contains("-benchmarkColdLaunch")
    }

    #if os(macOS)
    /// One-shot vault creation for Instruments scripts (`-createBenchmarkVault`).
    static var createBenchmarkVault: Bool {
        ProcessInfo.processInfo.arguments.contains("-createBenchmarkVault")
    }

    /// Result file path for Instruments (`-benchmarkColdLaunchResultPath <path>`).
    static var benchmarkResultPath: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-benchmarkColdLaunchResultPath"),
              args.index(after: index) < args.endIndex else {
            return nil
        }
        return args[args.index(after: index)]
    }
    #endif
}
