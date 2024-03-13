import UIKit

typealias KeyValue = (key: String, value: String)

@objc protocol KeyValueDataInputViewControllerDelegate {
    func keyValueDataInputVCWilComplete(with keyPairs: [String: String]?)
}

class KeyValueDataInputViewController: UIViewController {

    // MARK: - Constants
    private let rightLeftPadding: CGFloat = 12

    // MARK: - Properties

    weak var delegate: KeyValueDataInputViewControllerDelegate?

    private let scrollView = UIScrollView()
    private let keyPairStackView = UIStackView()
    private let ctaStackView = UIStackView()
    private let addKeyValueButton = UIButton()
    private let saveButton = UIButton()

    private let initialKeyValuePairs: [String: String]?
    private var keyPairInputViews: [SingleKeyValueInputView] = []

    // MARK: - Lifecycle

    init(initialKeyValuePairs: [String: String]?) {
        self.initialKeyValuePairs = initialKeyValuePairs
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }

    // MARK: Methods

    func addKeyValueInputToStackView(with keyValuePair: KeyValue?) {
        let keyPairInputView = SingleKeyValueInputView(keyValue: keyValuePair, order: keyPairInputViews.count + 1)
        keyPairInputViews.append(keyPairInputView)

        keyPairStackView.addSeparator()
        keyPairStackView.addArrangedSubview(keyPairInputView)

        var contentSize = scrollView.contentSize
        contentSize.height = CGFloat((keyPairInputViews.count + 1) * 110)
        scrollView.contentSize = contentSize

        keyPairStackView.widthAnchor.constraint(equalTo: keyPairInputView.widthAnchor).isActive = true
    }

    func saveAndDismiss() throws {
        var newKeyValuePairs = [String: String]()
        try keyPairInputViews.forEach { view in
            if let pair = try view.getCurrentKeyValue() {
                newKeyValuePairs[pair.key] = pair.value
            }
        }
        delegate?.keyValueDataInputVCWilComplete(with: newKeyValuePairs.isEmpty ? nil : newKeyValuePairs)
        dismiss(animated: true)
    }

    private func setup() {
        setupUI()
    }

    private func setupUI() {
        view.backgroundColor = .white
        setupScrollView()
        setupStackView()

        addKeyValueButton.addTarget(self, action: #selector(addKeyValueBtnTapped(sender:)), for: .touchUpInside)
        saveButton.addTarget(self, action: #selector(saveBtnTapped(sender:)), for: .touchUpInside)
    }

    private func setupScrollView() {
        scrollView.contentSize = CGSize(width: 320, height: 500)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.isDirectionalLockEnabled = true
        scrollView.bounces = false
        scrollView.addSubview(keyPairStackView)
        scrollView.addSubview(ctaStackView)

        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
                                        view.safeAreaLayoutGuide.topAnchor.constraint(equalTo: scrollView.topAnchor),
                                        view.safeAreaLayoutGuide.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
                                        view.safeAreaLayoutGuide.leftAnchor.constraint(equalTo: scrollView.leftAnchor, constant: -rightLeftPadding),
                                        view.safeAreaLayoutGuide.rightAnchor.constraint(equalTo: scrollView.rightAnchor, constant: rightLeftPadding),
                                    ])
    }

    private func setupStackView() {

        // Setup StackView UI
        keyPairStackView.translatesAutoresizingMaskIntoConstraints = false
        ctaStackView.translatesAutoresizingMaskIntoConstraints = false

        let defaultHeightConstraint = keyPairStackView.heightAnchor.constraint(equalToConstant: 20)
        defaultHeightConstraint.priority = .defaultLow

        NSLayoutConstraint.activate([

                                        defaultHeightConstraint,
                                        keyPairStackView.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -(rightLeftPadding * 2)),
                                        ctaStackView.widthAnchor.constraint(equalTo: keyPairStackView.widthAnchor),
                                        scrollView.contentLayoutGuide.topAnchor.constraint(equalTo: keyPairStackView.topAnchor),
                                        keyPairStackView.bottomAnchor.constraint(equalTo: ctaStackView.topAnchor, constant: -12)
                                    ])

        // StackView Config
        keyPairStackView.axis = .vertical
        keyPairStackView.alignment = .center
        keyPairStackView.spacing = 6
        ctaStackView.axis = .vertical
        ctaStackView.alignment = .center
        ctaStackView.spacing = 8

        // StackView SubViews

        ctaStackView.addCTAView(labelText: "Add new key,value input", button: addKeyValueButton, bgColor: .darkGray)
        ctaStackView.addCTAView(labelText: "Save", button: saveButton, bgColor: .blue)
        initialKeyValuePairs?.forEach(addKeyValueInputToStackView(with:))

        ctaStackView.addArrangedSubview(UIView())
    }

    @objc
    private func addKeyValueBtnTapped(sender: UIButton) {
        addKeyValueInputToStackView(with: nil)
    }

    @objc
    private func saveBtnTapped(sender: UIButton) {
        try? saveAndDismiss()
    }
}

private class SingleKeyValueInputView: UIStackView {

    enum InputError: Error {
        case IncompletePair
    }

    let initialKeyValue: KeyValue?
    let order: Int

    let keyTextField = UITextField()
    let valueTextField = UITextField()

    init(keyValue: KeyValue?, order: Int) {
        self.initialKeyValue = keyValue
        self.order = order
        super.init(frame: .zero)
        setup()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func getCurrentKeyValue() throws -> KeyValue? {
        let key = keyTextField.checkAndRetrieveValueText()
        let value = valueTextField.checkAndRetrieveValueText()
        guard let key = key, let value = value else {
            if key != value {
                // Only one text field is populated.
                throw InputError.IncompletePair
            } else {
                // Both text fields are empty which is fine.
                keyTextField.setToDefaultUI()
                valueTextField.setToDefaultUI()
                return nil
            }
        }
        return (key, value)
    }

    private func setup() {
        axis = .vertical
        alignment = .center
        spacing = 4
        setContentHuggingPriority(.defaultHigh, for: .vertical)

        addInputView(labelText: "Key \(order)", textfield: keyTextField)
        addInputView(labelText: "Value \(order)", textfield: valueTextField)

        keyTextField.text = initialKeyValue?.key
        valueTextField.text = initialKeyValue?.value
    }
}
