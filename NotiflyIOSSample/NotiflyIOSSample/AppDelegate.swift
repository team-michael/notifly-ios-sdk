//
//  AppDelegate.swift
//  NotiflyIOSSample
//
//  Created by Minkyu Cho on 4/19/25.
//

import Firebase
import notifly_sdk
import UIKit
import UserNotifications

class AppDelegate: UIResponder, UIApplicationDelegate
{
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool
    {
        // 1. Firebase 초기화
        FirebaseApp.configure()
        
        // 2. 푸시 알림 권한 요청
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error = error {
                print("Failed to request authorization: \(error)")
                return
            }
            
            if granted {
                DispatchQueue.main.async {
                    // 3. APNs 등록
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
        
        // 4. Notifly 초기화
        Notifly.initialize(
            projectId: "b80c3f0e2fbd5eb986df4f1d32ea2871",
            username: "minyong",
            password: "000000"
        )
        
        // 5. UserNotificationCenter delegate 설정
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
        // APNs 토큰 로깅
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        print("APNs device token: \(token)")
        
        // Firebase Messaging에 APNs 토큰 설정
        Messaging.messaging().apnsToken = deviceToken
        
        // Notifly에 APNs 토큰 전달
        Notifly.application(application,
                            didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
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
