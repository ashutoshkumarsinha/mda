//
//  DeveloperSettingsView.swift
//  MDE
//

import SwiftUI

#if DEBUG
struct DeveloperSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var recorder = PerformanceMetricsRecorder.shared
    @State private var residentMB = ProcessMemory.residentMegabytes()
    @State private var refreshTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                Section("Memory") {
                    LabeledContent("Resident") {
                        Text(String(format: "%.1f MB", residentMB))
                            .monospacedDigit()
                    }
                    LabeledContent("NFR-03 budget") {
                        Text(String(format: "< %.0f MB", PerformanceBudgets.memory1kNotesNFR03MB))
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Signpost intervals") {
                    if recorder.intervals.isEmpty {
                        Text("No intervals recorded yet. Edit notes or sync to populate.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(recorder.intervals.sorted { $0.name < $1.name }) { interval in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(interval.name)
                                    .font(.body.monospaced())
                                HStack(spacing: 12) {
                                    Text(String(format: "last %.1f ms", interval.lastMS))
                                    Text(String(format: "avg %.1f ms", interval.averageMS))
                                    Text("×\(interval.count)")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                Section {
                    Text("Intervals mirror os_signpost events (subsystem name.aks.mde, category Performance). Profile in Instruments → os_signpost.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Developer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Reset") {
                        recorder.reset()
                    }
                }
            }
            .onAppear { startMemoryRefresh() }
            .onDisappear { refreshTask?.cancel() }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #endif
    }

    private func startMemoryRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                residentMB = ProcessMemory.residentMegabytes()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
#endif
