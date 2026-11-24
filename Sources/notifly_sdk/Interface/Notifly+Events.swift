import Combine
import FirebaseCore
import FirebaseMessaging
import Foundation
import UIKit

/// Tracks events and manages in-app message listeners.
@available(iOSApplicationExtension, unavailable)
@objc public extension Notifly {

    /// Queues a custom event for tracking and in-app campaign evaluation.
    ///
    /// Call after initialization. Event processing runs through the SDK's asynchronous
    /// worker and may trigger an in-app message. Returning does not acknowledge server
    /// delivery; initialization or serialization failures are logged internally.
    ///
    /// - Parameters:
    ///   - eventName: The custom event name identifying the action being tracked.
    ///   - eventParams: Optional event attributes using values supported by
    ///     `NotiflyAnyCodable`. The default, `nil`, supplies no custom attributes.
    ///   - segmentationEventParamKeys: Optional attribute names attached to the tracking
    ///     payload for event-count segmentation. Supply keys from `eventParams`; `nil`
    ///     uses no segmentation keys. Local segmented counters currently use the first key.
    ///
    /// ```swift
    /// Notifly.trackEvent(
    ///     eventName: "product_viewed",
    ///     eventParams: ["product_id": "sku-123"],
    ///     segmentationEventParamKeys: ["product_id"]
    /// )
    /// ```
    static func trackEvent(
        eventName: String,
        eventParams: [String: Any]? = nil,
        segmentationEventParamKeys: [String]? = nil
    ) {
        guard let main = try? main else {
            Logger.error(
                "Notifly is not initialized. Please call Notifly.initialize before calling Notifly.trackEvent."
            )
            return
        }
        main.trackingManager.track(
            eventName: eventName,
            eventParams: eventParams,
            isInternal: false,
            segmentationEventParamKeys: segmentationEventParamKeys
        )
    }

    /// Disables the SDK's in-app messaging channel for the current process.
    ///
    /// This method sets the in-memory disable flag immediately and can be called before
    /// initialization. There is no corresponding public enable method; initializing
    /// again does not reset the flag. Push notification and event-tracking APIs remain
    /// separate from this channel setting.
    ///
    /// - Note: This method does not explicitly dismiss an already visible message or
    ///   cancel an already scheduled presentation.
    static func disableInAppMessage() {
        Notifly.inAppMessageDisabled = true
        Logger.info("In App Message Channel is disabled.")
    }

    /// Adds a listener for in-app message display and interaction events.
    ///
    /// Call after initialization; earlier calls are ignored. Listeners are retained by
    /// the current SDK instance until removed or that instance is replaced. Registering
    /// the same closure more than once creates multiple listener entries.
    ///
    /// - Parameter listener: The escaping closure receiving the event name and optional
    ///   event attributes described by `InAppMessageEventListener`.
    /// - Important: Listener callbacks run synchronously on the event producer's thread,
    ///   without a separate queue hop. Keep them short and avoid mutating registrations
    ///   during dispatch. Use a weak capture when the listener would otherwise retain
    ///   its owner for the lifetime of the SDK instance.
    static func addInAppMessageEventListener(listener: @escaping InAppMessageEventListener) {
        guard let main = try? main else { return }
        main.inAppMessageManager.addEventListener(listener)
    }

    /// Removes every in-app message listener from the current SDK instance.
    ///
    /// Removal is synchronous and affects future event dispatches. A callback already
    /// executing is not cancelled. Calling before initialization has no effect; calling
    /// repeatedly after initialization leaves the listener collection empty.
    ///
    /// - Note: This method removes all registrations. The SDK does not expose a public
    ///   operation for removing only one listener.
    static func removeAllInAppMessageEventListener() {
        guard let main = try? main else { return }
        main.inAppMessageManager.removeAllEventListeners()
    }
}
