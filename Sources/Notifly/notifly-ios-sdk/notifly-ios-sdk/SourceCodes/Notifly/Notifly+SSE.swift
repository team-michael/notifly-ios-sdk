//
//  Notifly+SSE.swift
//  notifly-ios-sdk
//

import Combine
import Foundation
import UIKit

@available(iOSApplicationExtension, unavailable)
extension Notifly {

    func startSSE() {
        guard !Notifly.inAppMessageDisabled else { return }
        guard let notiflyUserId = try? userManager.getNotiflyUserID() else {
            Logger.info("SSE: skip start — no notifly user id yet")
            return
        }
        let deviceId = AppHelper.getNotiflyDeviceID()
        let auth = self.auth
        let userStateManager = inAppMessageManager.userStateManager
        let inAppMgr = inAppMessageManager

        let client = SSEClient(
            projectId: projectId,
            notiflyUserId: notiflyUserId,
            deviceId: deviceId,
            tokenProvider: { [weak auth] in
                guard let auth = auth else { throw NotiflyError.notInitialized }
                for try await token in auth.authorizationPub.first().values {
                    return token
                }
                throw NotiflyError.notAuthorized
            }
        )

        let controller = SSEController(
            sseClient: client,
            onSyncRequested: { [weak userStateManager] completion in
                guard let mgr = userStateManager else {
                    completion()
                    return
                }
                mgr.syncState(
                    postProcessConfig: PostProcessConfigForSyncState(merge: true, clear: false)
                ) {
                    completion()
                }
            },
            onServerEventTriggered: { [weak inAppMgr] name, params in
                inAppMgr?.mayTriggerInAppMessage(
                    eventName: name,
                    eventParams: params,
                    segmentationEventParamKeys: nil
                )
            }
        )

        sseController?.stop()
        sseController = controller
        controller.start()
    }

    func stopSSE() {
        sseController?.stop()
    }

    func restartSSE() {
        startSSE()
    }

    func registerSSELifecycleObservers() {
        let center = NotificationCenter.default
        center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.stopSSE()
        }
        center.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.startSSE()
        }
    }
}
