import Foundation
import NotiflyCore

/// Adapts the shared renderer's result to the existing iOS popup presentation path.
@available(iOSApplicationExtension, unavailable)
final class InAppMessageRenderer {
    private let renderer: PopupRenderer

    init(projectId: String, baseURL: String, sdkVersion: String) {
        renderer = PopupFactory.shared.create(config: PopupRendererConfig(
            projectId: projectId, baseUrl: baseURL, sdkVersion: sdkVersion))
    }

    /// Resolves popup content. Failures never load an unrendered template.
    func render(
        data: InAppMessageData, userID: String,
        completion: @escaping (InAppMessageContent?) -> Void
    ) {
        guard data.templateRenderingMode == "ssr" else {
            completion(.url(data.url))
            return
        }

        let input = PopupRenderInput(
            templateRenderingMode: data.templateRenderingMode,
            campaignId: data.notiflyCampaignId, notiflyUserId: userID,
            deviceId: data.deviceID, eventName: data.eventName, eventParams: data.eventParams)
        renderer.render(input: input) { output in
            switch output.outcome {
            case "static":
                completion(.url(data.url))
            case "rendered":
                completion(output.html.map { .html($0, baseURL: data.url) })
            default:
                if output.outcome == "failed" {
                    Logger.error("Popup rendering failed: \(output.errorCode ?? "unknown").")
                }
                completion(nil)
            }
        }
    }
}
