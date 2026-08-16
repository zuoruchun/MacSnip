import Foundation
import AppKit

final class CaptureOverlayWindow: NSWindow {
    let overlayView: CaptureOverlayView
    
    init(screen: NSScreen, backgroundImage: NSImage) {
        let screenFrame = screen.frame
        self.overlayView = CaptureOverlayView(
            frame: NSRect(origin: .zero, size: screenFrame.size),
            backgroundImage: backgroundImage
        )
        
        super.init(
            contentRect: NSRect(origin: .zero, size: screenFrame.size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        self.setFrame(screenFrame, display: true)
        // 浮动在状态栏与所有普通窗口之上，但避免直接使用危险的 screenSaver 级别
        self.level = NSWindow.Level(Int(CGWindowLevelForKey(.maximumWindow)) - 1)
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.contentView = overlayView
        self.isReleasedWhenClosed = false
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
    }
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    override func cancelOperation(_ sender: Any?) {
        overlayView.handleCancel()
    }
}
