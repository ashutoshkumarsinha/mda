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
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: OnboardingKeys.hasSeenOnboarding)
    @State private var showSyncSetup = false
    @State private var syncCoordinator: SyncCoordinator?

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
        .task {
            if syncCoordinator == nil {
                let coordinator = SyncCoordinator(store: store)
                syncCoordinator = coordinator
                await coordinator.bootstrap()
            }
        }
    }
}

#Preview {
    ContentView(store: VaultStore())
}
