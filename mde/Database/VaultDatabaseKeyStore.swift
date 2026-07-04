//
//  VaultDatabaseKeyStore.swift
//  MDE
//
//  OQ-02 — per-vault SQLCipher key in Keychain (separate from sync encryption key).
//

import CryptoKit
import Foundation
import Security

protocol VaultDatabaseKeyStoring: Sendable {
    func loadKey(vaultID: String) throws -> Data?
    func saveKey(_ key: Data, vaultID: String) throws
    func loadOrCreateKey(vaultID: String) throws -> Data
}

enum VaultDatabaseKeyError: LocalizedError {
    case keyUnavailable

    var errorDescription: String? {
        switch self {
        case .keyUnavailable:
            return "Vault database encryption key is not available."
        }
    }
}

final class KeychainVaultDatabaseKeyStore: VaultDatabaseKeyStoring, @unchecked Sendable {
    private let service = "name.aks.mde.database"

    func loadKey(vaultID: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: vaultID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw VaultDatabaseKeyError.keyUnavailable
        }
        return data
    }

    func saveKey(_ key: Data, vaultID: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: vaultID,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        var addQuery = query
        addQuery.merge(attributes) { _, new in new }
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else { throw VaultDatabaseKeyError.keyUnavailable }
        } else if status != errSecSuccess {
            throw VaultDatabaseKeyError.keyUnavailable
        }
    }

    func loadOrCreateKey(vaultID: String) throws -> Data {
        if let existing = try loadKey(vaultID: vaultID) {
            return existing
        }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        try saveKey(data, vaultID: vaultID)
        return data
    }
}

final class InMemoryVaultDatabaseKeyStore: VaultDatabaseKeyStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [String: Data] = [:]

    func loadKey(vaultID: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return keys[vaultID]
    }

    func saveKey(_ key: Data, vaultID: String) throws {
        lock.lock()
        defer { lock.unlock() }
        keys[vaultID] = key
    }

    func loadOrCreateKey(vaultID: String) throws -> Data {
        if let existing = try loadKey(vaultID: vaultID) {
            return existing
        }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        try saveKey(data, vaultID: vaultID)
        return data
    }
}
