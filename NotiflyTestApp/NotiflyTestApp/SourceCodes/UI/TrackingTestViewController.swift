import Combine
@testable import notifly_ios_sdk
import UIKit

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
    }
    
    private func setupUI() {
        view.backgroundColor = .white
        title = "Test Tracking"
        setupStackView()
        
        eventNameTextField.placeholder = "Test Event Name"
        segmentationEventParamsTextField.placeholder = "Comma (',') Separated. e.g. 'value1, value2'"
        
        requestPayloadTextView.text = "N/A"
        responsePayloadTextView.text = "N/A"
        
        submitTrackingEventButton.addTarget(self, action: #selector(submitBtnTapped(sender:)), for: .touchUpInside)
        customEventParamsButton.addTarget(self, action: #selector(customEventParmsBtnTapped(sender:)), for: .touchUpInside)
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
        
        // StackView SubViews
        stackView.addInputView(labelText: "Event Name", textfield: eventNameTextField)
        stackView.addInputView(labelText: "Segmentation Events (Optional)", textfield: segmentationEventParamsTextField)
        stackView.addSwitchView(labelText: "Is Internal Event", switchView: isInternalEventSwitch)
        
        stackView.addCTAView(labelText: "Custom Event Params", button: customEventParamsButton, bgColor: .darkText)
        stackView.addCTAView(labelText: "Submit Event", button: submitTrackingEventButton, bgColor: .blue)
        
        stackView.addInfoView(labelText: "Request Payload", textView: requestPayloadTextView)
        stackView.addInfoView(labelText: "Response Payload", textView: responsePayloadTextView)
        
        stackView.addArrangedSubview(UIView())
    }
    
    func presentCustomEventParamsVS() {
        let keyValuePairsInputVC = KeyValueDataInputViewController(initialKeyValuePairs: customEventParams)
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
        
        // Inspect request payload
        let eventPub = Notifly.main.trackingManager.createTrackingEvent(name: eventName,
                                                                        isInternal: isInternalEventSwitch.isOn,
                                                                        eventParams: customEventParams,
                                                                        segmentationEventParamKeys: segmentationEventParamKeys)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        
        var cancellable = eventPub
            .encode(encoder: encoder)
            .map { String(data: $0, encoding: .utf8) ?? "Encoding Error" }
            .catch { Just("Failed to encode Event payload with error: \($0)") }
            .receive(on: RunLoop.main)
            .assign(to: \.text, on: requestPayloadTextView)
        cancellables.insert(cancellable)
        
        // Fire Tracking
        let trackingPub = Notifly.main.trackingManager.track(eventName: eventName,
                                                             isInternal: false,
                                                             params: customEventParams,
                                                             segmentationEventParamKeys: segmentationEventParamKeys)
        cancellable = trackingPub
            .catch { Just("Tracking Event Failed. Error: \($0)") }
            .receive(on: RunLoop.main)
            .sink { [weak self] resultingString in
                self?.responsePayloadTextView.text = resultingString
            }
        cancellables.insert(cancellable)
    }
    
    @objc
    private func customEventParmsBtnTapped(sender: UIButton) {
        presentCustomEventParamsVS()
    }
    
    @objc
    private func submitBtnTapped(sender: UIButton) {
        submitTrackingEventWithCurrentInputs()
    }
}

extension TrackingTestViewController: KeyValueDataInputViewControllerDelegate {
    func keyValueDataInputVCWilComplete(with keyPairs: [String : String]?) {
        customEventParams = keyPairs
    }
}
