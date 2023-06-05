# notifly-sdk 가이드 (iOS)

[![Version](https://img.shields.io/cocoapods/v/notifly_sdk.svg?style=flat)](https://cocoapods.org/pods/notifly_sdk)
[![License](https://img.shields.io/cocoapods/l/notifly_sdk.svg?style=flat)](https://cocoapods.org/pods/notifly_sdk)
[![Platform](https://img.shields.io/cocoapods/p/notifly_sdk.svg?style=flat)](https://cocoapods.org/pods/notifly_sdk)

## 앱에서 Notifly SDK 설치 하기

클라이언트 앱의 AppDelegate.swift 파일 에서 다음 코드들을 추가해 주세요.

`notifly_sdk` 프래임워크를 임포트 합니다.

```
import notifly_ios_sdk
```

다음 `UIApplicationDelegate` 함수들에 각각 코드를 추가해 주세요.

```
func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    '''
    // 여기서 프로젝트 아이디, 유저네임, 비밀번호를 본 앱의 정보로 바꿔주세요. 앱에서 따로 Push Notification 을 처리하는 경우 `useCustomClickHandler` 값을 `true` 로 바꿔주세요.
    Notifly.initialize(projectId: "<project id>", username: "<username>", password: "<password>")
    '''
}

func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    '''
    Notify.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    '''
}

func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    '''
    Notify.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
    '''
}

func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
    Notifly.application(application, didReceiveRemoteNotification: userInfo)
    completionHandler(.noData)
}
```

`UNUserNotificationCenterDelegate` 에서 노티피케이션 트래픽을 `Notifly` 에도 전달하기 위해 `UNUserNotificationCenterDelegate` 를 구현하는 클래스에서 다음 코드들을 추가해 주세요.

```
func userNotificationCenter(_ notificationCenter: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completion: () -> Void) {
    '''
    Notifly.userNotificationCenter(notificationCenter, didReceive: response)
    completion()
    '''
}

func userNotificationCenter(_ notificationCenter: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completion: (UNNotificationPresentationOptions) -> Void) {
    '''
    Notifly.userNotificationCenter(notificationCenter, willPresent: notification, withCompletionHandler: completion)
    '''
}
```

## 엡에서 Notifly 로 커스텀 트래킹 이벤트 보내기

트레킹 이벤트가 필요한곳에서 아래와 같이 `Notifly.track(eventName: , eventParams: , segmentationEventParamKeys: , userID: )` 함수를 호출 해주세요.

```
func someFunctionThatNeedsTracking() {
   '''
   let cancellable = Notifly.track(eventName: "<tracking event name>", eventParams: nil, segmentationEventParamKeys: nil, userID: nil)
   self.trackingCance
   '''
}
```
