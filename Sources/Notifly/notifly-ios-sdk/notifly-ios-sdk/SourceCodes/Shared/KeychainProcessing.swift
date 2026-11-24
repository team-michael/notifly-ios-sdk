import Foundation
import Security

/// The Security I/O boundary.
///
/// Tests can replace it without bypassing store logic.
protocol KeychainProcessing: Sendable {
    func copyMatching(_ query: [String: Any]) -> (OSStatus, Any?)
    func add(_ query: [String: Any]) -> OSStatus
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
}

extension KeychainProcessing {
    func copyMatching(_ query: [String: Any]) -> (OSStatus, Any?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result)
    }

    func add(_ query: [String: Any]) -> OSStatus {
        SecItemAdd(query as CFDictionary, nil)
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }
}

struct SystemKeychain: KeychainProcessing {}
