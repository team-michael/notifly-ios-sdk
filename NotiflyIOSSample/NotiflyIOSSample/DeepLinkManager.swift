import SwiftUI

class DeepLinkManager: ObservableObject {
    static let shared = DeepLinkManager()
    
    @Published var deepLinkParameters: [String: String]?
    
    private init() {}
    
    func handleDeepLink(_ url: URL) {
        print("DeepLinkManager - Received URL: \(url)")
        print("DeepLinkManager - URL Scheme: \(url.scheme ?? "nil")")
        print("DeepLinkManager - URL Host: \(url.host ?? "nil")")
        print("DeepLinkManager - URL Path: \(url.path)")
        print("DeepLinkManager - URL Query: \(url.query ?? "nil")")
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return }
        
        var parameters: [String: String] = [:]
        components.queryItems?.forEach { item in
            parameters[item.name] = item.value
        }
        
        if let name = parameters["name"],
           name.hasPrefix("deeplink") {
            DispatchQueue.main.async {
                self.deepLinkParameters = parameters
            }
        }
    }
} 