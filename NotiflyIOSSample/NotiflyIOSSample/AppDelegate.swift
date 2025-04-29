//
//  AppDelegate.swift
//  NotiflyIOSSample
//
//  Created by Minkyu Cho on 4/19/25.
//

import Firebase
import notifly_sdk
import SwiftUI
import UIKit
import UserNotifications

class AppDelegate: UIResponder, UIApplicationDelegate
{
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool
    {
        FirebaseApp.configure()

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        { granted, error in
            if let error = error
            {
                print("Failed to request authorization: \(error)")
                return
            }

            if granted
            {
                DispatchQueue.main.async
                {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }

        Notifly.initialize(
            projectId: "b80c3f0e2fbd5eb986df4f1d32ea2871",
            username: "minyong",
            password: "000000"
        )
        Notifly.setUserId(userId: "sample")

        UNUserNotificationCenter.current().delegate = self

        return true
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error)
    {
        print("Failed to register for remote notifications: \(error)")
        Notifly.application(application,
                            didFailToRegisterForRemoteNotificationsWithError: error)
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data)
    {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        print("APNs device token: \(token)")

        Messaging.messaging().apnsToken = deviceToken

        Notifly.application(application,
                            didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool
    {
        if url.scheme == "pushnotiflyios"
        {
            DeepLinkManager.shared.handleDeepLink(url)
            return true
        }
        return false
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate
{
    func userNotificationCenter(_ notificationCenter: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completion: @escaping () -> Void)
    {
        Notifly.userNotificationCenter(notificationCenter,
                                       didReceive: response)
        completion()
    }

    func userNotificationCenter(_ notificationCenter: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completion: @escaping (UNNotificationPresentationOptions) -> Void)
    {
        Notifly.userNotificationCenter(notificationCenter,
                                       willPresent: notification,
                                       withCompletionHandler: completion)
    }
}
