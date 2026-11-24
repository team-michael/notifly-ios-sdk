//
//  NotiflyValueComparator.swift
//  notifly-ios-sdk
//

import Foundation

@available(iOSApplicationExtension, unavailable)
enum NotiflyValueComparator {

    static func compare(
        type: String?,
        sourceValue: Any,
        operator: NotiflyOperator,
        targetValue: Any?
    ) -> Bool {
        switch `operator` {
        case .isNull:
            switch sourceValue {
            case Optional<Any>.none:
                return true
            default:
                return false
            }
        case .isNotNull:
            switch sourceValue {
            case Optional<Any>.none:
                return false
            default:
                return true
            }
        default:
            if let type = type,
                let typedSourceValue = NotiflyValueComparator.castAnyToSpecifiedType(
                    value: sourceValue,
                    type: `operator` == .contains ? "ARRAY" : type
                ),
                let typedTargetValue = NotiflyValueComparator.castAnyToSpecifiedType(
                    value: targetValue,
                    type: type
                )
            {
                return compareTypedValues(
                    type: type,
                    sourceValue: typedSourceValue,
                    operator: `operator`,
                    targetValue: typedTargetValue
                )
            }
            return false
        }
    }

    private static func compareTypedValues(
        type: String,
        sourceValue: Any,
        operator: NotiflyOperator,
        targetValue: Any
    ) -> Bool {
        switch `operator` {
        case .equal:
            return NotiflyValueComparator.isEqual(
                value1: sourceValue,
                value2: targetValue,
                type: type
            )
        case .notEqual:
            return NotiflyValueComparator.isNotEqual(
                value1: sourceValue,
                value2: targetValue,
                type: type
            )
        case .contains:
            return NotiflyValueComparator.doesContain(
                value1: sourceValue,
                value2: targetValue,
                type: type
            )
        case .greaterThan:
            return NotiflyValueComparator.isGreaterThan(
                value1: sourceValue,
                value2: targetValue,
                type: type
            )
        case .greaterOrEqualThan:
            return NotiflyValueComparator.isGreaterOrEqualThan(
                value1: sourceValue,
                value2: targetValue,
                type: type
            )
        case .lessThan:
            return NotiflyValueComparator.isLessThan(
                value1: sourceValue,
                value2: targetValue,
                type: type
            )
        case .lessOrEqualThan:
            return NotiflyValueComparator.isLessOrEqualThan(
                value1: sourceValue,
                value2: targetValue,
                type: type
            )
        default:
            return false
        }
    }

    static func isEqual(value1: Any, value2: Any, type: String) -> Bool {
        switch NotiflyValueType(rawValue: type) {
        case .string:
            if let value1 = value1 as? String, let value2 = value2 as? String {
                return value1 == value2
            }
            return false
        case .int:
            if let value1 = value1 as? Int, let value2 = value2 as? Int {
                return value1 == value2
            }
            return false
        case .bool:
            if let value1 = value1 as? Bool, let value2 = value2 as? Bool {
                return value1 == value2
            }
            return false
        default:
            return false
        }
    }

    static func isNotEqual(value1: Any, value2: Any, type: String) -> Bool {
        switch NotiflyValueType(rawValue: type) {
        case .string:
            if let value1 = value1 as? String, let value2 = value2 as? String {
                return value1 != value2
            }
            return false
        case .int:
            if let value1 = value1 as? Int, let value2 = value2 as? Int {
                return value1 != value2
            }
            return false
        case .bool:
            if let value1 = value1 as? Bool, let value2 = value2 as? Bool {
                return value1 != value2
            }
            return false
        default:
            return false
        }
    }

    static func isLessOrEqualThan(value1: Any, value2: Any, type: String) -> Bool {
        switch NotiflyValueType(rawValue: type) {
        case .string:
            if let value1 = value1 as? String, let value2 = value2 as? String {
                return value1 <= value2
            }
            return false
        case .int:
            if let value1 = value1 as? Int, let value2 = value2 as? Int {
                return value1 <= value2
            }
            return false
        default:
            return false
        }
    }

    static func isLessThan(value1: Any, value2: Any, type: String) -> Bool {
        switch NotiflyValueType(rawValue: type) {
        case .string:
            if let value1 = value1 as? String, let value2 = value2 as? String {
                return value1 < value2
            }
            return false
        case .int:
            if let value1 = value1 as? Int, let value2 = value2 as? Int {
                return value1 < value2
            }
            return false
        default:
            return false
        }
    }

    static func isGreaterOrEqualThan(value1: Any, value2: Any, type: String) -> Bool {
        switch NotiflyValueType(rawValue: type) {
        case .string:
            if let value1 = value1 as? String, let value2 = value2 as? String {
                return value1 >= value2
            }
            return false
        case .int:
            if let value1 = value1 as? Int, let value2 = value2 as? Int {
                return value1 >= value2
            }
            return false
        default:
            return false
        }
    }

    static func isGreaterThan(value1: Any, value2: Any, type: String) -> Bool {
        switch NotiflyValueType(rawValue: type) {
        case .string:
            if let value1 = value1 as? String, let value2 = value2 as? String {
                return value1 > value2
            }
            return false
        case .int:
            if let value1 = value1 as? Int, let value2 = value2 as? Int {
                return value1 > value2
            }
            return false
        default:
            return false
        }
    }

    static func doesContain(value1: Any, value2: Any, type: String) -> Bool {
        guard let array = value1 as? [Any] else {
            return false
        }
        for element in array where NotiflyValueComparator.isEqual(value1: element, value2: value2, type: type) {
            return true
        }
        return false
    }

    static func castAnyToSpecifiedType(value: Any?, type: String) -> Any? {
        switch (value, NotiflyValueType(rawValue: type)) {
        case let (value as String, .string):
            return value
        case let (value as Int, .int):
            return value
        case let (value as String, .int):
            return Int(value)
        case let (value as Bool, .bool):
            return value
        case let (value as String, .bool):
            return Bool(value)
        case let (value as [Any], .array):
            return value
        case let (value, .cgFloat):
            return castToCGFloat(value: value)
        case (_, _):
            return nil
        }
    }

    private static func castToCGFloat(value: Any?) -> CGFloat? {
        switch value {
        case let value as Int:
            return CGFloat(value)
        case let value as Double:
            return CGFloat(value)
        case let value as Float:
            return CGFloat(value)
        default:
            return nil
        }
    }
}
