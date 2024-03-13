import Combine

// @testable import notifly_ios_sdk

import UIKit

class MainViewController: UIViewController {

    // MARK: UI Components

    let stackView = UIStackView()

    let projectIDTextField = UITextField()
    let usernameTextField = UITextField()
    let passwordTextField = UITextField()
    let authorizeButton = UIButton()

    let authTokenTextView = UITextView()
    let pushTokenTextView = UITextView()

    let testTrackingButton = UIButton()
    let testPushNotificationButton = UIButton()
    let testUserSettingsButton = UIButton()

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }

    // MARK: = Methods

    func authorizeWithCurrentIntputs() {
        guard let projectID = projectIDTextField.checkAndRetrieveValueText(),
              let username = usernameTextField.checkAndRetrieveValueText(),
              let password = passwordTextField.checkAndRetrieveValueText()
        else {
            return
        }
    }

    func navigateToTestTrackingVC() {
        navigationController?.pushViewController(TrackingTestViewController(), animated: true)
    }

    func navigateToTestPushNotificationVC() {
        navigationController?.pushViewController(PushNotificationTestViewController(), animated: true)
    }

    func navigateToTestUserSettingsVC() {
        navigationController?.pushViewController(UserSettingsTestViewController(), animated: true)
    }

    private func setup() {
        setupUI()
        authorizeWithCurrentIntputs() // Initialize Notifly with default values.
    }

    private func setupUI() {
        view.backgroundColor = .white
        title = "Test Notifly"
        setupStackView()

        // Populate initial test values
        projectIDTextField.text = TestConstant.projectID
        usernameTextField.text = TestConstant.username
        passwordTextField.text = TestConstant.password

        authTokenTextView.text = "null"
        pushTokenTextView.text = "null"

        // Hookup CTAs
        authorizeButton.addTarget(self, action: #selector(authorizeBtnTapped(sender:)), for: .touchUpInside)
        testTrackingButton.addTarget(self, action: #selector(testTrackingBtnTapped(sender:)), for: .touchUpInside)
        testPushNotificationButton.addTarget(self, action: #selector(testPushNotificationBtnTapped(sender:)), for: .touchUpInside)
        testUserSettingsButton.addTarget(self, action: #selector(testUserSettingsBtnTapped(sender:)), for: .touchUpInside)
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
        stackView.addInputView(labelText: "Project ID", textfield: projectIDTextField)
        stackView.addInputView(labelText: "Username", textfield: usernameTextField)
        stackView.addInputView(labelText: "Password", textfield: passwordTextField)
        stackView.addCTAView(labelText: "Authorize", button: authorizeButton, bgColor: UIColor.blue)

        stackView.addInfoView(labelText: "Auth Token", textView: authTokenTextView)
        stackView.addInfoView(labelText: "Push Token", textView: pushTokenTextView)

        stackView.addCTAView(labelText: "Test Tracking Event", button: testTrackingButton, bgColor: .black)
        stackView.addCTAView(labelText: "Test Push Notification", button: testPushNotificationButton, bgColor: .black)
        stackView.addCTAView(labelText: "Test User Settings", button: testUserSettingsButton, bgColor: .black)

        stackView.addArrangedSubview(UIView())
    }

    @objc
    private func authorizeBtnTapped(sender: UIButton) {
        authorizeWithCurrentIntputs()
    }

    @objc
    private func testTrackingBtnTapped(sender: UIButton) {
        navigateToTestTrackingVC()
    }

    @objc
    private func testPushNotificationBtnTapped(sender: UIButton) {
        navigateToTestPushNotificationVC()
    }

    @objc
    private func testUserSettingsBtnTapped(sender: UIButton) {
        navigateToTestUserSettingsVC()
    }
}

extension MainViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 3
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell()
        cell.textLabel?.text = "Hello, World"
        return cell
    }

}

extension MainViewController: UITableViewDelegate {

}

