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
    let status: CampaignStatus

    let triggeringEvent: String
    let triggeringEventFilters: TriggeringEventFilters?

    let campaignStart: Int
    let campaignEnd: Int?
    let delay: Int
    let reEligibleCondition: NotiflyReEligibleConditionEnum.ReEligibleCondition?

    let testing: Bool
    let whitelist: [String]?

    let segmentType: NotiflySegmentation.SegmentationType
    let segmentInfo: NotiflySegmentation.SegmentInfo?

    let message: Message

    let lastUpdatedTimestamp: Int

    init?(from: [String: Any]) {
        guard let id = from["id"] as? String,
              let channel = from["channel"] as? String,
              channel == InAppMessageConstant.inAppMessageChannel,

              let rawStatusValue = from["status"] as? Int,
              let campaignStatus = CampaignStatus(rawValue: rawStatusValue),
              campaignStatus == .active,

              let triggeringEvent = from["triggering_event"] as? String,

              let testing = from["testing"] as? Bool,

              let messageDict = from["message"] as? [String: Any],
              let htmlURL = messageDict["html_url"] as? String,
              let modalProperties = ModalProperties(properties: messageDict["modal_properties"] as? [String: Any]),

              let rawSegmentType = from["segment_type"] as? String,
              let segmentType = NotiflySegmentation.SegmentationType(rawValue: rawSegmentType),
              segmentType == .conditionBased,
              let segmentInfoDict = from["segment_info"] as? [String: Any]

        else {
            return nil
        }

        self.id = id

        self.channel = channel
        status = campaignStatus

        self.triggeringEvent = triggeringEvent
        triggeringEventFilters = try? TriggeringEventFilters(from: from["triggering_event_filters"])

        let campaignStarts: [Int] = (from["starts"] as? [Int]) ?? []
        campaignStart = campaignStarts.count > 0 ? campaignStarts[0] : 0
        campaignEnd = from["end"] as? Int
        delay = (from["delay"] as? Int) ?? 0
        reEligibleCondition = NotiflyReEligibleConditionEnum.ReEligibleCondition(from: from["re_eligible_condition"] as? [String: Any])

        self.testing = testing
        whitelist = testing ? from["whitelist"] as? [String] : []

        self.segmentType = segmentType
        segmentInfo = NotiflySegmentation.SegmentInfo(from: segmentInfoDict)

        message = Message(htmlURL: htmlURL, modalProperties: modalProperties)

        lastUpdatedTimestamp = (from["last_updated_timestamp"] as? Int) ?? 0
    }
}

enum CampaignStatus: Int {
    case invalid = -1
    case draft = 0
    case active = 1
    case inactive = 2
    case completed = 3
}

struct Message {
    let htmlURL: String
    let modalProperties: ModalProperties
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

