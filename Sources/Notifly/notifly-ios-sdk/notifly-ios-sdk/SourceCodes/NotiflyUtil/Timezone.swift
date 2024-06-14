//
//  Timezone.swift
//  notifly-ios-sdk
//
//  Created by Junha Park on 6/14/24.
//

import Foundation

class TimezoneUtil {
    static func getCurrentTimezoneId() -> String {
        return TimeZone.current.identifier
    }
    
    static func isValidTimezoneId(_ timezoneId: String) -> Bool {
        return TimeZone.knownTimeZoneIdentifiers.contains(timezoneId)
    }
}
