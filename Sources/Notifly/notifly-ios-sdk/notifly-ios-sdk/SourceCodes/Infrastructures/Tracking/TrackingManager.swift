import Combine
import Foundation
import UIKit

@available(iOSApplicationExtension, unavailable)
class TrackingManager {
    // var trackingFiringInterval: TimeInterval = 5
    // var maxTrackingRecordsPerRequest: Int = 10

    let eventRequestPayloadPublisher: AnyPublisher<TrackingEvent, Never>
    let internalEventRequestPayloadPublisher: AnyPublisher<TrackingEvent, Never>
    let eventRequestResponsePublisher = PassthroughSubject<String, Never>()
    let internalEventRequestResponsePublisher = PassthroughSubject<String, Never>()
    private let eventPublisher = PassthroughSubject<TrackingRecord, Never>()
    private let internalEventPublisher = PassthroughSubject<TrackingRecord, Never>()

    private let projectId: String

    private var cancellables = Set<AnyCancellable>()
    private let cancellablesAccessQueue = DispatchQueue(
        label: "TrackingManagerCancellablesAccessQueue")

    init(projectId: String) {
        self.projectId = projectId
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

    func trackSessionStartInternalEvent() {
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
        Notifly.asyncWorker.addTask(lockAcquired: lockAcquired) { [weak self] in
            guard let notifly = try? Notifly.main else {
                Notifly.asyncWorker.unlock()
                Logger.error("Fail to track Event. \(eventName)")
                return
            }
            let userID = (try? notifly.userManager.getNotiflyUserID()) ?? ""
            let externalUserID = notifly.userManager.externalUserID
            let currentTimestamp = AppHelper.getCurrentTimestamp()
            let trackingTask = self?.handleTrackEvent(
                eventName: eventName,
                eventParams: eventParams,
                isInternal: isInternal,
                segmentationEventParamKeys: segmentationEventParamKeys,
                currentTimestamp: currentTimestamp,
                userID: userID,
                externalUserID: externalUserID
            ).sink(
                receiveCompletion: { completion in
                    if case let .failure(error) = completion {
                        Logger.error("Failed to Track Event \(eventName). Error: \(error)")
                    }
                },
                receiveValue: { [weak self] record in
                    if isInternal {
                        self?.internalEventPublisher.send(record)
                    } else {
                        self?.eventPublisher.send(record)
                    }
                    Notifly.asyncWorker.unlock()
                })
            if let task = trackingTask {
                self?.storeCanellables(cancellable: task)
            }
        }
    }

    private func handleTrackEvent(
        eventName: String, eventParams: [String: Any]?, isInternal: Bool,
        segmentationEventParamKeys: [String]?, currentTimestamp: Int, userID: String,
        externalUserID: String?
    ) -> AnyPublisher<TrackingRecord, Error> {

        let trackingEventName = NotiflyHelper.getEventName(
            event: eventName, isInternalEvent: isInternal)
        try? Notifly.main.inAppMessageManager.userStateManager.incrementEic(
            eventName: trackingEventName, eventParams: eventParams,
            segmentationEventParamKeys: segmentationEventParamKeys
        )
        try? Notifly.main.inAppMessageManager.mayTriggerInAppMessage(
            eventName: trackingEventName, eventParams: eventParams,
            segmentationEventParamKeys: segmentationEventParamKeys
        )

        return createTrackingRecord(
            eventName: eventName,
            eventParams: eventParams,
            isInternal: isInternal,
            segmentationEventParamKeys: segmentationEventParamKeys,
            currentTimestamp: currentTimestamp, userID: userID, externalUserID: externalUserID)
    }

    func createTrackingRecord(
        eventName: String,
        eventParams: [String: Any]?,
        isInternal: Bool,
        segmentationEventParamKeys: [String]?,
        currentTimestamp: Int, userID: String, externalUserID: String?
    ) -> AnyPublisher<TrackingRecord, Error> {
        guard let notifly = try? Notifly.main else {
            return Fail(outputType: TrackingRecord.self, failure: NotiflyError.notInitialized)
                .eraseToAnyPublisher()
        }
        guard let deviceTokenPub = notifly.notificationsManager.deviceTokenPub else {
            return Fail(
                outputType: TrackingRecord.self,
                failure: NotiflyError.unexpectedNil("APN Device Token is nil")
            )
            .eraseToAnyPublisher()
        }

        guard let notiflyDeviceID = AppHelper.getNotiflyDeviceID(),
            let deviceID = AppHelper.getDeviceID(),
            let appVersion = AppHelper.getAppVersion()
        else {
            Logger.error("Failed to track event: " + eventName)
            return Fail(
                outputType: TrackingRecord.self,
                failure: NotiflyError.unexpectedNil("Device data is invalid.")
            )
            .eraseToAnyPublisher()
        }

        return deviceTokenPub.tryMap { pushToken in
            if let data = TrackingData(
                id: UUID().uuidString,
                name: eventName,
                notifly_user_id: userID,
                external_user_id: externalUserID,
                time: currentTimestamp,
                notifly_device_id: notiflyDeviceID,
                external_device_id: deviceID,
                device_token: pushToken,
                is_internal_event: isInternal,
                segmentation_event_param_keys: segmentationEventParamKeys,
                project_id: notifly.projectId,
                platform: AppHelper.getDevicePlatform(),
                os_version: AppHelper.getiOSVersion(),
                app_version: appVersion,
                sdk_version: NotiflyHelper.getSdkVersion(),
                sdk_type: NotiflyHelper.getSdkType(),
                event_params: AnyCodable.makeJsonCodable(eventParams)) as? TrackingData,
                let stringfiedData = try? String(data: JSONEncoder().encode(data), encoding: .utf8)
            {
                return TrackingRecord(partitionKey: userID, data: stringfiedData)
            } else {
                Logger.error("Failed to track event: " + eventName)
                throw NotiflyError.unexpectedNil("Failed to create tracking data")
            }
        }
        .catch { _ in
            Fail(
                outputType: TrackingRecord.self,
                failure: NotiflyError.unexpectedNil("TrackingRecord Data is invalid")
            )
            .eraseToAnyPublisher()
        }
        .eraseToAnyPublisher()
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
