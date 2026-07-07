import Foundation
import UIKit

/// 인앱 메시지 링크의 open mode 파싱, URL 정제, Universal Link 처리를 담당합니다.
enum NotiflyLinkHelper {

    // MARK: - Open Mode

    private static let openModeParam = "nf_open_mode"

    static func parseOpenMode(from url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == openModeParam })?.value
    }

    static func stripNotiflyParams(from url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return url }
        components.queryItems = components.queryItems?.filter { $0.name != openModeParam }
        if components.queryItems?.isEmpty == true { components.queryItems = nil }
        return components.url ?? url
    }

    // MARK: - Universal Link Detection

    private static let domainQueue = DispatchQueue(label: "tech.notifly.link-helper.domains")
    private static var _cachedAssociatedDomains: [String]?
    private static var _didLoadAssociatedDomains = false

    static func getAssociatedDomains() -> [String] {
        domainQueue.sync {
            if _didLoadAssociatedDomains {
                return _cachedAssociatedDomains ?? []
            }
            _didLoadAssociatedDomains = true

            var rawDomains: [String] = []

            if let execName = Bundle.main.infoDictionary?["CFBundleExecutable"] as? String,
               let execPath = Bundle.main.path(forResource: execName, ofType: nil),
               let entitlements = try? EntitlementsReader(execPath).readEntitlements(),
               let domains = entitlements["com.apple.developer.associated-domains"] as? [String]
            {
                rawDomains = domains
            }

            let hosts = rawDomains.compactMap { entry -> String? in
                let cleaned = entry.components(separatedBy: "?").first ?? entry
                guard cleaned.hasPrefix("applinks:") else { return nil }
                return String(cleaned.dropFirst("applinks:".count)).lowercased()
            }
            _cachedAssociatedDomains = hosts
            Logger.info("[Notifly] Associated domains: \(hosts)")
            return hosts
        }
    }

    static func isOwnUniversalLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = url.host?.lowercased()
        else { return false }
        let domains = getAssociatedDomains()
        let result = domains.contains { domain in
            if domain.hasPrefix("*.") {
                return host.hasSuffix(String(domain.dropFirst(1)))
            }
            return domain == host
        }
        Logger.info("[Notifly] isOwnUniversalLink: host=\(host), domains=\(domains), result=\(result)")
        return result
    }

    // MARK: - Universal Link Forwarding

    /// NSUserActivity를 생성하여 앱의 SceneDelegate 또는 AppDelegate로 직접 전달합니다.
    /// - Parameters:
    ///   - url: 전달할 Universal Link URL
    ///   - windowScene: 호출처의 windowScene. nil이면 foreground active scene을 탐색합니다.
    /// - Returns: delegate에 전달 성공 여부
    @available(iOSApplicationExtension, unavailable)
    @discardableResult
    static func openAsUniversalLink(_ url: URL, in windowScene: UIWindowScene? = nil) -> Bool {
        Logger.info("[Notifly] Opening as Universal Link via NSUserActivity: \(url)")
        let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        activity.webpageURL = url

        // 1) 명시적으로 전달받은 scene 사용
        if let scene = windowScene, let sceneDelegate = scene.delegate {
            Logger.info("[Notifly] Forwarding to SceneDelegate (explicit scene)")
            sceneDelegate.scene?(scene, continue: activity)
            return true
        }

        // 2) foreground active scene 탐색
        if let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
           let sceneDelegate = scene.delegate
        {
            Logger.info("[Notifly] Forwarding to SceneDelegate (active scene)")
            sceneDelegate.scene?(scene, continue: activity)
            return true
        }

        // 3) AppDelegate fallback
        if let appDelegate = UIApplication.shared.delegate {
            Logger.info("[Notifly] Forwarding to AppDelegate")
            _ = appDelegate.application?(
                UIApplication.shared,
                continue: activity,
                restorationHandler: { _ in }
            )
            return true
        }

        Logger.error("[Notifly] No delegate found to handle Universal Link")
        return false
    }
}
