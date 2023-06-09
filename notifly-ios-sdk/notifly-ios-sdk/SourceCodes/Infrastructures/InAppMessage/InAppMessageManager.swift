//
//  InAppMessageManager.swift
//  notifly-ios-sdk
//
//  Created by 김대성 on 2023/06/12.
//

import Combine
import Foundation
import UIKit

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

    private var syncStateFinishedPromise: Future<Void, Error>.Promise?
    init() {
        syncStateFinishedPub = Future { [weak self] promise in
            self?.syncStateFinishedPromise = promise
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                if let promise = self?.syncStateFinishedPromise {
                    promise(.failure(NotiflyError.promiseTimeout))
                }
            }
        }.eraseToAnyPublisher()
    }

    func syncState() {
        guard let notifly = (try? Notifly.main) else {
            return
        }
        guard let projectID = notifly.projectID as String?,
              let notiflyUserID = (try? notifly.userManager.getNotiflyUserID()),
              let notiflyDeviceID = AppHelper.getNotiflyDeviceID()
        else {
            Logger.error("Fail to sync user state because Notifly is not initalized yet.")
            return
        }

        NotiflyAPI().requestSyncState(projectID: projectID, notiflyUserID: notiflyUserID, notiflyDeviceID: notiflyDeviceID)
            .sink(receiveCompletion: { completion in
                if case let .failure(error) = completion {
                    Logger.error("Fail to sync user state: " + error.localizedDescription)
                    self.syncStateFinishedPromise?(.success(()))
                }
            }, receiveValue: { [weak self] jsonString in
                if let jsonData = jsonString.data(using: .utf8),
                   let decodedData = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any]
                {
                    if let userData = decodedData["userData"] as? [String: Any] {
                        if let previousUserProperties = self?.userData.userProperties as? [String: Any] {
                            self?.userData = UserData(data: userData)
                            self?.updateUserProperties(properties: previousUserProperties)
                        } else {
                            self?.userData = UserData(data: userData)
                        }
                    }

                    if let campaignData = decodedData["campaignData"] as? [[String: Any]] {
                        self?.constructCampaignData(campaignData: campaignData)
                    }

                    if let eicData = decodedData["eventIntermediateCountsData"] as? [[String: Any]] {
                        self?.constructEventIntermediateCountsData(eicData: eicData)
                    }
                }
                self?.syncStateFinishedPromise?(.success(()))
            })
            .store(in: &requestSyncStateCancellables)
    }

    func updateUserProperties(properties: [String: Any]) {
        userData.userProperties.merge(properties) { _, new in new }
    }

    func updateEventData(eventName: String, eventParams: [String: Any]?, segmentationEventParamKeys: [String]?) {
        let dt = getCurrentDate()
        var eicID = eventName + InAppMessageConstant.idSeparator + dt + InAppMessageConstant.idSeparator

        if let segmentationEventParamKeys = segmentationEventParamKeys,
           let eventParams = eventParams,
           segmentationEventParamKeys.count > 0,
           eventParams.count > 0,
           let keyField = segmentationEventParamKeys[0] as? String, // TODO: support multiple segmentationEventParamKey
           let value = eventParams[keyField] as? String
        {
            eicID += keyField + InAppMessageConstant.idSeparator + String(describing: value)
            updateEventCountsInEventData(eicID: eicID, eventName: eventName, dt: dt, eventParams: [:])
        } else {
            eicID += InAppMessageConstant.idSeparator
            updateEventCountsInEventData(eicID: eicID, eventName: eventName, dt: dt, eventParams: [:])
        }
        
        if var campaignsToTrigger = inspectCampaignToTriggerAndGetCampaignData(eventName: eventName, eventParams: eventParams)
        {
            campaignsToTrigger.sort(by: { $0.lastUpdatedTimestamp > $1.lastUpdatedTimestamp })
            for campaignToTrigger in campaignsToTrigger {
                if let notiflyInAppMessageData = prepareInAppMessageData(campaign: campaignToTrigger) {
                    showInAppMessage(notiflyInAppMessageData: notiflyInAppMessageData)
                }
            }
        }
    }

    private func updateEventCountsInEventData(eicID: String, eventName: String, dt: String, eventParams: [String: Any]?) {
        if var eicToUpdate = eventData.eventCounts[eicID] as? EventIntermediateCount {
            eicToUpdate.count += 1
        } else {
            eventData.eventCounts[eicID] = EventIntermediateCount(name: eventName, dt: dt, count: 1, eventParams: eventParams ?? [:])
        }
    }

    /* method for showing in-app message */
    private func inspectCampaignToTriggerAndGetCampaignData(eventName: String, eventParams: [String: Any]?) -> [Campaign]? {
        let now = { () -> Int in
            Int(Date().timeIntervalSince1970)
        }
        
        let campaignsToTrigger = campaignData.inAppMessageCampaigns
            .filter { $0.triggeringEvent == eventName }
            .filter { isCampaignActive(campaign: $0) }
            .filter { !isBlacklistTemplate(templateName: $0.message.modalProperties.templateName) }
            .filter { self.isEntityOfSegment(campaign: $0, eventParams: eventParams) }
        
        if campaignsToTrigger.count == 0 {
            return nil
        }
        return campaignsToTrigger
    }

    private func isCampaignActive(campaign: Campaign) -> Bool {
        let now = Int(Date().timeIntervalSince1970)
        if let startTimestamp = campaign.campaignStart as? Int {
            if let endTimestamp = campaign.campaignEnd as? Int {
                return now >= startTimestamp && now <= endTimestamp
            } else {
                return now >= startTimestamp
            }
        }
        return false
    }

    private func isBlacklistTemplate(templateName: String) -> Bool {
        let propertyKeyForBlacklist = "hide_in_app_message_" + templateName
        guard let isBlacklist = self.userData.userProperties[propertyKeyForBlacklist] as? Bool else {
            return false
        }
        return isBlacklist
    }

    func prepareInAppMessageData(campaign: Campaign) -> InAppMessageData? {
        let messageId = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let campaignId = campaign.id
        let urlString = campaign.message.htmlURL
        let modalProperties = campaign.message.modalProperties
        let delay = DispatchTimeInterval.seconds(campaign.delay ?? 0)
        let deadline = DispatchTime.now() + delay

        if let url = URL(string: urlString) {
            return InAppMessageData(notiflyMessageId: messageId, notiflyCampaignId: campaignId, modalProps: modalProperties, url: url, deadline: deadline)
        }
        return nil
    }

    
    private func showInAppMessage(notiflyInAppMessageData: InAppMessageData) {
        DispatchQueue.main.asyncAfter(deadline: notiflyInAppMessageData.deadline) {
            guard WebViewModalViewController.openedInAppMessageCount == 0 else {
                Logger.error("Already In App Message Opened. New In App Message Ignored.")
                return
            }
            guard UIApplication.shared.applicationState == .active else {
                Logger.error("Due to being in a background state, in-app messages are being ignored.")
                return
            }
            guard let vc = try? WebViewModalViewController(notiflyInAppMessageData: notiflyInAppMessageData) else {
                Logger.error("Error presenting in-app message")
                return
            }
        }
    }

    /* method for showing in-app message */
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
                  segmentType == "condition"
            else {
                return nil
            }

            let message = Message(htmlURL: htmlURL, modalProperties: modalProperties)

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

            let segmentInfo = self.constructSegmnentInfo(segmentInfoDict: segmentInfoDict)
            let lastUpdatedTimestamp = (campaignDict["last_updated_timestamp"] as? Int) ?? 0
            
            return Campaign(id: id, channel: channel, segmentType: segmentType, message: message, segmentInfo: segmentInfo, triggeringEvent: triggeringEvent, campaignStart: campaignStart, campaignEnd: campaignEnd, delay: delay, status: campaignStatus, testing: testing, whitelist: whitelist,
                            lastUpdatedTimestamp: lastUpdatedTimestamp
            )
        }
    }

    private func constructSegmnentInfo(segmentInfoDict: [String: Any]) -> SegmentInfo? {
        guard let rawGroups = segmentInfoDict["groups"] as? [[String: Any]], rawGroups.count > 0 else {
            return SegmentInfo(groups: nil, groupOperator: nil)
        }
        let groups = rawGroups.compactMap { groupDict -> Group? in
            guard let conditionDictionaries = groupDict["conditions"] as? [[String: Any]] else {
                return nil
            }
            guard let conditions = conditionDictionaries.compactMap({ conditionDict -> Condition? in
                guard let unit = conditionDict["unit"] as? String else {
                    return nil
                }
                if unit == "event" {
                    guard let condition = try? EventBasedCondition(condition: conditionDict) else {
                        return nil
                    }
                    return .EventBasedCondition(condition)
                } else {
                    guard let condition = try? UserBasedCondition(condition: conditionDict) else {
                        return nil
                    }
                    return .UserBasedCondition(condition)
                }
            }) as? [Condition] else {
                return nil
            }
            let conditionOperator = (groupDict["condition_operator"] as? String) ?? InAppMessageConstant.segmentInfoDefaultConditionOperator
            return Group(conditions: conditions.compactMap { $0 }, conditionOperator: conditionOperator)
        }
        let groupOperator = segmentInfoDict["group_operator"] as? String ?? InAppMessageConstant.segmentInfoDefaultGroupOperator
        return SegmentInfo(groups: groups.compactMap { $0 }, groupOperator: groupOperator)
    }

    private func constructEventIntermediateCountsData(eicData: [[String: Any]]) {
        guard eicData.count > 0 else {
            return
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
        }.compactMap { $0 }.reduce(into: [:]) { $0[$1.0] = $1.1 }
    }

    private func getCurrentDate() -> String {
        let currentDate = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.string(from: currentDate)
    }

    private func isEntityOfSegment(campaign: Campaign, eventParams: [String: Any]?) -> Bool {
        // now only support for the condition-based-segment type
        guard campaign.segmentType == "condition",
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
            self.isEntityOfGroup(group: group, eventParams: eventParams)
        }
    }

    private func isEntityOfGroup(group: Group, eventParams: [String: Any]?) -> Bool {
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
            self.matchCondition(condition: condition, eventParams: eventParams)
        }
    }

    private func matchCondition(condition: Condition, eventParams: [String: Any]?) -> Bool {
        switch condition {
        case let .EventBasedCondition(eventCondition):
            return matchEventBasedCondition(condition: eventCondition)
        case let .UserBasedCondition(userCondition):
            return matchUserBasedCondition(condition: userCondition, eventParams: eventParams)
        }
    }

    private func matchEventBasedCondition(condition: EventBasedCondition) -> Bool {
        guard condition.value >= 0 else {
            return false
        }
        var startDate: String?
        if condition.eventConditionType == .lastNDays {
            startDate = getDateStringBeforeNDays(n: condition.secondaryValue)
            guard startDate != nil else {
                return false
            }
        }

        let userCounts = caculateEventCounts(eventName: condition.event, startDate: startDate)
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

    private func caculateEventCounts(eventName: String, startDate: String?) -> Int {
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

    private func getDateStringBeforeNDays(n: Int?) -> String? {
        guard let n = n else {
            return nil
        }
        guard n >= 0 else {
            return nil
        }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let currentDate = Date()
        let calendar = Calendar.current
        if let modifiedDate = calendar.date(byAdding: .day, value: -n, to: currentDate) {
            return dateFormatter.string(from: modifiedDate)
        }
        return nil
    }

    private func matchUserBasedCondition(condition: UserBasedCondition, eventParams: [String: Any]?) -> Bool {
        guard let values = extractValuesOfUserBasedConditionToCompare(condition: condition, eventParams: eventParams) else {
            return false
        }
        let valueType = condition.valueType
        if let userValue = convertAnyToSpecifiedType(value: values.0, type: condition.operator == "@>" ? "ARRAY" : valueType),
           let comparisonTargetValue = convertAnyToSpecifiedType(value: values.1, type: valueType)
        {
            switch condition.operator {
            case "=":
                return CompareValueHelper.isEqual(value1: userValue, value2: comparisonTargetValue, type: valueType)
            case "<>":
                return CompareValueHelper.isNotEqual(value1: userValue, value2: comparisonTargetValue, type: valueType)
            case "@>":
                return CompareValueHelper.isContains(value1: userValue, value2: comparisonTargetValue, type: valueType)
            case ">":
                return CompareValueHelper.isGreaterThan(value1: userValue, value2: comparisonTargetValue, type: valueType)
            case ">=":
                return CompareValueHelper.isGreaterOrEqualThan(value1: userValue, value2: comparisonTargetValue, type: valueType)
            case "<":
                return CompareValueHelper.isLessThan(value1: userValue, value2: comparisonTargetValue, type: valueType)
            case "<=":
                return CompareValueHelper.isLessOrEqualThan(value1: userValue, value2: comparisonTargetValue, type: valueType)
            default:
                return false
            }
        }

        return false
    }

    private func extractValuesOfUserBasedConditionToCompare(condition: UserBasedCondition, eventParams: [String: Any]?) -> (Any, Any)? {
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
                  let key = condition.comparisonParameter as? String,
                  let value = eventParams[key]
            else {
                return nil
            }
            comparisonTargetRawValue = value
        } else {
            comparisonTargetRawValue = condition.value
        }

        guard let userRawValue = userRawValue, let comparisonTargetRawValue = comparisonTargetRawValue else {
            return nil
        }
        return (userRawValue, comparisonTargetRawValue)
    }

    private func convertAnyToSpecifiedType(value: Any, type: String) -> Any? {
        switch (value, type) {
        case let (value as String, "TEXT"):
            return value
        case let (value as Int, "INT"):
            return value
        case let (value as String, "INT"):
            return Int(value)
        case let (value as Bool, "BOOL"):
            return value
        case let (value as String, "BOOL"):
            return Bool(value)
        case let (value as [Any], "ARRAY"):
            return value
        case (_, _):
            return nil
        }
    }
}

