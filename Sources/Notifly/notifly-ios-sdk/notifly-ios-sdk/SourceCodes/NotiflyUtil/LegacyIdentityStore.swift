import Foundation

enum IdentityMigrationError: Error, Equatable {
    case invalidLegacyValue
    case conflictingIdentity
    case legacyChanged
    case verificationFailed
    case identityUnavailable
}

/// Reads the exact keys used by older SDKs without deriving or normalizing identifiers.
/// Configuration is immutable and UserDefaults supports concurrent access. The identity
/// store locks compound migration operations; snapshot validation detects external changes.
final class LegacyIdentityStore: @unchecked Sendable {
    struct Snapshot: Equatable {
        let projectID: String?
        let username: String?
        let deviceID: String?
        let externalUserID: String?
    }

    private let defaults: UserDefaults
    private let projectID: String
    private let username: String

    init(
        defaults: UserDefaults,
        projectID: String,
        username: String
    ) {
        self.defaults = defaults
        self.projectID = projectID
        self.username = username
    }

    func snapshot() throws -> Snapshot {
        let snapshot = try Snapshot(
            projectID: string(for: NotiflyCustomDefaultKey.projectId),
            username: string(for: NotiflyCustomDefaultKey.username),
            deviceID: string(for: NotiflyCustomDefaultKey.deviceId),
            externalUserID: string(for: NotiflyCustomDefaultKey.externalUserId)
        )
        guard snapshot.projectID == nil || snapshot.projectID == projectID,
            snapshot.username == nil || snapshot.username == username,
            snapshot.deviceID?.isEmpty != true
        else { throw IdentityMigrationError.conflictingIdentity }
        return snapshot
    }

    /// Removes only an unchanged snapshot after a successful Keychain readback.
    ///
    /// Password, JWT, APNs registration and other projects belong to separate policies.
    func remove(_ snapshot: Snapshot) throws {
        guard try self.snapshot() == snapshot else { throw IdentityMigrationError.legacyChanged }
        for key in [
            NotiflyCustomDefaultKey.deviceId, NotiflyCustomDefaultKey.externalUserId,
            NotiflyCustomDefaultKey.projectId, NotiflyCustomDefaultKey.username,
        ] {
            defaults.removeObject(forKey: "\(projectID)_\(key)")
        }
    }

    func matches(_ snapshot: Snapshot, identity: StoredIdentity) -> Bool {
        // Missing keys can be left by an interruption during cleanup. A valid Keychain
        // record remains authoritative; an explicitly different legacy value is preserved.
        identity.projectID == projectID && identity.username == username && !identity.deviceID.isEmpty
            && (snapshot.deviceID == nil || snapshot.deviceID == identity.deviceID)
            && (snapshot.externalUserID == nil
                || snapshot.externalUserID == identity.externalUserID)
    }

    func identity(deviceID: String, snapshot: Snapshot) -> StoredIdentity {
        StoredIdentity(
            projectID: projectID, deviceID: deviceID,
            externalUserID: snapshot.externalUserID, username: username
        )
    }

    private func string(for key: String) throws -> String? {
        guard let value = defaults.object(forKey: "\(projectID)_\(key)") else { return nil }
        guard let string = value as? String else { throw IdentityMigrationError.invalidLegacyValue }
        return string
    }
}
