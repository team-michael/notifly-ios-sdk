import notifly_ios_sdk
import UIKit

class TrackingTestViewController: UIViewController {
    // MARK: UI Components

    let stackView = UIStackView()

    let eventNameTextField = UITextField()
    let segmentationEventParamsTextField = UITextField()
    let isInternalEventSwitch = UISwitch()

    let customEventParamsButton = UIButton()
    let submitTrackingEventButton = UIButton()

    private var customEventParams: [String: String]?

    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }

    private func setup() {
        setupUI()
    }

    private func setupUI() {
        view.backgroundColor = .white
        title = "Test Tracking"
        setupStackView()

        eventNameTextField.placeholder = "Test Event Name"
        segmentationEventParamsTextField.placeholder =
            "Comma (',') Separated. e.g. 'value1, value2'"

        submitTrackingEventButton.addTarget(
            self, action: #selector(submitBtnTapped(sender:)), for: .touchUpInside)
        customEventParamsButton.addTarget(
            self, action: #selector(customEventParmsBtnTapped(sender:)), for: .touchUpInside)
    }

    private func setupStackView() {
        // Setup StackView UI
        view.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.safeAreaLayoutGuide.topAnchor.constraint(equalTo: stackView.topAnchor),
            view.safeAreaLayoutGuide.bottomAnchor.constraint(equalTo: stackView.bottomAnchor),
            view.safeAreaLayoutGuide.leftAnchor.constraint(
                equalTo: stackView.leftAnchor, constant: -12),
            view.safeAreaLayoutGuide.rightAnchor.constraint(
                equalTo: stackView.rightAnchor, constant: 12)
        ])

        // StackView Config
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 6

        // StackView SubViews
        stackView.addInputView(labelText: "Event Name", textfield: eventNameTextField)
        stackView.addInputView(
            labelText: "Segmentation Events (Optional)", textfield: segmentationEventParamsTextField
        )
        stackView.addSwitchView(labelText: "Is Internal Event", switchView: isInternalEventSwitch)

        stackView.addCTAView(
            labelText: "Custom Event Params", button: customEventParamsButton, bgColor: .darkText)
        stackView.addCTAView(
            labelText: "Queue Tracking Event", button: submitTrackingEventButton, bgColor: .blue)

        stackView.addArrangedSubview(UIView())
    }

    func presentCustomEventParamsVS() {
        let keyValuePairsInputVC = KeyValueDataInputViewController(
            initialKeyValuePairs: customEventParams)
        keyValuePairsInputVC.delegate = self
        present(keyValuePairsInputVC, animated: true)
    }

    func submitTrackingEventWithCurrentInputs() {
        // Parse Inputs
        guard let eventName = eventNameTextField.checkAndRetrieveValueText() else {
            return
        }
        let segmentationEventParamKeys = segmentationEventParamsTextField.text?
            .split(separator: ",")
            .map(String.init)

        // let wrongGroup = DispatchGroup()
        // let wrongQueue = DispatchQueue(label: "WrongQueue")
        // for i in 0 ..< 30 {
        //     wrongGroup.enter()
        //     wrongQueue.async {
        //         Notifly.setUserId(userId: nil)
        //         Notifly.setUserId(userId: "WrongUserID\(i)")
        //         Notifly.trackEvent(eventName: "WrongEvent\(i)")
        //         Notifly.setUserId(userId: nil)
        //         wrongGroup.leave()
        //     }
        // }
        // wrongGroup.wait()

        Notifly.trackEvent(
            eventName: eventName,
            eventParams: customEventParams,
            segmentationEventParamKeys: segmentationEventParamKeys)
    }

    @objc
    private func customEventParmsBtnTapped(sender _: UIButton) {
        presentCustomEventParamsVS()
    }

    @objc
    private func submitBtnTapped(sender _: UIButton) {
        submitTrackingEventWithCurrentInputs()
    }
}

extension TrackingTestViewController: KeyValueDataInputViewControllerDelegate {
    func keyValueDataInputVCWilComplete(with keyPairs: [String: String]?) {
        customEventParams = keyPairs
    }
}
