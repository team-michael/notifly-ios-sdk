//
//  InAppMessageManager.swift
//  notifly-ios-sdk
//
//  Created by 김대성 on 2023/06/12.
//

import Combine
import Dispatch
import Foundation
import UIKit

@available(iOSApplicationExtension, unavailable)
class InAppMessageManager {
    private var userData: UserData = .init(data: [:])
    private var campaignData: CampaignData = .init(inAppMessageCampaigns: [])
    private var eventData: EventData = .init(eventCounts: [:])
    private var requestSyncStateCancellables = Set<AnyCancellable>()
    private var _syncStateFinishedPub: AnyPublisher<Void, Error>?
    private(set) var syncStateFinishedPub: AnyPublisher<Void, Error>? {
        get {
            if let pub = _syncStateFinishedPub {
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

    var syncStateFinishedPromise: Future<Void, Error>.Promise?
    var processSyncStateTimeout: DispatchWorkItem?

    init(disabled: Bool) {
        lock()
        if disabled {
            syncStateFinishedPromise?(.success(()))
        }
    }

    private func lock() {
        syncStateFinishedPub = Future { [weak self] promise in
            self?.syncStateFinishedPromise = promise
            self?.handleTimeout()
        }.eraseToAnyPublisher()
    }

    private func unlock(_ error: NotiflyError? = nil) {
        guard let promise = syncStateFinishedPromise else {
            Logger.error("Sync state promise is not exist")
            return
        }
        if let err = error {
            promise(.failure(err))
        } else {
            promise(.success(()))
        }
        if let deadTask = processSyncStateTimeout {
            deadTask.cancel()
        }
    }

    private func handleTimeout() {
        if let deadTask = processSyncStateTimeout {
            deadTask.cancel()
        }
        let newTask = DispatchWorkItem {
            self.unlock(NotiflyError.promiseTimeout)
        }
        processSyncStateTimeout = newTask
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: newTask)
    }

    @available(iOSApplicationExtension, unavailable)
    static func present(_ vc: UIViewController, animated: Bool = false, completion: (() -> Void)?) -> Bool {
        guard let window = UIApplication.shared.windows.first(where: \.isKeyWindow),
              let topVC = window.topMostViewController,
              !(vc.isBeingPresented)
        else {
            Logger.error("Invalid status for presenting in-app-message.")
            return false
        }
        topVC.present(vc, animated: animated, completion: completion)
        return true
    }

    func syncState(postProcessConfig: PostProcessConfigForSyncState) {
        guard let notifly = (try? Notifly.main) else {
            return
        }

        guard !Notifly.inAppMessageDisabled else {
            unlock()
            return
        }

        guard let projectId = notifly.projectId as String?,
              let notiflyUserID = (try? notifly.userManager.getNotiflyUserID()),
              let notiflyDeviceID = AppHelper.getNotiflyDeviceID()
        else {
            Logger.error("Fail to sync user state because Notifly is not initalized yet.")
            return
        }
        lock()

        NotiflyAPI().requestSyncState(projectId: projectId, notiflyUserID: notiflyUserID, notiflyDeviceID: notiflyDeviceID)
            .sink(receiveCompletion: { completion in
                if case let .failure(error) = completion {
                    Logger.error("Fail to sync user state: " + error.localizedDescription)
                    self.unlock(NotiflyError.unexpectedNil(error.localizedDescription))
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
                self?.unlock()
            })
            .store(in: &requestSyncStateCancellables)
    }

    func updateUserProperties(properties: [String: Any]) {
        guard !Notifly.inAppMessageDisabled else {
            return
        }
        userData.userProperties.merge(properties) { _, new in new }
    }

    func updateEventData(eventName: String, eventParams: [String: Any]?, segmentationEventParamKeys: [String]?) {
        guard !Notifly.inAppMessageDisabled else {
            return
        }

        if var campaignsToTrigger = getCampaignsShouldBeTriggered(eventName: eventName, eventParams: eventParams)
        {
            campaignsToTrigger.sort(by: { $0.lastUpdatedTimestamp > $1.lastUpdatedTimestamp })
            for campaignToTrigger in campaignsToTrigger {
                if let notiflyInAppMessageData = prepareInAppMessageData(campaign: campaignToTrigger) {
                    showInAppMessage(notiflyInAppMessageData: notiflyInAppMessageData)
                }
            }
        }

        let dt = NotiflyHelper.getCurrentDate()
        var eicID = eventName + InAppMessageConstant.idSeparator + dt + InAppMessageConstant.idSeparator
        if let segmentationEventParamKeys = segmentationEventParamKeys,
           let eventParams = eventParams,
           segmentationEventParamKeys.count > 0,
           eventParams.count > 0
        {
            let keyField = segmentationEventParamKeys[0] // TODO: support multiple segmentationEventParamKey
            if let value = eventParams[keyField] as? String {
                eicID += keyField + InAppMessageConstant.idSeparator + String(describing: value)
                updateEventCountsInEventData(eicID: eicID, eventName: eventName, dt: dt, eventParams: [:])
                return
            }
        }
        eicID += InAppMessageConstant.idSeparator
        updateEventCountsInEventData(eicID: eicID, eventName: eventName, dt: dt, eventParams: [:])
    }

    private func updateEventCountsInEventData(eicID: String, eventName: String, dt: String, eventParams: [String: Any]?) {
        if var eicToUpdate = eventData.eventCounts[eicID] {
            eicToUpdate.count += 1
            eventData.eventCounts[eicID] = eicToUpdate
        } else {
            eventData.eventCounts[eicID] = EventIntermediateCount(name: eventName, dt: dt, count: 1, eventParams: eventParams ?? [:])
        }
    }

    /* method for showing in-app message */
    private func getCampaignsShouldBeTriggered(eventName: String, eventParams: [String: Any]?) -> [Campaign]? {
        let campaignsToTrigger = campaignData.inAppMessageCampaigns
            .filter { $0.triggeringEvent == eventName }
            .filter { isCampaignActive(campaign: $0) }
            .filter { !isBlacklistTemplate(templateName: $0.message.modalProperties.templateName) }
            .filter { SegmentationHelper.isEntityOfSegment(campaign: $0, eventParams: eventParams, userData: userData, eventData: eventData) }

        if campaignsToTrigger.count == 0 {
            return nil
        }
        return campaignsToTrigger
    }

    private func isCampaignActive(campaign: Campaign) -> Bool {
        let now = AppHelper.getCurrentTimestamp(unit: .second)
        let startTimestamp = campaign.campaignStart
        if let endTimestamp = campaign.campaignEnd {
            return now >= startTimestamp && now <= endTimestamp
        }
        return now >= startTimestamp
    }

    private func isBlacklistTemplate(templateName: String) -> Bool {
        let outdatedPropertyKeyForBlacklist = "hide_in_app_message_" + templateName
        let propertyKeyForBlacklist = "hide_in_app_message_until_" + templateName
        if let hide = userData.userProperties[outdatedPropertyKeyForBlacklist] as? Bool {
            return hide
        }
        let hideUntil = userData.userProperties[propertyKeyForBlacklist]
        if hideUntil == nil {
            return false
        }
        if let intHideUntil = hideUntil as? Int {
            if intHideUntil == -1 {
                return true
            }
            let now = AppHelper.getCurrentTimestamp(unit: .second)
            if now <= intHideUntil {
                return true
            } else {
                return false
            }
        }
        Logger.error("Invalid user hide_in_app_message property.")
        return true
    }

    private func isHiddenCampaign(campaignID: String) -> Bool {
        let now = AppHelper.getCurrentTimestamp(unit: .second)
        if let hideUntil = userData.campaignHiddenUntil[campaignID] {
            if hideUntil == -1 {
                return true
            }
            if hideUntil >= now {
                return true
            }
        }
        return false
    }

    func prepareInAppMessageData(campaign: Campaign) -> InAppMessageData? {
        let messageId = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let campaignId = campaign.id
        let urlString = campaign.message.htmlURL
        let modalProperties = campaign.message.modalProperties
        let delay = DispatchTimeInterval.seconds(campaign.delay ?? 0)
        let deadline = DispatchTime.now() + delay

        if let url = URL(string: urlString) {
            return InAppMessageData(notiflyMessageId: messageId, notiflyCampaignId: campaignId, modalProps: modalProperties, url: url, deadline: deadline, notiflyReEligibleCondition: campaign.reEligibleCondition)
        }
        return nil
    }

    private func showInAppMessage(notiflyInAppMessageData: InAppMessageData) {
        DispatchQueue.main.asyncAfter(deadline: notiflyInAppMessageData.deadline) {
            if let reEligibleCondition = notiflyInAppMessageData.notiflyReEligibleCondition {
                guard !self.isHiddenCampaign(campaignID: notiflyInAppMessageData.notiflyCampaignId) else {
                    return
                }
            }
            guard WebViewModalViewController.openedInAppMessageCount == 0 else {
                Logger.error("Already In App Message Opened. New In App Message Ignored.")
                return
            }
            WebViewModalViewController.openedInAppMessageCount = 1
            guard UIApplication.shared.applicationState == .active else {
                Logger.error("Due to being in a background state, in-app messages are being ignored.")
                WebViewModalViewController.openedInAppMessageCount = 0
                return
            }
            guard let vc = try? WebViewModalViewController(notiflyInAppMessageData: notiflyInAppMessageData) else {
                Logger.error("Error presenting in-app message")
                WebViewModalViewController.openedInAppMessageCount = 0
                return
            }
        }
    }

    private func constructUserData(userData: [String: Any], postProcessConfig: PostProcessConfigForSyncState) {
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
                  channel == "in-app-message",
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

    func updateHideCampaignUntilData(hideUntilData: [String: Int]) {
        userData.campaignHiddenUntil.merge(hideUntilData) { _, new in new }
    }
}

struct SegmentationHelper {
    static func isEntityOfSegment(campaign: Campaign, eventParams: [String: Any]?, userData: UserData, eventData: EventData) -> Bool {
        // now only support for the condition-based-segment type
        guard let segmentationType = NotiflySegmentation.SegmentationType(rawValue: campaign.segmentType),
              segmentationType == .conditionBased,
              let segmentInfo = campaign.segmentInfo
        else {
            return false
        }

        if campaign.testing {
            guard let whitelist = campaign.whitelist,
                  let externalUserId = try? Notifly.main.userManager.externalUserID,
                  whitelist.contains(externalUserId)
            else {
                return false
            }
        }

        guard let groups = segmentInfo.groups else {
            return true // send to all
        }

        guard let groupOp = segmentInfo.groupOperator,
              groupOp == "OR"
        else {
            // now only supported for OR operator as group operator
            return false
        }
        return groups.contains { group in
            self.isEntityOfGroup(group: group, eventParams: eventParams, userData: userData, eventData: eventData)
        }
    }

    static func isEntityOfGroup(group: NotiflySegmentation.SegmentationGroup.Group, eventParams: [String: Any]?, userData: UserData, eventData: EventData) -> Bool {
        guard let conditions = group.conditions,
              conditions.count > 0
        else {
            return false
        }
        guard let conditionOp = group.conditionOperator,
              conditionOp == "AND"
        else {
            // now only supported for AND operator as conditon operator
            return false
        }

        return conditions.allSatisfy { condition in
            self.matchCondition(condition: condition, eventParams: eventParams, userData: userData, eventData: eventData)
        }
    }

    static func matchCondition(condition: NotiflySegmentation.SegmentationCondition.ConditionType, eventParams: [String: Any]?, userData: UserData, eventData: EventData) -> Bool {
        switch condition {
        case let .UserBasedType(userCondition):
            return matchUserBasedCondition(condition: userCondition, eventParams: eventParams, userData: userData)
        case let .EventBasedType(eventCondition):
            return matchEventBasedCondition(condition: eventCondition, eventData: eventData)
        }
    }

    static func matchUserBasedCondition(condition: NotiflySegmentation.SegmentationCondition.Conditions.UserBased.Condition, eventParams: [String: Any]?, userData: UserData) -> Bool {
        guard let values = extractValuesOfUserBasedConditionToCompare(condition: condition, eventParams: eventParams, userData: userData) else {
            return false
        }
        
        if let operatorType = NotiflyOperator(rawValue: condition.operator) {
            switch operatorType {
            case .isNull:
                return values.0 == nil
            case .isNotNull:
                return values.0 != nil
            default:
                let valueType = condition.valueType
                if let userValue = NotiflyComparingValueHelper.castAnyToSpecifiedType(value: values.0, type: operatorType == .contains ? "ARRAY" : valueType),
                   let comparisonTargetValue = NotiflyComparingValueHelper.castAnyToSpecifiedType(value: values.1, type: valueType)
                {
                    switch operatorType {
                    case .equal:
                        return NotiflyComparingValueHelper.isEqual(value1: userValue, value2: comparisonTargetValue, type: valueType)
                    case .notEqual:
                        return NotiflyComparingValueHelper.isNotEqual(value1: userValue, value2: comparisonTargetValue, type: valueType)
                    case .contains:
                        return NotiflyComparingValueHelper.isContains(value1: userValue, value2: comparisonTargetValue, type: valueType)
                    case .greaterThan:
                        return NotiflyComparingValueHelper.isGreaterThan(value1: userValue, value2: comparisonTargetValue, type: valueType)
                    case .greaterOrEqualThan:
                        return NotiflyComparingValueHelper.isGreaterOrEqualThan(value1: userValue, value2: comparisonTargetValue, type: valueType)
                    case .lessThan:
                        return NotiflyComparingValueHelper.isLessThan(value1: userValue, value2: comparisonTargetValue, type: valueType)
                    case .lessOrEqualThan:
                        return NotiflyComparingValueHelper.isLessOrEqualThan(value1: userValue, value2: comparisonTargetValue, type: valueType)
                    default:
                        return false
                    }
                }
            }
        }
        return false
    }

    static func extractValuesOfUserBasedConditionToCompare(condition: NotiflySegmentation.SegmentationCondition.Conditions.UserBased.Condition, eventParams: [String: Any]?, userData: UserData) -> (Any?, Any?)? {
        var userRawValue: Any?
        if condition.unit == "user" {
            userRawValue = userData.userProperties[condition.attribute]
        } else {
            userRawValue = userData.get(key: condition.attribute)
        }

        var comparisonTargetRawValue: Any?
        let useEventParamsAsCondition = condition.useEventParamsAsCondition
        if useEventParamsAsCondition {
            guard let eventParams = eventParams,
                  let key = condition.comparisonParameter,
                  let value = eventParams[key]
            else {
                return nil
            }
            comparisonTargetRawValue = value
        } else {
            comparisonTargetRawValue = condition.value
        }
        return (userRawValue, comparisonTargetRawValue)
    }

    static func matchEventBasedCondition(condition: NotiflySegmentation.SegmentationCondition.Conditions.EventBased.Condition, eventData: EventData) -> Bool {
        guard condition.value >= 0 else {
            return false
        }
        var startDate: String?
        if condition.eventConditionType == .lastNDays {
            startDate = NotiflyHelper.getDateStringBeforeNDays(n: condition.secondaryValue)
            guard startDate != nil else {
                return false
            }
        }

        let userCounts = caculateEventCounts(eventName: condition.event, startDate: startDate, eventData: eventData)
        guard userCounts >= 0 else {
            return false
        }

        switch condition.operator {
        case "=":
            return userCounts == condition.value
        case ">=":
            return userCounts >= condition.value
        case "<=":
            return userCounts <= condition.value
        case ">":
            return userCounts > condition.value
        case "<":
            return userCounts < condition.value
        default:
            return false
        }
    }

    static func caculateEventCounts(eventName: String, startDate: String?, eventData: EventData) -> Int {
        guard let eventCounts = Array(eventData.eventCounts.values) as? [EventIntermediateCount] else {
            return -1
        }

        var targetEventCounts = eventCounts.filter { $0.name == eventName }
        if let startDate = startDate {
            targetEventCounts = targetEventCounts.filter { $0.dt >= startDate }
        }
        guard !targetEventCounts.isEmpty else {
            return 0
        }
        return targetEventCounts.reduce(0) { $0 + $1.count }
    }
}

private extension UIWindow {
    var topMostViewController: UIViewController? {
        return rootViewController?.topMostViewController
    }
}

private extension UIViewController {
    var topMostViewController: UIViewController {
        if let presented = presentedViewController {
            return presented.topMostViewController
        }
        if let nav = self as? UINavigationController {
            return nav.visibleViewController?.topMostViewController ?? nav
        }
        if let tab = self as? UITabBarController {
            return (tab.selectedViewController ?? self).topMostViewController
        }
        return self
    }
}
