import SwiftUI
import AppKit

public struct HistoryView: View {
    @ObservedObject var historyManager = HistoryManager.shared
    @State private var searchText: String = ""
    @State private var selectedItem: HistoryItem?
    
    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 16)
    ]
    
    public init() {}
    
    private var filteredItems: [HistoryItem] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return historyManager.items
        }
        let query = searchText.lowercased()
        return historyManager.items.filter { item in
            if let ocr = item.ocrText, ocr.lowercased().contains(query) {
                return true
            }
            return item.imageFileName.lowercased().contains(query)
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // 顶栏搜索与操作
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("搜索 OCR 识别文本或文件名...", text: $searchText)
                    .textFieldStyle(.plain)
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                Text("共 \(filteredItems.count) 条记录")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button(action: {
                    historyManager.loadHistory()
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("刷新")
                
                Button(role: .destructive, action: {
                    let alert = NSAlert()
                    alert.messageText = "清空历史记录"
                    alert.informativeText = "确定要清空所有本地保存的截图历史吗？此操作无法撤销。"
                    alert.addButton(withTitle: "清空")
                    alert.addButton(withTitle: "取消")
                    if alert.runModal() == .alertFirstButtonReturn {
                        historyManager.clearAll()
                    }
                }) {
                    Image(systemName: "trash")
                }
                .help("清空全部")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // 历史网格列表
            if filteredItems.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(searchText.isEmpty ? "暂无截图历史" : "未找到匹配的截图")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("使用 ⌘⇧A 截图后，将自动保存在这里。")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.8))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(filteredItems) { item in
                            HistoryCardView(item: item, onSelect: {
                                selectedItem = item
                            })
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(minWidth: 700, minHeight: 480)
        .sheet(item: $selectedItem) { item in
            HistoryDetailSheet(item: item)
        }
    }
}

private struct HistoryCardView: View {
    let item: HistoryItem
    let onSelect: () -> Void
    @State private var isHovered = false
    
    private var dateFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateFormat = "MM-dd HH:mm"
        return df
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 缩略图
            ZStack {
                Color(NSColor.controlBackgroundColor)
                
                if let nsImage = HistoryManager.shared.loadImage(for: item) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                }
            }
            .frame(height: 120)
            .cornerRadius(6)
            .clipped()
            
            // 信息与快捷操作
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dateFormatter.string(from: item.timestamp))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                    Text("\(item.width) × \(item.height)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                // 快捷操作按钮
                Button(action: {
                    if let img = HistoryManager.shared.loadImage(for: item) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.writeObjects([img])
                        ToastHUD.shared.show(message: "已复制到剪贴板", systemImage: "doc.on.doc.fill")
                    }
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("复制图片")
                
                Button(action: {
                    if let img = HistoryManager.shared.loadImage(for: item) {
                        CaptureManager.shared.pinImage(img)
                    }
                }) {
                    Image(systemName: "pin")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("钉在屏幕")
                
                Button(action: {
                    HistoryManager.shared.deleteItem(item)
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.borderless)
                .help("删除")
            }
            
            if let ocr = item.ocrText, !ocr.isEmpty {
                Text(ocr.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .background(Color(NSColor.cardBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHovered ? Color.accentColor : Color.gray.opacity(0.2), lineWidth: isHovered ? 1.5 : 1)
        )
        .onHover { hover in
            isHovered = hover
        }
        .onTapGesture {
            onSelect()
        }
    }
}

private struct HistoryDetailSheet: View {
    let item: HistoryItem
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("截图详情")
                    .font(.headline)
                Spacer()
                Button("关闭") { dismiss() }
            }
            
            if let image = HistoryManager.shared.loadImage(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 300)
                    .cornerRadius(8)
            }
            
            if let ocr = item.ocrText, !ocr.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("OCR 识别文本")
                            .font(.subheadline.bold())
                        Spacer()
                        Button("复制文本") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(ocr, forType: .string)
                            ToastHUD.shared.show(message: "已复制文本", systemImage: "doc.on.doc.fill")
                        }
                        .font(.caption)
                        
                        Button("AI 翻译") {
                            dismiss()
                            CaptureManager.shared.showTranslationPanel(sourceText: ocr)
                        }
                        .font(.caption)
                    }
                    ScrollView {
                        Text(ocr)
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(height: 100)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                }
            }
            
            HStack {
                Button("钉在屏幕") {
                    if let img = HistoryManager.shared.loadImage(for: item) {
                        CaptureManager.shared.pinImage(img)
                        dismiss()
                    }
                }
                
                Button("复制图片") {
                    if let img = HistoryManager.shared.loadImage(for: item) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.writeObjects([img])
                        ToastHUD.shared.show(message: "已复制到剪贴板", systemImage: "doc.on.doc.fill")
                    }
                }
                
                Spacer()
                
                Button("删除此记录", role: .destructive) {
                    HistoryManager.shared.deleteItem(item)
                    dismiss()
                }
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}

private extension NSColor {
    static var cardBackgroundColor: NSColor {
        if #available(macOS 14.0, *) {
            return .unemphasizedSelectedContentBackgroundColor.withAlphaComponent(0.3)
        }
        return .controlBackgroundColor
    }
}
