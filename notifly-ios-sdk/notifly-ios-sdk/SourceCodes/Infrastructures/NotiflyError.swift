import Foundation

enum NotiflyError: Error {
    case notImplemented
    case notAuthorized
    case notInitialized
    case promiseTimeout
    case deviceTokenError
    case unexpectedNil(_ descripiton: String)
}
