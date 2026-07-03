//
//  ContentView.swift
//  MDE
//

import SwiftUI

struct ContentView: View {
    @Bindable var store: VaultStore

    @State private var selectedTagPath: String?
    @State private var selectedNoteID: String?
    @State private var searchQuery = ""
    @State private var showOnboarding = ContentView.shouldShowOnboarding
    @State private var showSyncSetup = false
    @State private var syncCoordinator: SyncCoordinator?
    @State private var showRecoveryAlert = false
    @State private var recoveryError: String?

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var compactScreen: CompactScreen = .notes
    #endif

    var body: some View {
        VStack(spacing: 0) {
            if let conflict = syncCoordinator?.conflict {
                SyncConflictBanner(
                    conflict: conflict,
                    onKeepLocal: {
                        Task { await syncCoordinator?.resolveConflict(keepLocal: true) }
                    },
                    onKeepCloud: {
                        Task { await syncCoordinator?.resolveConflict(keepLocal: false) }
                    }
                )
            }

            #if os(iOS)
            if horizontalSizeClass == .regular {
                splitLayout
            } else {
                compactLayout
            }
            #else
            splitLayout
            #endif
        }
        .toolbar {
            if let syncCoordinator {
                ToolbarItem(placement: .automatic) {
                    SyncStatusToolbarContent(
                        coordinator: syncCoordinator,
                        showSetup: $showSyncSetup
                    )
                }
            }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
        }
        .sheet(isPresented: $showSyncSetup) {
            if let syncCoordinator {
                SyncSetupView(coordinator: syncCoordinator, isPresented: $showSyncSetup)
            }
        }
        .alert("Database Recovery", isPresented: $showRecoveryAlert) {
            Button("Restore Backup") {
                restoreDatabase()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The vault database may be damaged. Restore from the last automatic backup?")
        }
        .alert("Recovery Failed", isPresented: Binding(
            get: { recoveryError != nil },
            set: { if !$0 { recoveryError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(recoveryError ?? "")
        }
        .onChange(of: store.needsDatabaseRecovery) { _, needs in
            showRecoveryAlert = needs
        }
        .onAppear {
            showRecoveryAlert = store.needsDatabaseRecovery
        }
        .task {
            if syncCoordinator == nil {
                let coordinator = SyncCoordinator(store: store)
                syncCoordinator = coordinator
                await coordinator.bootstrap()
            }
        }
    }

    private var splitLayout: some View {
        NavigationSplitView {
            TagSidebarView(store: store, selectedTagPath: $selectedTagPath)
                .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } content: {
            NoteListView(
                store: store,
                selectedNoteID: $selectedNoteID,
                searchQuery: $searchQuery,
                tagPath: selectedTagPath
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            NoteEditorView(
                store: store,
                noteID: selectedNoteID,
                selectedNoteID: $selectedNoteID
            )
        }
        .navigationSplitViewStyle(.balanced)
    }

    #if os(iOS)
    private var compactLayout: some View {
        NavigationStack {
            Group {
                switch compactScreen {
                case .tags:
                    TagSidebarView(store: store, selectedTagPath: $selectedTagPath)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Notes") {
                                    compactScreen = .notes
                                }
                            }
                        }
                case .notes:
                    NoteListView(
                        store: store,
                        selectedNoteID: $selectedNoteID,
                        searchQuery: $searchQuery,
                        tagPath: selectedTagPath
                    )
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Tags") {
                                compactScreen = .tags
                            }
                        }
                    }
                case .editor:
                    if let selectedNoteID {
                        NoteEditorView(
                            store: store,
                            noteID: selectedNoteID,
                            selectedNoteID: $selectedNoteID
                        )
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Back") {
                                    compactScreen = .notes
                                }
                            }
                        }
                    } else {
                        ContentUnavailableView(
                            "Select a note",
                            systemImage: "square.and.pencil",
                            description: Text("Choose a note from the list.")
                        )
                    }
                }
            }
            .navigationTitle(compactNavigationTitle)
        }
        .onChange(of: selectedNoteID) { _, newID in
            if newID != nil, compactScreen == .notes {
                compactScreen = .editor
            }
            if newID == nil, compactScreen == .editor {
                compactScreen = .notes
            }
        }
    }

    private var compactNavigationTitle: String {
        switch compactScreen {
        case .tags: return "Tags"
        case .notes: return "Notes"
        case .editor: return "Editor"
        }
    }

    private enum CompactScreen {
        case tags
        case notes
        case editor
    }
    #endif

    private func restoreDatabase() {
        do {
            try store.restoreDatabaseFromBackup()
        } catch {
            recoveryError = error.localizedDescription
        }
    }

    static var shouldShowOnboarding: Bool {
        if ProcessInfo.processInfo.arguments.contains("-skipOnboarding") {
            return false
        }
        return !UserDefaults.standard.bool(forKey: OnboardingKeys.hasSeenOnboarding)
    }
}

#Preview {
    ContentView(store: VaultStore())
}
