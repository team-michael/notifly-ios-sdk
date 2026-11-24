import Foundation
import Security
import XCTest
@testable import notifly_ios_sdk

final class KeychainTests: XCTestCase {
    private struct Preferences: Codable, Equatable {
        let enabled: Bool
        let tags: [String]
    }

    private final class MutableValue: Codable {
        var name: String
        init(name: String) { self.name = name }
    }

    func testCallerOwnedCodableRoundTripsWithoutIdentityFields() throws {
        let backend = MemoryKeychain()
        let writer: Keychain<Preferences> = try makeStore(backend)
        try save(writer, Preferences(enabled: true, tags: ["one", "two"])).get()
        let reader: Keychain<Preferences> = try makeStore(backend)
        XCTAssertEqual(try load(reader).get(), Preferences(enabled: true, tags: ["one", "two"]))
    }

    func testDifferentAccountsServicesAndGroupsHaveIndependentRecords() throws {
        let backend = MemoryKeychain()
        let stores: [Keychain<String>] = try [
            ("settings", "a", "group.test"),
            ("settings", "b", "group.test"),
            ("credentials", "a", "group.test"),
            ("settings", "a", "group.other"),
        ].map { try Keychain(service: $0.0, account: $0.1, accessGroup: $0.2, keychain: backend) }
        for (index, store) in stores.enumerated() { try save(store, "value-\(index)").get() }
        for (index, store) in stores.enumerated() {
            XCTAssertEqual(try load(store).get(), "value-\(index)")
        }
    }

    func testMutatingReferenceModelDoesNotMutatePersistedSnapshot() throws {
        let store: Keychain<MutableValue> = try makeStore(MemoryKeychain())
        let original = MutableValue(name: "saved")
        try save(store, original).get()
        original.name = "changed after save"
        let first = try XCTUnwrap(load(store).get())
        XCTAssertEqual(first.name, "saved")
        first.name = "changed after load"
        XCTAssertEqual(try load(store).get()?.name, "saved")
        XCTAssertEqual(try load(store).get()?.name, "saved")
    }

    func testEncodingFailurePreservesPersistedValues() throws {
        let store: Keychain<Double> = try makeStore(MemoryKeychain())
        try save(store, 42).get()
        guard case .failure = save(store, .nan) else {
            return XCTFail("NaN must fail JSON encoding")
        }
        XCTAssertEqual(try load(store).get(), 42)
        XCTAssertEqual(try load(store).get(), 42)
    }

    func testDifferentModelCannotOverwriteExistingIncompatiblePayload() throws {
        let backend = MemoryKeychain()
        let original: Keychain<Preferences> = try makeStore(backend)
        try save(original, Preferences(enabled: true, tags: [])).get()
        let incompatible: Keychain<String> = try makeStore(backend)
        guard case .failure(let error) = save(incompatible, "replacement") else {
            return XCTFail("Incompatible payload must be preserved")
        }
        XCTAssertEqual(error as? KeychainError, .invalidData)
        XCTAssertEqual(
            try load(original).get(),
            Preferences(enabled: true, tags: [])
        )
    }

    func testEmptyNamespaceConfigurationIsRejected() {
        for (service, account, group) in [
            ("", "a", "group.test"), ("s", " ", "group.test"), ("s", "a", ""),
        ] {
            XCTAssertThrowsError(
                try Keychain<String>(service: service, account: account, accessGroup: group)
            ) {
                XCTAssertEqual($0 as? KeychainError, .invalidConfiguration)
            }
        }
    }

    func testReadObservesChangesFromAnotherStore() throws {
        let backend = MemoryKeychain()
        let first: Keychain<String> = try makeStore(backend)
        let second: Keychain<String> = try makeStore(backend)
        try first.save("before")
        XCTAssertEqual(try first.load(), "before")
        try second.save("after")
        XCTAssertEqual(try first.load(), "after")
    }

    private func makeStore<Value: Codable>(_ backend: MemoryKeychain) throws -> Keychain<Value> {
        try Keychain(
            service: "test.settings",
            account: "settings-a",
            accessGroup: "group.test",
            keychain: backend
        )
    }

    private func load<Value>(_ store: Keychain<Value>) -> Result<Value?, Error> {
        Result { try store.load() }
    }

    private func save<Value>(_ store: Keychain<Value>, _ value: Value) -> Result<Void, Error> {
        Result { try store.save(value) }
    }
}

/// Accessed sequentially by these synchronous I/O tests; no concurrent mutations.
private final class MemoryKeychain: KeychainProcessing, @unchecked Sendable {
    private struct Address: Hashable {
        let service: String
        let account: String
        let group: String
    }
    private var records: [Address: Data] = [:]

    private func address(_ query: [String: Any]) -> Address? {
        guard query[kSecClass as String] as? String == kSecClassGenericPassword as String,
            query[kSecAttrSynchronizable as String] as? Bool == false,
            let service = query[kSecAttrService as String] as? String,
            let account = query[kSecAttrAccount as String] as? String,
            let group = query[kSecAttrAccessGroup as String] as? String
        else { return nil }
        return Address(service: service, account: account, group: group)
    }

    func copyMatching(_ query: [String: Any]) -> (OSStatus, Any?) {
        guard let key = address(query), query[kSecReturnData as String] as? Bool == true,
            query[kSecMatchLimit as String] as? String == kSecMatchLimitOne as String
        else {
            return (errSecParam, nil)
        }
        return records[key].map { (errSecSuccess, $0) } ?? (errSecItemNotFound, nil)
    }

    func add(_ query: [String: Any]) -> OSStatus {
        guard let key = address(query), let data = query[kSecValueData as String] as? Data else {
            return errSecParam
        }
        guard records[key] == nil else { return errSecDuplicateItem }
        records[key] = data
        return errSecSuccess
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        guard let key = address(query), let data = attributes[kSecValueData as String] as? Data
        else { return errSecParam }
        guard records[key] != nil else { return errSecItemNotFound }
        records[key] = data
        return errSecSuccess
    }
}
