import Foundation
import AppKit
import CoreImage

final class AnnotationCanvasView: NSView, NSTextFieldDelegate {
    let baseImage: NSImage
    let scale: CGFloat
    let history = AnnotationHistory()
    
    var currentTool: AnnotationTool = .rectangle
    var currentColor: NSColor = .systemRed
    var currentStrokeWidth: CGFloat = 3.0
    
    private var currentElement: AnnotationElement?
    private var isDrawing = false
    
    // 缓存生成的全图马赛克图像
    private var mosaicBaseImage: NSImage?
    
    // 内联文字输入框
    private var activeTextField: NSTextField?
    private var textInputOrigin: CGPoint = .zero
    
    var onHistoryChanged: (() -> Void)?
    var onCancelRequested: (() -> Void)?
    
    init(frame: NSRect, baseImage: NSImage, scale: CGFloat = 2.0) {
        self.baseImage = baseImage
        self.scale = scale
        super.init(frame: frame)
        self.wantsLayer = true
        self.layer?.borderWidth = 2.0
        self.layer?.borderColor = NSColor.systemBlue.cgColor
        self.layer?.cornerRadius = 2
        generateMosaicBaseImage()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// 预生成全图马赛克（像素化）滤镜图
    private func generateMosaicBaseImage() {
        guard let tiff = baseImage.tiffRepresentation,
              let ciImage = CIImage(data: tiff) else { return }
        
        let filter = CIFilter(name: "CIPixellate")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(16.0, forKey: kCIInputScaleKey)
        
        guard let output = filter?.outputImage else { return }
        let rep = NSCIImageRep(ciImage: output)
        let mosaicImg = NSImage(size: baseImage.size)
        mosaicImg.addRepresentation(rep)
        self.mosaicBaseImage = mosaicImg
    }
    
    // MARK: - 鼠标绘制事件
    
    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        
        // 如果当前有正在输入的文字框，先提交
        if activeTextField != nil {
            commitActiveText()
            return
        }
        
        if currentTool == .text {
            startInlineTextInput(at: location)
            return
        }
        
        isDrawing = true
        currentElement = AnnotationElement(
            tool: currentTool,
            startPoint: location,
            endPoint: location,
            points: [location],
            color: currentColor,
            strokeWidth: currentStrokeWidth
        )
        needsDisplay = true
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard isDrawing, var element = currentElement else { return }
        let location = convert(event.locationInWindow, from: nil)
        element.endPoint = location
        element.points.append(location)
        currentElement = element
        needsDisplay = true
    }
    
    override func mouseUp(with event: NSEvent) {
        guard isDrawing else { return }
        isDrawing = false
        
        if let element = currentElement {
            history.addElement(element)
            currentElement = nil
            onHistoryChanged?()
            needsDisplay = true
        }
    }
    
    // MARK: - 即点即输极简内联文字输入 (CleanShot X 风格)
    
