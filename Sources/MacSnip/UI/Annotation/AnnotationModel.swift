import Foundation
import AppKit

public enum AnnotationTool: String, CaseIterable, Identifiable {
    case rectangle = "矩形"
    case arrow = "箭头"
    case pen = "画笔"
    case highlighter = "高亮"
    case mosaic = "马赛克"
    case text = "文字"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .rectangle: return "rectangle"
        case .arrow: return "arrow.up.right"
        case .pen: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .mosaic: return "checkerboard.rectangle"
        case .text: return "character.cursor.ibeam"
        }
    }
}

public struct AnnotationElement {
    public var id: UUID = UUID()
    public var tool: AnnotationTool
    public var startPoint: CGPoint
    public var endPoint: CGPoint
    public var points: [CGPoint] = []
    public var color: NSColor
    public var strokeWidth: CGFloat
    public var text: String = ""
    
    public init(
        tool: AnnotationTool,
        startPoint: CGPoint,
        endPoint: CGPoint,
        points: [CGPoint] = [],
        color: NSColor = .systemRed,
        strokeWidth: CGFloat = 3.0,
        text: String = ""
    ) {
        self.tool = tool
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.points = points
        self.color = color
        self.strokeWidth = strokeWidth
        self.text = text
    }
}

public final class AnnotationHistory {
    private var undoStack: [AnnotationElement] = []
    private var redoStack: [AnnotationElement] = []
    
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    
    public var elements: [AnnotationElement] { undoStack }
    
    public func addElement(_ element: AnnotationElement) {
        undoStack.append(element)
        redoStack.removeAll()
    }
    
    public func undo() -> AnnotationElement? {
        guard let last = undoStack.popLast() else { return nil }
        redoStack.append(last)
        return last
    }
    
    public func redo() -> AnnotationElement? {
        guard let last = redoStack.popLast() else { return nil }
        undoStack.append(last)
        return last
    }
    
    public func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
