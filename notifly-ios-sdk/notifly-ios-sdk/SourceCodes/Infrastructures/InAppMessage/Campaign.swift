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
}

struct ModalProperties {
    let templateName: String
    let position: String?
    let width: Float?
    let min_width: Float?
    let max_width: Float?
    let width_vw: Float?
    let width_vh: Float?
    let height: Float?
    let min_height: Float?
    let max_height: Float?
    let height_vw: Float?
    let height_vh: Float?
    let borderBottomLeftRadius: Float?
    let borderBottomRightRadius: Float?
    let borderTopLeftRadius: Float?
    let borderTopRightRadius: Float?
    
    init?(properties: [String: Any]) {
        guard let name = properties["template_name"] as? String else {
            return nil
        }
        templateName = name
        position = properties["position"] as? String
        width = properties["width"] as? Float
        min_width = properties["min_width"] as? Float
        max_width = properties["max_width"] as? Float
        width_vw = properties["width_vw"] as? Float
        width_vh = properties["width_vh"] as? Float
        height = properties["height"] as? Float
        min_height = properties["min_height"] as? Float
        max_height = properties["max_height"] as? Float
        height_vw = properties["height_vw"] as? Float
        height_vh = properties["height_vh"] as? Float
        borderBottomLeftRadius = properties["borderBottomLeftRadius"] as? Float
        borderBottomRightRadius = properties["borderBottomRightRadius"] as? Float
        borderTopLeftRadius = properties["borderTopLeftRadius"] as? Float
        borderTopRightRadius = properties["borderTopRightRadius"] as? Float
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
        self.`operator` = `operator`
        self.useEventParamsAsCondition = Bool(useEventParamsAsConditionInDict ?? false)
        self.valueType = valueType
        self.value = value
        self.comparisonEvent = condition["comparison_event"] as? String
        self.comparisonParameter = condition["comparison_parameter"] as? String
    }
}

struct EventBasedCondition {
    let event: String
    let eventConditionType: String
    let secondaryValue: Float
    let `operator`: String
    let value: Int
    
    init(condition: [String: Any]) throws {
        guard let event = condition["event"] as? String,
              let eventConditionType = condition["event_condition_type"] as? String,
              let secondaryValue = condition["secondary_value"] as? Float,
              let `operator` = condition["operator"] as? String,
              let value = condition["value"] as? Int
        else {
            throw NotiflyError.unexpectedNil("segment_info is not valid.")
        }
        self.event = event
        self.eventConditionType = eventConditionType
        self.secondaryValue = secondaryValue
        self.value = value
        self.`operator` = `operator`
    }
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
