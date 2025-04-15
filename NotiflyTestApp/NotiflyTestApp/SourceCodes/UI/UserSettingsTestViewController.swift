import Combine
import Foundation
@testable import notifly_ios_sdk
import UIKit

class UserSettingsTestViewController: UIViewController {
    // MARK: Properties

    private var userProperties: [String: String]?

    // MARK: UI Components

    let stackView = UIStackView()
    let scrollView = UIScrollView()

    let userIDTextField = UITextField()
    let submitUserIDButton = UIButton()
    let userIDTrackingResponseTextView = UITextView()
    
    let phoneNumberTextField = UITextField()
    let submitPhoneNumberButton = UIButton()
    let phoneNumberSubmitResponseTextView = UITextView()
    
    let emailTextField = UITextField()
    let submitEmailButton = UIButton()
    let emailSubmitResponseTextView = UITextView()
    
    let timezoneTextField = UITextField()
    let submitTimezoneButton = UIButton()
    let timezoneSubmitResponseTextView = UITextView()

    let userPropertiesButton = UIButton()
    let submitUserPropertiesButton = UIButton()
    let userPropertiesResponseTextView = UITextView()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }

    // MARK: - Methods

    func submitUserIDTrackingEventWithCurrentInput() throws {
        let userID = userIDTextField.checkAndRetrieveValueText(changeBorderColorOnError: false)
        Notifly.setUserId(userId: userID)
        userIDTrackingResponseTextView.text = "User ID successfully set to: \(userID ?? "<null>")"
    }
    
    func submitPhoneNumberWithCurrentInput() throws {
        guard let phoneNumber = phoneNumberTextField.checkAndRetrieveValueText(changeBorderColorOnError: false) else {
            phoneNumberSubmitResponseTextView.text = "Please input phone number"
            return
        }
        Notifly.setPhoneNumber(phoneNumber)
        phoneNumberSubmitResponseTextView.text = "Phone Number successfully set to: \(phoneNumber)"
    }
    
    func submitEmailWithCurrentInput() throws {
        guard let email = emailTextField.checkAndRetrieveValueText(changeBorderColorOnError: false) else {
            emailSubmitResponseTextView.text = "Please input an email"
            return
        }
        Notifly.setEmail(email)
        emailSubmitResponseTextView.text = "Email successfully set to: \(email)"
    }
    
    func submitTimezoneWithCurrentInput() throws {
        guard let timezone = timezoneTextField.checkAndRetrieveValueText(changeBorderColorOnError: false) else {
            timezoneSubmitResponseTextView.text = "Please input an email"
            return
        }
        if !TimeZone.knownTimeZoneIdentifiers.contains(timezone) {
            timezoneSubmitResponseTextView.text = "Invalid timezone ID \(timezone). Please check your input"
            return
        }
        Notifly.setTimezone(timezone)
        timezoneSubmitResponseTextView.text = "Timezone successfully set to: \(timezone)"
    }

    func presentUserPropertiesVS() {
        let keyValuePairsInputVC = KeyValueDataInputViewController(initialKeyValuePairs: userProperties)
        keyValuePairsInputVC.delegate = self
        present(keyValuePairsInputVC, animated: true)
    }

    func submitUserPropertiesTrackingEventWithCurrentInputs() throws {
        if let userProperties = userProperties {
            Notifly.setUserProperties(userProperties: userProperties)
            userPropertiesResponseTextView.text = "User Properties submitted with following: \n\n\(userProperties)"
        } else {
            userPropertiesResponseTextView.text = "Aborted. Nothing to submit."
        }
    }

    private func setup() {
        setupUI()
    }

    private func setupUI() {
        view.backgroundColor = .black
        title = "Test User Settings"
        setupStackView()

        // Populate initial test values.

        userIDTextField.text = ""
        userIDTextField.placeholder = "User ID Value."

        // Hook up CTAs.
        submitUserIDButton.addTarget(self, action: #selector(submitUserIDBtnTapped(sender:)), for: .touchUpInside)
        submitPhoneNumberButton.addTarget(self, action: #selector(submitPhoneNumberBtnTapped(sender:)), for: .touchUpInside)
        submitEmailButton.addTarget(self, action: #selector(submitEmailBtnTapped(sender:)), for: .touchUpInside)
        submitTimezoneButton.addTarget(self, action: #selector(submitTimezoneBtnTapped(sender:)), for: .touchUpInside)
        
        userPropertiesButton.addTarget(self, action: #selector(configureUserPropertiesBtnTapped(sender:)), for: .touchUpInside)
        submitUserPropertiesButton.addTarget(self, action: #selector(submitUserPropertiesBtnTapped(sender:)), for: .touchUpInside)
    }

    private func setupStackView() {
        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.safeAreaLayoutGuide.topAnchor.constraint(equalTo: scrollView.topAnchor),
            view.safeAreaLayoutGuide.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            view.safeAreaLayoutGuide.leftAnchor.constraint(equalTo: scrollView.leftAnchor),
            view.safeAreaLayoutGuide.rightAnchor.constraint(equalTo: scrollView.rightAnchor)
        ])

        scrollView.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: stackView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: stackView.bottomAnchor),
            scrollView.leftAnchor.constraint(equalTo: stackView.leftAnchor),
            scrollView.rightAnchor.constraint(equalTo: stackView.rightAnchor),
            scrollView.widthAnchor.constraint(equalTo: stackView.widthAnchor)
        ])
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 6

        // StackView Subviews
        stackView.addInputView(labelText: "User ID (Optional)", textfield: userIDTextField)
        stackView.addCTAView(labelText: "Submit User ID", button: submitUserIDButton, bgColor: .blue)
        stackView.addInfoView(labelText: "Response", textView: userIDTrackingResponseTextView)
        
        stackView.addInputView(labelText: "Phone Number", textfield: phoneNumberTextField)
        stackView.addCTAView(labelText: "Submit Phone Number", button: submitPhoneNumberButton, bgColor: .blue)
        stackView.addInfoView(labelText: "Response", textView: phoneNumberSubmitResponseTextView)
        
        stackView.addInputView(labelText: "Email", textfield: emailTextField)
        stackView.addCTAView(labelText: "Submit Email", button: submitEmailButton, bgColor: .blue)
        stackView.addInfoView(labelText: "Response", textView: emailSubmitResponseTextView)
        
        stackView.addInputView(labelText: "Timezone", textfield: timezoneTextField)
        stackView.addCTAView(labelText: "Submit Timezone", button: submitTimezoneButton, bgColor: .blue)
        stackView.addInfoView(labelText: "Response", textView: timezoneSubmitResponseTextView)

        stackView.addSeparator(height: 5, color: .darkGray)

        stackView.addCTAView(labelText: "Configure User Properties", button: userPropertiesButton, bgColor: .black)
        stackView.addCTAView(labelText: "Submit User Properties", button: submitUserPropertiesButton, bgColor: .blue)
        stackView.addInfoView(labelText: "Response", textView: userPropertiesResponseTextView)

        stackView.addArrangedSubview(UIView())
    }

    @objc
    private func submitUserIDBtnTapped(sender _: UIButton) {
        try? submitUserIDTrackingEventWithCurrentInput()
    }
    
    @objc
    private func submitPhoneNumberBtnTapped(sender _: UIButton) {
        try? submitPhoneNumberWithCurrentInput()
    }
    
    @objc
    private func submitEmailBtnTapped(sender _: UIButton) {
        try? submitEmailWithCurrentInput()
    }
    
    @objc
    private func submitTimezoneBtnTapped(sender _: UIButton) {
        try? submitTimezoneWithCurrentInput()
    }

    @objc
    private func configureUserPropertiesBtnTapped(sender _: UIButton) {
        presentUserPropertiesVS()
    }

    @objc
    private func submitUserPropertiesBtnTapped(sender _: UIButton) {
        try? submitUserPropertiesTrackingEventWithCurrentInputs()
    }
}

extension UserSettingsTestViewController: KeyValueDataInputViewControllerDelegate {
    func keyValueDataInputVCWilComplete(with keyPairs: [String: String]?) {
        userProperties = keyPairs
    }
}
