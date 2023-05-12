import Foundation
import WebKit
import UIKit

class WebViewModalViewController: UIViewController {
    
    private let webviewModalSize = CGSize(width: 350, height: 400)
    
    let webView = WKWebView()
    
    convenience init(url: URL?) throws {
        guard let url = url else {
            throw NotiflyError.unexpectedNil("URL is nil. Cannot create WebViewModalViewController.")
        }
        self.init(nibName: nil, bundle: nil)
        webView.load(URLRequest(url: url))
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    func setupUI() {
        view.backgroundColor = .clear
        view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.widthAnchor.constraint(equalToConstant: webviewModalSize.width),
            webView.heightAnchor.constraint(equalToConstant: webviewModalSize.height),
            view.centerXAnchor.constraint(equalTo: webView.centerXAnchor),
            view.centerYAnchor.constraint(equalTo: webView.centerYAnchor)
        ])
        
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissCTATapped)))
    }
    
    @objc
    private func dismissCTATapped() {
        dismiss(animated: true)
    }
}
