//
//  Campaign.swift
//  notifly-ios-sdk
//
//  Created by 김대성 on 2023/06/12.
//

import Foundation

struct Campaign {
    let id: String
    let channel: String
    let segmentType: String
    let message: Message
    let segmentInfo: SegmentInfo?
    let triggeringEvent: String
    let campaignStart: Int
    let campaignEnd: Int?
    let delay: Int?
    let status: CampaignStatus
    let testing: Bool
    let whitelist: [String]?
    let lastUpdatedTimestamp: Int
    let reEligibleCondition: ReEligibleCondition?
}

struct ModalProperties {
    let templateName: String
    let position: String?
    let width: CGFloat?
    let min_width: CGFloat?
    let max_width: CGFloat?
    let width_vw: CGFloat?
    let width_vh: CGFloat?
    let height: CGFloat?
    let min_height: CGFloat?
    let max_height: CGFloat?
    let height_vw: CGFloat?
    let height_vh: CGFloat?
    let borderBottomLeftRadius: CGFloat?
    let borderBottomRightRadius: CGFloat?
    let borderTopLeftRadius: CGFloat?
    let borderTopRightRadius: CGFloat?
    let backgroundOpacity: CGFloat?
    let dismissCTATapped: Bool?

    init?(properties: [String: Any]) {
        guard let name = properties["template_name"] as? String else {
            return nil
        }
        templateName = name
        position = properties["position"] as? String
        width = properties["width"] as? CGFloat
        min_width = properties["min_width"] as? CGFloat
        max_width = properties["max_width"] as? CGFloat
        width_vw = properties["width_vw"] as? CGFloat
        width_vh = properties["width_vh"] as? CGFloat
        height = properties["height"] as? CGFloat
        min_height = properties["min_height"] as? CGFloat
        max_height = properties["max_height"] as? CGFloat
        height_vw = properties["height_vw"] as? CGFloat
        height_vh = properties["height_vh"] as? CGFloat
        borderBottomLeftRadius = (properties["borderBottomLeftRadius"] ?? 0.0) as? CGFloat
        borderBottomRightRadius = (properties["borderBottomRightRadius"] ?? 0.0) as? CGFloat
        borderTopLeftRadius = (properties["borderTopLeftRadius"] ?? 0.0) as? CGFloat
        borderTopRightRadius = (properties["borderTopRightRadius"] ?? 0.0) as? CGFloat
        backgroundOpacity = (properties["backgroundOpacity"] ?? 0.2) as? CGFloat
        dismissCTATapped = (properties["dismissCTATapped"] ?? false) as? Bool
    }
}

struct ReEligibleCondition {
    let value: Int
    let unit: String

    init?(data: [String: Any]) {
        guard let unit = data["unit"] as? String,
              let value = data["value"] as? Int
        else {
            return nil
        }
        self.value = value
        self.unit = unit
    }
}

struct Message {
    let htmlURL: String
    let modalProperties: ModalProperties
}

enum Condition {
    case UserBasedCondition(UserBasedCondition)
    case EventBasedCondition(EventBasedCondition)
}

struct UserBasedCondition {
    let unit: String
    let attribute: String
    let `operator`: String

    let useEventParamsAsCondition: Bool
    let comparisonEvent: String?
    let comparisonParameter: String?

    let valueType: String
    let value: Any

    init(condition: [String: Any]) throws {
        let useEventParamsAsConditionInDict = condition["useEventParamsAsConditionValue"] as? Bool
        guard useEventParamsAsConditionInDict != nil else {
            throw NotiflyError.unexpectedNil("segment_info is not valid.")
        }
        guard let unit = condition["unit"] as? String,
              let attribute = condition["attribute"] as? String,
              let `operator` = condition["operator"] as? String,
              let valueType = condition["valueType"] as? String,
              let value = condition["value"]
        else {
            throw NotiflyError.unexpectedNil("segment_info is not valid.")
        }
        self.unit = unit
        self.attribute = attribute
        self.operator = `operator`
        useEventParamsAsCondition = Bool(useEventParamsAsConditionInDict ?? false)
        self.valueType = valueType
        self.value = value
        comparisonEvent = condition["comparison_event"] as? String
        comparisonParameter = condition["comparison_parameter"] as? String
    }
}

struct EventBasedCondition {
    let event: String
    let eventConditionType: eventBasedConditionType
    let secondaryValue: Int?
    let `operator`: String
    let value: Int

    init(condition: [String: Any]) throws {
        guard let event = condition["event"] as? String,
              let eventConditionTypeStr = condition["event_condition_type"] as? String,
              let eventConditionType = eventBasedConditionType(rawValue: eventConditionTypeStr),
              let `operator` = condition["operator"] as? String,
              let value = condition["value"] as? Int
        else {
            throw NotiflyError.unexpectedNil("segment_info is not valid.")
        }
        self.event = event
        self.eventConditionType = eventConditionType
        secondaryValue = condition["secondary_value"] as? Int
        self.value = value
        self.operator = `operator`
    }
}

enum eventBasedConditionType: String {
    case allTime = "count X"
    case lastNDays = "count X in Y days"
}

struct Group {
    let conditions: [Condition]?
    let conditionOperator: String?
}

struct SegmentInfo {
    let groups: [Group]?
    let groupOperator: String?
}

enum CampaignStatus: Int {
    case draft = 0
    case active = 1
    case inactive = 2
    case completed = 3
}

enum SegmentationOperator: String {
    case isNull = "IS_NULL"
    case isNotNull = "IS_NOT_NULL"
    case equal = "="
    case notEqual = "<>"
    case contains = "@>"
    case greaterThan = ">"
    case greaterOrEqualThan = ">="
    case lessThan = "<"
    case lessOrEqualThan = "<="
}
