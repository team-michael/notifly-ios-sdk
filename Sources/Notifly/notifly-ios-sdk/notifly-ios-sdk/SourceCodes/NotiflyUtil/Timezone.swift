//
//  File.swift
//  
//
//  Created by 박준하 on 6/14/24.
//

import Foundation

class TimezoneUtils {
    static func getCurrentTimezoneId() -> String {
        return TimeZone.current.identifier
    }
    
    static func isValidTimezoneId(_ timezoneId: String) -> Bool {
        return TimeZone.knownTimeZoneIdentifiers.contains(timezoneId)
    }
}
