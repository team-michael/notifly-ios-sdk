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
    var owner: String?
    var campaignData: CampaignData = .init(inAppMessageCampaigns: [])
    var userData: UserData = .init(data: [:])
    var eventData: EventData = .init(eventCounts: [:])

    private var _waitSyncStateFinishedPub: AnyPublisher<Void, Error>?
    private(set) var waitSyncStateFinishedPub: AnyPublisher<Void, Error> {
        get {
            if let pub = waitSyncStateCompletedPubs.last as? AnyPublisher<Void, Error> {
                return pub
                    .catch { _ in
                        Just(()).setFailureType(to: Error.self)
                    }
                    .eraseToAnyPublisher()
            } else {
                return Just(()).setFailureType(to: Error.self).eraseToAnyPublisher()
            }
        }
        set {
            _waitSyncStateFinishedPub = newValue
        }
    }

    var waitParentUnlockPub: AnyPublisher<Void, Never> {
        let lockCount = waitSyncStateCompletedPubs.count
        let parentLockIndex = lockCount > 1 ? lockCount - 2 : -1
        let parentLock = lockCount > 1 ? waitSyncStateCompletedPubs[parentLockIndex] : nil
        return Future<Void, Never> { promise in
            if let parentLock = parentLock {
                parentLock
                    .sink(receiveCompletion: { _ in
                        promise(.success(()))
                    }, receiveValue: { _ in })
                    .store(in: &Notifly.cancellables)
            } else {
                promise(.success(()))
            }
        }.eraseToAnyPublisher()
    }

    var waitSyncStateCompletedPubs: [AnyPublisher<Void, Error>] = []
    var resolveLockPromises: [Future<Void, Error>.Promise] = []
    var tasksHandlingTimeout: [DispatchWorkItem] = []

    init(owner: String?) {
        self.owner = owner
    }

    /* manage sync state finished pub */
    func lock() -> Int {
        let lockId = resolveLockPromises.count
        let waitSyncStateCompletedPub = Future { [weak self] promise in
            self?.resolveLockPromises.append(promise)
        }.eraseToAnyPublisher()
        waitSyncStateCompletedPubs.append(waitSyncStateCompletedPub)
        Logger.error("LOCK \(lockId)")
        return lockId
    }

    private func unlock(lockId: Int, _ error: NotiflyError? = nil) {
        guard let promise = resolveLockPromises[safe: lockId] else {
            return
        }
        if let err = error {
            promise(.failure(err))
        } else {
            promise(.success(()))
        }

        if let task = tasksHandlingTimeout[safe: lockId] {
            task.cancel()
        }
        Logger.error("UNLOCK \(lockId)")
    }

    private func setTimeoutForLock(lockId: Int) {
        let newTask = DispatchWorkItem {
            self.unlock(lockId: lockId)
        }
        tasksHandlingTimeout.append(newTask)
        DispatchQueue.main.asyncAfter(deadline: .now() + UserStateConstant.syncStateLockTimeout, execute: newTask)
    }

    /* sync state */
    func syncState(postProcessConfig: PostProcessConfigForSyncState) {
        guard let notifly = (try? Notifly.main) else {
            return
        }

        guard !Notifly.inAppMessageDisabled else {
            for index in 0 ..< resolveLockPromises.count {
                unlock(lockId: index)
            }
            return
        }

        guard let projectId = notifly.projectId as String?,
              let notiflyUserID = (try? notifly.userManager.getNotiflyUserID()),
              let notiflyDeviceID = AppHelper.getNotiflyDeviceID()
        else {
            Logger.error("Fail to sync user state because Notifly is not initalized yet.")
            return
        }

        let lockId = lock()
        waitParentUnlockPub
            .sink(receiveCompletion: { _ in
                      self.fetchUserCampaignContext(projectId: projectId, notiflyUserID: notiflyUserID, notiflyDeviceID: notiflyDeviceID, lockId: lockId, postProcessConfig: postProcessConfig)
                  },
                  receiveValue: { _ in })
            .store(in: &Notifly.cancellables)
    }

    private func fetchUserCampaignContext(projectId: String, notiflyUserID: String, notiflyDeviceID: String, lockId: Int, postProcessConfig: PostProcessConfigForSyncState) {
        setTimeoutForLock(lockId: lockId)
        return NotiflyAPI().requestSyncState(projectId: projectId, notiflyUserID: notiflyUserID, notiflyDeviceID: notiflyDeviceID)
            .sink(receiveCompletion: { completion in
                if case let .failure(error) = completion {
                    Logger.error("Fail to sync user state: " + error.localizedDescription)
                    self.unlock(lockId: lockId, NotiflyError.unexpectedNil(error.localizedDescription))
                }

            }, receiveValue: { [weak self] jsonString in
                if let jsonData = jsonString.data(using: .utf8),
                   let decodedData = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any]
                {
                    if let userData = decodedData["userData"] as? [String: Any] {
                        self?.constructUserData(userData: userData, postProcessConfig: postProcessConfig)
                    }

                    if let eicData = decodedData["eventIntermediateCountsData"] as? [[String: Any]] {
                        self?.constructEventIntermediateCountsData(eicData: eicData, postProcessConfig: postProcessConfig)
                    }

                    if let campaignData = decodedData["campaignData"] as? [[String: Any]] {
                        self?.constructCampaignData(campaignData: campaignData)
                    }
                }

                let userDataAsEventParams = self?.userData.destruct()
                try? Notifly.main.trackingManager.trackSyncStateCompletedInternalEvent(properties: userDataAsEventParams)
                Logger.info("Sync State Completed. \(lockId)")
                self?.owner = notiflyUserID
                self?.unlock(lockId: lockId)
            })
            .store(in: &Notifly.cancellables)
    }

    /* post-process of sync state */
    private func constructUserData(userData: [String: Any], postProcessConfig: PostProcessConfigForSyncState)
    {
        let newUserData = UserData(data: userData)
        if postProcessConfig.merge, let previousUserData = self.userData as? UserData {
            self.userData = UserData.merge(p1: newUserData, p2: previousUserData)
        } else {
            self.userData = newUserData
        }

        if postProcessConfig.clear {
            self.userData.clearUserData()
        }
    }

    private func constructEventIntermediateCountsData(eicData: [[String: Any]], postProcessConfig: PostProcessConfigForSyncState) {
        guard eicData.count > 0 else {
            if !postProcessConfig.merge {
                eventData.eventCounts = [:]
            }
            return
        }

        if postProcessConfig.clear {
            eventData.eventCounts = [:]
        }

        eventData.eventCounts = eicData.compactMap { eic -> (String, EventIntermediateCount)? in
            guard let name = eic["name"] as? String,
                  let dt = eic["dt"] as? String,
                  let count = eic["count"] as? Int,
                  let eventParams = eic["event_params"] as? [String: Any]
            else {
                return nil
            }

            var segmentationEventParamKeys: [String]?
            if let key = eventParams.first?.key as? String {
                segmentationEventParamKeys = [key]
            }

            let eicID = constructEicId(eventName: name, eventParams: eventParams, segmentationEventParamKeys: segmentationEventParamKeys, dt: dt)

            return (eicID, EventIntermediateCount(name: name, dt: dt, count: count, eventParams: eventParams))
        }.compactMap { $0 }.reduce(into: postProcessConfig.merge ? eventData.eventCounts : [:]) { $0[$1.0] = $1.1 }
    }

    private func constructCampaignData(campaignData: [[String: Any]]) {
        self.campaignData.inAppMessageCampaigns = campaignData.compactMap { campaignDict -> Campaign? in
            guard let id = campaignDict["id"] as? String,
                  let testing = campaignDict["testing"] as? Bool,
                  let triggeringEvent = campaignDict["triggering_event"] as? String,
                  let statusRawValue = campaignDict["status"] as? Int,
                  statusRawValue == 1,
                  let campaignStatus = CampaignStatus(rawValue: statusRawValue),
                  let messageDict = campaignDict["message"] as? [String: Any],
                  let htmlURL = messageDict["html_url"] as? String,
                  let modalPropertiesDict = messageDict["modal_properties"] as? [String: Any],
                  let modalProperties = ModalProperties(properties: modalPropertiesDict),
                  let segmentInfoDict = campaignDict["segment_info"] as? [String: Any],
                  let channel = campaignDict["channel"] as? String,
                  let segmentType = campaignDict["segment_type"] as? String,
                  channel == InAppMessageConstant.inAppMessageChannel,
                  segmentType == NotiflySegmentation.SegmentationType.conditionBased.rawValue
            else {
                return nil
            }

            let triggeringEventFilters: TriggeringEventFilters? = try? TriggeringEventFilters(from: campaignDict["triggering_event_filters"])

            var campaignStart: Int
            if let starts = campaignDict["starts"] as? [Int] {
                campaignStart = starts[0]
            } else {
                campaignStart = 0
            }
            let delay = campaignDict["delay"] as? Int
            let campaignEnd = campaignDict["end"] as? Int

            var reEligibleCondition: NotiflyReEligibleConditionEnum.ReEligibleCondition?
            if let rawReEligibleCondition = campaignDict["re_eligible_condition"] as? [String: Any],
               let reEligibleConditionData = NotiflyReEligibleConditionEnum.ReEligibleCondition(data: rawReEligibleCondition)
            {
                reEligibleCondition = reEligibleConditionData
            }

            var whitelist: [String]?
            if testing == true {
                guard let whiteList = campaignDict["whitelist"] as? [String] else {
                    return nil
                }
                whitelist = whiteList
            } else {
                whitelist = nil
            }

            let segmentInfo = NotiflySegmentation.SegmentInfo(segmentInfoDict: segmentInfoDict)

            let message = Message(htmlURL: htmlURL, modalProperties: modalProperties)

            let lastUpdatedTimestamp = (campaignDict["last_updated_timestamp"] as? Int) ?? 0

            return Campaign(id: id, channel: channel, segmentType: segmentType, message: message, segmentInfo: segmentInfo, triggeringEvent: triggeringEvent, triggeringEventFilters: triggeringEventFilters, campaignStart: campaignStart, campaignEnd: campaignEnd, delay: delay, status: campaignStatus, testing: testing, whitelist: whitelist,
                            lastUpdatedTimestamp: lastUpdatedTimestamp, reEligibleCondition: reEligibleCondition)
        }
    }

    func incrementEic(eventName: String, eventParams: [String: Any]?, segmentationEventParamKeys: [String]?) {
        let dt = NotiflyHelper.getCurrentDate()
        let eicID = constructEicId(eventName: eventName, eventParams: eventParams, segmentationEventParamKeys: segmentationEventParamKeys, dt: dt)
        if var eicToUpdate = eventData.eventCounts[eicID] {
            eicToUpdate.count += 1
            eventData.eventCounts[eicID] = eicToUpdate
        } else {
            eventData.eventCounts[eicID] = EventIntermediateCount(name: eventName, dt: dt, count: 1, eventParams: eventParams ?? [:])
        }
    }

    func constructEicId(eventName: String, eventParams: [String: Any]?, segmentationEventParamKeys: [String]?, dt: String) -> String {
        var eicID = eventName + InAppMessageConstant.eicIdSeparator + dt
        guard let selectedEventParams = selectEventParams(eventParams: eventParams, segmentationEventParamKeys: segmentationEventParamKeys),
              let (selectedKey, selectedValue) = selectedEventParams.first
        else {
            return eicID + String(repeating: InAppMessageConstant.eicIdSeparator, count: 2)
        }

        return eicID + InAppMessageConstant.eicIdSeparator + selectedKey + InAppMessageConstant.eicIdSeparator + selectedValue
    }

    private func selectEventParams(eventParams: [String: Any]?, segmentationEventParamKeys: [String]?) -> [String: String]? {
        if let segmentationEventParamKeys = segmentationEventParamKeys,
           let eventParams = eventParams,
           segmentationEventParamKeys.count > 0,
           eventParams.count > 0
        {
            let keyField = segmentationEventParamKeys[0]
            if let value = eventParams[keyField] as? String {
                return [keyField: value]
            }
        }
        return nil
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
