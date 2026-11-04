import Foundation
import Security

/// The four Security-framework calls `KeychainStore` makes.
///
/// A value rather than a protocol because these signatures are the seam: tests can
/// fail the authoritative item or the downgrade mirror independently without touching
/// the reader's real login Keychain. Production uses the system functions unchanged.
struct KeychainOperations {
    let copyMatching: (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    let update: (CFDictionary, CFDictionary) -> OSStatus
    let add: (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    let delete: (CFDictionary) -> OSStatus

    static let system = KeychainOperations(
        copyMatching: SecItemCopyMatching,
        update: SecItemUpdate,
        add: SecItemAdd,
        delete: SecItemDelete)
}
