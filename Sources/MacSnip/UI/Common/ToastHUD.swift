import Foundation
import AppKit

public final class ToastHUD {
    public static let shared = ToastHUD()
    private var window: NSPanel?
    private var dismissTimer: Timer?
    
    private init() {}
    
    /// 在屏幕上方居中展示浮动轻量提示
    public func show(message: String, systemImage: String = "checkmark.circle.fill", duration: TimeInterval = 1.5) {
        DispatchQueue.main.async {
            self.dismissTimer?.invalidate()
            self.window?.close()
            
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 220, height: 44),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .floating
            panel.hasShadow = true
            panel.ignoresMouseEvents = true
            
            let visualEffect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 220, height: 44))
            visualEffect.material = .hudWindow
            visualEffect.blendingMode = .behindWindow
            visualEffect.state = .active
            visualEffect.wantsLayer = true
            visualEffect.layer?.cornerRadius = 22
            visualEffect.layer?.masksToBounds = true
            
            // 图标
            let imageView = NSImageView(frame: NSRect(x: 16, y: 12, width: 20, height: 20))
            if let image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil) {
                let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
                imageView.image = image.withSymbolConfiguration(config)
                imageView.contentTintColor = NSColor.systemGreen
            }
            visualEffect.addSubview(imageView)
            
            // 文案
            let label = NSTextField(frame: NSRect(x: 44, y: 12, width: 160, height: 20))
            label.isEditable = false
            label.isSelectable = false
            label.isBordered = false
            label.backgroundColor = .clear
            label.stringValue = message
            label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            label.textColor = .white
            label.alignment = .left
            visualEffect.addSubview(label)
            
            panel.contentView = visualEffect
            
            // 居中显示在主屏幕偏上方
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let x = screenFrame.midX - 110
                let y = screenFrame.maxY - 100
                panel.setFrameOrigin(NSPoint(x: x, y: y))
            }
            
            panel.alphaValue = 0.0
            panel.orderFrontRegardless()
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                panel.animator().alphaValue = 1.0
            }
            
            self.window = panel
            
            self.dismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                guard let self = self, let win = self.window else { return }
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.25
                    win.animator().alphaValue = 0.0
                }, completionHandler: {
                    win.close()
                    self.window = nil
                })
            }
        }
    }
}
