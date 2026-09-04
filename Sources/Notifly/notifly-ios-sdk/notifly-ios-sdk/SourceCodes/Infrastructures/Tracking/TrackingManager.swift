import Combine
import Foundation
import UIKit

@available(iOSApplicationExtension, unavailable)
class TrackingManager {
    struct RuntimeContext {
        let userID: String
        let externalUserID: String?
        let deviceTokenProvider: () -> String?
        let processEvent: (String, [String: Any]?, [String]?) -> Void
    }

    struct Dependencies {
        let asyncWorker: NotiflyAsyncWorker
        let contextProvider: () -> RuntimeContext?

        static var live: Dependencies {
            Dependencies(
                asyncWorker: Notifly.asyncWorker,
                contextProvider: {
                    guard let notifly = try? Notifly.main else {
                        return nil
                    }

                    return RuntimeContext(
                        userID: (try? notifly.userManager.getNotiflyUserID()) ?? "",
                        externalUserID: notifly.userManager.externalUserID,
                        deviceTokenProvider: {
                            notifly.notificationsManager.latestFCMToken
                        },
                        processEvent: { eventName, eventParams, segmentationEventParamKeys in
                            try? notifly.inAppMessageManager.userStateManager.incrementEic(
                                eventName: eventName,
                                eventParams: eventParams,
                                segmentationEventParamKeys: segmentationEventParamKeys
                            )
                            try? notifly.inAppMessageManager.mayTriggerInAppMessage(
                                eventName: eventName,
                                eventParams: eventParams,
                                segmentationEventParamKeys: segmentationEventParamKeys
                            )
                        }
                    )
                }
            )
        }
    }

    // var trackingFiringInterval: TimeInterval = 5
    // var maxTrackingRecordsPerRequest: Int = 10

    let eventRequestPayloadPublisher: AnyPublisher<TrackingEvent, Never>
    let internalEventRequestPayloadPublisher: AnyPublisher<TrackingEvent, Never>
    let eventRequestResponsePublisher = PassthroughSubject<String, Never>()
    let internalEventRequestResponsePublisher = PassthroughSubject<String, Never>()
    private let eventPublisher = PassthroughSubject<TrackingRecord, Never>()
    private let internalEventPublisher = PassthroughSubject<TrackingRecord, Never>()

    private let projectId: String
    private let dependencies: Dependencies

    private var cancellables = Set<AnyCancellable>()
    private let cancellablesAccessQueue = DispatchQueue(
        label: "TrackingManagerCancellablesAccessQueue")

    init(projectId: String, dependencies: Dependencies = .live) {
        self.projectId = projectId
        self.dependencies = dependencies
        // Collect the events from the `eventPublisher` queue at specified interval and fire the event.
        eventRequestPayloadPublisher =
            eventPublisher
            // .collect(.byTimeOrCount(DispatchQueue.global(), .seconds(trackingFiringInterval), maxTrackingRecordsPerRequest))
            .map { record in
                TrackingEvent(records: [record])
            }
            .eraseToAnyPublisher()

        internalEventRequestPayloadPublisher =
            internalEventPublisher
            .map { record in
                TrackingEvent(records: [record])
            }
            .eraseToAnyPublisher()

        setup()
    }

    private func storeCanellables(cancellable: AnyCancellable) {
        cancellablesAccessQueue.async {
            cancellable.store(in: &self.cancellables)
        }
    }

    static func canTrackSessionStart(applicationState: UIApplication.State) -> Bool {
        applicationState == .active
    }

    private static func canTrackSessionStartInCurrentApplicationState() -> Bool {
        if Thread.isMainThread {
            return canTrackSessionStart(applicationState: UIApplication.shared.applicationState)
        }

        return DispatchQueue.main.sync {
            canTrackSessionStart(applicationState: UIApplication.shared.applicationState)
        }
    }

