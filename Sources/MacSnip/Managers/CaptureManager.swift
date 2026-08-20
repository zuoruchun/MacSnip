import Foundation
import AppKit
import CoreGraphics
import ScreenCaptureKit

final class CaptureManager: NSObject, CaptureOverlayViewDelegate {
    static let shared = CaptureManager()
    
    private var overlayWindows: [CaptureOverlayWindow] = []
    private var pinnedWindows: [PinWindow] = []
    private var activePanels: [NSPanel] = []
    private var isCapturing = false
    private var isCursorPushed = false
    
    private override init() {
        super.init()
    }
    
    /// 开始截图流程
    func startCapture() {
        guard !isCapturing else { return }
        isCapturing = true

        let needsWindowServerFlush = !overlayWindows.isEmpty || activePanels.contains { $0.isVisible }
        
        // 1. 先关闭/隐藏本 App 自己的所有悬浮面板和遮罩，避免抓到自身 UI 残影
        closeAllOverlays()
        for panel in activePanels {
            panel.orderOut(nil)
        }
        activePanels.removeAll()
        
        Task { @MainActor in
            defer { self.isCapturing = false }
            
            // 只有刚隐藏过本 App 自身窗口时才等待窗口服务器完成刷新。
            if needsWindowServerFlush {
                try? await Task.sleep(nanoseconds: 30_000_000)
            }
            
            do {
                let screens = NSScreen.screens
                guard !screens.isEmpty else { return }
                
                // 采用现代 ScreenCaptureKit 并带有重试机制捕获
                let capturedScreens = try await self.captureAllScreensSCKWithRetry(screens: screens)
                
                guard !capturedScreens.isEmpty else {
                    _ = PermissionManager.shared.showPermissionAlertIfNeeded()
                    return
                }
                
                self.showOverlayWindows(for: capturedScreens)
            } catch {
                print("MacSnip: ScreenCaptureKit capture failed with error: \(error)")
                _ = PermissionManager.shared.showPermissionAlertIfNeeded()
            }
        }
    }
    
    /// 使用 ScreenCaptureKit 捕获所有显示器画面 (带 2 次重试，解决系统 XPC 瞬时冷启动抖动)
    private func captureAllScreensSCKWithRetry(screens: [NSScreen], retries: Int = 2) async throws -> [(screen: NSScreen, image: NSImage, cgImage: CGImage)] {
        guard #available(macOS 14.0, *) else {
            return []
        }
        
        var lastError: Error?
        
