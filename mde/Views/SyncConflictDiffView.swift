//
//  SyncConflictDiffView.swift
//  MDE
//

import SwiftUI

struct SyncConflictDiffView: View {
    let conflict: NoteConflict
    let onKeepLocal: () -> Void
    let onKeepCloud: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Compare Changes")
                .font(.title2.weight(.semibold))

            Text(conflict.local.title.isEmpty ? "Untitled" : conflict.local.title)
                .font(.headline)

            HStack(alignment: .top, spacing: 12) {
                conflictColumn(title: "This Device", payload: conflict.local)
                conflictColumn(title: "iCloud", payload: conflict.remote)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Keep Local") {
                    onKeepLocal()
                    dismiss()
                }
                Button("Keep Cloud") {
                    onKeepCloud()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 420)
        #endif
    }

    private func conflictColumn(title: String, payload: NoteSyncPayload) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(payload.updatedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(payload.content.isEmpty ? "(empty)" : payload.content)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(8)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
