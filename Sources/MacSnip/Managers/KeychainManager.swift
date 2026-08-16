import Foundation
import Security

public final class KeychainManager {
    public static let shared = KeychainManager()
    private let serviceName = "com.macsnip.apikeys"
    
    private init() {}
    
    /// 保存 API Key 到系统 Keychain
    @discardableResult
    public func saveKey(_ key: String, forProfileId profileId: String) -> Bool {
        guard let data = key.data(using: .utf8) else { return false }
        
        // 先删除旧值
        deleteKey(forProfileId: profileId)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: profileId,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    /// 从 Keychain 中读取 API Key
    public func loadKey(forProfileId profileId: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: profileId,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        guard status == errSecSuccess, let data = dataTypeRef as? Data else {
            return nil
        }
        
        return String(data: data, encoding: .utf8)
    }
    
    /// 从 Keychain 中删除 API Key
    @discardableResult
    public func deleteKey(forProfileId profileId: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: profileId
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
