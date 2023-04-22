import UIKit

extension UIStackView {
    
    func addInputView(labelText: String, textfield: UITextField) {
        let label = UILabel()
        label.text = labelText
        label.textColor = .darkGray
        
        textfield.layer.borderWidth = 1
        textfield.setToDefaultUI()
        
        addArrangedSubview(label)
        addArrangedSubview(textfield)
        
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalTo: label.widthAnchor),
            widthAnchor.constraint(equalTo: textfield.widthAnchor)
        ])
    }
    
    func addSwitchView(labelText: String, switchView: UISwitch) {
        let label = UILabel()
        label.text = labelText
        label.textColor = .darkGray
        
        addArrangedSubview(label)
        addArrangedSubview(switchView)
        
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalTo: label.widthAnchor),
            widthAnchor.constraint(equalTo: switchView.widthAnchor)
        ])
    }
    
    func addCTAView(labelText: String, button: UIButton, bgColor: UIColor) {
        button.setTitle(labelText, for: .normal)
        button.backgroundColor = bgColor
        button.translatesAutoresizingMaskIntoConstraints = false
        addArrangedSubview(button)
        
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalTo: button.widthAnchor, constant: 40),
            button.heightAnchor.constraint(equalToConstant: 40)
        ])
    }
    
    func addInfoView(labelText: String, textView: UITextView) {
        let label = UILabel()
        label.text = labelText
        label.textColor = .darkGray
        
        textView.isEditable = false
        textView.layer.borderWidth = 1
        textView.layer.borderColor = UIColor.lightGray.cgColor
        
        addArrangedSubview(label)
        addArrangedSubview(textView)
        
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalTo: label.widthAnchor),
            widthAnchor.constraint(equalTo: textView.widthAnchor),
            textView.heightAnchor.constraint(equalToConstant: 100)
        ])
    }
    
    func addSeparator(height: CGFloat = 1, color: UIColor = .separator) {
        let separatorView = UIView()
        separatorView.backgroundColor = color
        addArrangedSubview(separatorView)
        
        NSLayoutConstraint.activate([
            separatorView.widthAnchor.constraint(equalTo: widthAnchor),
            separatorView.heightAnchor.constraint(equalToConstant: height)
        ])
    }
}
