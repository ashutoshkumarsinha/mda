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

    var body: some View {
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
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
        }
    }
}

#Preview {
    ContentView(store: VaultStore())
}
