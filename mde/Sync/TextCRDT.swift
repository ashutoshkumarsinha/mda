//
//  TextCRDT.swift
//  MDE
//

import Foundation

enum TextCRDT {
    /// Merges concurrent text edits when they do not overlap.
    /// Returns nil when both sides edited the same region.
    static func merge(base: String, local: String, remote: String) -> String? {
        if local == remote { return local }
        if local == base { return remote }
        if remote == base { return local }

        if let merged = mergeAppendedLines(base: base, local: local, remote: remote) {
            return merged
        }

        if let merged = mergeSingleReplacement(base: base, local: local, remote: remote) {
            return merged
        }

        return nil
    }

    private static func mergeAppendedLines(base: String, local: String, remote: String) -> String? {
        let baseLines = base.components(separatedBy: "\n")
        let localLines = local.components(separatedBy: "\n")
        let remoteLines = remote.components(separatedBy: "\n")

        guard localLines.count >= baseLines.count, remoteLines.count >= baseLines.count else {
            return nil
        }
        guard Array(localLines.prefix(baseLines.count)) == baseLines,
              Array(remoteLines.prefix(baseLines.count)) == baseLines else {
            return nil
        }

        let localSuffix = Array(localLines.dropFirst(baseLines.count))
        let remoteSuffix = Array(remoteLines.dropFirst(baseLines.count))

        if localSuffix == remoteSuffix {
            return local
        }

        var merged = baseLines
        merged.append(contentsOf: localSuffix)
        for line in remoteSuffix where !merged.contains(line) {
            merged.append(line)
        }
        return merged.joined(separator: "\n")
    }

    private static func mergeSingleReplacement(base: String, local: String, remote: String) -> String? {
        guard let localRange = singleEditRange(base: base, edited: local),
              let remoteRange = singleEditRange(base: base, edited: remote) else {
            return nil
        }

        if localRange.intersection(remoteRange) != nil {
            return nil
        }

        let baseNSString = base as NSString
        let localNSString = local as NSString
        let remoteNSString = remote as NSString

        let prefix = baseNSString.substring(to: localRange.location)
        let suffixStart = localRange.upperBound
        let suffix = baseNSString.substring(from: suffixStart)

        let localMiddle = localNSString.substring(with: localRange)
        let remoteMiddle = remoteNSString.substring(with: remoteRange)

        return prefix + localMiddle + remoteMiddle + suffix
    }

    private static func singleEditRange(base: String, edited: String) -> NSRange? {
        let baseChars = Array(base)
        let editedChars = Array(edited)

        var prefix = 0
        while prefix < baseChars.count, prefix < editedChars.count, baseChars[prefix] == editedChars[prefix] {
            prefix += 1
        }

        var suffix = 0
        while suffix < baseChars.count - prefix,
              suffix < editedChars.count - prefix,
              baseChars[baseChars.count - 1 - suffix] == editedChars[editedChars.count - 1 - suffix] {
            suffix += 1
        }

        let baseMiddle = baseChars.count - prefix - suffix
        let editedMiddle = editedChars.count - prefix - suffix
        if baseMiddle < 0 || editedMiddle < 0 { return nil }

        return NSRange(location: prefix, length: editedMiddle)
    }
}
