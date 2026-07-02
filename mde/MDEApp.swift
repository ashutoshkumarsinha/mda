//
//  MDEApp.swift
//  MDE
//
//  Created by Deep Root on 6/25/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

@main
struct MDEApp: App {
    var body: some Scene {
        DocumentGroup(editing: .itemDocument, migrationPlan: MDEMigrationPlan.self) {
            ContentView()
        }
    }
}

extension UTType {
    static var itemDocument: UTType {
        UTType(importedAs: "name.aks.mde.document")
    }
}

struct MDEMigrationPlan: SchemaMigrationPlan {
    static var schemas: [VersionedSchema.Type] = [
        MDEVersionedSchema.self,
    ]

    static var stages: [MigrationStage] = [
        // Stages of migration between VersionedSchema, if required.
    ]
}

struct MDEVersionedSchema: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] = [
        Item.self,
    ]
}
