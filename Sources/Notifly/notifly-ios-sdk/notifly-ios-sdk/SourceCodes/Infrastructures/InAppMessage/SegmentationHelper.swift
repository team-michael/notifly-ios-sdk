//
//  SegmentationHelper.swift
//  notifly-ios-sdk
//
//  Created by 김대성 on 2024/01/10.
//

@available(iOSApplicationExtension, unavailable)
enum SegmentationHelper {
    static func isEntityOfSegment(campaign: Campaign, eventParams: [String: Any]?, userData: UserData, eventData: EventData) -> Bool {
        // now only support for the condition-based-segment type
        guard campaign.segmentType == .conditionBased,
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
            return false
        }

        if isTargetAll(segmentInfo: segmentInfo) {
            return true // send to all
        }

        guard let groupOp = segmentInfo.groupOperator,
              groupOp == .or
        else {
            // now only supported for OR operator as group operator
            return false
        }

        return groups.contains { group in
            self.isEntityOfGroup(group: group, eventParams: eventParams, userData: userData, eventData: eventData)
        }
    }

    static func isTargetAll(segmentInfo: NotiflySegmentation.SegmentInfo) -> Bool {
        guard let groups = segmentInfo.groups else {
            return false
        }

        let groupOp = segmentInfo.groupOperator
        if groups.count == 0 || groupOp == nil {
            return true
        }
        return false
    }

    static func isEntityOfGroup(group: NotiflySegmentation.SegmentationGroup.Group, eventParams: [String: Any]?, userData: UserData, eventData: EventData) -> Bool {
        guard let conditions = group.conditions,
              conditions.count > 0
        else {
            return false
        }
        guard let conditionOp = group.conditionOperator,
              conditionOp == .and
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
        let sourceValue = selectSourceValueFromUserData(condition: condition, userData: userData)
        let targetValue = selectTargetValue(condition: condition, eventParams: eventParams)

        return NotiflyValueComparator.compare(type: condition.valueType, sourceValue: sourceValue, operator: condition.operator, targetValue: targetValue)
    }

    static func selectSourceValueFromUserData(condition: NotiflySegmentation.SegmentationCondition.Conditions.UserBased.Condition, userData: UserData) -> Any? {
        var userRawValue: Any?
        if condition.unit == .user {
            userRawValue = userData.userProperties[condition.attribute]
        } else {
            userRawValue = userData.get(key: condition.attribute)
        }
        return userRawValue
    }

    static func selectTargetValue(condition: NotiflySegmentation.SegmentationCondition.Conditions.UserBased.Condition, eventParams: [String: Any]?) -> Any? {
        let useEventParamsAsCondition = condition.useEventParamsAsCondition
        if !useEventParamsAsCondition {
            return condition.value
        }

        guard let eventParams = eventParams,
              let key = condition.comparisonParameter,
              let value = eventParams[key]
        else {
            return nil
        }
        return value
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
        case .equal:
            return userCounts == condition.value
        case .greaterOrEqualThan:
            return userCounts >= condition.value
        case .lessOrEqualThan:
            return userCounts <= condition.value
        case .greaterThan:
            return userCounts > condition.value
        case .lessThan:
            return userCounts < condition.value
        default:
            return false
        }

        return false
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
