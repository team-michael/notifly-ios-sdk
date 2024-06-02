import CommonCrypto
import Foundation

extension UUID {
    /// UUID V5 Hashing Helper
    init(name: String, namespace: UUID) {
        // Get UUID bytes from name space:
        var spaceUID = UUID(uuidString: namespace.uuidString)!.uuid
        var data = withUnsafePointer(to: &spaceUID) { [count = MemoryLayout.size(ofValue: spaceUID)] in
            Data(bytes: $0, count: count)
        }

        // Append name string in UTF-8 encoding:
        data.append(contentsOf: name.utf8)

        // Compute digest (MD5 or SHA1, depending on the version):
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            _ = CC_SHA1(ptr.baseAddress, CC_LONG(data.count), &digest)
        }

        // Set version bits:
        digest[6] &= 0x0F
        digest[6] |= UInt8(5) << 4
        // Set variant bits:
        digest[8] &= 0x3F
        digest[8] |= 0x80

        // Create UUID from digest:
        self = NSUUID(uuidBytes: digest) as UUID
    }

    var notiflyStyleString: String {
        uuidString.replacingOccurrences(of: "-", with: "")
    }
}
