import Foundation
import Combine

public final class SettingsManager: ObservableObject {
    public static let shared = SettingsManager()
    
    private let userDefaults = UserDefaults.standard
    private let profilesKey = "com.macsnip.settings.profiles"
    private let activeProfileIdKey = "com.macsnip.settings.activeProfileId"
    private let retentionDaysKey = "com.macsnip.settings.retentionDays"
    private let hotKeyDisplayKey = "com.macsnip.settings.hotKeyDisplay"
    private let hotKeyCodeKey = "com.macsnip.settings.hotKeyCode"
    private let hotKeyModifiersKey = "com.macsnip.settings.hotKeyModifiers"
    private let customHistoryPathKey = "com.macsnip.settings.customHistoryPath"
    private let presetsVersionKey = "com.macsnip.settings.presetsVersion"
    
    /// 每次更新预置模板时递增此版本号，触发自动刷新
    private let currentPresetsVersion = 3
    
    @Published public var profiles: [LLMProfile] = [] {
        didSet {
            saveProfiles()
        }
    }
    
    @Published public var activeProfileId: String = "" {
        didSet {
            userDefaults.set(activeProfileId, forKey: activeProfileIdKey)
        }
    }
    
    @Published public var historyRetentionDays: Int = 30 {
        didSet {
            userDefaults.set(historyRetentionDays, forKey: retentionDaysKey)
        }
    }
    
    @Published public var hotKeyDisplay: String = "⌘ + ⇧ + A" {
        didSet {
            userDefaults.set(hotKeyDisplay, forKey: hotKeyDisplayKey)
        }
    }
    
    @Published public var hotKeyCode: UInt32 = 0 { // 0 is kVK_ANSI_A
        didSet {
            userDefaults.set(hotKeyCode, forKey: hotKeyCodeKey)
        }
    }
    
    @Published public var hotKeyModifiers: UInt32 = 768 { // cmdKey (256) | shiftKey (512) = 768
        didSet {
            userDefaults.set(hotKeyModifiers, forKey: hotKeyModifiersKey)
        }
    }
    
    @Published public var customHistoryPath: String = "" {
        didSet {
            userDefaults.set(customHistoryPath, forKey: customHistoryPathKey)
        }
    }
    
    private init() {
        loadSettings()
    }
    
    public var activeProfile: LLMProfile? {
        profiles.first { $0.id == activeProfileId } ?? profiles.first
    }
    
    public func loadSettings() {
        // 读取保留天数
        let savedDays = userDefaults.integer(forKey: retentionDaysKey)
        self.historyRetentionDays = savedDays > 0 ? savedDays : 30
        
        // 读取快捷键配置
        let savedHotKeyDisplay = userDefaults.string(forKey: hotKeyDisplayKey) ?? ""
        if !savedHotKeyDisplay.isEmpty {
            self.hotKeyDisplay = savedHotKeyDisplay
            self.hotKeyCode = UInt32(userDefaults.integer(forKey: hotKeyCodeKey))
            self.hotKeyModifiers = UInt32(userDefaults.integer(forKey: hotKeyModifiersKey))
        } else {
            self.hotKeyDisplay = "⌘ + ⇧ + A"
            self.hotKeyCode = 0
            self.hotKeyModifiers = 768
        }
        
        // 读取自定义路径
        self.customHistoryPath = userDefaults.string(forKey: customHistoryPathKey) ?? ""
        
        // 读取 profiles — 版本检查，过期则重置为最新预置
        let savedVersion = userDefaults.integer(forKey: presetsVersionKey)
        let savedData = userDefaults.data(forKey: profilesKey)
        let savedProfiles = savedData.flatMap { try? JSONDecoder().decode([LLMProfile].self, from: $0) } ?? []
        
        if savedVersion < currentPresetsVersion || savedProfiles.isEmpty {
            // 版本升级或首次启动：用最新预置模板覆盖旧配置
            self.profiles = LLMPresetTemplate.allPresets.map { preset in
                LLMProfile(
                    name: preset.defaultName,
                    baseURL: preset.defaultBaseURL,
                    modelName: preset.defaultModelName,
                    format: preset.format
                )
            }
            userDefaults.set(currentPresetsVersion, forKey: presetsVersionKey)
            saveProfiles()
        } else {
            self.profiles = savedProfiles
        }
        
        let savedActiveId = userDefaults.string(forKey: activeProfileIdKey) ?? ""
        if !savedActiveId.isEmpty, profiles.contains(where: { $0.id == savedActiveId }) {
            self.activeProfileId = savedActiveId
        } else {
            self.activeProfileId = profiles.first?.id ?? ""
        }
    }
    
    public func saveProfiles() {
        if let encoded = try? JSONEncoder().encode(profiles) {
            userDefaults.set(encoded, forKey: profilesKey)
        }
    }
    
    public func addProfile(_ profile: LLMProfile, apiKey: String? = nil) {
        profiles.append(profile)
        if let key = apiKey, !key.isEmpty {
            KeychainManager.shared.saveKey(key, forProfileId: profile.id)
        }
        if activeProfileId.isEmpty {
            activeProfileId = profile.id
        }
    }
    
    public func updateProfile(_ profile: LLMProfile, apiKey: String? = nil) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
            if let key = apiKey {
                KeychainManager.shared.saveKey(key, forProfileId: profile.id)
            }
        }
    }
    
    public func deleteProfile(withId id: String) {
        profiles.removeAll { $0.id == id }
        KeychainManager.shared.deleteKey(forProfileId: id)
        if activeProfileId == id {
            activeProfileId = profiles.first?.id ?? ""
        }
    }
}