    func trackSessionStartInternalEvent() {
        guard Self.canTrackSessionStartInCurrentApplicationState() else {
            return
        }

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            var authStatus = 0
            switch settings.authorizationStatus {
            case .authorized:
                authStatus = 1
            case .denied:
                authStatus = 0
            case .notDetermined:
                authStatus = -1
            case .provisional:
                authStatus = 2
            case .ephemeral:
                authStatus = 3
            @unknown default:
                authStatus = 0
            }

            self.trackInternalEvent(
                eventName: TrackingConstant.Internal.sessionStartEventName,
                eventParams: [
                    "type": "session_start_type",
                    "notif_auth_status": authStatus,
                    "in_app_message_disabled": Notifly.inAppMessageDisabled,
                    "timezone": TimezoneUtil.getCurrentTimezoneId()
                ],
                lockAcquired: true
            )
        }
    }

    func trackSetDevicePropertiesInternalEvent(properties: [String: Any]) {
        trackInternalEvent(
            eventName: TrackingConstant.Internal.setDevicePropertiesEventName,
            eventParams: properties
        )
    }

    func trackPushClickInternalEvent(pushData: [AnyHashable: Any], clickStatus: String) {
        if let campaignID = pushData["campaign_id"] as? String {
            let messageID = pushData["notifly_message_id"] ?? "" as String
            if let pushClickEventParams = [
                "type": "message_event",
                "channel": "push-notification",
                "campaign_id": campaignID,
                "notifly_message_id": messageID,
                "click_status": clickStatus
            ] as? [String: Any] {
                trackInternalEvent(
                    eventName: TrackingConstant.Internal.pushClickEventName,
                    eventParams: pushClickEventParams)
            }
        }
    }

    func trackInternalEvent(
        eventName: String, eventParams: [String: Any]?,
        lockAcquired: Bool = false
    ) {
        return track(
            eventName: eventName,
            eventParams: eventParams,
            isInternal: true,
            segmentationEventParamKeys: nil,
            lockAcquired: lockAcquired)
    }

    func track(
        eventName: String,
        eventParams: [String: Any]?,
        isInternal: Bool,
        segmentationEventParamKeys: [String]?,
        lockAcquired: Bool = false
    ) {
        dependencies.asyncWorker.addTask(lockAcquired: lockAcquired) { [weak self] finishTask in
            guard let self = self, let context = self.dependencies.contextProvider() else {
                Logger.error("Fail to track Event. \(eventName)")
                finishTask()
                return
            }
            let currentTimestamp = AppHelper.getCurrentTimestamp()

            let trackingEventName = NotiflyHelper.getEventName(
                event: eventName, isInternalEvent: isInternal)
            context.processEvent(
                trackingEventName,
                eventParams,
                segmentationEventParamKeys
            )

            defer { finishTask() }

            guard let record = self.createTrackingRecord(
                eventName: eventName,
                eventParams: eventParams,
                isInternal: isInternal,
                segmentationEventParamKeys: segmentationEventParamKeys,
                currentTimestamp: currentTimestamp,
                userID: context.userID,
                externalUserID: context.externalUserID,
                deviceToken: context.deviceTokenProvider()
            ) else {
                Logger.error(
                    "Failed to Track Event \(eventName). TrackingRecord Data is invalid"
                )
                return
            }

            if isInternal {
                self.internalEventPublisher.send(record)
            } else {
                self.eventPublisher.send(record)
            }
        }
    }

    func createTrackingRecord(
        eventName: String,
        eventParams: [String: Any]?,
        isInternal: Bool,
        segmentationEventParamKeys: [String]?,
        currentTimestamp: Int,
        userID: String,
        externalUserID: String?,
        deviceToken: String?
    ) -> TrackingRecord? {
        guard let notiflyDeviceID = AppHelper.getNotiflyDeviceID(),
            let deviceID = AppHelper.getDeviceID(),
            let appVersion = AppHelper.getAppVersion()
        else {
            Logger.error("Failed to track event: " + eventName)
            return nil
        }

        let data = TrackingData(
            id: UUID().uuidString,
            name: eventName,
            notifly_user_id: userID,
            external_user_id: externalUserID,
            time: currentTimestamp,
            notifly_device_id: notiflyDeviceID,
            external_device_id: deviceID,
            device_token: deviceToken,
            is_internal_event: isInternal,
            segmentation_event_param_keys: segmentationEventParamKeys,
            project_id: projectId,
            platform: AppHelper.getDevicePlatform(),
            os_version: AppHelper.getiOSVersion(),
            app_version: appVersion,
            sdk_version: NotiflyHelper.getSdkVersion(),
            sdk_type: NotiflyHelper.getSdkType(),
            event_params: try? NotiflyAnyCodable(eventParams)
        )

        guard
            let encodedData = try? JSONEncoder().encode(data),
            let stringifiedData = String(data: encodedData, encoding: .utf8)
        else {
            Logger.error("Failed to track event: " + eventName)
            return nil
        }

        return TrackingRecord(partitionKey: notiflyDeviceID, data: stringifiedData)
    }

    private func setup() {
        // Submit the tracking event to API & log result.
        let firingCustomEventTask =
            eventRequestPayloadPublisher
            .flatMap { payload in
                NotiflyAPI().trackEvent(payload)
                    .catch { error in
                        Just("Tracking Event request failed with error: \(error)")
                    }
            }
            .sink { [weak self] result in
                self?.eventRequestResponsePublisher.send(result)
            }

        let firingInternalEventTask =
            internalEventRequestPayloadPublisher
            .flatMap { payload in
                NotiflyAPI().trackEvent(payload)
                    .catch { error in
                        Just("Tracking Event request failed with error: \(error)")
                    }
            }
            .sink { [weak self] result in
                self?.internalEventRequestResponsePublisher.send(result)
            }

        if let firingCustomEventTask = firingCustomEventTask as? AnyCancellable {
            storeCanellables(cancellable: firingCustomEventTask)
        }
        if let firingInternalEventTask = firingInternalEventTask as? AnyCancellable {
            storeCanellables(cancellable: firingInternalEventTask)
        }
    }
}
