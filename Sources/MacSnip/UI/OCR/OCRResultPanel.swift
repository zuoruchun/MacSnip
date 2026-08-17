import Foundation
import AppKit

public final class OCRResultPanel: NSPanel {
    private let recognizedText: String
    private let onTranslateRequested: ((String) -> Void)?
    
    public init(recognizedText: String, onTranslate: ((String) -> Void)? = nil) {
        self.recognizedText = recognizedText
        self.onTranslateRequested = onTranslate
        
        let width: CGFloat = 480
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
        
        self.title = "文字识别 (OCR)"
        self.isFloatingPanel = true
        self.level = .floating
        self.hasShadow = true
        self.isReleasedWhenClosed = false
        
        setupViews()
    }
    
    private func setupViews() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 360))
        container.autoresizingMask = [.width, .height]
        
        // 滚动文本框 (字体放大 1.3 倍)
        let scrollView = NSScrollView(frame: NSRect(x: 16, y: 60, width: 448, height: 284))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        
        let textView = NSTextView(frame: scrollView.contentView.bounds)
        textView.autoresizingMask = [.width, .height]
        textView.string = recognizedText
        textView.font = NSFont.systemFont(ofSize: 17)
        textView.isEditable = true
        textView.isSelectable = true
        
        scrollView.documentView = textView
        container.addSubview(scrollView)
        
        // 复制按钮
        let copyButton = NSButton(frame: NSRect(x: 16, y: 16, width: 100, height: 32))
        copyButton.bezelStyle = .rounded
        copyButton.title = "复制文字"
        copyButton.target = self
        copyButton.action = #selector(copyText)
        container.addSubview(copyButton)
        
        // 翻译按钮
        let translateButton = NSButton(frame: NSRect(x: 124, y: 16, width: 120, height: 32))
        translateButton.bezelStyle = .rounded
        translateButton.title = "AI 翻译为中文"
        translateButton.target = self
        translateButton.action = #selector(triggerTranslate)
        container.addSubview(translateButton)
        
        // 关闭按钮
        let closeBtn = NSButton(frame: NSRect(x: 384, y: 16, width: 80, height: 32))
        closeBtn.bezelStyle = .rounded
        closeBtn.title = "关闭"
        closeBtn.target = self
        closeBtn.action = #selector(closePanel)
        container.addSubview(closeBtn)
        
        self.contentView = container
    }
    
    @objc private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(recognizedText, forType: .string)
    }
    
    @objc private func triggerTranslate() {
        self.close()
        onTranslateRequested?(recognizedText)
    }
    
    @objc private func closePanel() {
        self.close()
    }
}
