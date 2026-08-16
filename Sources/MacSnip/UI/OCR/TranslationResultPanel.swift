import Foundation
import AppKit

public final class TranslationResultPanel: NSPanel {
    private let sourceText: String
    private var translatedText: String = ""
    
    private let progressIndicator = NSProgressIndicator()
    private let statusLabel = NSTextField()
    private let resultTextView = NSTextView()
    private let copyButton = NSButton()
    private let closeButton = NSButton()
    
    public init(sourceText: String) {
        self.sourceText = sourceText
        
        let width: CGFloat = 460
        let height: CGFloat = 360
        
        var frame = NSRect(x: 300, y: 300, width: width, height: height)
        if let screen = NSScreen.main {
            frame = NSRect(
                x: screen.visibleFrame.midX - width / 2,
                y: screen.visibleFrame.midY - height / 2,
                width: width,
                height: height
            )
        }
        
        super.init(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        let activeProfile = SettingsManager.shared.activeProfile
        let modelDesc = activeProfile != nil ? "(\(activeProfile!.name) - \(activeProfile!.modelName))" : ""
        self.title = "AI 翻译 \(modelDesc)"
        self.isFloatingPanel = true
        self.level = .floating
        self.hasShadow = true
        self.isReleasedWhenClosed = false
        
        setupViews()
        startTranslation()
    }
    
    private func setupViews() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 360))
        container.autoresizingMask = [.width, .height]
        
        // 状态文案
        statusLabel.frame = NSRect(x: 16, y: 320, width: 380, height: 24)
        statusLabel.isEditable = false
        statusLabel.isSelectable = false
        statusLabel.isBordered = false
        statusLabel.backgroundColor = .clear
        statusLabel.stringValue = "正在请求 AI 模型翻译..."
        statusLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        container.addSubview(statusLabel)
        
        // 进度转轮
        progressIndicator.frame = NSRect(x: 420, y: 322, width: 20, height: 20)
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.startAnimation(nil)
        container.addSubview(progressIndicator)
        
        // 文本展示滚动区域
        let scrollView = NSScrollView(frame: NSRect(x: 16, y: 60, width: 428, height: 250))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        
        resultTextView.frame = scrollView.contentView.bounds
        resultTextView.autoresizingMask = [.width, .height]
        resultTextView.font = NSFont.systemFont(ofSize: 13)
        resultTextView.isEditable = false
        resultTextView.isSelectable = true
        resultTextView.string = "正在等待翻译响应..."
        
        scrollView.documentView = resultTextView
        container.addSubview(scrollView)
        
        // 复制译文按钮
        copyButton.frame = NSRect(x: 16, y: 16, width: 110, height: 32)
        copyButton.bezelStyle = .rounded
        copyButton.title = "复制译文"
        copyButton.target = self
        copyButton.action = #selector(copyTranslation)
        copyButton.isEnabled = false
        container.addSubview(copyButton)
        
        // 关闭按钮
        closeButton.frame = NSRect(x: 364, y: 16, width: 80, height: 32)
        closeButton.bezelStyle = .rounded
        closeButton.title = "关闭"
        closeButton.target = self
        closeButton.action = #selector(closePanel)
        container.addSubview(closeButton)
        
        self.contentView = container
    }
    
    private func startTranslation() {
        guard let profile = SettingsManager.shared.activeProfile else {
            showError("未找到激活的 AI 翻译配置，请前往设置页面添加。")
            return
        }
        
        guard let apiKey = KeychainManager.shared.loadKey(forProfileId: profile.id), !apiKey.isEmpty else {
            showError("未找到 [\(profile.name)] 的 API Key，请在设置中配置。")
            return
        }
        
        Task {
            do {
                let translation = try await LLMService.shared.translate(
                    text: sourceText,
                    profile: profile,
                    apiKey: apiKey
                )
                
                await MainActor.run {
                    self.translatedText = translation
                    self.resultTextView.string = translation
                    self.statusLabel.stringValue = "翻译完成"
                    self.statusLabel.textColor = .systemGreen
                    self.progressIndicator.stopAnimation(nil)
                    self.progressIndicator.isHidden = true
                    self.copyButton.isEnabled = true
                }
            } catch {
                await MainActor.run {
                    self.showError(error.localizedDescription)
                }
            }
        }
    }
    
    private func showError(_ message: String) {
        statusLabel.stringValue = "翻译失败"
        statusLabel.textColor = .systemRed
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
        resultTextView.string = "错误信息：\n\(message)"
    }
    
    @objc private func copyTranslation() {
        guard !translatedText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(translatedText, forType: .string)
        ToastHUD.shared.show(message: "译文已复制", systemImage: "doc.on.doc.fill")
    }
    
    @objc private func closePanel() {
        self.close()
    }
}
