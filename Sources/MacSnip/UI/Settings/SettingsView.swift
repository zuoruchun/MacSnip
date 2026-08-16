import SwiftUI
import AppKit

public struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @State private var selectedTab = 0
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                GeneralSettingsView()
                    .tabItem {
                        Label("通用偏好", systemImage: "gearshape")
                    }
                    .tag(0)
                
                AIProfileSettingsView()
                    .tabItem {
                        Label("AI 翻译配置", systemImage: "character.bubble")
                    }
                    .tag(1)
                
                PermissionSettingsView()
                    .tabItem {
                        Label("权限状态", systemImage: "lock.shield")
                    }
                    .tag(2)
            }
            
            // ── 底部版本信息栏 ──
            Divider()
            HStack {
                Text("MacSnip")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Text("v1.0.0")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Text("by nocasdom")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.secondary.opacity(0.7))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 7)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .padding(18)
        .frame(minWidth: 780, minHeight: 520)
    }
}

// MARK: - 1. 通用偏好页面

private struct GeneralSettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @State private var launchAtLogin = LaunchAtLoginManager.shared.isEnabled
    @State private var isRecordingHotKey = false
    @State private var keyMonitor: Any?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox(label: Label("全局截图快捷键", systemImage: "keyboard").font(.headline)) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Text("当前快捷键：")
                                .font(.system(size: 13, weight: .medium))
                            
                            Button(action: toggleRecording) {
                                HStack(spacing: 6) {
                                    if isRecordingHotKey {
                                        Image(systemName: "record.circle")
                                            .foregroundColor(.red)
                                        Text("请在键盘上按下快捷键...")
                                            .font(.system(size: 13, weight: .semibold))
                                    } else {
                                        Text(settings.hotKeyDisplay)
                                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                            }
                            .buttonStyle(.bordered)
                            
                            if isRecordingHotKey {
                                Button("取消") { stopRecording() }
                                    .buttonStyle(.plain)
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                            
                            Spacer()
                            
                            Button("恢复默认 (⌘⇧A)") {
                                settings.hotKeyDisplay = "⌘ + ⇧ + A"
                                settings.hotKeyCode = 0
                                settings.hotKeyModifiers = 768
                                HotKeyManager.shared.registerDefaultHotKey()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        
                        Text("点击按钮后，直接按下目标组合键即可实时生效。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                }
                
                GroupBox(label: Label("历史记录存储位置", systemImage: "folder").font(.headline)) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("存储路径：")
                                .font(.system(size: 13, weight: .medium))
                            Text(displayPath)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        
                        HStack(spacing: 12) {
                            Button("在访达中显示") { revealInFinder() }
                                .buttonStyle(.bordered)
                            
                            Button("更改存储目录...") { chooseCustomDirectory() }
                                .buttonStyle(.bordered)
                            
                            if !settings.customHistoryPath.isEmpty {
                                Button("恢复默认路径") {
                                    settings.customHistoryPath = ""
                                    HistoryManager.shared.loadHistory()
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.red)
                                .font(.caption)
                            }
                        }
                        
                        Divider().padding(.vertical, 4)
                        
                        Stepper(value: $settings.historyRetentionDays, in: 1...365) {
                            Text("自动清理超过 **\(settings.historyRetentionDays)** 天的历史记录")
                        }
                        Text("过期历史记录及 PNG 图像文件将自动从磁盘释放。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                }
                
                GroupBox(label: Label("系统常驻与启动", systemImage: "macmini").font(.headline)) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("开机自动启动 MacSnip", isOn: $launchAtLogin)
                            .onChange(of: launchAtLogin) { value in
                                _ = LaunchAtLoginManager.shared.setEnabled(value)
                            }
                        Text("开启后每次登录系统将自动在菜单栏常驻运行，不占用 Dock 栏。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                }
            }
            .padding(12)
        }
        .onDisappear { stopRecording() }
    }
    
    private var displayPath: String {
        settings.customHistoryPath.isEmpty ? HistoryManager.defaultDirectory.path : settings.customHistoryPath
    }
    
    private func toggleRecording() {
        isRecordingHotKey ? stopRecording() : startRecording()
    }
    
    private func startRecording() {
        isRecordingHotKey = true
        HotKeyManager.shared.unregisterHotKey()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if let result = HotKeyManager.formatHotKey(keyCode: event.keyCode, flags: event.modifierFlags) {
                settings.hotKeyDisplay = result.display
                settings.hotKeyCode = result.keyCode
                settings.hotKeyModifiers = result.carbonModifiers
                HotKeyManager.shared.registerHotKey(keyCode: result.keyCode, modifiers: result.carbonModifiers)
                self.stopRecording()
                return nil
            }
            return event
        }
    }
    
    private func stopRecording() {
        isRecordingHotKey = false
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        HotKeyManager.shared.registerDefaultHotKey()
    }
    
    private func revealInFinder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: HistoryManager.shared.historyDirectory.path)
    }
    
    private func chooseCustomDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择目录"
        panel.title = "选择 MacSnip 截图历史记录存储目录"
        if panel.runModal() == .OK, let selectedURL = panel.url {
            settings.customHistoryPath = selectedURL.path
            HistoryManager.shared.loadHistory()
        }
    }
}

