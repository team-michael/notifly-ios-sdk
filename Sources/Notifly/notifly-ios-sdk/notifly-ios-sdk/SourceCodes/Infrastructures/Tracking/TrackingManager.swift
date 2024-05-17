
import Combine
import Foundation
import UIKit

@available(iOSApplicationExtension, unavailable)
class TrackingManager {
    // MARK: Constants

    /// Timeinverval between firing tracking events to the API.
    var trackingFiringInterval: TimeInterval = 5
    /// Max Tracking Records per request. If this number is reached, the tracking event will fire even if it didn't past the time internal.
    var maxTrackingRecordsPerRequest: Int = 10

    // MARK: Properties

    let eventRequestPayloadPublisher: AnyPublisher<TrackingEvent, Never>
    let internalEventRequestPayloadPublisher: AnyPublisher<TrackingEvent, Never>
    let eventRequestResponsePublisher = PassthroughSubject<String, Never>()
    let internalEventRequestResponsePublisher = PassthroughSubject<String, Never>()
    private let eventPublisher = PassthroughSubject<TrackingRecord, Never>()
    private let internalEventPublisher = PassthroughSubject<TrackingRecord, Never>()

    private let projectId: String
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Lifecycle

    init(projectId: String) {
        self.projectId = projectId
        // Collect the events from the `eventPublisher` queue at specified interval and fire the event.
        eventRequestPayloadPublisher = eventPublisher
            // .collect(.byTimeOrCount(DispatchQueue.global(), .seconds(trackingFiringInterval), maxTrackingRecordsPerRequest))
            .map { record in
                TrackingEvent(records: [record])
            }
            .eraseToAnyPublisher()

        internalEventRequestPayloadPublisher = internalEventPublisher
            .map { record in
                TrackingEvent(records: [record])
            }
            .eraseToAnyPublisher()
        setup()
    }

    // MARK: Methods

    func trackSessionStartInternalEvent() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            var authStatus: Int = 0
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

