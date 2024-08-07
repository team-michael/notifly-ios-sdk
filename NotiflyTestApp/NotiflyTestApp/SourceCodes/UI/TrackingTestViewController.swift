import Combine
import UIKit

@testable import notifly_ios_sdk

class TrackingTestViewController: UIViewController {
    // MARK: UI Components

    let stackView = UIStackView()

    let eventNameTextField = UITextField()
    let segmentationEventParamsTextField = UITextField()
    let isInternalEventSwitch = UISwitch()

    let customEventParamsButton = UIButton()
    let submitTrackingEventButton = UIButton()

    let requestPayloadTextView = UITextView()
    let responsePayloadTextView = UITextView()

    private var cancellables = Set<AnyCancellable>()
    private var customEventParams: [String: String]?

    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }

    private func setup() {
        setupUI()

        // Inspect request payload
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        try? Notifly.main.trackingManager.eventRequestPayloadPublisher
            .encode(encoder: encoder)
            .map {
                String(data: $0, encoding: .utf8) ?? "Encoding Error"
            }
            .catch {
                Just("Failed to encode Event payload with error: \($0)")
            }
            .receive(on: RunLoop.main)
            .assign(to: \.text, on: requestPayloadTextView)
            .store(in: &cancellables)

        // Inspect Response Payload.
        try? Notifly.main.trackingManager.eventRequestResponsePublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] resultingString in
                self?.responsePayloadTextView.text = resultingString
            }
            .store(in: &cancellables)
    }

    private func setupUI() {
        view.backgroundColor = .white
        title = "Test Tracking"
        setupStackView()

        eventNameTextField.placeholder = "Test Event Name"
        segmentationEventParamsTextField.placeholder =
            "Comma (',') Separated. e.g. 'value1, value2'"

        requestPayloadTextView.text = "N/A"
        responsePayloadTextView.text = "N/A"

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

        stackView.addInfoView(labelText: "Request Payload", textView: requestPayloadTextView)
        stackView.addInfoView(labelText: "Response Payload", textView: responsePayloadTextView)

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

        responsePayloadTextView.text = "N/A"

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

        try? Notifly.trackEvent(
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
