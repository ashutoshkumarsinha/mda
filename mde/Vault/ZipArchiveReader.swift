//
//  ZipArchiveReader.swift
//  MDE
//

import Foundation

enum ZipArchiveReader {
    enum Error: Swift.Error, LocalizedError {
        case invalidArchive
        case unsupportedCompression(UInt16)
        case pathTraversal(String)

        var errorDescription: String? {
            switch self {
            case .invalidArchive:
                return "The zip archive could not be read."
            case .unsupportedCompression(let method):
                return "Unsupported zip compression method \(method)."
            case .pathTraversal(let path):
                return "Unsafe path in archive: \(path)"
            }
        }
    }

    static func extractArchive(from zipURL: URL, to destinationURL: URL) throws {
        let data = try Data(contentsOf: zipURL)
        try extractArchive(from: data, to: destinationURL)
    }

    static func extractArchive(from data: Data, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        var offset = 0
        while offset + 30 <= data.count {
            guard data.readUInt32(at: offset) == 0x0403_4b50 else { break }

            let compression = data.readUInt16(at: offset + 8)
            guard compression == 0 else {
                throw Error.unsupportedCompression(compression)
            }

            let compressedSize = Int(data.readUInt32(at: offset + 18))
            let uncompressedSize = Int(data.readUInt32(at: offset + 22))
            let filenameLength = Int(data.readUInt16(at: offset + 26))
            let extraLength = Int(data.readUInt16(at: offset + 28))
            let headerSize = 30 + filenameLength + extraLength
            guard offset + headerSize + compressedSize <= data.count else {
                throw Error.invalidArchive
            }

            let nameData = data.subdata(in: offset + 30 ..< offset + 30 + filenameLength)
            guard let entryName = String(data: nameData, encoding: .utf8), !entryName.isEmpty else {
                throw Error.invalidArchive
            }

            let normalized = entryName.replacingOccurrences(of: "\\", with: "/")
            try validateEntryPath(normalized)

            let payloadOffset = offset + headerSize
            let payload = data.subdata(in: payloadOffset ..< payloadOffset + compressedSize)
            guard payload.count == uncompressedSize else { throw Error.invalidArchive }

            let destination = destinationURL.appendingPathComponent(normalized)
            if normalized.hasSuffix("/") {
                try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            } else {
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try payload.write(to: destination, options: .atomic)
            }

            offset = payloadOffset + compressedSize
        }
    }

    private static func validateEntryPath(_ path: String) throws {
        if path.hasPrefix("/") || path.contains("..") {
            throw Error.pathTraversal(path)
        }
    }
}

private extension Data {
    func readUInt16(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return subdata(in: offset ..< offset + 2).withUnsafeBytes {
            UInt16(littleEndian: $0.load(as: UInt16.self))
        }
    }

    func readUInt32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return subdata(in: offset ..< offset + 4).withUnsafeBytes {
            UInt32(littleEndian: $0.load(as: UInt32.self))
        }
    }
}
