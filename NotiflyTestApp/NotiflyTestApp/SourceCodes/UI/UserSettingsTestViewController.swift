import Combine
import Foundation
@testable import notifly_ios_sdk
import UIKit

class UserSettingsTestViewController: UIViewController {
    
    // MARK: Properties
    
    private var userProperties: [String: String]?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: UI Components

    let stackView = UIStackView()
    
    let userIDTextField = UITextField()
    let submitUserIDButton = UIButton()
    let userIDTrackingResponseTextView = UITextView()
    
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
        let cancellable = try Notifly.main.userManager.setExternalUserID(userID)
            .catch { Just("Failed with error: \($0)") }
            .receive(on: RunLoop.main)
            .assign(to: \.text, on: userIDTrackingResponseTextView)
        cancellables.insert(cancellable)
    }
    
    func presentUserPropertiesVS() {
        let keyValuePairsInputVC = KeyValueDataInputViewController(initialKeyValuePairs: userProperties)
        keyValuePairsInputVC.delegate = self
        present(keyValuePairsInputVC, animated: true)
    }
    
    func submitUserPropertiesTrackingEventWithCurrentInputs() throws {
        if let userProperties = userProperties {
            let cancellable = try Notifly.main.userManager.setUserProperties(userProperties)
                .catch { Just("Failed with error: \($0)") }
                .receive(on: RunLoop.main)
                .assign(to: \.text, on: userPropertiesResponseTextView)
            cancellables.insert(cancellable)
        } else {
            userPropertiesResponseTextView.text = "Aborted. Nothing to submit."
        }
    }
    
    private func setup() {
        setupUI()
    }
    
    private func setupUI() {
        view.backgroundColor = .white
        title = "Test User Settings"
        setupStackView()
        
        // Populate initial test values.
        userIDTextField.text = Notifly.main.userManager.externalUserID
        userIDTextField.placeholder = "User ID Value."
        
        // Hook up CTAs.
        submitUserIDButton.addTarget(self, action: #selector(submitUserIDBtnTapped(sender:)), for: .touchUpInside)
        userPropertiesButton.addTarget(self, action: #selector(configureUserPropertiesBtnTapped(sender:)), for: .touchUpInside)
        submitUserPropertiesButton.addTarget(self, action: #selector(submitUserPropertiesBtnTapped(sender:)), for: .touchUpInside)
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
        stackView.addInputView(labelText: "User ID (Optional)", textfield: userIDTextField)
        stackView.addCTAView(labelText: "Submit User ID", button: submitUserIDButton, bgColor: .blue)
        stackView.addInfoView(labelText: "Response", textView: userIDTrackingResponseTextView)
        
        stackView.addSeparator(height: 5, color: .darkGray)
        
        stackView.addCTAView(labelText: "Configure User Properties", button: userPropertiesButton, bgColor: .black)
        stackView.addCTAView(labelText: "Submit User Properties", button: submitUserPropertiesButton, bgColor: .blue)
        stackView.addInfoView(labelText: "Response", textView: userPropertiesResponseTextView)

        stackView.addArrangedSubview(UIView())
    }
    
    @objc
    private func submitUserIDBtnTapped(sender: UIButton) {
        try? submitUserIDTrackingEventWithCurrentInput()
    }
    
    @objc
    private func configureUserPropertiesBtnTapped(sender: UIButton) {
        presentUserPropertiesVS()
    }
    
    @objc
    private func submitUserPropertiesBtnTapped(sender: UIButton) {
        try? submitUserPropertiesTrackingEventWithCurrentInputs()
    }
}

extension UserSettingsTestViewController: KeyValueDataInputViewControllerDelegate {

    func keyValueDataInputVCWilComplete(with keyPairs: [String : String]?) {
        userProperties = keyPairs
    }
}
