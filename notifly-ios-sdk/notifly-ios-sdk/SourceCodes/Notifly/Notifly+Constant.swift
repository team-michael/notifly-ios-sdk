//
//  Notifly+Constant.swift
//  notifly-ios-sdk
//
//  Created by 김대성 on 2023/06/27.
//

import Foundation

enum NotiflyConstant {
    static let sdkVersion: String = "1.0.6"
    enum EndPoint {
        static let trackEventEndPoint = "https://12lnng07q2.execute-api.ap-northeast-2.amazonaws.com/prod/records"
        static let syncStateEndPoint = "https://api.notifly.tech/user-state"
        static let authorizationEndPoint = "https://api.notifly.tech/authorize"
    }
}
