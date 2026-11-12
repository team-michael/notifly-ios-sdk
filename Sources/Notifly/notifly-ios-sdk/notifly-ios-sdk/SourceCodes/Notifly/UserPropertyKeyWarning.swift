import Foundation
import NotiflyCore

/// Adapts Swift keys to the shared policy without inspecting or changing property values.
enum UserPropertyKeyWarning {
    static func message(for keys: [String]) -> String? {
        let coreKeys = KotlinArray<NSString>(size: Int32(keys.count)) { index in
            keys[index.intValue] as NSString
        }
        return UserPropertyKeyPolicy.shared.warningMessage(keys: coreKeys)
    }
}
