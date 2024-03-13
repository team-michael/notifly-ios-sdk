import UIKit

extension UITextField {

    func checkAndRetrieveValueText(changeBorderColorOnError: Bool = true) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            if changeBorderColorOnError {
                setToErrorUI()
            }
            return nil
        }
        if changeBorderColorOnError {
            setToDefaultUI()
        }
        return text
    }

    func setToErrorUI() {
        layer.borderColor = UIColor.red.cgColor
    }

    func setToDefaultUI(borderColor: UIColor = .black) {
        layer.borderColor = borderColor.cgColor
    }
}
