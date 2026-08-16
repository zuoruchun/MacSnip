import Foundation
import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    public static let shared = AppDelegate()
    
    public override init() {
        super.init()
    }
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // 单实例保护：清理同名旧实例
        terminateOtherInstances()
        
        // 常驻菜单栏，不占用 Dock
        NSApp.setActivationPolicy(.accessory)
        
        // 构建系统主菜单 (让 ⌘V 粘贴、⌘C 复制、⌘A 全选全局生效)
        setupSystemEditMenu()
        
        // 初始化状态栏菜单
        MenuBarController.shared.setupMenuBar()
        
        // 注册全局热键 (从 SettingsManager 读取)
        HotKeyManager.shared.onHotKeyPressed = {
            CaptureManager.shared.startCapture()
        }
        HotKeyManager.shared.registerDefaultHotKey()
        
        // 启动历史管理与后台清理任务
        HistoryManager.shared.startPeriodicCleanup()
        
        print("MacSnip: Application successfully launched.")
    }
    
    /// 构建基础系统编辑菜单，使输入框支持 ⌘V 粘贴、⌘C 复制、⌘A 全选、⌘Z 撤销
    private func setupSystemEditMenu() {
        let mainMenu = NSMenu()
        
        // App 菜单项
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 MacSnip", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "退出 MacSnip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        
        // Edit 编辑菜单项 (关键：驱动全局输入框快捷键)
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        
        NSApp.mainMenu = mainMenu
    }
    
    private func terminateOtherInstances() {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let bundleID = Bundle.main.bundleIdentifier ?? "com.macsnip.app"
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        
        for app in runningApps {
            if app.processIdentifier != currentPID {
                app.terminate()
            }
        }
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        HotKeyManager.shared.unregisterHotKey()
    }
}
