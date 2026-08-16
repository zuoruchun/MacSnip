import Foundation
import AppKit

protocol CaptureOverlayViewDelegate: AnyObject {
    func captureOverlayDidRequestClose(_ overlayView: CaptureOverlayView)
    func captureOverlay(_ overlayView: CaptureOverlayView, didFinishWithImage image: NSImage, screenRect: NSRect, action: FloatingToolbarAction)
}

final class CaptureOverlayView: NSView {
    weak var delegate: CaptureOverlayViewDelegate?
    
    private let backgroundImage: NSImage
    private var selectionRect: NSRect = .zero
    private var isSelecting = false
    private var isMovingSelection = false
    private var isResizingSelection = false
    private var activeHandle: ResizeHandle = .none
    
    private var dragStartPoint: NSPoint = .zero
    private var initialSelectionRect: NSRect = .zero
    
    private var floatingToolbar: FloatingToolbarView?
    private var annotationCanvas: AnnotationCanvasView?
    private var annotationToolbar: AnnotationToolbarView?
    
    private var isAnnotating = false
    
    private enum ResizeHandle {
        case none, topLeft, topMiddle, topRight, middleLeft, middleRight, bottomLeft, bottomMiddle, bottomRight
    }
    
    init(frame: NSRect, backgroundImage: NSImage) {
        self.backgroundImage = backgroundImage
        super.init(frame: frame)
        self.wantsLayer = true
        setupTrackingArea()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupTrackingArea() {
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }
    
    override func resetCursorRects() {
        super.resetCursorRects()
        if !isAnnotating {
            addCursorRect(bounds, cursor: .crosshair)
        }
    }
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            NSCursor.crosshair.set()
            window?.invalidateCursorRects(for: self)
        }
    }
    
    // MARK: - 键盘与取消事件
    
    override var acceptsFirstResponder: Bool { true }
    
    func handleCancel() {
        if isAnnotating {
            exitAnnotationMode()
        } else {
            delegate?.captureOverlayDidRequestClose(self)
        }
    }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            handleCancel()
        } else if event.keyCode == 36 { // Enter
            if selectionRect.width > 5 && selectionRect.height > 5 {
                confirmSelection(action: .copy)
            }
        } else {
            super.keyDown(with: event)
        }
    }
    
    // MARK: - 鼠标事件
    
    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if !isAnnotating && !selectionRect.isEmpty {
            let handle = detectHandle(at: location)
            if handle != .none {
                switch handle {
                case .topMiddle, .bottomMiddle:
                    NSCursor.resizeUpDown.set()
                case .middleLeft, .middleRight:
                    NSCursor.resizeLeftRight.set()
                default:
                    NSCursor.crosshair.set()
                }
            } else if selectionRect.contains(location) {
                NSCursor.openHand.set()
            } else {
                NSCursor.crosshair.set()
            }
        } else if !isAnnotating {
            NSCursor.crosshair.set()
        }
        needsDisplay = true
    }
    
    override func mouseDown(with event: NSEvent) {
        if isAnnotating { return }
        
        let location = convert(event.locationInWindow, from: nil)
        dragStartPoint = location
        initialSelectionRect = selectionRect
        
        if event.clickCount == 2 && selectionRect.contains(location) {
            confirmSelection(action: .copy)
            return
        }
        
        hideFloatingToolbar()
        
        if !selectionRect.isEmpty {
            let handle = detectHandle(at: location)
            if handle != .none {
                isResizingSelection = true
                activeHandle = handle
                return
            } else if selectionRect.contains(location) {
                isMovingSelection = true
                return
            }
        }
        
        // 开始全新框选
        isSelecting = true
        selectionRect = NSRect(origin: location, size: .zero)
        needsDisplay = true
    }
    
    override func mouseDragged(with event: NSEvent) {
        if isAnnotating { return }
        
        let location = convert(event.locationInWindow, from: nil)
        
        if isSelecting {
            let x = min(dragStartPoint.x, location.x)
            let y = min(dragStartPoint.y, location.y)
            let w = abs(dragStartPoint.x - location.x)
            let h = abs(dragStartPoint.y - location.y)
            selectionRect = NSRect(x: x, y: y, width: w, height: h)
            needsDisplay = true
        } else if isMovingSelection {
            let deltaX = location.x - dragStartPoint.x
            let deltaY = location.y - dragStartPoint.y
            var newRect = initialSelectionRect.offsetBy(dx: deltaX, dy: deltaY)
            
            // 约束在屏幕内部
            newRect.origin.x = max(0, min(bounds.width - newRect.width, newRect.origin.x))
            newRect.origin.y = max(0, min(bounds.height - newRect.height, newRect.origin.y))
            
            selectionRect = newRect
            needsDisplay = true
        } else if isResizingSelection {
            resizeSelection(to: location)
            needsDisplay = true
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        if isAnnotating { return }
        
        isSelecting = false
        isMovingSelection = false
        isResizingSelection = false
        activeHandle = .none
        
        // 修正负尺寸并过滤微小误触
        selectionRect = selectionRect.standardized
        if selectionRect.width >= 10 && selectionRect.height >= 10 {
            showFloatingToolbar()
        } else {
            selectionRect = .zero
        }
        needsDisplay = true
    }
    
    // MARK: - 手柄检测与缩放
    
    private func detectHandle(at point: NSPoint) -> ResizeHandle {
        guard !selectionRect.isEmpty else { return .none }
        let handleSize: CGFloat = 10
        
        let rects: [(ResizeHandle, NSRect)] = [
            (.topLeft, NSRect(x: selectionRect.minX - handleSize, y: selectionRect.maxY - handleSize, width: handleSize * 2, height: handleSize * 2)),
            (.topMiddle, NSRect(x: selectionRect.midX - handleSize, y: selectionRect.maxY - handleSize, width: handleSize * 2, height: handleSize * 2)),
            (.topRight, NSRect(x: selectionRect.maxX - handleSize, y: selectionRect.maxY - handleSize, width: handleSize * 2, height: handleSize * 2)),
            (.middleLeft, NSRect(x: selectionRect.minX - handleSize, y: selectionRect.midY - handleSize, width: handleSize * 2, height: handleSize * 2)),
            (.middleRight, NSRect(x: selectionRect.maxX - handleSize, y: selectionRect.midY - handleSize, width: handleSize * 2, height: handleSize * 2)),
            (.bottomLeft, NSRect(x: selectionRect.minX - handleSize, y: selectionRect.minY - handleSize, width: handleSize * 2, height: handleSize * 2)),
            (.bottomMiddle, NSRect(x: selectionRect.midX - handleSize, y: selectionRect.minY - handleSize, width: handleSize * 2, height: handleSize * 2)),
            (.bottomRight, NSRect(x: selectionRect.maxX - handleSize, y: selectionRect.minY - handleSize, width: handleSize * 2, height: handleSize * 2))
        ]
        
        for (handle, rect) in rects {
            if rect.contains(point) {
                return handle
            }
        }
        return .none
    }
    
    private func resizeSelection(to point: NSPoint) {
        var rect = initialSelectionRect
        switch activeHandle {
        case .topLeft:
            rect.origin.x = point.x
            rect.size.width = initialSelectionRect.maxX - point.x
            rect.size.height = point.y - initialSelectionRect.minY
        case .topMiddle:
            rect.size.height = point.y - initialSelectionRect.minY
        case .topRight:
            rect.size.width = point.x - initialSelectionRect.minX
            rect.size.height = point.y - initialSelectionRect.minY
        case .middleLeft:
            rect.origin.x = point.x
            rect.size.width = initialSelectionRect.maxX - point.x
        case .middleRight:
            rect.size.width = point.x - initialSelectionRect.minX
        case .bottomLeft:
            rect.origin.x = point.x
            rect.origin.y = point.y
            rect.size.width = initialSelectionRect.maxX - point.x
            rect.size.height = initialSelectionRect.maxY - point.y
        case .bottomMiddle:
            rect.origin.y = point.y
            rect.size.height = initialSelectionRect.maxY - point.y
        case .bottomRight:
            rect.origin.y = point.y
            rect.size.width = point.x - initialSelectionRect.minX
            rect.size.height = initialSelectionRect.maxY - point.y
        case .none:
            break
        }
        selectionRect = rect.standardized
    }
    
    // MARK: - 绘制
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // 1. 绘制底图
        backgroundImage.draw(in: bounds)
        
        // 2. 绘制选区阴影与边界 (只有选区非空时才绘制四周暗色阴影)
        if !selectionRect.isEmpty {
            // 四个方位的暗色半透明遮罩
            let topRect = NSRect(x: 0, y: selectionRect.maxY, width: bounds.width, height: max(0, bounds.height - selectionRect.maxY))
            let bottomRect = NSRect(x: 0, y: 0, width: bounds.width, height: max(0, selectionRect.minY))
            let leftRect = NSRect(x: 0, y: selectionRect.minY, width: max(0, selectionRect.minX), height: selectionRect.height)
            let rightRect = NSRect(x: selectionRect.maxX, y: selectionRect.minY, width: max(0, bounds.width - selectionRect.maxX), height: selectionRect.height)
            
            context.setFillColor(NSColor.black.withAlphaComponent(0.40).cgColor)
            context.fill([topRect, bottomRect, leftRect, rightRect])
            
            // 绘制选区高亮边框 (标注模式下也保持可见)
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(2.0)
            context.stroke(selectionRect)
            
            if !isAnnotating {
                // 绘制 8 个控制手柄
                drawHandles(in: context)
            }
            
            // 绘制尺寸提示标签 (W x H)
            drawDimensionLabel(in: context)
        }
    }
    
    private func drawHandles(in context: CGContext) {
        let handleSize: CGFloat = 6
        let points: [CGPoint] = [
            CGPoint(x: selectionRect.minX, y: selectionRect.maxY),
            CGPoint(x: selectionRect.midX, y: selectionRect.maxY),
            CGPoint(x: selectionRect.maxX, y: selectionRect.maxY),
            CGPoint(x: selectionRect.minX, y: selectionRect.midY),
            CGPoint(x: selectionRect.maxX, y: selectionRect.midY),
            CGPoint(x: selectionRect.minX, y: selectionRect.minY),
            CGPoint(x: selectionRect.midX, y: selectionRect.minY),
            CGPoint(x: selectionRect.maxX, y: selectionRect.minY)
        ]
        
        context.setFillColor(NSColor.white.cgColor)
        context.setStrokeColor(NSColor.systemBlue.cgColor)
        context.setLineWidth(1.5)
        
        for pt in points {
            let rect = CGRect(x: pt.x - handleSize / 2, y: pt.y - handleSize / 2, width: handleSize, height: handleSize)
            context.fill(rect)
            context.stroke(rect)
        }
    }
    
    private func drawDimensionLabel(in context: CGContext) {
        let text = "\(Int(selectionRect.width)) × \(Int(selectionRect.height))"
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let textSize = attrStr.size()
        
        let labelPadding: CGFloat = 6
        let labelWidth = textSize.width + labelPadding * 2
        let labelHeight = textSize.height + 6
        
        var labelOrigin = CGPoint(x: selectionRect.minX, y: selectionRect.maxY + 6)
        if labelOrigin.y + labelHeight > bounds.maxY {
            labelOrigin.y = selectionRect.minY - labelHeight - 6
        }
        if labelOrigin.x + labelWidth > bounds.maxX {
            labelOrigin.x = bounds.maxX - labelWidth - 6
        }
        
        let labelRect = CGRect(origin: labelOrigin, size: CGSize(width: labelWidth, height: labelHeight))
        
        context.setFillColor(NSColor.black.withAlphaComponent(0.75).cgColor)
        let path = CGPath(roundedRect: labelRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        context.addPath(path)
        context.fillPath()
        
        attrStr.draw(at: CGPoint(x: labelOrigin.x + labelPadding, y: labelOrigin.y + 3))
    }
    
    // MARK: - 浮动工具栏管理
    
    private func showFloatingToolbar() {
        hideFloatingToolbar()
        
        let toolbar = FloatingToolbarView()
        toolbar.onAction = { [weak self] action in
            guard let self = self else { return }
            switch action {
            case .cancel:
                self.delegate?.captureOverlayDidRequestClose(self)
            case .edit:
                self.enterAnnotationMode()
            case .copy, .pin, .save, .ocr, .translate:
                self.confirmSelection(action: action)
            }
        }
        
        let toolbarWidth = toolbar.frame.width
        let toolbarHeight = toolbar.frame.height
        
        var toolbarX = selectionRect.maxX - toolbarWidth
        var toolbarY = selectionRect.minY - toolbarHeight - 8
        
        if toolbarY < 10 {
            toolbarY = selectionRect.maxY + 8
        }
        if toolbarY + toolbarHeight > bounds.maxY {
            toolbarY = selectionRect.maxY - toolbarHeight - 8
        }
        if toolbarX < 10 {
            toolbarX = 10
        }
        
        toolbar.frame.origin = NSPoint(x: toolbarX, y: toolbarY)
        addSubview(toolbar)
        self.floatingToolbar = toolbar
    }
    
    private func hideFloatingToolbar() {
        floatingToolbar?.removeFromSuperview()
        floatingToolbar = nil
    }
    
    // MARK: - 标注模式
    
    private func enterAnnotationMode() {
        hideFloatingToolbar()
        isAnnotating = true
        
        guard let croppedImage = cropSelectedImage() else { return }
        
        let canvas = AnnotationCanvasView(frame: selectionRect, baseImage: croppedImage)
        canvas.onCancelRequested = { [weak self] in
            self?.exitAnnotationMode()
        }
        addSubview(canvas)
        self.annotationCanvas = canvas
        
        let toolbar = AnnotationToolbarView()
        toolbar.onToolSelected = { [weak canvas] tool in canvas?.currentTool = tool }
        toolbar.onColorSelected = { [weak canvas] color in canvas?.currentColor = color }
        toolbar.onUndo = { [weak canvas] in
            _ = canvas?.history.undo()
            canvas?.needsDisplay = true
        }
        toolbar.onRedo = { [weak canvas] in
            _ = canvas?.history.redo()
            canvas?.needsDisplay = true
        }
        toolbar.onDone = { [weak self] in
            guard let self = self, let canvas = self.annotationCanvas else { return }
            let finalImage = canvas.renderCompositeImage()
            let screenRect = self.window?.convertToScreen(self.selectionRect) ?? self.selectionRect
            self.delegate?.captureOverlay(self, didFinishWithImage: finalImage, screenRect: screenRect, action: .copy)
        }
        
        var toolbarX = selectionRect.midX - toolbar.frame.width / 2
        var toolbarY = selectionRect.minY - toolbar.frame.height - 8
        if toolbarY < 10 { toolbarY = selectionRect.maxY + 8 }
        if toolbarX < 10 { toolbarX = 10 }
        
        toolbar.frame.origin = NSPoint(x: toolbarX, y: toolbarY)
        addSubview(toolbar)
        self.annotationToolbar = toolbar
        
        needsDisplay = true
    }
    
    private func exitAnnotationMode() {
        annotationCanvas?.removeFromSuperview()
        annotationCanvas = nil
        annotationToolbar?.removeFromSuperview()
        annotationToolbar = nil
        isAnnotating = false
        showFloatingToolbar()
        needsDisplay = true
    }
    
    // MARK: - 图像裁剪与确认
    
    private func cropSelectedImage() -> NSImage? {
        guard selectionRect.width > 0 && selectionRect.height > 0 else { return nil }
        
        let cropped = NSImage(size: selectionRect.size)
        cropped.lockFocus()
        backgroundImage.draw(
            in: NSRect(origin: .zero, size: selectionRect.size),
            from: selectionRect,
            operation: .copy,
            fraction: 1.0
        )
        cropped.unlockFocus()
        return cropped
    }
    
    private func confirmSelection(action: FloatingToolbarAction) {
        let finalImage: NSImage
        if isAnnotating, let canvas = annotationCanvas {
            finalImage = canvas.renderCompositeImage()
        } else if let cropped = cropSelectedImage() {
            finalImage = cropped
        } else {
            return
        }
        
        let screenRect = window?.convertToScreen(selectionRect) ?? selectionRect
        delegate?.captureOverlay(self, didFinishWithImage: finalImage, screenRect: screenRect, action: action)
    }
}
