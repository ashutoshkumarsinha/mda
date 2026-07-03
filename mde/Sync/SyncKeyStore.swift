//
//  SyncKeyStore.swift
//  MDE
//

import CryptoKit
import Foundation
import Security

protocol SyncKeyStoring: Sendable {
    func loadKey(vaultID: String) throws -> SymmetricKey?
    func saveKey(_ key: SymmetricKey, vaultID: String) throws
    func deleteKey(vaultID: String) throws
}

final class KeychainSyncKeyStore: SyncKeyStoring, @unchecked Sendable {
    private let service = "name.aks.mde.sync"

    func loadKey(vaultID: String) throws -> SymmetricKey? {
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
            throw SyncError.keyUnavailable
        }
        return SymmetricKey(data: data)
    }

    func saveKey(_ key: SymmetricKey, vaultID: String) throws {
        let data = key.withUnsafeBytes { Data($0) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: vaultID,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        var addQuery = query
        addQuery.merge(attributes) { _, new in new }
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else { throw SyncError.keyUnavailable }
        } else if status != errSecSuccess {
            throw SyncError.keyUnavailable
        }
    }

    func deleteKey(vaultID: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: vaultID,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

final class InMemorySyncKeyStore: SyncKeyStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [String: SymmetricKey] = [:]

    func loadKey(vaultID: String) throws -> SymmetricKey? {
        lock.lock()
        defer { lock.unlock() }
        return keys[vaultID]
    }

    func saveKey(_ key: SymmetricKey, vaultID: String) throws {
        lock.lock()
        defer { lock.unlock() }
        keys[vaultID] = key
    }

    func deleteKey(vaultID: String) throws {
        lock.lock()
        defer { lock.unlock() }
        keys.removeValue(forKey: vaultID)
    }
}
