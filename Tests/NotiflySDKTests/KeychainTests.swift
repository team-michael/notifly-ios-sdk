import Foundation
import Security
import XCTest
@testable import notifly_sdk

final class KeychainTests: XCTestCase {

    func testMissingItemIsDistinctFromAccessFailure() throws {
        let backend = StubKeychain()
        let store = try makeStore(backend)
        XCTAssertNil(try store.load())

        for status in [errSecInteractionNotAllowed, errSecMissingEntitlement] {
            backend.readResult = (status, nil)
            XCTAssertThrowsError(try store.load()) { error in
                XCTAssertEqual(error as? KeychainError, .status(status))
            }
        }
    }

    func testLoadDecodesCallerDefinedModelAndUsesExactNamespace() throws {
        let backend = StubKeychain()
        let expected = SampleValue(name: "한글", count: 3)
        backend.readResult = (errSecSuccess, try JSONEncoder().encode(expected) as NSData)
        let store = try makeStore(backend)

        XCTAssertEqual(try store.load(), expected)
        let query = try XCTUnwrap(backend.queries.last)
        XCTAssertEqual(query[kSecClass as String] as? String, kSecClassGenericPassword as String)
        XCTAssertEqual(query[kSecAttrService as String] as? String, "test.service")
        XCTAssertEqual(query[kSecAttrAccount as String] as? String, "test.account")
        XCTAssertEqual(query[kSecAttrAccessGroup as String] as? String, "group.test")
        XCTAssertEqual(query[kSecAttrSynchronizable as String] as? Bool, false)
        XCTAssertEqual(query[kSecReturnData as String] as? Bool, true)
        XCTAssertEqual(query[kSecMatchLimit as String] as? String, kSecMatchLimitOne as String)
    }

