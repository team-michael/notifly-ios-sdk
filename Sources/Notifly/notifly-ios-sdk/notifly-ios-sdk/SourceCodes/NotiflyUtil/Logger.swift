//
//  Logger.swift
//  notifly-ios-sdk
//
//  Created by Juyong Kim on 4/17/23.
//

import Foundation

class Logger {

    enum Level {
        case info
        case error
    }

    static func info(_ msg: String) {
        print("[Notifly Info] ", msg)
    }

    static func warning(_ msg: String) {
        print("[Notifly Warning] ", msg)
    }

    static func error(_ msg: String) {
        print("🔥 [Notifly Error] ", msg)
    }

    private init() {}
}
