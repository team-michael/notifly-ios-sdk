//
//  NotiflyIOSSampleApp.swift
//  NotiflyIOSSample
//
//  Created by Minkyu Cho on 4/19/25.
//

import notifly_sdk
import SwiftUI

@main
struct NotiflyIOSSampleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
