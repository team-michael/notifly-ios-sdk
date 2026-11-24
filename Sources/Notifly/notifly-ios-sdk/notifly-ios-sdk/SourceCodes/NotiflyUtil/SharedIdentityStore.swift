import Foundation
import Security

/// Raw persisted identifiers.
///
/// Device/user ID derivation belongs to the caller.
/// This model belongs to the SDK; the Shared Keychain component knows only Codable.
struct StoredIdentity: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let projectID: String
    let deviceID: String
    let externalUserID: String?
    let username: String

    init(projectID: String, deviceID: String, externalUserID: String?, username: String) {
        self.schemaVersion = 1
        self.projectID = projectID
        self.deviceID = deviceID
        self.externalUserID = externalUserID
        self.username = username
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        // Persisted keys are a compatibility contract, independent of Swift naming.
        case projectID = "projectId"
        case deviceID = "deviceId"
        case externalUserID = "externalUserId"
        case username
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        // Check the version before fields: a future schema may change required fields.
        guard schemaVersion == 1 else {
            throw SharedIdentityStoreError.unsupportedSchema(schemaVersion)
        }
        projectID = try container.decode(String.self, forKey: .projectID)
        deviceID = try container.decode(String.self, forKey: .deviceID)
        externalUserID = try container.decodeIfPresent(String.self, forKey: .externalUserID)
        username = try container.decode(String.self, forKey: .username)
    }
}

enum SharedIdentityStoreError: Error, Equatable {
    case unsupportedSchema(Int)
    case projectMismatch
}

/// Synchronous identity storage and migration on the calling thread.
/// A lock keeps cache updates and migration atomic across SDK and network callers.
/// No queue, task or thread switch is performed here.
final class SharedIdentityStore {
    private let storage: Keychain<StoredIdentity>
    private let legacy: LegacyIdentityStore?
    private let isReadOnly: Bool
    private let newDeviceID: () -> String?
    private let lock = NSLock()
    private var cachedIdentity: StoredIdentity?

    var current: StoredIdentity? {
        lock.lock()
        defer { lock.unlock() }
        return cachedIdentity
    }

    init(
        projectID: String,
        accessGroup: String,
        keychain: KeychainProcessing = SystemKeychain(),
        legacy: LegacyIdentityStore? = nil,
        isReadOnly: Bool = false,
        newDeviceID: @escaping () -> String? = { nil }
    ) throws {
        self.legacy = legacy
        self.isReadOnly = isReadOnly
        self.newDeviceID = newDeviceID
        storage = try Keychain(
            service: "tech.notifly.identity",
            account: projectID,
            accessGroup: accessGroup,
            keychain: keychain
        ) { identity in
            guard identity.projectID == projectID else {
                throw SharedIdentityStoreError.projectMismatch
            }
        }
    }

    func load(forceRefresh: Bool = false) throws -> StoredIdentity? {
        lock.lock()
        defer { lock.unlock() }
        if !forceRefresh, let identity = cachedIdentity { return identity }
        cachedIdentity = nil
        let identity = try read()
        cachedIdentity = identity
        return identity
    }

    func save(_ identity: StoredIdentity) throws {
        lock.lock()
        defer { lock.unlock() }
        try writeAndCache(identity)
    }

    private func writeAndCache(_ identity: StoredIdentity) throws {
        do {
            try write(identity)
            cachedIdentity = identity
        } catch let error as VerificationFailure {
            cachedIdentity = nil
            throw error.cause
        }
    }

    func setExternalUserID(_ value: String?) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let identity = try read() else {
            throw IdentityMigrationError.identityUnavailable
        }
        cachedIdentity = identity
        let updated = StoredIdentity(
            projectID: identity.projectID, deviceID: identity.deviceID,
            externalUserID: value, username: identity.username
        )
        try writeAndCache(updated)
    }

    private func read() throws -> StoredIdentity? {
        let stored = try storage.load()
        guard let legacy = legacy else { return stored }
        let snapshot = try legacy.snapshot()
        if let stored = stored {
            guard legacy.matches(snapshot, identity: stored) else {
                throw IdentityMigrationError.conflictingIdentity
            }
            if !isReadOnly { try legacy.remove(snapshot) }
            return stored
        }

        let deviceID: String?
        if let existing = snapshot.deviceID {
            deviceID = existing
        } else {
            // Extensions read old defaults but never create a new device identity.
            guard !isReadOnly else { throw IdentityMigrationError.identityUnavailable }
            deviceID = newDeviceID()
        }
        guard let deviceID = deviceID, !deviceID.isEmpty else {
            throw IdentityMigrationError.identityUnavailable
        }
        let identity = legacy.identity(deviceID: deviceID, snapshot: snapshot)
        if !isReadOnly {
            do {
                try storage.insert(identity)
            } catch KeychainError.keychain(errSecDuplicateItem) {
                // Accept a concurrent insertion only if it contains the same identity.
            }
            try verify(identity)
            try legacy.remove(snapshot)
        }
        return identity
    }

    private func write(_ identity: StoredIdentity) throws {
        guard !isReadOnly else { throw IdentityMigrationError.identityUnavailable }
        try storage.save(identity)
        do {
            try verify(identity)
        } catch {
            // Only a successful write followed by failed verification invalidates
            // the old cache. An unsuccessful write preserves the previous identity.
            throw VerificationFailure(cause: error)
        }
    }

    private func verify(_ expected: StoredIdentity) throws {
        guard try storage.load() == expected else {
            throw IdentityMigrationError.verificationFailed
        }
    }

    private struct VerificationFailure: Error {
        let cause: Error
    }
}