    private func startInlineTextInput(at location: CGPoint) {
        textInputOrigin = location
        
        let fontSize = max(16, currentStrokeWidth * 5.0)
        let initialWidth: CGFloat = 160
        let fieldHeight: CGFloat = fontSize + 12
        
        let textField = NSTextField(frame: NSRect(x: location.x, y: location.y - 2, width: initialWidth, height: fieldHeight))
        textField.font = NSFont.boldSystemFont(ofSize: fontSize)
        textField.textColor = currentColor
        textField.drawsBackground = false
        textField.isBordered = false
        textField.isBezeled = false
        textField.focusRingType = .none
        textField.wantsLayer = true
        
        // 精致轻量虚线下划线，提示输入位置
        let borderLayer = CAShapeLayer()
        borderLayer.strokeColor = currentColor.withAlphaComponent(0.8).cgColor
        borderLayer.fillColor = NSColor.clear.cgColor
        borderLayer.lineWidth = 1.5
        borderLayer.lineDashPattern = [4, 3]
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: initialWidth, y: 0))
        borderLayer.path = path
        textField.layer?.addSublayer(borderLayer)
        
        textField.delegate = self
        textField.placeholderString = "输入文字..."
        
        addSubview(textField)
        window?.makeFirstResponder(textField)
        self.activeTextField = textField
    }
    
    func controlTextDidChange(_ obj: Notification) {
        guard let textField = activeTextField else { return }
        let size = (textField.stringValue as NSString).size(withAttributes: [.font: textField.font ?? NSFont.systemFont(ofSize: 16)])
        let newWidth = max(160, min(size.width + 30, bounds.width - textInputOrigin.x - 10))
        textField.frame.size.width = newWidth
        
        // 更新下划线长度
        if let sublayers = textField.layer?.sublayers {
            for layer in sublayers {
                if let shape = layer as? CAShapeLayer {
                    let path = CGMutablePath()
                    path.move(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: newWidth, y: 0))
                    shape.path = path
                }
            }
        }
    }
    
    func commitActiveText() {
        guard let textField = activeTextField else { return }
        let text = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !text.isEmpty {
            let element = AnnotationElement(
                tool: .text,
                startPoint: textInputOrigin,
                endPoint: textInputOrigin,
                color: currentColor,
                strokeWidth: currentStrokeWidth,
                text: text
            )
            history.addElement(element)
            onHistoryChanged?()
        }
        
        textField.removeFromSuperview()
        activeTextField = nil
        needsDisplay = true
    }
    
    func cancelActiveText() {
        activeTextField?.removeFromSuperview()
        activeTextField = nil
        needsDisplay = true
    }
    
    // 监听按键：回车提交，Esc 取消
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(insertNewline(_:)) {
            commitActiveText()
            return true
        } else if commandSelector == #selector(cancelOperation(_:)) {
            cancelActiveText()
            return true
        }
        return false
    }
    
    // MARK: - 绘制
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // 1. 绘制底图
        baseImage.draw(in: bounds)
        
        // 2. 绘制所有已提交图元
        for elem in history.elements {
            drawElement(elem, in: context)
        }
        
        // 3. 绘制当前正在拖拽的图元
        if let current = currentElement {
            drawElement(current, in: context)
        }
    }
    
    private func drawElement(_ element: AnnotationElement, in context: CGContext) {
        context.saveGState()
        
        switch element.tool {
        case .rectangle:
            context.setStrokeColor(element.color.cgColor)
            context.setLineWidth(element.strokeWidth)
            let rect = makeRect(from: element.startPoint, to: element.endPoint)
            context.stroke(rect)
            
        case .arrow:
            context.setStrokeColor(element.color.cgColor)
            context.setFillColor(element.color.cgColor)
            context.setLineWidth(element.strokeWidth)
            drawArrow(from: element.startPoint, to: element.endPoint, strokeWidth: element.strokeWidth, in: context)
            
        case .pen:
            context.setStrokeColor(element.color.cgColor)
            context.setLineWidth(element.strokeWidth)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            if element.points.count > 1 {
                context.beginPath()
                context.move(to: element.points[0])
                for pt in element.points.dropFirst() {
                    context.addLine(to: pt)
                }
                context.strokePath()
            }
            
        case .highlighter:
            context.setStrokeColor(element.color.withAlphaComponent(0.4).cgColor)
            context.setLineWidth(element.strokeWidth * 3.5)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            if element.points.count > 1 {
                context.beginPath()
                context.move(to: element.points[0])
                for pt in element.points.dropFirst() {
                    context.addLine(to: pt)
                }
                context.strokePath()
            }
            
        case .mosaic:
            if let mosaicImg = mosaicBaseImage {
                let rect = makeRect(from: element.startPoint, to: element.endPoint)
                context.saveGState()
                context.clip(to: rect)
                mosaicImg.draw(in: bounds)
                context.restoreGState()
                
                context.setStrokeColor(NSColor.white.withAlphaComponent(0.4).cgColor)
                context.setLineWidth(1)
                context.setLineDash(phase: 0, lengths: [4, 4])
                context.stroke(rect)
            }
            
        case .text:
            let font = NSFont.boldSystemFont(ofSize: max(16, element.strokeWidth * 5.0))
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.shadowBlurRadius = 2.0
            
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: element.color,
                .shadow: shadow
            ]
            let attrStr = NSAttributedString(string: element.text, attributes: attrs)
            attrStr.draw(at: element.startPoint)
        }
        
        context.restoreGState()
    }
    
    private func makeRect(from p1: CGPoint, to p2: CGPoint) -> CGRect {
        let x = min(p1.x, p2.x)
        let y = min(p1.y, p2.y)
        let w = abs(p1.x - p2.x)
        let h = abs(p1.y - p2.y)
        return CGRect(x: x, y: y, width: max(w, 1), height: max(h, 1))
    }
    
    private func drawArrow(from start: CGPoint, to end: CGPoint, strokeWidth: CGFloat, in context: CGContext) {
        let length = hypot(end.x - start.x, end.y - start.y)
        guard length > 5 else { return }
        
        // 主线段
        context.beginPath()
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
        
        // 箭头头部
        let arrowLength: CGFloat = max(12, strokeWidth * 3.5)
        let arrowAngle: CGFloat = .pi / 6.0
        let angle = atan2(end.y - start.y, end.x - start.x)
        
        let p1 = CGPoint(
            x: end.x - arrowLength * cos(angle - arrowAngle),
            y: end.y - arrowLength * sin(angle - arrowAngle)
        )
        let p2 = CGPoint(
            x: end.x - arrowLength * cos(angle + arrowAngle),
            y: end.y - arrowLength * sin(angle + arrowAngle)
        )
        
        context.beginPath()
        context.move(to: end)
        context.addLine(to: p1)
        context.addLine(to: p2)
        context.closePath()
        context.fillPath()
    }
    
    // MARK: - 合成最终图像
    
    func renderCompositeImage() -> NSImage {
        commitActiveText()
        
        let width = bounds.width
        let height = bounds.height
        let pixelWidth = Int(round(width * scale))
        let pixelHeight = Int(round(height * scale))
        
        guard pixelWidth > 0, pixelHeight > 0,
              let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelWidth,
                pixelsHigh: pixelHeight,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
              ) else {
            return baseImage
        }
        
        rep.size = bounds.size
        
        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            NSGraphicsContext.restoreGraphicsState()
            return baseImage
        }
        
        NSGraphicsContext.current = context
        let cgContext = context.cgContext
        
        // rep.size 已建立 point 到物理像素的映射，避免再次缩放 CTM
        
        // 1. 绘制高清底图
        baseImage.draw(in: bounds)
        
        // 2. 绘制所有标注矢量元素
        for elem in history.elements {
            drawElement(elem, in: cgContext)
        }
        
        NSGraphicsContext.restoreGraphicsState()
        
        let finalImage = NSImage(size: bounds.size)
        finalImage.addRepresentation(rep)
        return finalImage
    }
}
