//
//  SyncPolicy.swift
//  MDE
//

import Foundation

enum SyncPolicy {
    /// Debounce window after local note edits before uploading.
    static let editDebounceSeconds: TimeInterval = 2

    /// Skip CloudKit pull when last successful sync is newer than this interval.
    static let minPullIntervalSeconds: TimeInterval = 5 * 60

    /// Maximum encrypted payload size before upload is rejected (CloudKit field guidance).
    static let maxRecordBytes = 1_024 * 1_024
}
