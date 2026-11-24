import Foundation
import UIKit
import WebKit

@available(iOSApplicationExtension, unavailable)
class WebViewModalViewController: UIViewController, WKNavigationDelegate, WKScriptMessageHandler,
    WKUIDelegate
{

    private static let openedInAppMessageCountAccessQueue = DispatchQueue(
        label: "com.notifly.openedInAppMessageCountQueue"
    )
    private static var _openedInAppMessageCount: Int = 0
    static var openedInAppMessageCount: Int {
        get {
            WebViewModalViewController.openedInAppMessageCountAccessQueue.sync {
                WebViewModalViewController._openedInAppMessageCount
            }
        }
        set {
            WebViewModalViewController.openedInAppMessageCountAccessQueue.sync {
                WebViewModalViewController._openedInAppMessageCount = newValue
            }
        }
    }

    var webView = FullScreenWKWebView()
    var notiflyCampaignID: String?
    var notiflyMessageID: String?
    var notiflyExtraData: [String: Any]?
    var notiflyReEligibleCondition: NotiflyReEligibleConditionEnum.ReEligibleCondition?
    var modalProps: ModalProperties?
    private var modalWidthConstraint: NSLayoutConstraint?
    private var modalHeightConstraint: NSLayoutConstraint?
    private var lastMaskSize: CGSize?

    convenience init(notiflyInAppMessageData: InAppMessageData, content: InAppMessageContent) throws {
        self.init(nibName: nil, bundle: nil)
        view.isHidden = false
        modalPresentationStyle = .overFullScreen
        notiflyCampaignID = notiflyInAppMessageData.notiflyCampaignId
        notiflyMessageID = notiflyInAppMessageData.notiflyMessageId
        notiflyReEligibleCondition = notiflyInAppMessageData.notiflyReEligibleCondition
        modalProps = notiflyInAppMessageData.modalProps
        if case let .url(url) = content, !UIApplication.shared.canOpenURL(url) {
            Logger.error("Fail to load in app message: invalid url.")
            throw NotiflyError.unexpectedNil(
                "Fail to load in app message: invalid url or Network issue."
            )
        }
        DispatchQueue.main.async { [weak self] in
            self?.loadContent(content)
        }
    }

    /// Keeps the original URL as the base for relative assets in rendered HTML.
    func loadContent(_ content: InAppMessageContent) {
        switch content {
        case let .url(url):
            webView.load(URLRequest(url: url))
        case let .html(html, baseURL):
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        webView.navigationDelegate = self
        webView.configuration.userContentController.add(
            self,
            name: "notiflyInAppMessageEventHandler"
        )
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed else { return }
        WebViewModalViewController.openedInAppMessageCount = 0
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        guard view.window != nil else { return }
        updateModalSize(containerSize: view.bounds.size)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard view.window != nil,
            modalWidthConstraint != nil,
            modalHeightConstraint != nil
        else { return }
        updateWebViewMaskIfNeeded()
    }

    func setupUI() -> Bool {
        let initialSize =
            keyWindow?.bounds.size
            ?? UIScreen.main.bounds.size
        guard let modalSize = getModalSize(in: initialSize) else {
            return false
        }
        let webViewLayer = getWebViewLayer(modalSize: modalSize)
        let modalPositionConstraint = getModalPositionConstraint() as NSLayoutConstraint

        webView.translatesAutoresizingMaskIntoConstraints = false
        let opacity = (modalProps?.backgroundOpacity as? CGFloat).map { max(0, min(1, $0)) } ?? 0.2
        view.backgroundColor = UIColor.black.withAlphaComponent(opacity)

        webView.layer.mask = webViewLayer

        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear

        if let backgroundColorString = modalProps?.backgroundColor as? String,
            let backgroundColor = UIColor(hex: backgroundColorString)
        {
            webView.scrollView.backgroundColor = backgroundColor
        }

        if let shouldDismissCTATapped = modalProps?.dismissCTATapped,
            shouldDismissCTATapped
        {
            view.addGestureRecognizer(
                UITapGestureRecognizer(target: self, action: #selector(dismissCTATapped))
            )
        }

        view.addSubview(webView)
        let width = webView.widthAnchor.constraint(equalToConstant: modalSize.width)
        let height = webView.heightAnchor.constraint(equalToConstant: modalSize.height)
        modalWidthConstraint = width
        modalHeightConstraint = height
        NSLayoutConstraint.activate([
            width,
            height,
            view.centerXAnchor.constraint(equalTo: webView.centerXAnchor),
            modalPositionConstraint
        ])
        let shown = show()
        return shown
    }

    func show(animated: Bool = false, completion _: (() -> Void)? = nil) -> Bool {
        DispatchQueue.main.async {
            guard let window = self.keyWindow,
                let topVC = WebViewModalPresentation.topMostViewController(in: window),
                !(self.isBeingPresented),
                !(self.isBeingDismissed),
                self.presentingViewController == nil
            else {
                WebViewModalViewController.openedInAppMessageCount = 0
                Logger.error("Fail to present in app message.")
                return
            }
            self.updateModalSize(containerSize: window.bounds.size)
            topVC.present(self, animated: animated)
        }
        return true
    }

    @objc
    private func dismissCTATapped() {
        dismiss(animated: false)
    }
}

@available(iOSApplicationExtension, unavailable)
private extension WebViewModalViewController {

    var keyWindow: UIWindow? {
        if let window = viewIfLoaded?.window, window.isKeyWindow {
            return window
        }
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        {
            return window
        }
        // Apps using the application-delegate lifecycle may have no connected scenes.
        let window = UIApplication.shared.delegate?.window ?? nil
        return window?.isKeyWindow == true ? window : nil
    }

    func getModalSize(in screenSize: CGSize) -> CGSize? {
        let screenWidth = screenSize.width
        let screenHeight = screenSize.height
        if screenWidth == 0 || screenHeight == 0 {
            return nil
        }

        return CGSize(
            width: getModalWidth(screenWidth: screenWidth, screenHeight: screenHeight),
            height: getModalHeight(screenWidth: screenWidth, screenHeight: screenHeight)
        )
    }

    func getModalWidth(screenWidth: CGFloat, screenHeight: CGFloat) -> CGFloat {
        var viewWidth: CGFloat = 0.0
        if let width = modalProps?.width {
            viewWidth = width
        }
        else if let widthVW = modalProps?.width_vw {
            viewWidth = screenWidth * (widthVW / 100)
        }
        else if let widthVH = modalProps?.width_vh, screenHeight != 0.0 {
            viewWidth = screenHeight * (widthVH / 100)
        }
        else {
            viewWidth = screenWidth
        }

        if let minWidth = modalProps?.min_width, viewWidth < minWidth {
            viewWidth = minWidth
        }
        if let maxWidth = modalProps?.max_width, viewWidth > maxWidth {
            viewWidth = maxWidth
        }

        return viewWidth
    }

    func getModalHeight(screenWidth: CGFloat, screenHeight: CGFloat) -> CGFloat {
        var viewHeight: CGFloat = 0.0
        if let height = modalProps?.height {
            viewHeight = height
        }
        else if let heightVH = modalProps?.height_vh {
            viewHeight = screenHeight * (heightVH / 100)
        }
        else if let heightVW = modalProps?.height_vw, screenWidth != 0.0 {
            viewHeight = screenWidth * (heightVW / 100)
        }
        else {
            viewHeight = screenHeight
        }

        if let minHeight = modalProps?.min_height, viewHeight < minHeight {
            viewHeight = minHeight
        }
        if let maxHeight = modalProps?.max_height, viewHeight > maxHeight {
            viewHeight = maxHeight
        }

        return viewHeight
    }

    func getModalPositionConstraint() -> NSLayoutConstraint {
        if modalProps?.position == "bottom" {
            return view.bottomAnchor.constraint(equalTo: webView.bottomAnchor)
        }

        return view.centerYAnchor.constraint(equalTo: webView.centerYAnchor)
    }

    func getWebViewLayer(modalSize: CGSize) -> CALayer? {
        guard let modalProps = modalProps,
            let tlRadius = modalProps.borderTopLeftRadius,
            let trRadius = modalProps.borderTopRightRadius,
            let blRadius = modalProps.borderBottomLeftRadius,
            let brRadius = modalProps.borderBottomRightRadius
        else {
            return nil
        }

        let path = UIBezierPath()
        path.move(to: CGPoint(x: tlRadius, y: 0))
        path.addLine(to: CGPoint(x: modalSize.width - trRadius, y: 0))
        path.addArc(
            withCenter: CGPoint(x: modalSize.width - trRadius, y: trRadius),
            radius: trRadius,
            startAngle: -CGFloat.pi / 2,
            endAngle: 0,
            clockwise: true
        )
        path.addLine(to: CGPoint(x: modalSize.width, y: modalSize.height - brRadius))
        path.addArc(
            withCenter: CGPoint(x: modalSize.width - brRadius, y: modalSize.height - brRadius),
            radius: brRadius,
            startAngle: 0,
            endAngle: CGFloat.pi / 2,
            clockwise: true
        )
        path.addLine(to: CGPoint(x: blRadius, y: modalSize.height))
        path.addArc(
            withCenter: CGPoint(x: blRadius, y: modalSize.height - blRadius),
            radius: blRadius,
            startAngle: CGFloat.pi / 2,
            endAngle: CGFloat.pi,
            clockwise: true
        )
        path.addLine(to: CGPoint(x: 0, y: tlRadius))
        path.addArc(
            withCenter: CGPoint(x: tlRadius, y: tlRadius),
            radius: tlRadius,
            startAngle: CGFloat.pi,
            endAngle: -CGFloat.pi / 2,
            clockwise: true
        )
        path.close()

        let maskLayer = CAShapeLayer()
        maskLayer.path = path.cgPath
        return maskLayer
    }

    func updateModalSize(containerSize: CGSize) {
        guard containerSize.width.isFinite,
            containerSize.height.isFinite,
            containerSize.width > 0,
            containerSize.height > 0,
            let width = modalWidthConstraint,
            let height = modalHeightConstraint,
            let size = getModalSize(in: containerSize)
        else { return }

        if width.constant != size.width { width.constant = size.width }
        if height.constant != size.height { height.constant = size.height }
    }

    func updateWebViewMaskIfNeeded() {
        let size = webView.bounds.size
        guard size.width.isFinite,
            size.height.isFinite,
            size.width > 0,
            size.height > 0,
            size != lastMaskSize
        else { return }

        let calculatedMask = getWebViewLayer(modalSize: size) as? CAShapeLayer
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let calculatedMask = calculatedMask {
            let mask = (webView.layer.mask as? CAShapeLayer) ?? calculatedMask
            mask.frame = CGRect(origin: .zero, size: size)
            mask.path = calculatedMask.path
            webView.layer.mask = mask
        }
        else {
            webView.layer.mask = nil
        }
        CATransaction.commit()
        lastMaskSize = size
    }
}

private extension UIColor {

    convenience init?(hex: String) {
        let r, g, b, a: CGFloat

        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgba: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgba)

        switch hexSanitized.count {
        case 3:
            r = CGFloat((rgba >> 8) & 0xF) / 15.0
            g = CGFloat((rgba >> 4) & 0xF) / 15.0
            b = CGFloat(rgba & 0xF) / 15.0
            a = 1.0
        case 4:
            r = CGFloat((rgba >> 8) & 0xF) / 15.0
            g = CGFloat((rgba >> 4) & 0xF) / 15.0
            b = CGFloat(rgba & 0xF) / 15.0
            a = CGFloat((rgba >> 12) & 0xF) / 15.0
        case 6:
            r = CGFloat((rgba >> 16) & 0xFF) / 255.0
            g = CGFloat((rgba >> 8) & 0xFF) / 255.0
            b = CGFloat(rgba & 0xFF) / 255.0
            a = 1.0
        case 8:
            r = CGFloat((rgba >> 16) & 0xFF) / 255.0
            g = CGFloat((rgba >> 8) & 0xFF) / 255.0
            b = CGFloat(rgba & 0xFF) / 255.0
            a = CGFloat((rgba >> 24) & 0xFF) / 255.0
        default:
            return nil
        }

        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
