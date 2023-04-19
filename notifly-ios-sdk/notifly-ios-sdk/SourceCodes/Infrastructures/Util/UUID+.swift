import Foundation

extension UUID {
    
    var notiflyStyleString: String {
        uuidString.replacingOccurrences(of: "-", with: "")
    }
}
