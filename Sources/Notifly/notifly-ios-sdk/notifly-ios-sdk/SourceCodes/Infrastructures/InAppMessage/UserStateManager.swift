//
//  UserStateManager.swift
//  notifly-ios-sdk
//
//  Created by 김대성 on 2024/01/10.
//

import Combine
import Dispatch
import Foundation

@available(iOSApplicationExtension, unavailable)
class UserStateManager {
    private var _owner: String?
    private let ownerAccessQueue = DispatchQueue(label: "com.yourapp.userStateManager.ownerQueue")
    var owner: String? {
        get {
            ownerAccessQueue.sync {
                _owner
            }
        }
        set {
            ownerAccessQueue.sync {
                _owner = newValue
            }
        }
    }

    private var _campaignData: CampaignData = .init(from: [])
    private var _userData: UserData = .init(data: [:])
    private var _eventData: EventData = .init(eventCounts: [:])
    private var campaignDataAccessQueue = DispatchQueue(label: "com.yourapp.userStateManager.campaignDataAccessQueue")
    private var userDataAccessQueue = DispatchQueue(label: "com.yourapp.userStateManager.userDataAccessQueue")
    private var eventDataAccessQueue = DispatchQueue(label: "com.yourapp.userStateManager.eventDataAccessQueue")

    var campaignData: CampaignData {
        get {
            campaignDataAccessQueue.sync {
                _campaignData
            }
        }
        set {
            campaignDataAccessQueue.sync {
                _campaignData = newValue
            }
        }
    }

    var userData: UserData {
        get {
            userDataAccessQueue.sync {
                _userData
            }
        }
        set {
            userDataAccessQueue.sync {
                _userData = newValue
            }
        }
    }

    var eventData: EventData {
        get {
            eventDataAccessQueue.sync {
                _eventData
            }
        }
        set {
            eventDataAccessQueue.sync {
                _eventData = newValue
            }
        }
    }

    init(owner: String?) {
        _owner = owner
    }

    /* change owner of current state */
    func changeOwner(userID: String?) {
        guard !Notifly.inAppMessageDisabled else {
            return
        }

        guard let userID = userID else {
            return
        }
        owner = userID
    }

    /* sync state from notifly server */
    func syncState(postProcessConfig: PostProcessConfigForSyncState,
                   completion: @escaping () -> Void)
    {
        guard let notifly = (try? Notifly.main) else {
            completion()
            return
        }

        guard !Notifly.inAppMessageDisabled else {
            completion()
            return
        }

        guard let projectId = notifly.projectId as String?,
              let notiflyUserID = (try? notifly.userManager.getNotiflyUserID()),
              let notiflyDeviceID = AppHelper.getNotiflyDeviceID()
        else {
            Logger.error("Fail to sync user state because Notifly is not initalized yet.")
            completion()
            return
        }

        let externalUserID = notifly.userManager.externalUserID
        let syncStateTask = NotiflyAPI().requestSyncState(projectId: projectId, notiflyUserID: notiflyUserID, notiflyDeviceID: notiflyDeviceID)
            .sink(receiveCompletion: { syncStateCompletion in
                if case let .failure(error) = syncStateCompletion {
                    Logger.error("Fail to sync user state: " + error.localizedDescription)
                }
            }, receiveValue: { [weak self] jsonString in
                if let jsonData = jsonString.data(using: .utf8),
                   let decodedData = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any]
                {
                    if let rawUserData = decodedData["userData"] as? [String: Any] {
                        self?.constructUserData(rawUserData: rawUserData, postProcessConfig: postProcessConfig)
                    }

                    if let rawEventData = decodedData["eventIntermediateCountsData"] as? [[String: Any]] {
                        self?.constructEventData(rawEventData: rawEventData, postProcessConfig: postProcessConfig)
                    }

                    if let rawCampaignData = decodedData["campaignData"] as? [[String: Any]] {
                        self?.constructCampaignData(rawCampaignData: rawCampaignData)
                    }
                }
                Logger.info("Sync State Completed.")
                self?.owner = notiflyUserID
                let fetchedUserData = self?.userData.destruct()
                completion()
                try? Notifly.main.trackingManager.trackSyncStateCompletedInternalEvent(userID: notiflyUserID, externalUserID: externalUserID, properties: fetchedUserData)
            })

        guard let main = try? Notifly.main, syncStateTask != nil else {
            Logger.error("Fail to sync user state: Notifly is not initialized")
            completion()
            return
        }
        main.storeCancellable(cancellable: syncStateTask)
    }

    /* post-process of sync state */
    private func constructUserData(rawUserData: [String: Any], postProcessConfig: PostProcessConfigForSyncState) {
        var newUserData = UserData(data: rawUserData)
        if postProcessConfig.merge, let previousUserData = userData as? UserData {
            newUserData = UserData.merge(p1: previousUserData, p2: newUserData)
        }
        if postProcessConfig.clear {
            newUserData.clear()
        }
        userData = newUserData
    }

    private func constructEventData(rawEventData: [[String: Any]], postProcessConfig: PostProcessConfigForSyncState) {
        let existing = postProcessConfig.merge ? eventData : EventData(from: [[:]])
        let new = !rawEventData.isEmpty && !postProcessConfig.clear ? EventData(from: rawEventData) : EventData(from: [[:]])
        eventData = EventData.merge(p1: existing, p2: new)
    }

    private func constructCampaignData(rawCampaignData: [[String: Any]]) {
        campaignData = CampaignData(from: rawCampaignData)
    }

    /* update client state */
    func incrementEic(eventName: String, eventParams: [String: Any]?, segmentationEventParamKeys: [String]?) {
        let dt = NotiflyHelper.getCurrentDate()
        let eicID = EventIntermediateCount.generateId(eventName: eventName, eventParams: eventParams, segmentationEventParamKeys: segmentationEventParamKeys, dt: dt)
        if eventData.eventCounts[eicID] == nil {
            eventData.eventCounts[eicID] = EventIntermediateCount(name: eventName, dt: dt, count: 0, eventParams: eventParams ?? [:])
        }
        eventData.eventCounts[eicID]?.addCount(count: 1)
    }

    func getUserData(userID: String) -> UserData? {
        guard owner == userID else {
            return UserData(data: [:])
        }
        return userData
    }

    func updateUserData(userID: String?, properties: [String: Any]) {
        guard owner == userID else {
            return
        }
        userData.userProperties.merge(properties) { _, new in new }
    }

    func updateUserCampaignHiddenUntilData(
        userID: String?,
        hideUntilData: [String: Int]
    ) {
        guard userID == owner else {
            Logger.error("Fail to update client-side user state (user campaign hidden until): owner mismatch")
            return
        }

        userData.campaignHiddenUntil.merge(hideUntilData) { _, new in new }
    }

    func getInAppMessageCampaigns() -> [Campaign] {
        return campaignData.inAppMessageCampaigns
    }

    func clear() {
        userData.clear()
        eventData.clear()
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
