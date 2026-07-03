//
//  NoteMerger.swift
//  MDE
//

import Foundation

enum MergeResult: Equatable {
    case merged(NoteSyncPayload)
    case conflict(NoteConflict)
    case unchanged(NoteSyncPayload)
}

enum NoteMerger {
    static func merge(
        local: NoteSyncPayload,
        remote: NoteSyncPayload,
        base: NoteSyncPayload?
    ) -> MergeResult {
        if local.checksum == remote.checksum {
            return .unchanged(local)
        }

        if let base {
            let localChanged = local.checksum != base.checksum
            let remoteChanged = remote.checksum != base.checksum

            if localChanged && remoteChanged {
                if let mergedContent = TextCRDT.merge(
                    base: base.content,
                    local: local.content,
                    remote: remote.content
                ) {
                    var winner = local.clientUpdatedAt >= remote.clientUpdatedAt ? local : remote
                    winner.content = mergedContent
                    winner.title = local.clientUpdatedAt >= remote.clientUpdatedAt ? local.title : remote.title
                    winner.version = max(local.version, remote.version) + 1
                    winner.updatedAt = max(local.updatedAt, remote.updatedAt)
                    winner.clientUpdatedAt = max(local.clientUpdatedAt, remote.clientUpdatedAt)
                    winner.isPinned = local.isPinned || remote.isPinned
                    winner.isDeleted = local.isDeleted || remote.isDeleted
                    winner.checksum = SyncChecksum.compute(for: winner)
                    return .merged(winner)
                }

                return .conflict(NoteConflict(noteID: local.noteID, local: local, remote: remote, base: base))
            }

            if localChanged { return .merged(local) }
            if remoteChanged { return .merged(remote) }
            return .unchanged(local)
        }

        if local.clientUpdatedAt >= remote.clientUpdatedAt {
            return .merged(local)
        }
        return .merged(remote)
    }
}
