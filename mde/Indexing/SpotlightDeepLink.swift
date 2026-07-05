//
//  SpotlightDeepLink.swift
//  MDE
//

import CoreSpotlight
import Foundation

/// Parses Core Spotlight continuation payloads (`vaultID/noteID`).
enum SpotlightDeepLink {
    static let activityType = CSSearchableItemActionType

    struct Target: Equatable, Sendable {
        var vaultID: String
        var noteID: String
    }

    static func target(from userActivity: NSUserActivity) -> Target? {
        let identifier: String?
        if let spotlightID = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
            identifier = spotlightID
        } else if let spotlightID = userActivity.userInfo?["kCSSearchableItemActivityIdentifier"] as? String {
            identifier = spotlightID
        } else {
            identifier = nil
        }
        guard let identifier else { return nil }
        return target(fromIdentifier: identifier)
    }

    static func target(fromIdentifier identifier: String) -> Target? {
        let parts = identifier.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return Target(vaultID: parts[0], noteID: parts[1])
    }
}
