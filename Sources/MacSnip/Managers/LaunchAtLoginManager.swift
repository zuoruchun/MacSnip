import Foundation
import ServiceManagement

public final class LaunchAtLoginManager {
    public static let shared = LaunchAtLoginManager()
    
    private init() {}
    
    /// 当前是否开机自启
    public var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }
    
    /// 设置开机自启
    @discardableResult
    public func setEnabled(_ enabled: Bool) -> Bool {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
                return true
            } catch {
                print("MacSnip: LaunchAtLogin error: \(error.localizedDescription)")
                return false
            }
        }
        return false
    }
}
