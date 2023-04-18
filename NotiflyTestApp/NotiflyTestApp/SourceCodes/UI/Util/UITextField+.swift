import UIKit

extension UITextField {
    
    func checkAndRetrieveValueText(changeBorderColorOnError: Bool = true) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            if changeBorderColorOnError {
                layer.borderColor = UIColor.red.cgColor
            }
            return nil
        }
        if changeBorderColorOnError {
            layer.borderColor = UIColor.black.cgColor
        }
        return text
    }
}
