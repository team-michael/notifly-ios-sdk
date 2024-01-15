import Foundation

enum NotiflyError: Error {
    case notImplemented
    case notAuthorized
    case notInitialized
    case promiseTimeout
    case deviceTokenError
    case invalidPayload
    case nilValueReceived
    case unexpectedNil(_ descripiton: String)
}
