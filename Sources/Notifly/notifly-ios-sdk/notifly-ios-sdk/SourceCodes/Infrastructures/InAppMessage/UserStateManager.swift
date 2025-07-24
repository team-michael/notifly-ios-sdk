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
    private var campaignDataAccessQueue = DispatchQueue(
        label: "com.yourapp.userStateManager.campaignDataAccessQueue"
    )
    private var userDataAccessQueue = DispatchQueue(
        label: "com.yourapp.userStateManager.userDataAccessQueue"
    )
    private var eventDataAccessQueue = DispatchQueue(
        label: "com.yourapp.userStateManager.eventDataAccessQueue"
    )

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

    /* sync state from notifly server */
    func syncState(
        postProcessConfig: PostProcessConfigForSyncState,
        handleExternalUserIdMismatch: Bool = false,
        completion: @escaping () -> Void
    ) {
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

        let syncStateTask = NotiflyAPI().requestSyncState(
            projectId: projectId,
            notiflyUserID: notiflyUserID,
            notiflyDeviceID: notiflyDeviceID
        )
        .sink(
            receiveCompletion: { syncStateCompletion in
                if case let .failure(error) = syncStateCompletion {
                    Logger.error("Fail to sync user state: " + error.localizedDescription)
                }
            },
            receiveValue: { [weak self] jsonString in
                var deviceExternalUserID: String? = nil

                if let userState = NotiflyAnyCodable.parseJsonString(jsonString) {
                    if let rawUserData = userState["userData"] as? [String: Any] {
                        self?.constructUserData(
                            rawUserData: rawUserData,
                            postProcessConfig: postProcessConfig
                        )

                        deviceExternalUserID = rawUserData["device_external_user_id"] as? String
                        if let id = deviceExternalUserID, id.isEmpty {
                            deviceExternalUserID = nil
                        }
                    }

                    if let rawEventData = userState["eventIntermediateCountsData"]
                        as? [[String: Any]]
                    {
                        self?.constructEventData(
                            rawEventData: rawEventData,
                            postProcessConfig: postProcessConfig
                        )
                    }

                    if let rawCampaignData = userState["campaignData"] as? [[String: Any]] {
                        self?.constructCampaignData(rawCampaignData: rawCampaignData)
                    }
                }

                // DB의 디바이스-유저 매핑 정보와 SDK에 저장된 유저 정보가 다른 경우
                // DB를 Source of Truth로 하여 SDK의 external_user_id를 DB 값으로 변경
                if handleExternalUserIdMismatch, let notifly = try? Notifly.main {
                    let sdkExternalUserID = notifly.userManager.externalUserID

                    if self?.shouldHandleExternalUserIdMismatch(
                        sdkExternalUserID: sdkExternalUserID,
                        deviceExternalUserID: deviceExternalUserID
                    ) == true {
                        // SDK의 external_user_id를 DB 값으로 변경
                        notifly.userManager.changeExternalUserId(newValue: deviceExternalUserID)

                        notifly.inAppMessageManager.userStateManager.syncState(
                            postProcessConfig: PostProcessConfigForSyncState(
                                merge: false,
                                clear: false
                            )
                        ) {
                            completion()
                        }
                        return
                    }
                }

                Logger.info("Sync State Completed.")
                self?.owner = notiflyUserID
                completion()
            }
        )

        guard let main = try? Notifly.main, syncStateTask != nil else {
            Logger.error("Fail to sync user state: Notifly is not initialized")
            completion()
            return
        }
        main.storeCancellable(cancellable: syncStateTask)
    }

    /* post-process of sync state */
    private func constructUserData(
        rawUserData: [String: Any],
        postProcessConfig: PostProcessConfigForSyncState
    ) {
        var newUserData = UserData(data: rawUserData)
        if postProcessConfig.merge, let previousUserData = userData as? UserData {
            newUserData = UserData.merge(p1: previousUserData, p2: newUserData)
        }
        if postProcessConfig.clear {
            newUserData.clear()
        }
        userData = newUserData
    }

    private func constructEventData(
        rawEventData: [[String: Any]],
        postProcessConfig: PostProcessConfigForSyncState
    ) {
        let existing = postProcessConfig.merge ? eventData : EventData(from: [[:]])
        let new =
            !rawEventData.isEmpty && !postProcessConfig.clear
            ? EventData(from: rawEventData) : EventData(from: [[:]])
        eventData = EventData.merge(p1: existing, p2: new)
    }

    private func constructCampaignData(rawCampaignData: [[String: Any]]) {
        campaignData = CampaignData(from: rawCampaignData)
    }

    /* update client state */
    func incrementEic(
        eventName: String,
        eventParams: [String: Any]?,
        segmentationEventParamKeys: [String]?
    ) {
        let dt = NotiflyHelper.getCurrentDate()
        let eicID = EventIntermediateCount.generateId(
            eventName: eventName,
            eventParams: eventParams,
            segmentationEventParamKeys: segmentationEventParamKeys,
            dt: dt
        )
        if eventData.eventCounts[eicID] == nil {
            eventData.eventCounts[eicID] = EventIntermediateCount(
                name: eventName,
                dt: dt,
                count: 0,
                eventParams: eventParams ?? [:]
            )
        }
        eventData.eventCounts[eicID]?.addCount(count: 1)
    }

    private func shouldHandleExternalUserIdMismatch(
        sdkExternalUserID: String?,
        deviceExternalUserID: String?
    ) -> Bool {
        // SDK가 null인 경우는 앱 재설치 등으로 허용되는 상황이므로 핸들링하지 않음
        if sdkExternalUserID == nil {
            return false
        }
        // DB가 null인 경우는 다양한 원인(쿼리 에러, 디바이스 미저장 등)으로 인해 실제 값이 null이 아닐 가능성이 있어 핸들링하지 않음
        if deviceExternalUserID == nil {
            return false
        }
        // 두 값이 같은 경우는 정상적인 상황
        if sdkExternalUserID == deviceExternalUserID {
            return false
        }
        return true
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
            Logger.error(
                "Fail to update client-side user state (user campaign hidden until): owner mismatch"
            )
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

extension Array {
    fileprivate subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
