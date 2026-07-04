//
//  ZipArchiveBuilder.swift
//  MDE
//

import Foundation
import zlib

/// Minimal PKZip writer (stored entries) for portable vault exports.
enum ZipArchiveBuilder {
    static func zipData(from wrapper: FileWrapper) throws -> Data {
        var builder = Builder()
        try addEntries(from: wrapper, pathPrefix: "", to: &builder)
        return builder.finish()
    }

    private static func addEntries(
        from wrapper: FileWrapper,
        pathPrefix: String,
        to builder: inout Builder
    ) throws {
        if wrapper.isDirectory {
            guard let children = wrapper.fileWrappers else { return }
            for (name, child) in children.sorted(by: { $0.key < $1.key }) {
                let childPrefix = pathPrefix.isEmpty ? "\(name)/" : "\(pathPrefix)\(name)/"
                if child.isDirectory {
                    try addEntries(from: child, pathPrefix: childPrefix, to: &builder)
                } else if let data = child.regularFileContents {
                    let entryPath = pathPrefix.isEmpty ? name : "\(pathPrefix)\(name)"
                    builder.addEntry(path: entryPath, data: data)
                }
            }
        } else if let data = wrapper.regularFileContents {
            let entryPath = pathPrefix.isEmpty ? "export" : String(pathPrefix.dropLast())
            builder.addEntry(path: entryPath, data: data)
        }
    }

    private struct Builder {
        private var localParts: [Data] = []
        private var centralParts: [Data] = []
        private var entryCount: UInt16 = 0

        mutating func addEntry(path: String, data: Data) {
            let normalizedPath = path.replacingOccurrences(of: "\\", with: "/")
            let pathData = Data(normalizedPath.utf8)
            let crc = crc32(of: data)
            let size = UInt32(data.count)

            var local = Data()
            local.appendUInt32(0x0403_4b50)
            local.appendUInt16(20) // version needed to extract
            local.appendUInt16(0) // flags
            local.appendUInt16(0) // compression: store
            local.appendUInt16(0) // mod time
            local.appendUInt16(0) // mod date
            local.appendUInt32(crc)
            local.appendUInt32(size)
            local.appendUInt32(size)
            local.appendUInt16(UInt16(pathData.count))
            local.appendUInt16(0) // extra length
            local.append(pathData)
            local.append(data)
            localParts.append(local)

            var central = Data()
            central.appendUInt32(0x0201_4b50)
            central.appendUInt16(20) // version made by
            central.appendUInt16(20) // version needed
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt32(crc)
            central.appendUInt32(size)
            central.appendUInt32(size)
            central.appendUInt16(UInt16(pathData.count))
            central.appendUInt16(0)
            central.appendUInt16(0) // comment
            central.appendUInt16(0) // disk number start
            central.appendUInt16(0) // internal attrs
            central.appendUInt32(0) // external attrs
            central.appendUInt32(0) // local header offset — patched below
            central.append(pathData)
            centralParts.append(central)

            entryCount &+= 1
        }

        mutating func finish() -> Data {
            var archive = Data()
            var offset: UInt32 = 0
            var patchedCentral: [Data] = []

            for (index, local) in localParts.enumerated() {
                archive.append(local)
                var central = centralParts[index]
                central.replaceUInt32(at: 42, value: offset)
                patchedCentral.append(central)
                offset &+= UInt32(local.count)
            }

            let centralStart = offset
            for central in patchedCentral {
                archive.append(central)
            }
            let centralSize = UInt32(archive.count) - centralStart

            var end = Data()
            end.appendUInt32(0x0605_4b50)
            end.appendUInt16(0) // disk number
            end.appendUInt16(0) // central dir disk
            end.appendUInt16(entryCount)
            end.appendUInt16(entryCount)
            end.appendUInt32(centralSize)
            end.appendUInt32(centralStart)
            end.appendUInt16(0) // comment length
            archive.append(end)
            return archive
        }

        private func crc32(of data: Data) -> UInt32 {
            data.withUnsafeBytes { buffer in
                guard let base = buffer.baseAddress?.assumingMemoryBound(to: Bytef.self) else {
                    return 0
                }
                return UInt32(zlib.crc32(0, base, uInt(buffer.count)))
            }
        }
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    mutating func appendUInt32(_ value: UInt32) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    mutating func replaceUInt32(at offset: Int, value: UInt32) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { bytes in
            replaceSubrange(offset ..< offset + 4, with: bytes)
        }
    }
}
