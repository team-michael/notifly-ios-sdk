import Foundation

/// Reads SDK identifiers from Keychain and migrates project-prefixed UserDefaults values.
///
/// Use one writable instance per project. Operations are synchronous and serialized by
/// this instance's lock. Extensions should use a read-only instance, which always reads
/// fresh values and never migrates or removes the host application's data.
final class IdentityStore {

    private let projectID: String
    private let username: String?
    private let defaults: UserDefaults
    private let keychain: Keychain<StoredIdentity>
    private let isReadOnly: Bool
    private let lock = NSLock()
    private var cachedIdentity: StoredIdentity?

    // Remove the migration marker last. Other SDK values are outside this store's scope.
    private let legacyKeys = [
        NotiflyCustomDefaultKey.deviceId,
        NotiflyCustomDefaultKey.externalUserId,
        NotiflyCustomDefaultKey.username,
        NotiflyCustomDefaultKey.projectId
    ]

    init(
        projectID: String,
        defaults: UserDefaults,
        keychain: Keychain<StoredIdentity>,
        isReadOnly: Bool = false,
        username: String? = nil
    ) throws {
        guard !projectID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw IdentityStoreError.invalidProjectID
        }
        self.projectID = projectID
        self.username = username
        self.defaults = defaults
        self.keychain = keychain
        self.isReadOnly = isReadOnly
    }

    /// Returns the cached identity, or loads and migrates it on the calling thread.
    /// A missing Keychain item and legacy project marker return nil without generating IDs.
    func load() throws -> StoredIdentity? {
        lock.lock()
        defer { lock.unlock() }
        if let cachedIdentity = cachedIdentity { return cachedIdentity }
        return try loadUncached()
    }

    /// Supplies registration values only for missing fields, without replacing existing IDs.
    func load(orCreate initialIdentity: StoredIdentity) throws -> StoredIdentity {
        lock.lock()
        defer { lock.unlock() }
        guard !isReadOnly else { throw IdentityStoreError.readOnly }
        try validate(initialIdentity)
        let current = try cachedIdentity ?? loadUncached()
        if current == nil {
            guard try legacyValues().isEmpty else { throw IdentityStoreError.conflictingIdentity }
        }
        let identity = StoredIdentity(
            projectID: projectID,
            username: current?.username ?? initialIdentity.username,
            deviceID: current?.deviceID ?? initialIdentity.deviceID,
            externalUserID: current == nil ? initialIdentity.externalUserID : current?.externalUserID
        )
        guard identity.username != nil, identity.deviceID != nil else {
            throw IdentityStoreError.identityUnavailable
        }
        if identity != current {
            try writeAndVerify(identity)
            cachedIdentity = identity
        }
        return identity
    }

    /// Changes the user while preserving the latest persisted device and registration fields.
    func setExternalUserID(_ value: String?) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !isReadOnly else { throw IdentityStoreError.readOnly }
        guard let current = try loadUncached() else { throw IdentityStoreError.identityUnavailable }
        let identity = StoredIdentity(
            projectID: current.projectID,
            username: current.username,
            deviceID: current.deviceID,
            externalUserID: value
        )
        if identity != current { try keychain.save(identity) }
        cachedIdentity = identity
    }

    /// Replaces the identity after resolving any pending migration.
    /// Publishes the new identity only after a successful write and matching Keychain readback.
    func save(_ identity: StoredIdentity) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !isReadOnly else { throw IdentityStoreError.readOnly }
        try validate(identity)
        _ = try loadUncached()
        try writeAndVerify(identity)
        cachedIdentity = identity
    }

    private func loadUncached() throws -> StoredIdentity? {
        cachedIdentity = nil
        if let identity = try keychain.load() {
            try validate(identity)
            if !isReadOnly {
                // A previous process may have exited after the write or during cleanup.
                try removeLegacyValues(try legacyValues(), matching: identity)
                cachedIdentity = identity
            }
            return identity
        }

        guard defaults.object(forKey: legacyKey(NotiflyCustomDefaultKey.projectId)) != nil else {
            return nil
        }
        let values = try legacyValues()
        guard values[NotiflyCustomDefaultKey.projectId] == projectID else {
            throw IdentityStoreError.conflictingIdentity
        }
        let identity = StoredIdentity(
            projectID: projectID,
            username: values[NotiflyCustomDefaultKey.username],
            deviceID: values[NotiflyCustomDefaultKey.deviceId],
            externalUserID: values[NotiflyCustomDefaultKey.externalUserId]
        )
        try validate(identity)
        if !isReadOnly {
            try writeAndVerify(identity)
            try removeLegacyValues(values, matching: identity)
            cachedIdentity = identity
        }
        return identity
    }

    private func writeAndVerify(_ identity: StoredIdentity) throws {
        try keychain.save(identity)
        // A successful write followed by a failed read leaves persistence uncertain.
        cachedIdentity = nil
        guard try keychain.load() == identity else {
            throw IdentityStoreError.verificationFailed
        }
    }

    private func validate(_ identity: StoredIdentity) throws {
        guard identity.projectID == projectID,
            username == nil || identity.username == nil || identity.username == username
        else {
            throw IdentityStoreError.conflictingIdentity
        }
    }

    private func legacyValues() throws -> [String: String] {
        var values: [String: String] = [:]
        for key in legacyKeys {
            guard let value = defaults.object(forKey: legacyKey(key)) else { continue }
            guard let string = value as? String else { throw IdentityStoreError.invalidLegacyValue }
            values[key] = string
        }
        return values
    }

    private func removeLegacyValues(_ values: [String: String], matching identity: StoredIdentity) throws {
        var expected = [NotiflyCustomDefaultKey.projectId: identity.projectID]
        expected[NotiflyCustomDefaultKey.username] = identity.username
        expected[NotiflyCustomDefaultKey.deviceId] = identity.deviceID
        expected[NotiflyCustomDefaultKey.externalUserId] = identity.externalUserID
        for (key, value) in values {
            guard expected[key] == value else { throw IdentityStoreError.conflictingIdentity }
        }
        guard try legacyValues() == values else { throw IdentityStoreError.legacyChanged }
        for key in legacyKeys where values[key] != nil {
            defaults.removeObject(forKey: legacyKey(key))
        }
    }

    private func legacyKey(_ key: String) -> String {
        "\(projectID)_\(key)"
    }
}

struct StoredIdentity: Codable, Equatable {

    let projectID: String
    let username: String?
    let deviceID: String?
    let externalUserID: String?

    private enum CodingKeys: String, CodingKey {

        case projectID = "projectId"
        case username
        case deviceID = "deviceId"
        case externalUserID = "externalUserId"
    }
}

enum IdentityStoreError: Error, Equatable {

    case invalidProjectID
    case invalidLegacyValue
    case conflictingIdentity
    case legacyChanged
    case verificationFailed
    case readOnly
    case identityUnavailable
}
