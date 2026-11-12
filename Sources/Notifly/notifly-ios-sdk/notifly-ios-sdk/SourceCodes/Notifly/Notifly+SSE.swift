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
        let current: SSEController? = sseAccessQueue.sync {
            guard !_sseInvalidated else { return nil }
            if let existing = _sseController { return existing }
            guard let notiflyUserId = try? userManager.getNotiflyUserID() else {
                Logger.info("SSE: skip start — no notifly user id yet")
                return nil
            }
            // Snapshot the user and install its controller atomically with restart/teardown.
            let controller = makeSSEController(notiflyUserId: notiflyUserId)
            _sseController = controller
            return controller
        }
        // Starting can synchronously check UIApplication on the main queue.
        current?.start()
    }

    private func makeSSEController(notiflyUserId: String) -> SSEController {
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
                return try await Notifly.fetchAuthorizationToken(auth: auth)
            }
        )

        return SSEController(
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
            },
            canConnect: { Notifly.isApplicationInForeground() }
        )

    }

    func stopSSE() {
        let current: SSEController? = sseAccessQueue.sync { _sseController }
        current?.stop()
    }

    /// Permanently retire SSE before replacing this SDK instance.
    func invalidateSSE() {
        let current: SSEController? = sseAccessQueue.sync {
            _sseInvalidated = true
            let controller = _sseController
            _sseController = nil
            return controller
        }
        current?.invalidate()
        unregisterSSELifecycleObservers()
    }

    func restartSSE() {
        let previous: SSEController? = sseAccessQueue.sync {
            let c = _sseController
            _sseController = nil
            return c
        }
        previous?.invalidate()
        startSSE()
    }

    func registerSSELifecycleObservers() {
        sseAccessQueue.sync {
            guard !_sseInvalidated, !_sseObserversRegistered else { return }
            _sseObserversRegistered = true

            let center = NotificationCenter.default
            let bgToken = center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.stopSSE()
            }
            let fgToken = center.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.startSSE()
            }
            _sseLifecycleObserverTokens = [bgToken, fgToken]
        }
    }

    func unregisterSSELifecycleObservers() {
        let tokens: [NSObjectProtocol] = sseAccessQueue.sync {
            let t = _sseLifecycleObserverTokens
            _sseLifecycleObserverTokens = []
            _sseObserversRegistered = false
            return t
        }
        let center = NotificationCenter.default
        for token in tokens {
            center.removeObserver(token)
        }
    }

    private static func isApplicationInForeground() -> Bool {
        if Thread.isMainThread {
            return UIApplication.shared.applicationState != .background
        }
        return DispatchQueue.main.sync {
            UIApplication.shared.applicationState != .background
        }
    }

    private static func fetchAuthorizationToken(auth: Auth) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                for try await token in auth.authorizationPub.first().values {
                    return token
                }
                throw NotiflyError.notAuthorized
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 10_000_000_000)
                throw NotiflyError.notAuthorized
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw NotiflyError.notAuthorized
            }
            return first
        }
    }
}
