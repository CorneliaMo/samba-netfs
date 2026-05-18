import Foundation

public struct Credential: Equatable, Sendable {
    public let account: String
    public let password: String

    public init(account: String, password: String) {
        self.account = account
        self.password = password
    }
}

public protocol CredentialStore {
    func password(host: String, share: String, account: String) throws -> String?
    func setPassword(_ password: String, host: String, share: String, account: String) throws
}

public enum CredentialKey {
    public static func service(host: String, share: String) -> String {
        "mount-samba-swift:\(host)/\(share)"
    }
}

public enum CredentialError: LocalizedError, Equatable {
    case missing(host: String, share: String, account: String)
    case unsupported
    case keychainStatus(Int32)

    public var errorDescription: String? {
        switch self {
        case let .missing(host, share, account):
            return "missing Keychain credential for \(account)@\(host)/\(share)"
        case .unsupported:
            return "Keychain is only available on macOS"
        case let .keychainStatus(status):
            return "Keychain operation failed with status \(status)"
        }
    }
}

#if canImport(Security)
import Security

public final class KeychainCredentialStore: CredentialStore {
    public init() {}

    public func password(host: String, share: String, account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: CredentialKey.service(host: host, share: share),
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw CredentialError.keychainStatus(status)
        }
        guard let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func setPassword(_ password: String, host: String, share: String, account: String) throws {
        let service = CredentialKey.service(host: host, share: share)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let data = Data(password.utf8)
        let update = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw CredentialError.keychainStatus(updateStatus)
        }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CredentialError.keychainStatus(addStatus)
        }
    }
}
#else
public final class KeychainCredentialStore: CredentialStore {
    public init() {}

    public func password(host: String, share: String, account: String) throws -> String? {
        throw CredentialError.unsupported
    }

    public func setPassword(_ password: String, host: String, share: String, account: String) throws {
        throw CredentialError.unsupported
    }
}
#endif
