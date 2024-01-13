//
//  Notifly+Helper.swift
//  notifly-ios-sdk
//
//  Created by 김대성 on 2023/10/17.
//

import Foundation

@available(iOSApplicationExtension, unavailable)
enum NotiflyHelper {
    static func getEventName(event: String, isInternalEvent: Bool) -> String {
        return isInternalEvent ? "notifly__" + event : event
    }

    static func getSDKVersion() -> String? {
        return Notifly.sdkVersion
    }

    static func getSDKType() -> String {
        return Notifly.sdkType.rawValue
    }

    static func getDateStringBeforeNDays(n: Int?) -> String? {
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

    static func getCurrentDate() -> String {
        let currentDate = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.string(from: currentDate)
    }

    static func calculateHideUntil(reEligibleCondition: NotiflyReEligibleConditionEnum.ReEligibleCondition) -> Int? {
        let now = AppHelper.getCurrentTimestamp(unit: .second)
        switch NotiflyReEligibleConditionEnum.Unit(rawValue: reEligibleCondition.unit) {
        case .infinite:
            return -1
        case .hour:
            return now + reEligibleCondition.value * TimeConstant.oneHourInSeconds
        case .day:
            return now + reEligibleCondition.value * TimeConstant.oneDayInSeconds
        case .week:
            return now + reEligibleCondition.value * TimeConstant.oneWeekInSeconds
        case .month:
            return now + reEligibleCondition.value * TimeConstant.oneMonthInSeconds
        default:
            return nil
        }
    }
    
    static func parseRandomBucketNumber(num: Any?) -> Int? {
        if let str = num as? String {
            return Int(str)
        } else if let intNum = num as? Int {
            return intNum
        }
        return nil
        
    }
}

enum NotiflyComparingValueHelper {
    static func compare(type: String?, sourceValue: Any, operator: NotiflyOperator, targetValue: Any?) -> Bool {
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
               let typedSourceValue = NotiflyComparingValueHelper.castAnyToSpecifiedType(value: sourceValue, type: `operator` == .contains ? "ARRAY" : type),
               let typedTargetValue = NotiflyComparingValueHelper.castAnyToSpecifiedType(value: targetValue, type: type)
            {
                switch `operator` {
                case .equal:
                    return NotiflyComparingValueHelper.isEqual(value1: typedSourceValue, value2: typedTargetValue, type: type)
                case .notEqual:
                    return NotiflyComparingValueHelper.isNotEqual(value1: typedSourceValue, value2: typedTargetValue, type: type)
                case .contains:
                    return NotiflyComparingValueHelper.isContains(value1: typedSourceValue, value2: typedTargetValue, type: type)
                case .greaterThan:
                    return NotiflyComparingValueHelper.isGreaterThan(value1: typedSourceValue, value2: typedTargetValue, type: type)
                case .greaterOrEqualThan:
                    return NotiflyComparingValueHelper.isGreaterOrEqualThan(value1: typedSourceValue, value2: typedTargetValue, type: type)
                case .lessThan:
                    return NotiflyComparingValueHelper.isLessThan(value1: typedSourceValue, value2: typedTargetValue, type: type)
                case .lessOrEqualThan:
                    return NotiflyComparingValueHelper.isLessOrEqualThan(value1: typedSourceValue, value2: typedTargetValue, type: type)
                default:
                    return false
                }
            }
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

    static func isContains(value1: Any, value2: Any, type: String) -> Bool {
        guard let array = value1 as? [Any] else {
            return false
        }
        for element in array {
            if NotiflyComparingValueHelper.isEqual(value1: element, value2: value2, type: type) {
                return true
            }
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
        case (_, _):
            return nil
        }
    }
}
