import Foundation
import AppKit

public final class MenuBarController: NSObject {
    public static let shared = MenuBarController()
    
    private var statusItem: NSStatusItem?
    
    private override init() {
        super.init()
    }
    
    public func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let button = statusItem?.button else { return }
        button.toolTip = "MacSnip 截图 (⌘⇧A)"
        
        if let icon = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "MacSnip") {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            if let configured = icon.withSymbolConfiguration(config) {
                configured.isTemplate = true
                button.image = configured
            } else {
                icon.isTemplate = true
                button.image = icon
            }
        } else {
            button.title = "✂️"
        }
        
        let menu = NSMenu()
        
        let captureItem = NSMenuItem(title: "区域截图 (⌘⇧A)", action: #selector(triggerCapture), keyEquivalent: "")
        captureItem.target = self
        menu.addItem(captureItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let historyItem = NSMenuItem(title: "历史记录...", action: #selector(showHistory), keyEquivalent: "")
        historyItem.target = self
        menu.addItem(historyItem)
        
        let settingsItem = NSMenuItem(title: "偏好设置...", action: #selector(showSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let permItem = NSMenuItem(title: "检查 / 修复屏幕录制权限...", action: #selector(checkPermission), keyEquivalent: "")
        permItem.target = self
        menu.addItem(permItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "退出 MacSnip", action: #selector(quitApp), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    @objc private func triggerCapture() {
        CaptureManager.shared.startCapture()
    }
    
    @objc private func showHistory() {
        HistoryWindowController.shared.showWindow()
    }
    
    @objc private func showSettings() {
        SettingsWindowController.shared.showWindow()
    }
    
    @objc private func checkPermission() {
        _ = PermissionManager.shared.showPermissionAlertIfNeeded()
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
