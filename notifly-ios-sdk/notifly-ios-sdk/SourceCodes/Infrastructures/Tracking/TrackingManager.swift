
import Foundation
import Combine
import UIKit

class TrackingManager {
    
    // MARK: Properties
    
    private let projectID: String
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Lifecycle
    
    init(projectID: String) {
        self.projectID = projectID
    }
    
    // MARK: Methods
    
    func trackInternalEventPub(name: String, params: [String: String]?) -> AnyPublisher<String, Error> {
        return track(eventName: name,
                     isInternal: true,
                     params: params,
                     segmentationEventParamKeys: nil)
    }
    
    func trackInternalEvent(name: String, params: [String: String]?) {
        let cancellable = trackInternalEventPub(name: name, params: params)
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    Logger.error("Internal Tracking Event \(name) failed with error: \(error)")
                case .finished:
                    Logger.info("Internal Tracking Event \(name) posted successfuly.")
                }
            },
            receiveValue: { _ in })
        cancellables.insert(cancellable)
    }
    
    func track(eventName: String,
               isInternal: Bool,
               params: [String: String]?,
               segmentationEventParamKeys: [String]?) -> AnyPublisher<String, Error> {
        let pub = createTrackingEvent(name: eventName,
                                      isInternal: isInternal,
                                      eventParams: params,
                                      segmentationEventParamKeys: segmentationEventParamKeys)
            .flatMap(NotiflyAPI().trackEvent)
            .eraseToAnyPublisher()
        
        Logger.info("Firing Tracking Event \(eventName)")
        return pub
    }
    
    func createTrackingEvent(name: String,
                             isInternal: Bool,
                             eventParams: [String: String]?,
                             segmentationEventParamKeys: [String]?) -> AnyPublisher<TrackingEvent, Error> {
        
        if let pub = Notifly.main.notificationsManager.apnDeviceTokenPub {
            return pub.tryMap { pushToken in
                TrackingEvent(id: UUID().uuidString,
                              name: name,
                              notifly_user_id: try Notifly.main.userManager.getNotiflyUserID(),
                              external_user_id: Notifly.main.userManager.externalUserID,
                              time: Int(Date().timeIntervalSince1970),
                              notifly_device_id: try AppHelper.getDeviceID(),
                              external_device_id: try AppHelper.getDeviceID(),
                              device_token: pushToken,
                              is_internal_event: isInternal,
                              segmentation_event_param_keys: segmentationEventParamKeys,
                              project_id: Notifly.main.projectID,
                              platform: AppHelper.getDevicePlatform(),
                              os_version: AppHelper.getiOSVersion(),
                              app_version: try AppHelper.getAppVersion(),
                              sdk_version: try AppHelper.getSDKVersion(),
                              event_params: eventParams)
            }.eraseToAnyPublisher()
        } else {
            return Fail(outputType: TrackingEvent.self, failure: NotiflyError.unexpectedNil("APN Device Token is nil"))
                .eraseToAnyPublisher()
        }
    }
}