    func testInvalidDataDoesNotBecomeMissing() throws {
        let backend = StubKeychain()
        let store = try makeStore(backend)
        backend.readResult = (errSecSuccess, nil)
        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? KeychainError, .invalidData)
        }

        backend.readResult = (errSecSuccess, Data("invalid JSON".utf8) as NSData)
        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertTrue(error is DecodingError)
        }
        XCTAssertEqual(backend.operations, ["read", "read"])
    }

    func testSaveEncodesBeforeAddingWithDeviceOnlyProtection() throws {
        let backend = StubKeychain()
        let store = try makeStore(backend)
        let expected = SampleValue(name: "new", count: 1)
        try store.save(expected)

        XCTAssertEqual(backend.operations, ["update", "add"])
        let item = try XCTUnwrap(backend.addedItem)
        let data = try XCTUnwrap(item[kSecValueData as String] as? Data)
        XCTAssertEqual(try JSONDecoder().decode(SampleValue.self, from: data), expected)
        XCTAssertEqual(
            item[kSecAttrAccessible as String] as? String,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        )
        XCTAssertEqual(item[kSecAttrAccessGroup as String] as? String, "group.test")
        XCTAssertEqual(item[kSecAttrSynchronizable as String] as? Bool, false)
    }

    func testSaveUpdatesExistingItemWithoutDeletingIt() throws {
        let backend = StubKeychain()
        backend.updateResults = [errSecSuccess]
        try makeStore(backend).save(SampleValue(name: "updated", count: 2))

        XCTAssertEqual(backend.operations, ["update"])
        let data = try XCTUnwrap(backend.updatedAttributes?[kSecValueData as String] as? Data)
        XCTAssertEqual(
            try JSONDecoder().decode(SampleValue.self, from: data),
            SampleValue(name: "updated", count: 2)
        )
    }

    func testDuplicateCreationRetriesUpdateOnceAndPropagatesFailure() throws {
        for finalStatus in [errSecSuccess, errSecInteractionNotAllowed] {
            let backend = StubKeychain()
            backend.updateResults = [errSecItemNotFound, finalStatus]
            backend.addResult = errSecDuplicateItem
            let store = try makeStore(backend)

            if finalStatus == errSecSuccess {
                XCTAssertNoThrow(try store.save(SampleValue(name: "value", count: 1)))
            } else {
                XCTAssertThrowsError(try store.save(SampleValue(name: "value", count: 1))) { error in
                    XCTAssertEqual(error as? KeychainError, .status(finalStatus))
                }
            }
            XCTAssertEqual(backend.operations, ["update", "add", "update"])
        }
    }

    func testWriteFailuresArePropagatedWithoutDeletingItems() throws {
        let backend = StubKeychain()
        let store = try makeStore(backend)
        backend.updateResults = [errSecInteractionNotAllowed]
        XCTAssertThrowsError(try store.save(SampleValue(name: "value", count: 1))) { error in
            XCTAssertEqual(error as? KeychainError, .status(errSecInteractionNotAllowed))
        }
        XCTAssertEqual(backend.operations, ["update"])

        backend.addResult = errSecMissingEntitlement
        XCTAssertThrowsError(try store.save(SampleValue(name: "value", count: 1))) { error in
            XCTAssertEqual(error as? KeychainError, .status(errSecMissingEntitlement))
        }
        XCTAssertEqual(backend.operations, ["update", "update", "add"])
    }

    func testEncodingFailureDoesNotTouchKeychain() throws {
        let backend = StubKeychain()
        let store = try Keychain<FailingValue>(
            service: "test", account: "test", accessGroup: "group.test", keychain: backend
        )
        XCTAssertThrowsError(try store.save(FailingValue())) { error in
            XCTAssertTrue(error is EncodingError)
        }
        XCTAssertTrue(backend.operations.isEmpty)
    }

    func testDeleteAcceptsMissingItemAndPropagatesAccessFailure() throws {
        let backend = StubKeychain()
        let store = try makeStore(backend)
        for status in [errSecSuccess, errSecItemNotFound] {
            backend.deleteResult = status
            XCTAssertNoThrow(try store.delete())
        }
        backend.deleteResult = errSecMissingEntitlement
        XCTAssertThrowsError(try store.delete()) { error in
            XCTAssertEqual(error as? KeychainError, .status(errSecMissingEntitlement))
        }
        let query = try XCTUnwrap(backend.queries.last)
        XCTAssertEqual(query[kSecAttrService as String] as? String, "test.service")
        XCTAssertEqual(query[kSecAttrAccount as String] as? String, "test.account")
        XCTAssertEqual(query[kSecAttrAccessGroup as String] as? String, "group.test")
    }

    func testEmptyNamespaceIsRejectedBeforeAccessingKeychain() throws {
        let backend = StubKeychain()
        XCTAssertThrowsError(
            try Keychain<SampleValue>(
                service: " ", account: "test", accessGroup: "group.test", keychain: backend
            )
        )
        XCTAssertThrowsError(
            try Keychain<SampleValue>(
                service: "test", account: "", accessGroup: "group.test", keychain: backend
            )
        )
        XCTAssertThrowsError(
            try Keychain<SampleValue>(
                service: "test", account: "test", accessGroup: " ", keychain: backend
            )
        )
        XCTAssertTrue(backend.operations.isEmpty)
    }

    private func makeStore(_ backend: StubKeychain) throws -> Keychain<SampleValue> {
        try Keychain(
            service: "test.service",
            account: "test.account",
            accessGroup: "group.test",
            keychain: backend
        )
    }
}

private struct SampleValue: Codable, Equatable {

    let name: String
    let count: Int
}

private struct FailingValue: Codable {

    func encode(to encoder: Encoder) throws {
        throw EncodingError.invalidValue(
            self,
            EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Test failure")
        )
    }
}

private final class StubKeychain: KeychainProcessing {

    var readResult: (OSStatus, AnyObject?) = (errSecItemNotFound, nil)
    var updateResults: [OSStatus] = []
    var addResult = errSecSuccess
    var deleteResult = errSecSuccess
    var operations: [String] = []
    var queries: [[String: Any]] = []
    var addedItem: [String: Any]?
    var updatedAttributes: [String: Any]?

    func copyMatching(_ query: [String: Any]) -> (OSStatus, AnyObject?) {
        operations.append("read")
        queries.append(query)
        return readResult
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        operations.append("add")
        addedItem = attributes
        return addResult
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        operations.append("update")
        queries.append(query)
        updatedAttributes = attributes
        return updateResults.isEmpty ? errSecItemNotFound : updateResults.removeFirst()
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        operations.append("delete")
        queries.append(query)
        return deleteResult
    }
}
