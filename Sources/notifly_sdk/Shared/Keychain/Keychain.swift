import Foundation
import Security

/// Stores one caller-defined Codable value as a generic-password Keychain item.
///
/// Operations run synchronously on the calling thread. This type does not cache values
/// or choose an execution queue; callers control scheduling and multi-step transactions.
struct Keychain<Value: Codable> {

    private let service: String
    private let account: String
    private let accessGroup: String
    private let keychain: KeychainProcessing

    /// Scopes every operation to an explicit group allowed by the signing entitlements.
    init(
        service: String,
        account: String,
        accessGroup: String,
        keychain: KeychainProcessing = SystemKeychain()
    ) throws {
        guard !service.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !accessGroup.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw KeychainError.invalidConfiguration
        }
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
        self.keychain = keychain
    }

    /// Returns nil only when the item does not exist. Access and decoding errors propagate.
    func load() throws -> Value? {
        var query = itemQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, result) = keychain.copyMatching(query)
        guard status != errSecItemNotFound else { return nil }
        try check(status)
        guard let data = result as? Data else { throw KeychainError.invalidData }
        return try JSONDecoder().decode(Value.self, from: data)
    }

    /// Creates or replaces the value without deleting the existing item first.
    /// Items remain on this device and are accessible after its first unlock.
    func save(_ value: Value) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: try JSONEncoder().encode(value),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = keychain.update(itemQuery, attributes: attributes)
        guard status == errSecItemNotFound else {
            try check(status)
            return
        }

        let newItem = itemQuery.merging(attributes) { _, newValue in newValue }
        let addStatus = keychain.add(newItem)
        if addStatus == errSecDuplicateItem {
            // Another caller may create the item between our update and add.
            try check(keychain.update(itemQuery, attributes: attributes))
        }
        else {
            try check(addStatus)
        }
    }

    /// Removes the item. An already absent item is a successful no-op.
    func delete() throws {
        let status = keychain.delete(itemQuery)
        guard status != errSecItemNotFound else { return }
        try check(status)
    }

    private var itemQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecAttrSynchronizable as String: false
        ]
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }
}

enum KeychainError: Error, Equatable {

    case invalidConfiguration
    case invalidData
    case status(OSStatus)
}
