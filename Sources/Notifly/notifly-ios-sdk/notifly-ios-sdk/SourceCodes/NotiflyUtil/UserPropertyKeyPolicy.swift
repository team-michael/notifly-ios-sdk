import Foundation

enum UserPropertyKeyPolicy {
    private static let reservedKeys: Set<String> = [
        TrackingConstant.InternalUserPropertyKey.email,
        TrackingConstant.InternalUserPropertyKey.phoneNumber,
        TrackingConstant.InternalUserPropertyKey.timezone,
        "$line_user_id", "$appsflyer_id",
    ]

    static func warningMessage(for keys: [String]) -> String? {
        let invalidKeys = keys.filter { key in
            !reservedKeys.contains(key)
                && (key.isEmpty
                    || key.unicodeScalars.contains { scalar in
                        switch scalar.value {
                        case 65...90, 97...122, 48...57, 95: return false
                        default: return true
                        }
                    })
        }.sorted()
        guard !invalidKeys.isEmpty,
            let data = try? JSONSerialization.data(withJSONObject: invalidKeys),
            let keyList = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return "Invalid custom user property key(s): \(keyList). "
            + "Only English letters (A-Z, a-z), digits (0-9), and underscores (_) are supported. "
            + "This warning does not block the operation."
    }
}
