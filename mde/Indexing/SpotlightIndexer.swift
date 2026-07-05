//
//  SpotlightIndexer.swift
//  MDE
//

import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

enum SpotlightIndexer {
    static func indexNote(_ note: Note, vaultID: String) {
        guard !note.isDeleted else {
            deleteNote(noteID: note.id, vaultID: vaultID)
            return
        }

        let attributes = CSSearchableItemAttributeSet(contentType: .plainText)
        let displayTitle = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        attributes.title = displayTitle.isEmpty ? "Untitled" : displayTitle
        attributes.contentDescription = NoteListItem.makeSnippet(from: note.content)
        attributes.textContent = note.content

        let item = CSSearchableItem(
            uniqueIdentifier: identifier(noteID: note.id, vaultID: vaultID),
            domainIdentifier: vaultID,
            attributeSet: attributes
        )
        CSSearchableIndex.default().indexSearchableItems([item])
    }

    static func deleteNote(noteID: String, vaultID: String) {
        CSSearchableIndex.default().deleteSearchableItems(
            withIdentifiers: [identifier(noteID: noteID, vaultID: vaultID)]
        )
    }

    static func reindexNotes(_ notes: [Note], vaultID: String) {
        deleteAll(in: vaultID)
        let active = notes.filter { !$0.isDeleted }
        let items = active.map { note -> CSSearchableItem in
            let attributes = CSSearchableItemAttributeSet(contentType: .plainText)
            let displayTitle = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
            attributes.title = displayTitle.isEmpty ? "Untitled" : displayTitle
            attributes.contentDescription = NoteListItem.makeSnippet(from: note.content)
            attributes.textContent = note.content
            return CSSearchableItem(
                uniqueIdentifier: identifier(noteID: note.id, vaultID: vaultID),
                domainIdentifier: vaultID,
                attributeSet: attributes
            )
        }
        CSSearchableIndex.default().indexSearchableItems(items)
    }

    static func deleteAll(in vaultID: String) {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [vaultID])
    }

    private static func identifier(noteID: String, vaultID: String) -> String {
        "\(vaultID)/\(noteID)"
    }
}
