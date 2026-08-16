import Foundation
import AppKit

final class AnnotationToolbarView: NSView {
    var onToolSelected: ((AnnotationTool) -> Void)?
    var onColorSelected: ((NSColor) -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onDone: (() -> Void)?
    
    private var toolButtons: [AnnotationTool: NSButton] = [:]
    private var colorButtons: [ColorDotButton] = []
    private var undoButton: NSButton?
    private var redoButton: NSButton?
    
    private let presetColors: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .systemPurple, .black
    ]
    
    private var currentColor: NSColor = .systemRed
    
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 520, height: 42))
        setupVisuals()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupVisuals() {
        self.wantsLayer = true
        self.layer?.cornerRadius = 10
        self.layer?.masksToBounds = false
        self.layer?.shadowColor = NSColor.black.cgColor
        self.layer?.shadowOpacity = 0.35
        self.layer?.shadowOffset = CGSize(width: 0, height: -3)
        self.layer?.shadowRadius = 8
        
        self.appearance = NSAppearance(named: .darkAqua)
        
        let visualEffect = NSVisualEffectView(frame: bounds)
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.material = .popover
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 10
        visualEffect.layer?.masksToBounds = true
        visualEffect.layer?.borderWidth = 1
        visualEffect.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        addSubview(visualEffect)
        
        var currentX: CGFloat = 8
        
        // ============================================
        // 1. 绘图工具组 (矩形、箭头、画笔、高亮、马赛克、文字)
        // ============================================
        for tool in AnnotationTool.allCases {
            let btn = createIconButton(systemName: tool.iconName, tooltip: tool.rawValue)
            btn.frame = NSRect(x: currentX, y: 5, width: 32, height: 32)
            btn.target = self
            btn.action = #selector(toolButtonClicked(_:))
            visualEffect.addSubview(btn)
            toolButtons[tool] = btn
            currentX += 34
        }
        
        // 分隔线 1
        currentX += 2
        addSeparator(at: currentX, to: visualEffect)
        currentX += 10
        
        // ============================================
        // 2. 颜色选择组 (纯净 7 种实心色块)
        // ============================================
        for color in presetColors {
            let dotBtn = ColorDotButton(color: color, isSelected: color == currentColor)
            dotBtn.frame = NSRect(x: currentX, y: 11, width: 20, height: 20)
            dotBtn.target = self
            dotBtn.action = #selector(colorDotClicked(_:))
            visualEffect.addSubview(dotBtn)
            colorButtons.append(dotBtn)
            currentX += 24
        }
        
        // 分隔线 2
        currentX += 4
        addSeparator(at: currentX, to: visualEffect)
        currentX += 10
        
        // ============================================
        // 3. 撤销 / 重做组
        // ============================================
        let undoBtn = createIconButton(systemName: "arrow.uturn.backward", tooltip: "撤销 (⌘Z)")
        undoBtn.frame = NSRect(x: currentX, y: 5, width: 32, height: 32)
        undoBtn.target = self
        undoBtn.action = #selector(undoClicked)
        visualEffect.addSubview(undoBtn)
        self.undoButton = undoBtn
        currentX += 34
        
        let redoBtn = createIconButton(systemName: "arrow.uturn.forward", tooltip: "重做 (⌘⇧Z)")
        redoBtn.frame = NSRect(x: currentX, y: 5, width: 32, height: 32)
        redoBtn.target = self
        redoBtn.action = #selector(redoClicked)
        visualEffect.addSubview(redoBtn)
        self.redoButton = redoBtn
        currentX += 34
        
        // 分隔线 3
        currentX += 2
        addSeparator(at: currentX, to: visualEffect)
        currentX += 10
        
        // ============================================
        // 4. 完成按钮 (绿色高亮对号)
        // ============================================
        let doneBtn = NSButton(frame: NSRect(x: currentX, y: 5, width: 36, height: 32))
        doneBtn.title = ""
        doneBtn.bezelStyle = .texturedRounded
        doneBtn.isBordered = false
        doneBtn.toolTip = "完成并复制 (Enter)"
        doneBtn.wantsLayer = true
        doneBtn.layer?.cornerRadius = 6
        doneBtn.layer?.backgroundColor = NSColor.systemGreen.cgColor
        if let checkImg = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "完成") {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .bold)
            doneBtn.image = checkImg.withSymbolConfiguration(config)
            doneBtn.contentTintColor = .white
        }
        doneBtn.target = self
        doneBtn.action = #selector(doneClicked)
        visualEffect.addSubview(doneBtn)
        currentX += 42
        
        self.frame.size.width = currentX + 4
        
        setSelectedTool(.rectangle)
    }
    
    private func createIconButton(systemName: String, tooltip: String) -> NSButton {
        let button = NSButton()
        button.title = ""
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.toolTip = tooltip
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        if let img = NSImage(systemSymbolName: systemName, accessibilityDescription: tooltip) {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            button.image = img.withSymbolConfiguration(config)
            button.contentTintColor = .white
        }
        return button
    }
    
    private func addSeparator(at x: CGFloat, to parent: NSView) {
        let sep = NSBox(frame: NSRect(x: x, y: 9, width: 1, height: 24))
        sep.boxType = .separator
        parent.addSubview(sep)
    }
    
    func setSelectedTool(_ tool: AnnotationTool) {
        for (t, btn) in toolButtons {
            if t == tool {
                btn.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.28).cgColor
            } else {
                btn.layer?.backgroundColor = NSColor.clear.cgColor
            }
        }
    }
    
    @objc private func toolButtonClicked(_ sender: NSButton) {
        for (tool, btn) in toolButtons where btn == sender {
            setSelectedTool(tool)
            onToolSelected?(tool)
            break
        }
    }
    
    @objc private func colorDotClicked(_ sender: ColorDotButton) {
        self.currentColor = sender.color
        for dot in colorButtons {
            dot.setSelected(dot.color == sender.color)
        }
        onColorSelected?(sender.color)
    }
    
    @objc private func undoClicked() {
        onUndo?()
    }
    
    @objc private func redoClicked() {
        onRedo?()
    }
    
    @objc private func doneClicked() {
        onDone?()
    }
}

/// 纯实心圆颜色选择按钮 (彻底杜绝任何系统文字和残留)
final class ColorDotButton: NSButton {
    let color: NSColor
    private var isDotSelected: Bool = false
    
    init(color: NSColor, isSelected: Bool) {
        self.color = color
        self.isDotSelected = isSelected
        super.init(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        
        self.title = ""
        self.attributedTitle = NSAttributedString(string: "")
        self.isBordered = false
        self.wantsLayer = true
        self.layer?.cornerRadius = 10
        self.layer?.masksToBounds = true
        updateVisuals()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setSelected(_ selected: Bool) {
        self.isDotSelected = selected
        updateVisuals()
    }
    
    private func updateVisuals() {
        self.layer?.backgroundColor = color.cgColor
        if isDotSelected {
            self.layer?.borderWidth = 2.5
            self.layer?.borderColor = NSColor.white.cgColor
        } else {
            self.layer?.borderWidth = 1.0
            self.layer?.borderColor = (color == .black ? NSColor.white.withAlphaComponent(0.4) : NSColor.black.withAlphaComponent(0.2)).cgColor
        }
    }
}
