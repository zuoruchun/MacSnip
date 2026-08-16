import Foundation
import AppKit
import SwiftUI

public final class HistoryWindowController: NSWindowController {
    public static let shared = HistoryWindowController()
    
    private init() {
        let historyView = HistoryView()
        let hostingController = NSHostingController(rootView: historyView)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 840, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "MacSnip 截图历史"
        window.center()
        window.setFrameAutosaveName("MacSnipHistoryWindow")
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        
        super.init(window: window)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func showWindow() {
        HistoryManager.shared.loadHistory()
        self.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
