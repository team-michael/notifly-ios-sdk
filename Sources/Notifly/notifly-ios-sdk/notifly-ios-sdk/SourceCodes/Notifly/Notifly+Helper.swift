//
//  Notifly+Helper.swift
//  notifly-ios-sdk
//
//  Created by 김대성 on 2023/10/17.
//

import Foundation

@available(iOSApplicationExtension, unavailable)
class NotiflyHelper {
    static func getSDKVersion() -> String? {
        return Notifly.sdkVersion
    }
    
    static func getSDKType() -> String {
        return Notifly.sdkType.rawValue
    }
}
