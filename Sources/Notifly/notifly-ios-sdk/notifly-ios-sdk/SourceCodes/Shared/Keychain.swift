//
//  Keychain.swift
//  notifly-ios-sdk
//
//  Created by 박건우 on 11/23/26.
//

import Foundation
import Security

enum KeychainError: Error, Equatable {
    case invalidConfiguration
    case keychain(OSStatus)
    case invalidData
}

/// Stores one caller-owned Codable value in an explicitly scoped Keychain item.
///
/// Synchronous I/O on the calling thread. The caller owns caching and coordination.
final class Keychain<Value: Codable>: Sendable {
    private let keychain: KeychainProcessing
    private let service: String
    private let account: String
    private let accessGroup: String
    private let validate: (@Sendable (Value) throws -> Void)?

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecAttrSynchronizable as String: false,
        ]
    }

    init(
        service: String,
        account: String,
        accessGroup: String,
        keychain: KeychainProcessing = SystemKeychain(),
        validate: (@Sendable (Value) throws -> Void)? = nil
    ) throws {
        guard
            [service, account, accessGroup].allSatisfy({
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })
        else {
            throw KeychainError.invalidConfiguration
        }
        self.keychain = keychain
        self.validate = validate
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
    }

    func load() throws -> Value? {
        try readRecord()
    }

    func save(_ value: Value) throws {
        try write(value, replacingExisting: true)
    }

    /// Inserts without replacing an item created by another writer during migration.
    func insert(_ value: Value) throws {
        try write(value, replacingExisting: false)
    }

    private func write(_ value: Value, replacingExisting: Bool) throws {
        try validate?(value)
        // Recheck persisted schema and scope before replacing an existing record.
        let existing = try readRecord()
        if existing != nil, !replacingExisting {
            throw KeychainError.keychain(errSecDuplicateItem)
        }
        let data = try JSONEncoder().encode(value)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status: OSStatus
        if existing != nil {
            status = keychain.update(baseQuery, attributes: attributes)
        } else {
            status = keychain.add(baseQuery.merging(attributes) { _, value in value })
        }
        // A concurrent creator is never overwritten by an insertion.
        guard status == errSecSuccess else { throw KeychainError.keychain(status) }
    }

    private func readRecord() throws -> Value? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, value) = keychain.copyMatching(query)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.keychain(status) }
        guard let data = value as? Data else { throw KeychainError.invalidData }
        return try decode(data)
    }

    private func decode(_ data: Data) throws -> Value {
        let value: Value
        do { value = try JSONDecoder().decode(Value.self, from: data) } catch is DecodingError {
            throw KeychainError.invalidData
        }
        // Domain errors thrown by the model or validator reach the caller unchanged.
        try validate?(value)
        return value
    }
}