enum CompareValueHelper {
    static func isEqual(value1: Any, value2: Any, type: String) -> Bool {
        switch type {
        case "TEXT":
            if let value1 = value1 as? String, let value2 = value2 as? String {
                return value1 == value2
            }
            return false
        case "INT":
            if let value1 = value1 as? Int, let value2 = value2 as? Int {
                return value1 == value2
            }
            return false
        case "BOOL":
            if let value1 = value1 as? Bool, let value2 = value2 as? Bool {
                return value1 == value2
            }
            return false
        default:
            return false
        }
    }

    static func isNotEqual(value1: Any, value2: Any, type: String) -> Bool {
        switch type {
        case "TEXT":
            if let value1 = value1 as? String, let value2 = value2 as? String {
                return value1 != value2
            }
            return false
        case "INT":
            if let value1 = value1 as? Int, let value2 = value2 as? Int {
                return value1 != value2
            }
            return false
        case "BOOL":
            if let value1 = value1 as? Bool, let value2 = value2 as? Bool {
                return value1 != value2
            }
            return false
        default:
            return false
        }
    }

    static func isContains(value1: Any, value2: Any, type: String) -> Bool {
        guard let array = value1 as? [Any] else {
            return false
        }
        for element in array {
            if CompareValueHelper.isEqual(value1: element, value2: value2, type: type) {
                return true
            }
        }
        return false
    }

