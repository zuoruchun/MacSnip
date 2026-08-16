import Foundation
import AppKit
import CoreGraphics

public final class PermissionManager {
    public static let shared = PermissionManager()
    
    private init() {}
    
    /// 真实检查是否有屏幕录制权限
    public var hasScreenRecordingPermission: Bool {
        if let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            let hasNamedWindows = windowList.contains { dict in
                if let name = dict[kCGWindowName as String] as? String, !name.isEmpty {
                    return true
                }
                return false
            }
            if hasNamedWindows {
                return true
            }
        }
        return CGPreflightScreenCaptureAccess()
    }
    
    /// 申请屏幕录制权限
    @discardableResult
    public func requestScreenRecordingPermission() -> Bool {
        return CGRequestScreenCaptureAccess()
    }
    
    /// 重置本应用的权限缓存
    public func resetPermissionCache() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "ScreenCapture", "com.macsnip.app"]
        try? process.run()
        process.waitUntilExit()
    }
    
    /// 引导用户打开系统偏好设置中的屏幕录制权限页
    public func openScreenRecordingPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// 展示权限引导弹窗
    public func showPermissionAlertIfNeeded() -> Bool {
        requestScreenRecordingPermission()
        
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "需要屏幕录制权限"
            alert.informativeText = "MacSnip 需要「屏幕录制」权限才能捕获当前所有应用窗口。\n\n【重要提示】：\n若「系统设置」中已显示勾选，请先将其【关闭再重新打开一次】（或先点「重置权限缓存」），系统方可刷新最新签名！"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "重置权限缓存")
            alert.addButton(withTitle: "稍后再说")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                self.openScreenRecordingPreferences()
            } else if response == .alertSecondButtonReturn {
                self.resetPermissionCache()
                ToastHUD.shared.show(message: "已重置权限缓存，请重新打开系统设置勾选", systemImage: "arrow.triangle.2.circlepath")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.openScreenRecordingPreferences()
                }
            }
        }
        
        return false
    }
}