            return self.trackInternalEvent(
                eventName: TrackingConstant.Internal.sessionStartEventName,
                eventParams: [
                    "type": "session_start_type",
                    "notif_auth_status": authStatus,
                    "in_app_message_disabled": Notifly.inAppMessageDisabled,
                ]
            )
        }
    }

    func trackSetDevicePropertiesInternalEvent(properties: [String: Any]) {
        return trackInternalEvent(
            eventName: TrackingConstant.Internal.setDevicePropertiesEventName,
            eventParams: properties
        )
    }

    func trackInternalEvent(eventName: String, eventParams: [String: Any]?, urgent: Bool = false) {
        return track(eventName: eventName,
                     eventParams: eventParams,
                     isInternal: true,
                     segmentationEventParamKeys: nil,
                     urgent: urgent)
    }

    func track(eventName: String,
               eventParams: [String: Any]?,
               isInternal: Bool,
               segmentationEventParamKeys: [String]?,
               urgent: Bool = false)
    {
        guard let notifly = try? Notifly.main else {
            Logger.error("Fail to track Event. \(eventName)")
            return
        }
        let userID = (try? notifly.userManager.getNotiflyUserID()) ?? ""
        
        let externalUserID = notifly.userManager.externalUserID
        let currentTimestamp = AppHelper.getCurrentTimestamp()
        
        var trackingTask: AnyPublisher<TrackingRecord, Error>?
        if urgent {
            trackingTask = handleTrackEvent(eventName: eventName, eventParams: eventParams, isInternal: isInternal, segmentationEventParamKeys: segmentationEventParamKeys, currentTimestamp: currentTimestamp, userID: userID, externalUserID: externalUserID)
        } else {
            trackingTask = Notifly.keepGoingPub.flatMap { _ in
                return self.handleTrackEvent(eventName: eventName, eventParams: eventParams, isInternal: isInternal, segmentationEventParamKeys: segmentationEventParamKeys, currentTimestamp: currentTimestamp, userID: userID, externalUserID: externalUserID)
            }.eraseToAnyPublisher()
        }
        trackingTask?.sink(receiveCompletion: { completion in
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
        })
        .store(in: &cancellables)
    }
                   
    
    private func handleTrackEvent(eventName: String, eventParams: [String: Any]?, isInternal: Bool, segmentationEventParamKeys: [String]?, currentTimestamp: Int, userID: String, externalUserID: String?) -> AnyPublisher<TrackingRecord, Error> {
        let trackingEventName = NotiflyHelper.getEventName(event: eventName, isInternalEvent: isInternal)
        try? Notifly.main.inAppMessageManager.updateEventData(userID:
                userID,
                eventName: trackingEventName, eventParams: eventParams, segmentationEventParamKeys: segmentationEventParamKeys)
            return createTrackingRecord(eventName: eventName,
                                             eventParams: eventParams,
                                             isInternal: isInternal,
                                             segmentationEventParamKeys: segmentationEventParamKeys,
                                             currentTimestamp: currentTimestamp, userID: userID, externalUserID: externalUserID)

    }

    func trackSyncStateCompletedInternalEvent(userID: String, externalUserID: String?, properties: [String: Any]?) {
        let currentTimestamp = AppHelper.getCurrentTimestamp()
        createTrackingRecord(eventName: TrackingConstant.Internal.syncStateCompletedEventName,
                             eventParams: properties,
                             isInternal: true,
                             segmentationEventParamKeys: nil,
                             currentTimestamp: currentTimestamp, userID: userID, externalUserID: externalUserID)
            .sink(receiveCompletion: { completion in
                      if case let .failure(error) = completion {
                          Logger.error("Failed to Track Event \(TrackingConstant.Internal.syncStateCompletedEventName). Error: \(error)")
                      }
                  },
                  receiveValue: { [weak self] record in
                      self?.internalEventPublisher.send(record)
                  })
            .store(in: &cancellables)
    }

    func createTrackingRecord(eventName: String,
                              eventParams: [String: Any]?,
                              isInternal: Bool,
                              segmentationEventParamKeys: [String]?,
                              currentTimestamp: Int, userID: String, externalUserID: String?) -> AnyPublisher<TrackingRecord, Error>
    {
        guard let notifly = try? Notifly.main else {
            return Fail(outputType: TrackingRecord.self, failure: NotiflyError.notInitialized)
                .eraseToAnyPublisher()
        }
        guard let deviceTokenPub = notifly.notificationsManager.deviceTokenPub else {
            return Fail(outputType: TrackingRecord.self, failure: NotiflyError.unexpectedNil("APN Device Token is nil"))
                .eraseToAnyPublisher()
        }

        guard let notiflyDeviceID = AppHelper.getNotiflyDeviceID(),
              let deviceID = AppHelper.getDeviceID(),
              let appVersion = AppHelper.getAppVersion()
        else {
            Logger.error("Failed to track event: " + eventName)
            return Fail(outputType: TrackingRecord.self, failure: NotiflyError.unexpectedNil("Device data is invalid."))
                .eraseToAnyPublisher()
        }

        return deviceTokenPub.tryMap { pushToken in
            if let data = TrackingData(id: UUID().uuidString,
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
                                       event_params: AppHelper.makeJsonCodable(eventParams)) as? TrackingData,
                let stringfiedData = try? String(data: JSONEncoder().encode(data), encoding: .utf8)

            {
                return TrackingRecord(partitionKey: userID, data: stringfiedData)
            } else {
                Logger.error("Failed to track event: " + eventName)
                throw NotiflyError.unexpectedNil("Failed to create tracking data")
            }
        }
        .catch { _ in
            Fail(outputType: TrackingRecord.self, failure: NotiflyError.unexpectedNil("TrackingRecord Data is invalid"))
                .eraseToAnyPublisher()
        }
        .eraseToAnyPublisher()
    }

    private func setup() {
        // Submit the tracking event to API & log result.
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
            .store(in: &cancellables)

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
            .store(in: &cancellables)
    }
}
