//
//  TagSidebarView.swift
//  MDE
//

import SwiftUI

struct TagSidebarView: View {
    @Bindable var store: VaultStore
    @Binding var selectedTagPath: String?

    var body: some View {
        List(selection: $selectedTagPath) {
            Text("All")
                .tag(Optional<String>.none)
                .font(.body.weight(selectedTagPath == nil ? .semibold : .regular))
                .foregroundStyle(selectedTagPath == nil ? .primary : .secondary)
                .accessibilityLabel(AccessibilityLabels.allTagsFilter)
                .accessibilityAddTraits(selectedTagPath == nil ? .isSelected : [])

            ForEach(store.tagTree) { tag in
                Text("#\(tag.path)")
                    .tag(Optional(tag.path))
                    .padding(.leading, CGFloat(tag.level) * 12)
                    .font(.body.weight(selectedTagPath == tag.path ? .semibold : .regular))
                    .foregroundStyle(selectedTagPath == tag.path ? .primary : .secondary)
                    .accessibilityLabel(
                        AccessibilityLabels.tagFilter(path: tag.path, isSelected: selectedTagPath == tag.path)
                    )
                    .accessibilityAddTraits(selectedTagPath == tag.path ? .isSelected : [])
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Tags")
        .accessibilityLabel(AccessibilityLabels.tagSidebar)
        .focusSection()
    }
}
