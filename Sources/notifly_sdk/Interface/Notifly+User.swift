import Combine
import FirebaseCore
import FirebaseMessaging
import Foundation
import UIKit

/// Manages Notifly user identity and profile properties.
@available(iOSApplicationExtension, unavailable)
@objc public extension Notifly {

    /// Queues an update to the application's external user identifier.
    ///
    /// Call after initialization when the signed-in user changes. Passing `nil` removes
    /// the external identity and returns to anonymous identification. An empty string is
    /// rejected, and setting the current identifier again does not change the identity.
    /// User-state synchronization and the server-sent event restart happen asynchronously.
    ///
    /// - Parameter userId: The application's nonempty user identifier, or `nil` to clear
    ///   the association. The default is `nil`.
    /// - Note: Returning does not mean the queued identity transition has finished.
    ///   An immediate call to `getNotiflyUserId()` may still observe the previous user.
    ///
    /// ```swift
    /// Notifly.setUserId(userId: "customer-123")
    /// // Clear the external identity when the user signs out.
    /// Notifly.setUserId()
    /// ```
    static func setUserId(userId: String? = nil) {
        guard let main = try? main else {
            if userId != nil {
                Logger.error(
                    "Notifly is not initialized. Please call Notifly.initialize before calling Notifly.setUserId."
                )
            }
            else {
                Logger.error(
                    "Notifly is not initialized. Please call Notifly.initialize before calling Notifly.setUserId to unregister user id."
                )
            }
            return
        }
        main.userManager.setExternalUserId(userId)
        Notifly.asyncWorker.addTask { finishTask in
            main.restartSSE()
            finishTask()
        }
    }

    /// Returns the SDK's current Notifly user identifier.
    ///
    /// The identifier is generated or retrieved locally and is distinct from the
    /// application's external user ID. This call does not wait for queued identity
    /// changes or make a server request to confirm the user.
    /// A cache miss reads Keychain synchronously. Storage access or an in-progress
    /// identity write can delay the calling thread, including the main thread.
    ///
    /// - Returns: The current lowercase Notifly identifier, or `nil` if the SDK has not
    ///   been initialized or the identifier cannot be generated.
    static func getNotiflyUserId() -> String? {
        guard let main = try? main else {
            Logger.error(
                "Notifly is not initialized. Please call Notifly.initialize before calling Notifly.getNotiflyUserId."
            )
            return nil
        }
        return try? main.userManager.getNotiflyUserID()
    }

    /// Queues the supplied properties for the current user.
    ///
    /// Call after initialization. An empty dictionary is ignored. Custom keys support
    /// ASCII letters, digits, and underscores; invalid keys produce a warning without
    /// blocking the call. Built-in and official integration keys are exempt. An invalid
    /// built-in time-zone value is omitted while the remaining properties are processed.
    ///
    /// When in-app messaging is enabled and local user properties are available, a call
    /// is skipped if every supplied key/value matches local state and less than five
    /// seconds have elapsed since the last non-identity property send attempt. The
    /// window starts at that attempt, not a server acknowledgement. Skipped calls do not
    /// extend it, and identity changes reset it. First calls, changed values, and calls
    /// at or after five seconds follow the normal asynchronous send flow. Server-side
    /// changes may not yet be reflected in the local state used for comparison.
    ///
    /// - Parameter userProperties: Property names mapped to values supported by
    ///   `NotiflyAnyCodable`, including strings, booleans, numbers, arrays, and dictionaries.
    /// - Note: Returning does not confirm that the server has accepted the update.
    ///
    /// ```swift
    /// Notifly.setUserProperties(userProperties: [
    ///     "membership": "premium",
    ///     "purchase_count": 3
    /// ])
    /// ```
    static func setUserProperties(userProperties: [String: Any]) {
        guard let main = try? main else {
            Logger.error(
                "Notifly is not initialized. Please call Notifly.initialize before calling Notifly.setUserProperties."
            )
            return
        }

        if userProperties.isEmpty {
            Logger.info(
                "Empty dictionary provided for setting user properties. Ignoring this call."
            )
            return
        }

        if let timezone = userProperties[TrackingConstant.InternalUserPropertyKey.timezone]
            as? String
        {
            if !TimezoneUtil.isValidTimezoneId(timezone) {
                Logger.info(
                    "Invalid timezone ID \(timezone). Please check your timezone ID. Omitting timezone property."
                )
                var newUserProperties = userProperties
                newUserProperties.removeValue(
                    forKey: TrackingConstant.InternalUserPropertyKey.timezone
                )
                return setUserProperties(userProperties: newUserProperties)
            }
        }

        if let warning = UserPropertyKeyWarning.message(for: Array(userProperties.keys)) {
            Logger.warning(warning)
        }

        main.userManager.setUserProperties(userProperties: userProperties)
    }

    /// Queues the user's phone-number property for update.
    ///
    /// This convenience method forwards to `setUserProperties(userProperties:)` and
    /// inherits its initialization requirements, asynchronous processing, and duplicate
    /// suppression. The supplied string is not validated or normalized.
    ///
    /// - Parameter phoneNumber: The phone-number string to send for the current user.
    static func setPhoneNumber(_ phoneNumber: String) {
        setUserProperties(userProperties: [
            TrackingConstant.InternalUserPropertyKey.phoneNumber: phoneNumber
        ])
    }

    /// Queues the user's email-address property for update.
    ///
    /// This convenience method forwards to `setUserProperties(userProperties:)` and
    /// inherits its initialization requirements, asynchronous processing, and duplicate
    /// suppression. The supplied string is not validated or normalized.
    ///
    /// - Parameter email: The email-address string to send for the current user.
    static func setEmail(_ email: String) {
        setUserProperties(userProperties: [
            TrackingConstant.InternalUserPropertyKey.email: email
        ])
    }

    /// Queues a supported time-zone identifier as a user property.
    ///
    /// The identifier must appear in `TimeZone.knownTimeZoneIdentifiers`. Invalid values
    /// are logged and ignored. Valid values are forwarded to
    /// `setUserProperties(userProperties:)` and follow its asynchronous update behavior.
    ///
    /// - Parameter timezone: A recognized time-zone identifier, such as `Asia/Seoul`.
    static func setTimezone(_ timezone: String) {
        if !TimezoneUtil.isValidTimezoneId(timezone) {
            Logger.info("Invalid timezone ID \(timezone). Please check your timezone ID.")
            return
        }
        setUserProperties(userProperties: [
            TrackingConstant.InternalUserPropertyKey.timezone: timezone
        ])
    }
}
