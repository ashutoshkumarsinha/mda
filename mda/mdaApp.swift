//
//  mdaApp.swift
//  mda
//
//  Created by Deep Root on 6/25/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

@main
struct mdaApp: App {
    var body: some Scene {
        DocumentGroup(editing: .itemDocument, migrationPlan: mdaMigrationPlan.self) {
            ContentView()
        }
    }
}

extension UTType {
    static var itemDocument: UTType {
        UTType(importedAs: "com.example.item-document")
    }
}

struct mdaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [VersionedSchema.Type] = [
        mdaVersionedSchema.self,
    ]

    static var stages: [MigrationStage] = [
        // Stages of migration between VersionedSchema, if required.
    ]
}

struct mdaVersionedSchema: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] = [
        Item.self,
    ]
}
