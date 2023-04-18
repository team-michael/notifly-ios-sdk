@testable import notifly_ios_sdk
import UIKit

class PushNotificationTestViewController: UIViewController {
    
    // MARK: UI Components

    let stackView = UIStackView()
    
    let titleTextField = UITextField()
    let bodyTextField = UITextField()
    let urlTextField = UITextField()
    let delayTextField = UITextField()
    
    let scheduleButton = UIButton()
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }
    
    // MARK: - Methods
    
    private func setup() {
        setupUI()
    }
    
    private func setupUI() {
        view.backgroundColor = .white
        title = "Test Push Notification"
        setupStackView()
        
        // Populate initial test values
        titleTextField.placeholder = "Title for the push notification"
        bodyTextField.placeholder = "Notification Message"
        
        urlTextField.placeholder = "URL to open for this notification"
        urlTextField.text = "https://docs.notifly.tech/ko/"
        urlTextField.keyboardType = .URL
        
        delayTextField.text = "3"
        delayTextField.keyboardType = .numberPad
        
        // Hookup CTAs
        scheduleButton.addTarget(self, action: #selector(scheduleBtnTapped(sender:)), for: .touchUpInside)
    }
    
    private func setupStackView() {
        // Setup StackView UI
        view.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.safeAreaLayoutGuide.topAnchor.constraint(equalTo: stackView.topAnchor),
            view.safeAreaLayoutGuide.bottomAnchor.constraint(equalTo: stackView.bottomAnchor),
            view.safeAreaLayoutGuide.leftAnchor.constraint(equalTo: stackView.leftAnchor, constant: -12),
            view.safeAreaLayoutGuide.rightAnchor.constraint(equalTo: stackView.rightAnchor, constant: 12)
        ])
        
        // StackView Config
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 6
        
        // StackView Subviews
        stackView.addInputView(labelText: "Title (Optional)", textfield: titleTextField)
        stackView.addInputView(labelText: "Body (Optional)", textfield: bodyTextField)
        stackView.addInputView(labelText: "URL", textfield: urlTextField)
        stackView.addInputView(labelText: "Seconds after to receive the push (Int only)", textfield: delayTextField)
        
        stackView.addSeparator(height: 24, color: .clear)
        stackView.addCTAView(labelText: "Schedule", button: scheduleButton, bgColor: .black)

        stackView.addArrangedSubview(UIView())
    }
    
    func scheduleNotificationWithCurrentIntputs() {
        guard let urlString = urlTextField.checkAndRetrieveValueText(),
              let delayString = delayTextField.checkAndRetrieveValueText() else {
            return
        }
        guard let url = URL(string: urlString) else {
            urlTextField.setToErrorUI()
            return
        }
        guard let delay = TimeInterval(delayString) else {
            delayTextField.setToErrorUI()
            return
        }
        
        let title = titleTextField.checkAndRetrieveValueText(changeBorderColorOnError: false)
        let body = bodyTextField.checkAndRetrieveValueText(changeBorderColorOnError: false)
        
        Notifly.schedulePushNotification(title: title,
                                         body: body,
                                         url: url,
                                         delay: delay)
    }
    
    @objc
    private func scheduleBtnTapped(sender: UIButton) {
        scheduleNotificationWithCurrentIntputs()
    }
}
