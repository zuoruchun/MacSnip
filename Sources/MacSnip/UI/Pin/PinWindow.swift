import Foundation
import AppKit

public final class PinWindow: NSPanel {
    public let image: NSImage
    private var currentAlpha: CGFloat = 1.0
    
    public init(image: NSImage, initialFrame: NSRect? = nil) {
        self.image = image
        
        var frame = initialFrame ?? NSRect(x: 200, y: 200, width: image.size.width, height: image.size.height)
        if initialFrame == nil, let screen = NSScreen.main {
            let width = max(100, min(image.size.width, screen.frame.width * 0.8))
            let height = max(60, min(image.size.height, screen.frame.height * 0.8))
            frame = NSRect(
                x: screen.visibleFrame.midX - width / 2,
                y: screen.visibleFrame.midY - height / 2,
                width: width,
                height: height
            )
        }
        
        super.init(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .resizable, .borderless],
            backing: .buffered,
            defer: false
        )
        
        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = true
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        
        setupContentView()
    }
    
    private func setupContentView() {
        let container = PinContainerView(frame: NSRect(origin: .zero, size: frame.size), image: image, pinWindow: self)
        self.contentView = container
    }
    
    /// 调整透明度
    public func adjustAlpha(delta: CGFloat) {
        currentAlpha = max(0.2, min(1.0, currentAlpha + delta))
        self.alphaValue = currentAlpha
    }
}

private final class PinContainerView: NSView {
    private let image: NSImage
    private weak var pinWindow: PinWindow?
    private let imageView = NSImageView()
    private let closeButton = NSButton()
    
    private var initialDragLocation: NSPoint = .zero
    
    init(frame: NSRect, image: NSImage, pinWindow: PinWindow) {
        self.image = image
        self.pinWindow = pinWindow
        super.init(frame: frame)
        
        self.wantsLayer = true
        self.layer?.cornerRadius = 6
        self.layer?.masksToBounds = true
        self.layer?.borderWidth = 1
        self.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
        
        imageView.frame = self.bounds
        imageView.autoresizingMask = [.width, .height]
        imageView.image = image
        imageView.imageScaling = .scaleAxesIndependently
        imageView.unregisterDraggedTypes()
        addSubview(imageView)
        
        // 悬浮关闭按钮 (左上角)
        closeButton.frame = NSRect(x: 8, y: bounds.height - 26, width: 18, height: 18)
        closeButton.autoresizingMask = [.minYMargin, .maxXMargin]
        closeButton.bezelStyle = .circular
        closeButton.isBordered = false
        closeButton.title = ""
        closeButton.wantsLayer = true
        closeButton.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        closeButton.layer?.cornerRadius = 9
        if let xmark = NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭") {
            let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
            closeButton.image = xmark.withSymbolConfiguration(config)
            closeButton.contentTintColor = .white
        }
        closeButton.target = self
        closeButton.action = #selector(onCloseClicked)
        closeButton.alphaValue = 0.0
        addSubview(closeButton)
        
        setupTrackingArea()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupTrackingArea() {
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }
    
    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            closeButton.animator().alphaValue = 1.0
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            closeButton.animator().alphaValue = 0.0
        }
    }
    
    // MARK: - 自由拖拽移动
    
    override func mouseDown(with event: NSEvent) {
        initialDragLocation = event.locationInWindow
        if event.clickCount == 2 {
            pinWindow?.close()
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let window = self.window else { return }
        let currentOrigin = window.frame.origin
        let dx = event.locationInWindow.x - initialDragLocation.x
        let dy = event.locationInWindow.y - initialDragLocation.y
        window.setFrameOrigin(NSPoint(x: currentOrigin.x + dx, y: currentOrigin.y + dy))
    }
    
    @objc private func onCloseClicked() {
        pinWindow?.close()
    }
    
    // 滚轮调节透明度
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.control) || event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) {
            let delta = event.scrollingDeltaY * 0.02
            pinWindow?.adjustAlpha(delta: delta)
        } else {
            super.scrollWheel(with: event)
        }
    }
    
    // 右键菜单
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        
        let copyItem = NSMenuItem(title: "复制图片", action: #selector(copyImage), keyEquivalent: "c")
        copyItem.target = self
        menu.addItem(copyItem)
        
        let saveItem = NSMenuItem(title: "另存为...", action: #selector(saveAsFile), keyEquivalent: "s")
        saveItem.target = self
        menu.addItem(saveItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let resetAlphaItem = NSMenuItem(title: "恢复 100% 不透明度", action: #selector(resetAlpha), keyEquivalent: "")
        resetAlphaItem.target = self
        menu.addItem(resetAlphaItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let closeItem = NSMenuItem(title: "关闭贴图", action: #selector(onCloseClicked), keyEquivalent: "w")
        closeItem.target = self
        menu.addItem(closeItem)
        
        return menu
    }
    
    @objc private func copyImage() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }
    
    @objc private func saveAsFile() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = "Screenshot_\(Int(Date().timeIntervalSince1970)).png"
        
        savePanel.begin { [weak self] result in
            guard result == .OK, let url = savePanel.url, let self = self else { return }
            if let tiffData = self.image.tiffRepresentation,
               let bitmapRep = NSBitmapImageRep(data: tiffData),
               let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                try? pngData.write(to: url)
            }
        }
    }
    
    @objc private func resetAlpha() {
        pinWindow?.adjustAlpha(delta: 1.0)
    }
}
