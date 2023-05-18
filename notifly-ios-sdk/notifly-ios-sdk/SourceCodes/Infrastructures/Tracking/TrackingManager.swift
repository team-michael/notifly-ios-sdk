
import Combine
import Foundation
import UIKit

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

    private let projectID: String
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Lifecycle

    init(projectID: String) {
        self.projectID = projectID

        // Collect the events from the `eventPublisher` queue at specified interval and fire the event.
        eventRequestPayloadPublisher = eventPublisher
            .collect(.byTimeOrCount(RunLoop.current, .seconds(trackingFiringInterval), maxTrackingRecordsPerRequest))
            .map { records in
                TrackingEvent(records: records)
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
                name: TrackingConstant.Internal.sessionStartEventName,
                params: [
                    "type": "session_start_type",
                    "notif_auth_status": authStatus,
                ]
            )
        }
    }

    func trackInternalEvent(name: String, params: [String: Any]?) {
        return track(eventName: name,
                     isInternal: true,
                     params: params,
                     segmentationEventParamKeys: nil)
    }

    func track(eventName: String,
               isInternal: Bool,
               params: [String: Any]?,
               segmentationEventParamKeys: [String]?)
    {
        createTrackingRecord(name: eventName,
                             isInternal: isInternal,
                             eventParams: params,
                             segmentationEventParamKeys: segmentationEventParamKeys)
            .sink(receiveCompletion: { completion in
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

    func createTrackingRecord(name: String,
                              isInternal: Bool,
                              eventParams: [String: Any]?,
                              segmentationEventParamKeys: [String]?) -> AnyPublisher<TrackingRecord, Error>
    {
        if let pub = Notifly.main.notificationsManager.apnDeviceTokenPub {
            return pub.tryMap { pushToken in
                let userID = try Notifly.main.userManager.getNotiflyUserID()
                let data = try TrackingData(id: UUID().uuidString,
                                            name: name,
                                            notifly_user_id: userID,
                                            external_user_id: Notifly.main.userManager.externalUserID,
                                            time: Int(Date().timeIntervalSince1970),
                                            notifly_device_id: UUID(name: AppHelper.getDeviceID(),
                                                                    namespace: TrackingConstant.HashNamespace.deviceID).notiflyStyleString,
                                            external_device_id: AppHelper.getDeviceID(),
                                            device_token: pushToken,
                                            is_internal_event: isInternal,
                                            segmentation_event_param_keys: segmentationEventParamKeys,
                                            project_id: Notifly.main.projectID,
                                            platform: AppHelper.getDevicePlatform(),
                                            os_version: AppHelper.getiOSVersion(),
                                            app_version: AppHelper.getAppVersion(),
                                            sdk_version: AppHelper.getSDKVersion(),
                                            sdk_type: AppHelper.getSDKType(),
                                            event_params: AppHelper.makeJsonCodable(eventParams))
                let stringfiedData = String(data: try! JSONEncoder().encode(data), encoding: .utf8)!
                return TrackingRecord(partitionKey: userID, data: stringfiedData)
            }.eraseToAnyPublisher()
        } else {
            return Fail(outputType: TrackingRecord.self, failure: NotiflyError.unexpectedNil("APN Device Token is nil"))
                .eraseToAnyPublisher()
        }
    }

    // MARK: - Private Methods

    private func setup() {
        // Submit the tracking event to API & log result.
        eventRequestPayloadPublisher
            .flatMap(NotiflyAPI().trackEvent)
            .catch { error in
                Just("Tracking Event request failed with error: \(error)")
            }
            .sink { [weak self] result in
                self?.eventRequestResponsePublisher.send(result)
            }
            .store(in: &cancellables)

        internalEventRequestPayloadPublisher
            .flatMap(NotiflyAPI().trackEvent)
            .catch { error in
                Just("Tracking Event request failed with error: \(error)")
            }
            .sink { [weak self] result in
                self?.internalEventRequestResponsePublisher.send(result)
            }
            .store(in: &cancellables)
    }
}