// MARK: - 2. AI 翻译配置页面

private struct AIProfileSettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @State private var selectedProfileId: String?
    @State private var editingProfile: LLMProfile = LLMProfile(name: "", baseURL: "", modelName: "")
    @State private var editingApiKey: String = ""
    @State private var isTestingConnection = false
    @State private var testResult: String?
    @State private var isShowingSuccess = false
    
    var body: some View {
        HStack(spacing: 18) {
            
            // ── 左侧配置列表 ──────────────────────────────────────
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("配置列表")
                        .font(.headline)
                    Spacer()
                    // 仅保留「新建空白配置」的 + 号
                    Button(action: addBlankProfile) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .help("新建空白配置")
                }
                .padding(.horizontal, 4)
                
                List(selection: $selectedProfileId) {
                    ForEach(settings.profiles) { profile in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.name)
                                    .font(.system(size: 13, weight: .medium))
                                Text(profile.modelName)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if settings.activeProfileId == profile.id {
                                Text("默认")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.15))
                                    .foregroundColor(.accentColor)
                                    .cornerRadius(4)
                            }
                        }
                        .tag(profile.id)
                        .contextMenu {
                            Button("设为默认") {
                                settings.activeProfileId = profile.id
                            }
                            if settings.profiles.count > 1 {
                                Divider()
                                Button("删除此配置", role: .destructive) {
                                    deleteProfile(withId: profile.id)
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .cornerRadius(8)
                
                // 「设为默认」底部快捷按钮（仅在非默认时显示）
                if let activeId = selectedProfileId, activeId != settings.activeProfileId {
                    Button("设为默认翻译模型") {
                        settings.activeProfileId = activeId
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.horizontal, 4)
                }
            }
            .frame(width: 230)
            .padding(.leading, 4)
            
            Divider()
            
            // ── 右侧编辑面板 ──────────────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let _ = selectedProfileId {
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("配置名称")
                                .font(.caption.bold())
                            TextField("例如: DeepSeek", text: $editingProfile.name)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("接口格式")
                                .font(.caption.bold())
                            Picker("", selection: $editingProfile.format) {
                                ForEach(LLMProviderFormat.allCases) { format in
                                    Text(format.displayName).tag(format)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Base URL")
                                .font(.caption.bold())
                            TextField("例如: https://api.deepseek.com", text: $editingProfile.baseURL)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Model 名称")
                                .font(.caption.bold())
                            TextField("例如: deepseek-v4-flash", text: $editingProfile.modelName)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("API Key (支持 ⌘V 粘贴，保存在系统 Keychain)")
                                .font(.caption.bold())
                            SecureField("输入或粘贴 API Key", text: $editingApiKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        if let result = testResult {
                            Text(result)
                                .font(.caption)
                                .foregroundColor(isShowingSuccess ? .green : .red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        HStack(spacing: 14) {
                            Button(action: testConnection) {
                                if isTestingConnection {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Text("测试连接")
                                }
                            }
                            .disabled(isTestingConnection || editingApiKey.isEmpty)
                            
                            Spacer()
                            
                            // 唯一的删除入口：右侧「删除此配置」
                            if settings.profiles.count > 1, let currentId = selectedProfileId {
                                Button("删除此配置", role: .destructive) {
                                    deleteProfile(withId: currentId)
                                }
                                .buttonStyle(.bordered)
                            }
                            
                            Button("保存修改") {
                                saveCurrentProfile()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.top, 8)
                        
                    } else {
                        VStack {
                            Spacer(minLength: 50)
                            Text("请在左侧选择配置或点击 + 新建")
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.trailing, 8)
                .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            if let first = settings.profiles.first(where: { $0.id == settings.activeProfileId }) ?? settings.profiles.first {
                selectedProfileId = first.id
                loadProfile(first)
            }
        }
        .onChange(of: selectedProfileId) { newId in
            if let id = newId, let profile = settings.profiles.first(where: { $0.id == id }) {
                loadProfile(profile)
            }
        }
    }
    
    private func loadProfile(_ profile: LLMProfile) {
        editingProfile = profile
        editingApiKey = KeychainManager.shared.loadKey(forProfileId: profile.id) ?? ""
        testResult = nil
    }
    
    private func addBlankProfile() {
        let newProfile = LLMProfile(
            name: "新配置",
            baseURL: "",
            modelName: "",
            format: .openAICompatible
        )
        settings.addProfile(newProfile)
        selectedProfileId = newProfile.id
        loadProfile(newProfile)
    }
    
    private func deleteProfile(withId id: String) {
        guard settings.profiles.count > 1 else { return }
        settings.deleteProfile(withId: id)
        if let next = settings.profiles.first {
            selectedProfileId = next.id
            loadProfile(next)
        }
    }
    
    private func saveCurrentProfile() {
        settings.updateProfile(editingProfile, apiKey: editingApiKey)
    }
    
    private func testConnection() {
        isTestingConnection = true
        testResult = nil
        Task {
            do {
                let reply = try await LLMService.shared.translate(
                    text: "Hello World",
                    profile: editingProfile,
                    apiKey: editingApiKey
                )
                await MainActor.run {
                    isTestingConnection = false
                    isShowingSuccess = true
                    testResult = "连接成功！测试结果: \(reply)"
                }
            } catch {
                await MainActor.run {
                    isTestingConnection = false
                    isShowingSuccess = false
                    testResult = "连接失败: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - 3. 权限状态页面

private struct PermissionSettingsView: View {
    @State private var hasPermission = PermissionManager.shared.hasScreenRecordingPermission
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: hasPermission ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .font(.system(size: 56))
                .foregroundColor(hasPermission ? .green : .orange)
            
            Text(hasPermission ? "已授予屏幕录制权限" : "未授予屏幕录制权限")
                .font(.title2.bold())
            
            Text(hasPermission
                 ? "MacSnip 可以正常截取所有屏幕内容。"
                 : "MacSnip 需要「屏幕录制」权限才能捕获屏幕图像。\n若已在系统设置中授权，请尝试重启应用以使其生效。")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            Button("打开系统偏好设置") {
                PermissionManager.shared.openScreenRecordingPreferences()
            }
            .buttonStyle(.borderedProminent)
            
            Spacer()
        }
        .padding(20)
        .onAppear {
            hasPermission = PermissionManager.shared.hasScreenRecordingPermission
        }
    }
}
