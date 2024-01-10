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
    var campaignData: CampaignData = .init(inAppMessageCampaigns: [])
    var userData: UserData = .init(data: [:])
    var eventData: EventData = .init(eventCounts: [:])

    private var requestSyncStateCancellables = Set<AnyCancellable>()
    private var _syncStateFinishedPub: AnyPublisher<Void, Error>?
    private(set) var syncStateFinishedPub: AnyPublisher<Void, Error>? {
        get {
            if let pub = syncStateFinishedPubishers.last as? AnyPublisher<Void, Error> {
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
            _syncStateFinishedPub = newValue
        }
    }

    var syncStateFinishedPromise: Future<Void, Error>.Promise? {
        return lockPromises.last
    }

    var syncStateFinishedPubishers: [AnyPublisher<Void, Error>] = []
    var lockPromises: [Future<Void, Error>.Promise] = []
    var processSyncStateTimeout: DispatchWorkItem?

    init(disabled: Bool) {
        if disabled {
            syncStateFinishedPromise?(.success(()))
        }
    }

    /* manage sync state finished pub */
    func lock() -> Int {
        let lockId = lockPromises.count
        Logger.error("LOCK \(lockId)")
        let newSyncStateFinishedPub = Future { [weak self] promise in
            self?.lockPromises.append(promise)
            self?.handleTimeout(lockId: lockId)
        }.eraseToAnyPublisher()
        syncStateFinishedPubishers.append(newSyncStateFinishedPub)
        return lockId
    }

    private func unlock(lockId: Int, _ error: NotiflyError? = nil) {
        guard let promise = lockPromises[safe: lockId] else {
            return
        }
        if let err = error {
            promise(.failure(err))
        } else {
            promise(.success(()))
        }
    }

    private func handleTimeout(lockId: Int) {
        let newTask = DispatchWorkItem {
            self.unlock(lockId: lockId)
        }
        processSyncStateTimeout = newTask
        DispatchQueue.main.asyncAfter(deadline: .now() + UserStateConstant.syncStateLockTimeout, execute: newTask)
    }

    /* sync state */
    func syncState(postProcessConfig: PostProcessConfigForSyncState) {
        guard let notifly = (try? Notifly.main) else {
            return
        }

        guard !Notifly.inAppMessageDisabled else {
            for index in 0 ..< lockPromises.count {
                unlock(lockId: index)
            }

            return
        }
        let external = notifly.userManager.externalUserID
        guard let projectId = notifly.projectId as String?,
              let notiflyUserID = (try? notifly.userManager.getNotiflyUserID()),
              let notiflyDeviceID = AppHelper.getNotiflyDeviceID()
        else {
            Logger.error("Fail to sync user state because Notifly is not initalized yet.")
            return
        }

        let lockId = lock()
        
        var parentPub: AnyPublisher<Void, Error>
        if let lastPub = try? self.syncStateFinishedPub {
            parentPub = lastPub
        } else {
            parentPub = Just(()).setFailureType(to: Error.self).eraseToAnyPublisher()
        }
        
        parentPub.tryMap { _ in
            NotiflyAPI().requestSyncState(projectId: projectId, notiflyUserID: notiflyUserID, notiflyDeviceID: notiflyDeviceID)
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
                            let newUserData = UserData(data: userData)
                            if postProcessConfig.merge, let previousUserData = self?.userData as? UserData {
                                self?.userData = UserData.merge(p1: newUserData, p2: previousUserData)
                            } else {
                                self?.userData = newUserData
                            }

                            if postProcessConfig.clear {
                                self?.userData.clearUserData()
                            }
                        }

                        if let eicData = decodedData["eventIntermediateCountsData"] as? [[String: Any]] {
                            self?.constructEventIntermediateCountsData(eicData: eicData, postProcessConfig: postProcessConfig)
                        }

                        if let campaignData = decodedData["campaignData"] as? [[String: Any]] {
                            self?.constructCampaignData(campaignData: campaignData)
                        }
                    }
                    Logger.info("Sync State Completed.")
                    self?.unlock(lockId: lockId)
                })
                .store(in: &self.requestSyncStateCancellables)
        }
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
            var eicID = name + InAppMessageConstant.idSeparator + dt + InAppMessageConstant.idSeparator
            if eventParams.count > 0,
               let key = eventParams.keys.first,
               let value = eventParams.values.first
            {
                eicID += key + InAppMessageConstant.idSeparator + String(describing: value)
            } else {
                eicID += InAppMessageConstant.idSeparator
            }

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

            let message = Message(htmlURL: htmlURL, modalProperties: modalProperties)

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

            var campaignStart: Int
            if let starts = campaignDict["starts"] as? [Int] {
                campaignStart = starts[0]
            } else {
                campaignStart = 0
            }
            let delay = campaignDict["delay"] as? Int
            let campaignEnd = campaignDict["end"] as? Int
            let segmentInfo = NotiflySegmentation.SegmentInfo(segmentInfoDict: segmentInfoDict)
            let lastUpdatedTimestamp = (campaignDict["last_updated_timestamp"] as? Int) ?? 0

            return Campaign(id: id, channel: channel, segmentType: segmentType, message: message, segmentInfo: segmentInfo, triggeringEvent: triggeringEvent, campaignStart: campaignStart, campaignEnd: campaignEnd, delay: delay, status: campaignStatus, testing: testing, whitelist: whitelist,
                            lastUpdatedTimestamp: lastUpdatedTimestamp, reEligibleCondition: reEligibleCondition)
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