        for attempt in 1...retries {
            do {
                let shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                
                // 排除本 App 自身的所有窗口（遮罩、工具条、设置、历史记录、置顶悬浮窗等），避免抓到自身 UI 残影
                let currentPID = NSRunningApplication.current.processIdentifier
                let currentBundleID = Bundle.main.bundleIdentifier
                let myWindows = shareableContent.windows.filter { window in
                    if let app = window.owningApplication {
                        if app.processID == currentPID { return true }
                        if let currentBID = currentBundleID, app.bundleIdentifier == currentBID { return true }
                    }
                    return false
                }
                
                let myWinDescriptions = myWindows.map { "[\($0.windowID)] \($0.title ?? "untitled")" }.joined(separator: ", ")
                print("MacSnip: SCK captured \(myWindows.count) self-windows to exclude: \(myWinDescriptions)")
                
                var results: [(screen: NSScreen, image: NSImage, cgImage: CGImage)] = []
                
                for screen in screens {
                    guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                        continue
                    }
                    
                    guard let scDisplay = shareableContent.displays.first(where: { $0.displayID == screenNumber }) else {
                        continue
                    }
                    
                    let filter = SCContentFilter(display: scDisplay, excludingWindows: myWindows)
                    let config = SCStreamConfiguration()
                    
                    // 【核心修复 1】按真实物理分辨率（Retina 2x/3x）配置，彻底杜绝 1x 降采样导致的模糊与拉伸
                    let pixelWidth = Int(round(CGFloat(scDisplay.width) * screen.backingScaleFactor))
                    let pixelHeight = Int(round(CGFloat(scDisplay.height) * screen.backingScaleFactor))
                    config.width = pixelWidth
                    config.height = pixelHeight
                    config.showsCursor = false
                    config.scalesToFit = false
                    
                    let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    print("MacSnip: Screen '\(screen.localizedName)' captured CGImage size: \(cgImage.width)x\(cgImage.height) (Physical), Screen point size: \(screen.frame.size), Scale: \(screen.backingScaleFactor)")
                    
                    let nsImage = NSImage(cgImage: cgImage, size: screen.frame.size)
                    results.append((screen: screen, image: nsImage, cgImage: cgImage))
                }
                
                if !results.isEmpty {
                    return results
                }
            } catch {
                lastError = error
                if attempt < retries {
                    try? await Task.sleep(nanoseconds: 180_000_000) // 等待 180ms 重试
                    continue
                }
            }
        }
        
        if let err = lastError {
            throw err
        }
        
        return []
    }
    
    private func showOverlayWindows(for captured: [(screen: NSScreen, image: NSImage, cgImage: CGImage)]) {
        let mouseLocation = NSEvent.mouseLocation
        var keyWindow: CaptureOverlayWindow?
        
        for item in captured {
            let window = CaptureOverlayWindow(
                screen: item.screen,
                backgroundImage: item.image,
                backgroundCGImage: item.cgImage
            )
            window.overlayView.delegate = self
            overlayWindows.append(window)
            window.orderFrontRegardless()
            
            if NSMouseInRect(mouseLocation, item.screen.frame, false) {
                keyWindow = window
            }
        }
        
        let targetWindow = keyWindow ?? overlayWindows.first
        targetWindow?.makeKey()
        if let overlay = targetWindow?.overlayView {
            targetWindow?.makeFirstResponder(overlay)
        }
        
        // 瞬间将全局光标设置为十字
        if !isCursorPushed {
            NSCursor.crosshair.push()
            isCursorPushed = true
        }
        NSCursor.crosshair.set()
    }
    
    func closeAllOverlays() {
        if isCursorPushed {
            NSCursor.pop()
            isCursorPushed = false
        }
        
        for window in overlayWindows {
            window.close()
        }
        overlayWindows.removeAll()
    }
    
    // MARK: - CaptureOverlayViewDelegate
    
    func captureOverlayDidRequestClose(_ overlayView: CaptureOverlayView) {
        closeAllOverlays()
    }
    
    func captureOverlay(_ overlayView: CaptureOverlayView, didFinishWithImage image: NSImage, screenRect: NSRect, action: FloatingToolbarAction) {
        closeAllOverlays()
        
        switch action {
        case .copy:
            copyToPasteboard(image: image)
            _ = try? HistoryManager.shared.saveScreenshot(image: image)
            
        case .pin:
            let pinWin = PinWindow(image: image, initialFrame: screenRect)
            pinnedWindows.append(pinWin)
            pinWin.makeKeyAndOrderFront(nil)
            _ = try? HistoryManager.shared.saveScreenshot(image: image)
            
        case .save:
            _ = try? HistoryManager.shared.saveScreenshot(image: image)
            
        case .ocr:
            let savedItem = try? HistoryManager.shared.saveScreenshot(image: image)
            
            Task {
                do {
                    let text = try await OCRManager.shared.recognizeText(from: image)
                    if let itemId = savedItem?.id {
                        HistoryManager.shared.updateOCRText(for: itemId, ocrText: text)
                    }
                    await MainActor.run {
                        let ocrPanel = OCRResultPanel(recognizedText: text) { [weak self] reqText in
                            self?.showTranslationPanel(sourceText: reqText)
                        }
                        self.activePanels.append(ocrPanel)
                        ocrPanel.makeKeyAndOrderFront(nil)
                    }
                } catch {
                    print("MacSnip: OCR failed: \(error.localizedDescription)")
                }
            }
            
        case .translate:
            let savedItem = try? HistoryManager.shared.saveScreenshot(image: image)
            
            Task {
                do {
                    let text = try await OCRManager.shared.recognizeText(from: image)
                    if let itemId = savedItem?.id {
                        HistoryManager.shared.updateOCRText(for: itemId, ocrText: text)
                    }
                    await MainActor.run {
                        self.showTranslationPanel(sourceText: text)
                    }
                } catch {
                    print("MacSnip: Translate failed: \(error.localizedDescription)")
                }
            }
            
        case .edit, .cancel:
            break
        }
    }
    
    private func copyToPasteboard(image: NSImage) {
        ImageExportManager.writeToPasteboard(image)
    }
    
    func showTranslationPanel(sourceText: String) {
        let transPanel = TranslationResultPanel(sourceText: sourceText)
        activePanels.append(transPanel)
        transPanel.makeKeyAndOrderFront(nil)
    }
    
    func pinImage(_ image: NSImage) {
        let pinWin = PinWindow(image: image)
        pinnedWindows.append(pinWin)
        pinWin.makeKeyAndOrderFront(nil)
    }
}
