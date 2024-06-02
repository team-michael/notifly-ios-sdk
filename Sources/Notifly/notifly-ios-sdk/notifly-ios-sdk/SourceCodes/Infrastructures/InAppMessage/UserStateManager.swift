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
    var campaignData: CampaignData = .init(from: [])
    var userData: UserData = .init(data: [:])
    var eventData: EventData = .init(eventCounts: [:])

    private let userStateAccessQueue = DispatchQueue(label: "com.notifly.userStateAccessQueue")
    private let userDataAccessQueue = DispatchQueue(label: "com.notifly.userDataAccessQueue")
    private let eventDataAccessQueue = DispatchQueue(label: "com.notifly.eventDataAccessQueue")
    private let campaignDataAccessQueue = DispatchQueue(label: "com.notifly.campaignDataAccessQueue")

    private var _waitSyncStateFinishedPub: AnyPublisher<Void, Error>?
    private(set) var waitSyncStateFinishedPub: AnyPublisher<Void, Error> {
        get {
            return userStateAccessQueue.sync {
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
        }
        set {
            userStateAccessQueue.async {
                self._waitSyncStateFinishedPub = newValue
            }
        }
    }

    var waitParentUnlockPub: AnyPublisher<Void, Never> {
        let lockCount = waitSyncStateCompletedPubs.count
        let parentLockIndex = lockCount > 1 ? lockCount - 2 : -1
        let parentLock = lockCount > 1 ? waitSyncStateCompletedPubs[parentLockIndex] : nil
        return Future<Void, Never> { promise in
            if let parentLock = parentLock {
                let task = parentLock
                    .sink(receiveCompletion: { _ in
                        promise(.success(()))
                    }, receiveValue: { _ in })
                guard let main = try? Notifly.main, task != nil else {
                    return
                }
                main.storeCancellable(cancellable: task)

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
        return userStateAccessQueue.sync {
            let lockId = resolveLockPromises.count
            let waitSyncStateCompletedPub = Future { [weak self] promise in
                self?.resolveLockPromises.append(promise)
            }.eraseToAnyPublisher()
            waitSyncStateCompletedPubs.append(waitSyncStateCompletedPub)
            return lockId
        }
    }

    private func unlock(lockId: Int, _ error: NotiflyError? = nil) {
        userStateAccessQueue.async {
            guard let promise = self.resolveLockPromises[safe: lockId] else {
                return
            }
            if let err = error {
                promise(.failure(err))
            } else {
                promise(.success(()))
            }

            if let task = self.tasksHandlingTimeout[safe: lockId] {
                task.cancel()
            }
        }
    }

    private func setTimeoutForLock(lockId: Int) {
        userStateAccessQueue.async {
            let newTask = DispatchWorkItem {
                self.unlock(lockId: lockId)
            }
            self.tasksHandlingTimeout.append(newTask)
            DispatchQueue.main.asyncAfter(deadline: .now() + UserStateConstant.syncStateLockTimeout, execute: newTask)
        }
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

        let externalUserID = notifly.userManager.externalUserID
        let lockId = lock()
        let task = waitParentUnlockPub
            .sink(receiveCompletion: { _ in
                      self.fetchUserCampaignContext(projectId: projectId, notiflyUserID: notiflyUserID, notiflyDeviceID: notiflyDeviceID, externalUserID: externalUserID, lockId: lockId, postProcessConfig: postProcessConfig)
                  },
                  receiveValue: { _ in })
        notifly.storeCancellable(cancellable: task)
    }

    private func fetchUserCampaignContext(projectId: String, notiflyUserID: String, notiflyDeviceID: String, externalUserID: String?, lockId: Int, postProcessConfig: PostProcessConfigForSyncState) {
        setTimeoutForLock(lockId: lockId)
        let task = NotiflyAPI().requestSyncState(projectId: projectId, notiflyUserID: notiflyUserID, notiflyDeviceID: notiflyDeviceID)
            .sink(receiveCompletion: { completion in
                if case let .failure(error) = completion {
                    Logger.error("Fail to sync user state: " + error.localizedDescription)
                    self.unlock(lockId: lockId, NotiflyError.unexpectedNil(error.localizedDescription))
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

                let userDataAsEventParams = self?.userData.destruct()
                Logger.info("Sync State Completed.")
                self?.owner = notiflyUserID
                try? Notifly.main.trackingManager.trackSyncStateCompletedInternalEvent(userID: notiflyUserID, externalUserID: externalUserID, properties: userDataAsEventParams)

                self?.unlock(lockId: lockId)
            })
        guard let main = try? Notifly.main, task != nil else {
            Logger.error("Fail to sync user state: Notifly is not initialized")
            unlock(lockId: lockId, NotiflyError.notInitialized)
            return
        }
        main.storeCancellable(cancellable: task)
    }

    /* post-process of sync state */
    private func constructUserData(rawUserData: [String: Any], postProcessConfig: PostProcessConfigForSyncState) {
        userDataAccessQueue.async {
            let newUserData = UserData(data: rawUserData)
            if postProcessConfig.merge, let previousUserData = self.userData as? UserData {
                self.userData = UserData.merge(p1: previousUserData, p2: newUserData)
            } else {
                self.userData = newUserData
            }

            if postProcessConfig.clear {
                self.userData.clear()
            }
        }
    }

    private func constructEventData(rawEventData: [[String: Any]], postProcessConfig: PostProcessConfigForSyncState) {
        eventDataAccessQueue.async {
            let existing = postProcessConfig.merge ? self.eventData : EventData(from: [[:]])
            let new = rawEventData.count > 0 && !postProcessConfig.clear ? EventData(from: rawEventData) : EventData(from: [[:]])
            self.eventData = EventData.merge(p1: existing, p2: new)
        }
    }

    private func constructCampaignData(rawCampaignData: [[String: Any]]) {
        campaignDataAccessQueue.async {
            self.campaignData = CampaignData(from: rawCampaignData)
        }
    }

    /* update client state */
    func incrementEic(eventName: String, eventParams: [String: Any]?, segmentationEventParamKeys: [String]?) {
        eventDataAccessQueue.async {
            let dt = NotiflyHelper.getCurrentDate()
            let eicID = EventIntermediateCount.generateId(eventName: eventName, eventParams: eventParams, segmentationEventParamKeys: segmentationEventParamKeys, dt: dt)
            if var eic = self.eventData.eventCounts[eicID] {
                eic.addCount(count: 1)
                self.eventData.eventCounts[eicID] = eic
            } else {
                self.eventData.eventCounts[eicID] = EventIntermediateCount(name: eventName, dt: dt, count: 1, eventParams: eventParams ?? [:])
            }
        }
    }

    func getUserData(userID: String) -> UserData? {
        return userDataAccessQueue.sync { [weak self] in
            guard let self = self else {
                return UserData(data: [:])
            }
            guard self.owner == userID else {
                return UserData(data: [:])
            }
            return self.userData ?? UserData(data: [:])
        }
    }

    func updateUserData(userID: String?, properties: [String: Any]) {
        userDataAccessQueue.async { [weak self] in
            guard let self = self else {
                return
            }
            guard self.owner == userID else {
                return
            }
            self.userData.userProperties.merge(properties) { _, new in new }
        }
    }

    func clear() {
        userDataAccessQueue.async {
            self.userData.clear()
        }
        eventDataAccessQueue.async {
            self.eventData.clear()
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
