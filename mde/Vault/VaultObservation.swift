//
//  VaultObservation.swift
//  MDE
//

import Foundation
import Observation

/// List/sidebar observation surface — tag tree and row revision only.
@Observable
final class VaultListState {
    private(set) var revision = 0
    var tagTree: [TagNode] = []

    func bumpRevision() {
        revision += 1
    }
}

/// Editor observation surface — body epoch, link graph, and save errors.
@Observable
final class VaultEditorState {
    private(set) var contentEpoch = 0
    private(set) var linksRevision = 0
    var autosaveErrorMessage: String?

    func bumpContentEpoch() {
        contentEpoch += 1
    }

    func bumpLinksRevision() {
        linksRevision += 1
    }
}