    init?(properties: [String: Any]?) {
        guard let properties = properties else {
            return nil
        }
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

typealias TriggeringEventFilterUnitArray = [TriggeringEventFilter.Unit]
typealias TriggeringEventFilterArray = [TriggeringEventFilterUnitArray]

struct TriggeringEventFilters {
    var filters: TriggeringEventFilterArray

    init(from: Any?) throws {
        guard let from = from as? [[[String: Any]]] else {
            throw NotiflyError.nilValueReceived
        }

        filters = []
        for filter in from {
            guard let rawFilter = filter as? [[String: Any]] else {
                throw NotiflyError.invalidPayload
            }
            guard let filter = try? TriggeringEventFilter.fromArray(rawFilter) else {
                throw NotiflyError.invalidPayload
            }
            filters.append(filter)
        }
    }
}

enum TriggeringEventFilter {
    struct Unit {
        let key: String
        let `operator`: NotiflyOperator
        let targetValue: NotiflyValue?

        init?(from: [String: Any]) {
            guard let key = from["key"] as? String,
                  let operatorStr = from["operator"] as? String,
                  let `operator` = NotiflyOperator(rawValue: operatorStr)
            else {
                return nil
            }
            self.key = key
            self.operator = `operator`
            targetValue = NotiflyValue(type: from["value_type"] as? String, value: from["value"])
        }
    }

    static func fromArray(_ array: [[String: Any]]) throws -> TriggeringEventFilterUnitArray {
        let units = array.map { Unit(from: $0) }
        if units.contains(where: { $0 == nil }) {
            throw NotiflyError.invalidPayload
        }
        guard let filters = units as? TriggeringEventFilterUnitArray else {
            throw NotiflyError.invalidPayload
        }
        return filters
    }

    static func matchFilterCondition(filters: TriggeringEventFilterArray, eventParams: [String: Any]?) -> Bool {
        guard let params = eventParams, params.count > 0 else {
            return false
        }

        func matchFilterCondition(filterUnit: TriggeringEventFilter.Unit) -> Bool {
            guard let sourceValue = params[filterUnit.key] else {
                return false
            }
            return NotiflyComparingValueHelper.compare(type: filterUnit.targetValue?.type, sourceValue: sourceValue, operator: filterUnit.operator, targetValue: filterUnit.targetValue?.value)
        }

        func matchFilterCondition(filter: TriggeringEventFilterUnitArray) -> Bool {
            return filter.allSatisfy { matchFilterCondition(filterUnit: $0) }
        }

        return filters.contains { matchFilterCondition(filter: $0) }
    }
}

enum NotiflySegmentation {
    enum SegmentationType: String {
        case conditionBased = "condition"
    }

    struct SegmentInfo {
        let groups: [SegmentationGroup.Group]?
        let groupOperator: SegmentationGroup.GroupOperator?

        init(from: [String: Any]) {
            let rawGroups = from["groups"] as? [[String: Any]] ?? []
            groups = rawGroups.compactMap { groupDict -> NotiflySegmentation.SegmentationGroup.Group? in
                guard let conditionDictionaries = groupDict["conditions"] as? [[String: Any]] else {
                    return nil
                }
                let conditions = conditionDictionaries.compactMap { conditionDict -> SegmentationCondition.ConditionType? in
                    guard let unit = conditionDict["unit"] as? String else {
                        return nil
                    }
                    if unit == SegmentationCondition.ConditionUnit.event.rawValue {
                        guard let condition = try? SegmentationCondition.Conditions.EventBased.Condition(condition: conditionDict) else {
                            return nil
                        }
                        return SegmentationCondition.ConditionType.EventBasedType(condition)
                    } else {
                        guard let condition = try? SegmentationCondition.Conditions.UserBased.Condition(condition: conditionDict) else {
                            return nil
                        }
                        return SegmentationCondition.ConditionType.UserBasedType(condition)
                    }
                } as? [SegmentationCondition.ConditionType]

                let conditionOperator = (groupDict["condition_operator"] as? String) ?? InAppMessageConstant.segmentInfoDefaultConditionOperator
                return SegmentationGroup.Group(conditions: conditions ?? [], conditionOperator: conditionOperator)
            }
            groupOperator = SegmentationGroup.GroupOperator(rawValue: from["group_operator"] as? String ?? InAppMessageConstant.segmentInfoDefaultGroupOperator) ?? .or
        }
    }

    enum SegmentationGroup {
        enum GroupOperator: String {
            case or = "OR"
        }

        struct Group {
            let conditions: [SegmentationCondition.ConditionType]?
            let conditionOperator: SegmentationCondition.ConditionOperator?
            init(conditions: [SegmentationCondition.ConditionType], conditionOperator: String) {
                self.conditions = conditions
                self.conditionOperator = SegmentationCondition.ConditionOperator(rawValue: conditionOperator) ?? .and
            }
        }
    }

    enum SegmentationCondition {
        enum ConditionOperator: String {
            case and = "AND"
        }

        enum ConditionUnit: String {
            case device
            case user
            case event
            case userMetadata = "user_metadata"
        }

        enum ConditionType {
            case UserBasedType(Conditions.UserBased.Condition)
            case EventBasedType(Conditions.EventBased.Condition)
        }

        enum Conditions {
            enum UserBased {
                struct Condition {
                    let unit: ConditionUnit
                    let attribute: String
                    let `operator`: NotiflyOperator

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
                        guard let unitStr = condition["unit"] as? String,
                              let unit = ConditionUnit(rawValue: unitStr),
                              let attribute = condition["attribute"] as? String,
                              let operatorStr = condition["operator"] as? String,
                              let `operator` = NotiflyOperator(rawValue: operatorStr),
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
            }

            enum EventBased {
                struct Condition {
                    let unit: ConditionUnit = .event
                    let event: String
                    let eventConditionType: EventBasedConditionType
                    let secondaryValue: Int?
                    let `operator`: NotiflyOperator
                    let value: Int

                    init(condition: [String: Any]) throws {
                        guard let event = condition["event"] as? String,
                              let eventConditionTypeStr = condition["event_condition_type"] as? String,
                              let eventConditionType = EventBasedConditionType(rawValue: eventConditionTypeStr),
                              let operatorStr = condition["operator"] as? String,
                              let `operator` = NotiflyOperator(rawValue: operatorStr),
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

                enum EventBasedConditionType: String {
                    case allTime = "count X"
                    case lastNDays = "count X in Y days"
                }
            }
        }
    }
}

enum NotiflyReEligibleConditionEnum {
    enum Unit: String {
        case hour = "h"
        case day = "d"
        case week = "w"
        case month = "m"
        case infinite
    }

    struct ReEligibleCondition {
        let value: Int
        let unit: String

        init?(from: [String: Any]?) {
            guard let from = from else {
                return nil
            }
            guard let unit = from["unit"] as? String,
                  let value = from["value"] as? Int
            else {
                return nil
            }
            self.value = value
            self.unit = unit
        }
    }

    static let defaultValue = -1
}
