//
//  ColdLaunchBenchmark.swift
//  MDE
//
//  NFR-02 — cold launch to interactive editor (Instruments os_signpost interval).
//

import Foundation
import OSLog

enum ColdLaunchBenchmark {
    private static let log = OSLog(subsystem: "name.aks.mde", category: "Performance")
    private static var signpostID: OSSignpostID?
    private static var hasStarted = false
    private static var hasFinished = false
    private static var startTime: CFAbsoluteTime?
    private static let lock = NSLock()

    static var resultFilePath: String {
        #if os(macOS)
        if let fromArgs = LaunchArguments.benchmarkResultPath {
            return fromArgs
        }
        #endif
        if let fromEnv = ProcessInfo.processInfo.environment["MDE_COLD_LAUNCH_RESULT_PATH"] {
            return fromEnv
        }
        if LaunchArguments.benchmarkColdLaunch {
            if let vaultPath = ProcessInfo.processInfo.arguments.first(where: { $0.hasSuffix(".mde") }) {
                return URL(fileURLWithPath: vaultPath)
                    .appendingPathComponent("cold-launch-result.ms")
                    .path
            }
            return "/tmp/mde-cold-launch-result.ms"
        }
        return NSTemporaryDirectory().appending("mde-cold-launch-ms.txt")
    }

    /// Begins the cold-launch interval once per process (first vault document).
    static func beginIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard !hasStarted else { return }
        hasStarted = true
        startTime = CFAbsoluteTimeGetCurrent()
        let id = OSSignpostID(log: log)
        signpostID = id
        os_signpost(.begin, log: log, name: "cold_launch_to_editor", signpostID: id)
    }

    /// Ends the interval when the editor has loaded note content and is ready for input.
    static func markEditorReady() {
        lock.lock()
        defer { lock.unlock() }
        guard hasStarted, !hasFinished, let id = signpostID else { return }
        hasFinished = true
        os_signpost(.end, log: log, name: "cold_launch_to_editor", signpostID: id)

        if LaunchArguments.benchmarkColdLaunch, let startTime {
            let milliseconds = (CFAbsoluteTimeGetCurrent() - startTime) * 1_000
            writeBenchmarkResult(milliseconds: milliseconds)
        }
    }

    private static func writeBenchmarkResult(milliseconds: Double) {
        let path = resultFilePath
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let payload = String(format: "%.3f\n", milliseconds)
        try? payload.write(to: url, atomically: true, encoding: .utf8)
    }

    #if os(macOS)
    /// Creates a vault package with one note for Instruments cold-launch runs (`-createBenchmarkVault`).
    static func createBenchmarkVaultPackage(at url: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        let store = VaultStore()
        try store.attachToPackage(at: url)
        _ = try store.createNote(title: "Benchmark", content: "Ready")
        try store.flushPackageIfNeeded()
    }

    /// Exits early when invoked as a vault-setup helper for `benchmark-cold-launch.sh`.
    static func exitIfCreateBenchmarkVaultRequested() {
        guard LaunchArguments.createBenchmarkVault,
              let path = ProcessInfo.processInfo.environment["MDE_BENCHMARK_VAULT_PATH"] else {
            return
        }
        do {
            try createBenchmarkVaultPackage(at: URL(fileURLWithPath: path))
        } catch {
            fputs("createBenchmarkVault failed: \(error)\n", stderr)
            exit(2)
        }
        exit(0)
    }
    #endif
}