    static func isLessOrEqualThan(value1: Any, value2: Any, type: String) -> Bool {
        switch type {
        case "TEXT":
            if let value1 = value1 as? String, let value2 = value2 as? String {
                return value1 <= value2
            }
            return false
        case "INT":
            if let value1 = value1 as? Int, let value2 = value2 as? Int {
                return value1 <= value2
            }
            return false
        default:
            return false
        }
    }

    static func isLessThan(value1: Any, value2: Any, type: String) -> Bool {
        switch type {
        case "TEXT":
            if let value1 = value1 as? String, let value2 = value2 as? String {
                return value1 < value2
            }
            return false
        case "INT":
            if let value1 = value1 as? Int, let value2 = value2 as? Int {
                return value1 < value2
            }
            return false
        default:
            return false
        }
    }

    static func isGreaterOrEqualThan(value1: Any, value2: Any, type: String) -> Bool {
        switch type {
        case "TEXT":
            if let value1 = value1 as? String, let value2 = value2 as? String {
                return value1 >= value2
            }
            return false
        case "INT":
            if let value1 = value1 as? Int, let value2 = value2 as? Int {
                return value1 >= value2
            }
            return false
        default:
            return false
        }
    }

    static func isGreaterThan(value1: Any, value2: Any, type: String) -> Bool {
        switch type {
        case "TEXT":
            if let value1 = value1 as? String, let value2 = value2 as? String {
                return value1 > value2
            }
            return false
        case "INT":
            if let value1 = value1 as? Int, let value2 = value2 as? Int {
                return value1 > value2
            }
            return false
        default:
            return false
        }
    }
}
