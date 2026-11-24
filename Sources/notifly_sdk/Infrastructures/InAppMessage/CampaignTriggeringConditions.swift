import Foundation

@available(iOSApplicationExtension, unavailable)
struct TriggeringConditions {

    var conditions: [TriggeringConditionGroup]

    init(from: Any?) throws {
        guard let from = from as? [[[String: Any]]] else {
            throw NotiflyError.invalidPayload
        }

        conditions = []
        for condition in from {
            var conditionGroup: TriggeringConditionGroup = []
            for unit in condition {
                guard let unit = try? TriggeringConditionUnit(from: unit) else {
                    throw NotiflyError.invalidPayload
                }
                conditionGroup.append(unit)
            }
            conditions.append(conditionGroup)
        }
    }

    func match(eventName: String) -> Bool {
        return conditions.contains {
            $0.allSatisfy {
                NotiflyStringComparator.compare(
                    reference: eventName,
                    operator: $0.operator,
                    rhs: $0.operand
                )
            }
        }
    }
}

@available(iOSApplicationExtension, unavailable)
typealias TriggeringConditionGroup = [TriggeringConditionUnit]

@available(iOSApplicationExtension, unavailable)
struct TriggeringConditionUnit {

    let `operator`: NotiflyStringOperator
    let operand: String

    init(from: [String: Any]) throws {
        guard let typeStr = from["type"] as? String,
            NotiflyTriggeringConditonType(rawValue: typeStr) != nil,
            let operatorStr = from["operator"] as? String,
            let comparisonOperator = NotiflyStringOperator(rawValue: operatorStr),
            let operand = from["operand"] as? String
        else {
            throw NotiflyError.invalidPayload
        }
        `operator` = comparisonOperator
        self.operand = operand
    }
}

@available(iOSApplicationExtension, unavailable)
typealias TriggeringEventFilterUnitArray = [TriggeringEventFilter.Unit]
@available(iOSApplicationExtension, unavailable)
typealias TriggeringEventFilterArray = [TriggeringEventFilterUnitArray]

@available(iOSApplicationExtension, unavailable)
struct TriggeringEventFilters {

    var filters: TriggeringEventFilterArray

    init(from: Any?) throws {
        guard let from = from as? [[[String: Any]]] else {
            throw NotiflyError.nilValueReceived
        }

        filters = []
        for filter in from {
            guard let filter = try? TriggeringEventFilter.fromArray(filter) else {
                throw NotiflyError.invalidPayload
            }
            filters.append(filter)
        }
    }
}

@available(iOSApplicationExtension, unavailable)
enum TriggeringEventFilter {

    struct Unit {

        let key: String
        let `operator`: NotiflyOperator
        let targetValue: NotiflyValue?

        init?(from: [String: Any]) {
            guard let key = from["key"] as? String,
                let operatorStr = from["operator"] as? String,
                let comparisonOperator = NotiflyOperator(rawValue: operatorStr)
            else {
                return nil
            }
            self.key = key
            `operator` = comparisonOperator
            targetValue = NotiflyValue(type: from["value_type"] as? String, value: from["value"])
        }
    }

    static func fromArray(_ array: [[String: Any]]) throws -> TriggeringEventFilterUnitArray {
        let units = array.map {
            Unit(from: $0)
        }
        if units.contains(where: { $0 == nil }) {
            throw NotiflyError.invalidPayload
        }
        guard let filters = units as? TriggeringEventFilterUnitArray else {
            throw NotiflyError.invalidPayload
        }
        return filters
    }

    static func matchFilterCondition(
        filters: TriggeringEventFilterArray,
        eventParams: [String: Any]?
    ) -> Bool {
        guard let params = eventParams, !params.isEmpty else {
            return false
        }

        func matchFilterCondition(filterUnit: TriggeringEventFilter.Unit) -> Bool {
            if filterUnit.operator != .isNull {
                guard params[filterUnit.key] != nil
                else {
                    return false
                }
            }
            return NotiflyValueComparator.compare(
                type: filterUnit.targetValue?.type,
                sourceValue: params[filterUnit.key] as Any,
                operator: filterUnit.operator,
                targetValue: filterUnit.targetValue?.value
            )
        }

        func matchFilterCondition(filter: TriggeringEventFilterUnitArray) -> Bool {
            return filter.allSatisfy {
                matchFilterCondition(filterUnit: $0)
            }
        }

        return filters.contains {
            matchFilterCondition(filter: $0)
        }
    }
}
