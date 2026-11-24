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

    static func getNativeSdkVersion() -> String {
        return NotiflySdkConfig.sdkVersion
    }

    static func getSdkWrapperVersion() -> String? {
        return NotiflySdkConfig.sdkWrapperVersion
    }

    static func getSdkVersion() -> String {
        return getSdkWrapperVersion() ?? getNativeSdkVersion()
    }

    static func getSdkWrapperType() -> String? {
        return NotiflySdkConfig.sdkWrapperType?.rawValue
    }

    static func getSdkType() -> String {
        return getSdkWrapperType() ?? NotiflySdkConfig.sdkType
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

    static func calculateHideUntil(
        reEligibleCondition: NotiflyReEligibleConditionEnum.ReEligibleCondition
    ) -> Int? {
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
        }
        else if let intNum = num as? Int {
            return intNum
        }
        return nil
    }

    static func testRegex(_ reference: String, regex: String) -> Bool {
        do {
            let regex = try NSRegularExpression(pattern: regex)
            let results = regex.firstMatch(
                in: reference,
                options: [],
                range: NSRange(reference.startIndex..., in: reference)
            )
            return results != nil
        }
        catch {
            Logger.info("Invalid regex pattern \(regex)")
            return false
        }
    }
}

@available(iOSApplicationExtension, unavailable)
enum NotiflyStringComparator {

    static func compare(reference: String, operator: NotiflyStringOperator, rhs: String) -> Bool {
        switch `operator` {
        case .equals:
            return reference == rhs
        case .notEquals:
            return reference != rhs
        case .startsWith:
            return reference.hasPrefix(rhs)
        case .doesNotStartWith:
            return !reference.hasPrefix(rhs)
        case .contains:
            return reference.contains(rhs)
        case .doesNotContain:
            return !reference.contains(rhs)
        case .endsWith:
            return reference.hasSuffix(rhs)
        case .doesNotEndWith:
            return !reference.hasSuffix(rhs)
        case .matchesRegex:
            return NotiflyHelper.testRegex(reference, regex: rhs)
        case .doesNotMatchRegex:
            return !NotiflyHelper.testRegex(reference, regex: rhs)
        }
    }
}
