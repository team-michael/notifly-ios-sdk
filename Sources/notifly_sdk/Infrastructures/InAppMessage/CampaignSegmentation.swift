import Foundation

@available(iOSApplicationExtension, unavailable)
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
                let conditions =
                    conditionDictionaries.compactMap { conditionDict -> SegmentationCondition.ConditionType? in
                        guard let unit = conditionDict["unit"] as? String else {
                            return nil
                        }
                        if unit == SegmentationCondition.ConditionUnit.event.rawValue {
                            guard
                                let condition = try? SegmentationCondition.Conditions.EventBased
                                    .Condition(condition: conditionDict)
                            else {
                                return nil
                            }
                            return SegmentationCondition.ConditionType.EventBasedType(condition)
                        }
                        else {
                            guard
                                let condition = try? SegmentationCondition.Conditions.UserBased
                                    .Condition(condition: conditionDict)
                            else {
                                return nil
                            }
                            return SegmentationCondition.ConditionType.UserBasedType(condition)
                        }
                    }

                let conditionOperator =
                    (groupDict["condition_operator"] as? String)
                    ?? InAppMessageConstant.segmentInfoDefaultConditionOperator
                return SegmentationGroup.Group(
                    conditions: conditions,
                    conditionOperator: conditionOperator
                )
            }
            groupOperator =
                SegmentationGroup.GroupOperator(
                    rawValue: from["group_operator"] as? String
                        ?? InAppMessageConstant.segmentInfoDefaultGroupOperator
                ) ?? .or
        }
    }

    enum SegmentationGroup {

    }

    enum SegmentationCondition {

    }
}

@available(iOSApplicationExtension, unavailable)
extension NotiflySegmentation.SegmentationGroup {

    enum GroupOperator: String {

        case or = "OR"
    }

    struct Group {

        let conditions: [NotiflySegmentation.SegmentationCondition.ConditionType]?
        let conditionOperator: NotiflySegmentation.SegmentationCondition.ConditionOperator?

        init(conditions: [NotiflySegmentation.SegmentationCondition.ConditionType], conditionOperator: String) {
            self.conditions = conditions
            self.conditionOperator =
                NotiflySegmentation.SegmentationCondition.ConditionOperator(rawValue: conditionOperator) ?? .and
        }
    }
}

@available(iOSApplicationExtension, unavailable)
extension NotiflySegmentation.SegmentationCondition {

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

    }
}

@available(iOSApplicationExtension, unavailable)
extension NotiflySegmentation.SegmentationCondition.Conditions {

    enum UserBased {

    }

    enum EventBased {

    }
}

@available(iOSApplicationExtension, unavailable)
extension NotiflySegmentation.SegmentationCondition.Conditions.UserBased {

    struct Condition {

        let unit: NotiflySegmentation.SegmentationCondition.ConditionUnit
        let attribute: String
        let `operator`: NotiflyOperator

        let useEventParamsAsCondition: Bool
        let comparisonParameter: String?

        let valueType: String
        let value: Any

        init(condition: [String: Any]) throws {
            let useEventParamsAsConditionInDict =
                condition["useEventParamsAsConditionValue"] as? Bool
            guard useEventParamsAsConditionInDict != nil else {
                throw NotiflyError.unexpectedNil("segment_info is not valid.")
            }
            guard let unitStr = condition["unit"] as? String,
                let unit = NotiflySegmentation.SegmentationCondition.ConditionUnit(rawValue: unitStr),
                let attribute = condition["attribute"] as? String,
                let operatorStr = condition["operator"] as? String,
                let comparisonOperator = NotiflyOperator(rawValue: operatorStr)

            else {
                throw NotiflyError.unexpectedNil("segment_info is not valid.")
            }

            let valueNullableOperators = [NotiflyOperator.isNotNull, NotiflyOperator.isNull]
            if !valueNullableOperators.contains(comparisonOperator) {
                guard condition["valueType"] is String,
                    condition["value"] != nil
                else {
                    throw NotiflyError.unexpectedNil("segment_info is not valid.")
                }
            }

            self.unit = unit
            self.attribute = attribute
            `operator` = comparisonOperator
            useEventParamsAsCondition = Bool(useEventParamsAsConditionInDict ?? false)
            valueType = condition["valueType"] as? String ?? "TEXT"
            value = condition["value"] as Any
            comparisonParameter = condition["comparison_parameter"] as? String
        }
    }
}

@available(iOSApplicationExtension, unavailable)
extension NotiflySegmentation.SegmentationCondition.Conditions.EventBased {

    struct Condition {

        let event: String
        let eventConditionType: EventBasedConditionType
        let secondaryValue: Int?
        let `operator`: NotiflyOperator
        let value: Int

        init(condition: [String: Any]) throws {
            guard let event = condition["event"] as? String,
                let eventConditionTypeStr = condition["event_condition_type"]
                    as? String,
                let eventConditionType = EventBasedConditionType(
                    rawValue: eventConditionTypeStr
                ),
                let operatorStr = condition["operator"] as? String,
                let comparisonOperator = NotiflyOperator(rawValue: operatorStr),
                let value = condition["value"] as? Int
            else {
                throw NotiflyError.unexpectedNil("segment_info is not valid.")
            }
            self.event = event
            self.eventConditionType = eventConditionType
            secondaryValue = condition["secondary_value"] as? Int
            self.value = value
            `operator` = comparisonOperator
        }
    }

    enum EventBasedConditionType: String {

        case allTime = "count X"
        case lastNDays = "count X in Y days"
    }
}
