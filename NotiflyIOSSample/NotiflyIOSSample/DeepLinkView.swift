import SafariServices
import SwiftUI

struct DeepLinkView: View, Identifiable {
    let id = UUID()
    let parameters: [String: String]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack {
            Text("Deep Link Page")
                .font(.title)
                .padding()
            
            ForEach(parameters.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                HStack {
                    Text(key)
                        .font(.headline)
                    Text(value)
                        .font(.body)
                }
                .padding(.horizontal)
            }
            
            Button("Close") {
                dismiss()
            }
            .padding()
        }
        .onAppear {
            handleDeepLink()
        }
    }
    
    private func handleDeepLink() {
        guard let name = parameters["name"] else { return }
        
        switch name {
        case "deeplink":
            if let targetURL = URL(string: "https://notifly.tech") {
                UIApplication.shared.open(targetURL)
            }
        case "deeplink_present":
            if let targetURL = URL(string: "https://notifly.tech") {
                presentURL(targetURL)
            }
        default:
            break
        }
    }
    
    private func presentURL(_ url: URL) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else { return }
        
        let safariVC = SFSafariViewController(url: url)
        rootViewController.present(safariVC, animated: true)
    }
}
