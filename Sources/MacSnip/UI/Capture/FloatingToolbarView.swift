import Foundation
import AppKit

public enum FloatingToolbarAction {
    case copy       // 对号确认并复制
    case edit       // 标注编辑
    case pin        // 贴图置顶
    case save       // 保存到历史
    case ocr        // 文字识别
    case translate  // AI 翻译
    case cancel     // 取消 (通过 Esc)
}

final class FloatingToolbarView: NSView {
    var onAction: ((FloatingToolbarAction) -> Void)?
    
    private struct ToolbarButtonDef {
        let action: FloatingToolbarAction
        let iconName: String
        let title: String
        let isPrimary: Bool
    }
    
    // 左侧功能按钮组 (编辑、保存、OCR、翻译)
    private let toolButtons: [ToolbarButtonDef] = [
        ToolbarButtonDef(action: .edit, iconName: "pencil.and.outline", title: "标注编辑 (E)", isPrimary: false),
        ToolbarButtonDef(action: .save, iconName: "square.and.arrow.down", title: "保存到历史 (S)", isPrimary: false),
        ToolbarButtonDef(action: .ocr, iconName: "text.viewfinder", title: "离线提取文字 (O)", isPrimary: false),
        ToolbarButtonDef(action: .translate, iconName: "globe", title: "AI 翻译 (T)", isPrimary: false),
    ]
    
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 46))
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        self.wantsLayer = true
        self.layer?.cornerRadius = 11
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
        visualEffect.layer?.cornerRadius = 11
        visualEffect.layer?.masksToBounds = true
        visualEffect.layer?.borderWidth = 1
        visualEffect.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        addSubview(visualEffect)
        
        var currentX: CGFloat = 8
        
        // 1. 左侧功能按钮组 (编辑、保存、OCR、翻译) — 尺寸放大 1.1 倍
        for def in toolButtons {
            let btn = createButton(def: def, width: 38, height: 36)
            btn.frame.origin = NSPoint(x: currentX, y: 5)
            visualEffect.addSubview(btn)
            currentX += 40
        }
        
        // 2. 右侧操作区分隔线
        currentX += 2
        let sep = NSBox(frame: NSRect(x: currentX, y: 10, width: 1, height: 26))
        sep.boxType = .separator
        visualEffect.addSubview(sep)
        currentX += 10
        
        // 3. 置顶贴图按钮 (放置在对号左边，放大 1.1 倍)
        let pinDef = ToolbarButtonDef(action: .pin, iconName: "pin.fill", title: "贴在屏幕上置顶 (P)", isPrimary: false)
        let pinBtn = createButton(def: pinDef, width: 38, height: 36)
        pinBtn.frame.origin = NSPoint(x: currentX, y: 5)
        visualEffect.addSubview(pinBtn)
        currentX += 42
        
        // 4. 对号按钮 (确认并复制，放大 1.1 倍)
        let checkDef = ToolbarButtonDef(action: .copy, iconName: "checkmark", title: "确认并复制 (Enter / 退出按 Esc)", isPrimary: true)
        let checkBtn = createButton(def: checkDef, width: 44, height: 36)
        checkBtn.frame.origin = NSPoint(x: currentX, y: 5)
        visualEffect.addSubview(checkBtn)
        currentX += 48
        
        self.frame.size.width = currentX + 4
    }
    
    private func createButton(def: ToolbarButtonDef, width: CGFloat, height: CGFloat) -> NSButton {
        let btn = ToolbarIconButton(
            frame: NSRect(x: 0, y: 0, width: width, height: height),
            isPrimary: def.isPrimary
        )
        btn.toolTip = def.title
        btn.title = ""
        
        if let img = NSImage(systemSymbolName: def.iconName, accessibilityDescription: def.title) {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: def.isPrimary ? .bold : .medium)
            btn.image = img.withSymbolConfiguration(config)
        }
        
        btn.target = self
        btn.action = #selector(buttonTapped(_:))
        btn.tag = tag(for: def.action)
        return btn
    }
    
    private func tag(for action: FloatingToolbarAction) -> Int {
        switch action {
        case .copy: return 1
        case .edit: return 2
        case .pin: return 3
        case .save: return 4
        case .ocr: return 5
        case .translate: return 6
        case .cancel: return 7
        }
    }
    
    private func action(for tag: Int) -> FloatingToolbarAction? {
        switch tag {
        case 1: return .copy
        case 2: return .edit
        case 3: return .pin
        case 4: return .save
        case 5: return .ocr
        case 6: return .translate
        case 7: return .cancel
        default: return nil
        }
    }
    
    @objc private func buttonTapped(_ sender: NSButton) {
        if let act = action(for: sender.tag) {
            onAction?(act)
        }
    }
}

/// 自定义高质感悬停按钮
private final class ToolbarIconButton: NSButton {
    private let isPrimary: Bool
    
    init(frame: NSRect, isPrimary: Bool) {
        self.isPrimary = isPrimary
        super.init(frame: frame)
        
        self.isBordered = false
        self.bezelStyle = .texturedRounded
        self.wantsLayer = true
        self.layer?.cornerRadius = 6
        self.layer?.masksToBounds = true
        
        if isPrimary {
            self.layer?.backgroundColor = NSColor.systemGreen.cgColor
            self.contentTintColor = .white
        } else {
            self.layer?.backgroundColor = NSColor.clear.cgColor
            self.contentTintColor = NSColor.white.withAlphaComponent(0.92)
        }
        
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func mouseEntered(with event: NSEvent) {
        if isPrimary {
            self.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.85).cgColor
        } else {
            self.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.20).cgColor
            self.contentTintColor = .white
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        if isPrimary {
            self.layer?.backgroundColor = NSColor.systemGreen.cgColor
        } else {
            self.layer?.backgroundColor = NSColor.clear.cgColor
            self.contentTintColor = NSColor.white.withAlphaComponent(0.92)
        }
    }
}
