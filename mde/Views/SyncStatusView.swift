//
//  SyncStatusView.swift
//  MDE
//

import SwiftUI

struct SyncStatusToolbarContent: View {
    @Bindable var coordinator: SyncCoordinator
    @Binding var showSetup: Bool

    var body: some View {
        HStack(spacing: 8) {
            if coordinator.isSyncEnabled {
                statusLabel
                if coordinator.pendingUploadCount > 0 {
                    Text("\(coordinator.pendingUploadCount)")
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Button("Sync Now") {
                    Task { await coordinator.syncNow(forceFull: true) }
                }
                .disabled(coordinator.status == .syncing)
                .accessibilityLabel("Sync now")
                Button {
                    showSetup = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .help("Sync conflict history")
                .accessibilityLabel("Sync conflict history")
            } else {
                Button("Enable iCloud Sync") {
                    showSetup = true
                }
                .accessibilityLabel("Enable iCloud sync")
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch coordinator.status {
        case .disabled:
            Label("Sync off", systemImage: "icloud.slash")
                .foregroundStyle(.secondary)
                .accessibilityLabel(AccessibilityLabels.syncStatus("off", pendingCount: coordinator.pendingUploadCount))
        case .idle:
            Label("Synced", systemImage: "icloud")
                .foregroundStyle(.secondary)
                .accessibilityLabel(AccessibilityLabels.syncStatus("synced", pendingCount: coordinator.pendingUploadCount))
        case .syncing:
            Label("Syncing…", systemImage: "arrow.triangle.2.circlepath.icloud")
                .accessibilityLabel(AccessibilityLabels.syncStatus("syncing", pendingCount: coordinator.pendingUploadCount))
        case .offline:
            Label("Offline", systemImage: "icloud.slash")
                .foregroundStyle(.orange)
                .accessibilityLabel(AccessibilityLabels.syncStatus("offline", pendingCount: coordinator.pendingUploadCount))
        case .error:
            Label("Sync issue", systemImage: "exclamationmark.icloud")
                .foregroundStyle(.orange)
                .accessibilityLabel(AccessibilityLabels.syncStatus("error", pendingCount: coordinator.pendingUploadCount))
        }
    }
}

struct SyncConflictBanner: View {
    let conflict: NoteConflict
    let onKeepLocal: () -> Void
    let onKeepCloud: () -> Void
    @State private var showDiff = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("This note changed on another device.")
                .font(.subheadline)
            Spacer()
            Button("Compare") { showDiff = true }
            Button("Keep Local", action: onKeepLocal)
            Button("Keep Cloud", action: onKeepCloud)
        }
        .padding(12)
        .background(.orange.opacity(0.12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sync conflict. This note changed on another device.")
        .sheet(isPresented: $showDiff) {
            SyncConflictDiffView(
                conflict: conflict,
                onKeepLocal: onKeepLocal,
                onKeepCloud: onKeepCloud
            )
        }
    }
}

struct SyncSetupView: View {
    @Bindable var coordinator: SyncCoordinator
    @Binding var isPresented: Bool
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if coordinator.isSyncEnabled {
                Text("iCloud Sync")
                    .font(.title2.weight(.semibold))

                let entries = coordinator.conflictLogEntries()
                if entries.isEmpty {
                    Text("No sync conflicts recorded for this vault.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Recent conflicts")
                        .font(.headline)
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.noteTitle.isEmpty ? "Untitled" : entry.noteTitle)
                                .font(.subheadline.weight(.medium))
                            Text(entry.recordedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button("Done") { isPresented = false }
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                Text("Enable iCloud Sync")
                    .font(.title2.weight(.semibold))

                Text("Notes are encrypted on this device before upload. The encryption key stays in your Keychain and is not synced — if you lose this device without a local backup, synced notes cannot be recovered.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) {
                        isPresented = false
                    }
                    Button("Enable Sync") {
                        Task {
                            do {
                                try await coordinator.enableSync()
                                isPresented = false
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 420)
        .alert("Sync Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }
}
