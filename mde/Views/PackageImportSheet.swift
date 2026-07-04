//
//  PackageImportSheet.swift
//  MDE
//

import SwiftUI

struct PackageImportSheet: View {
    let sourceDescription: String
    let onImport: (VaultPackageImportMode) -> Void
    let onCancel: () -> Void

    @State private var mode: VaultPackageImportMode = .merge
    @State private var confirmReplace = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(sourceDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Import mode") {
                    Picker("Mode", selection: $mode) {
                        ForEach(VaultPackageImportMode.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()

                    Text(mode.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Import Package")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        if mode.requiresConfirmation {
                            confirmReplace = true
                        } else {
                            onImport(mode)
                        }
                    }
                }
            }
            .alert("Replace vault contents?", isPresented: $confirmReplace) {
                Button("Replace", role: .destructive) {
                    onImport(.replace)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All active notes will be moved to Trash before importing.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 320)
        #endif
    }
}
