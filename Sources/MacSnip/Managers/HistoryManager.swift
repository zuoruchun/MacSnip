import Foundation
import AppKit

public struct HistoryItem: Identifiable, Codable, Hashable {
    public var id: String
    public var timestamp: Date
    public var imageFileName: String
    public var width: Int
    public var height: Int
    public var ocrText: String?
    
    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        imageFileName: String,
        width: Int,
        height: Int,
        ocrText: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.imageFileName = imageFileName
        self.width = width
        self.height = height
        self.ocrText = ocrText
    }
}

public final class HistoryManager: ObservableObject {
    public static let shared = HistoryManager()
    
    @Published public var items: [HistoryItem] = []
    
    private let fileManager = FileManager.default
    private var cleanupTimer: Timer?
    
    public static var defaultDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("MacSnip/History", isDirectory: true)
    }
    
    public var historyDirectory: URL {
        let custom = SettingsManager.shared.customHistoryPath
        if !custom.isEmpty {
            let dir = URL(fileURLWithPath: custom, isDirectory: true)
            if !fileManager.fileExists(atPath: dir.path) {
                try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
            }
            return dir
        }
        
        let dir = HistoryManager.defaultDirectory
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
        return dir
    }
    
    private init() {
        loadHistory()
        startPeriodicCleanup()
    }
    
    /// 获取历史图片的完整本地 URL
    public func imageURL(for item: HistoryItem) -> URL {
        return historyDirectory.appendingPathComponent(item.imageFileName)
    }
    
    /// 加载历史图片为 NSImage
    public func loadImage(for item: HistoryItem) -> NSImage? {
        let url = imageURL(for: item)
        return NSImage(contentsOf: url)
    }
    
    /// 保存截图到历史记录
    @discardableResult
    public func saveScreenshot(image: NSImage, ocrText: String? = nil) throws -> HistoryItem {
        let id = UUID().uuidString
        let imageFileName = "\(id).png"
        let jsonFileName = "\(id).json"
        
        let imageFileURL = historyDirectory.appendingPathComponent(imageFileName)
        let jsonFileURL = historyDirectory.appendingPathComponent(jsonFileName)
        
        // 保留物理像素与 point 尺寸，使 Retina PNG 携带正确的高 DPI 语义
        guard let pngData = ImageExportManager.pngData(from: image) else {
            throw NSError(domain: "com.macsnip.history", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法将图像编码为 PNG"])
        }
        
        try pngData.write(to: imageFileURL)
        
        let pixelWidth = image.cgImage(forProposedRect: nil, context: nil, hints: nil)?.width ?? Int(image.size.width)
        let pixelHeight = image.cgImage(forProposedRect: nil, context: nil, hints: nil)?.height ?? Int(image.size.height)
        
        let item = HistoryItem(
            id: id,
            timestamp: Date(),
            imageFileName: imageFileName,
            width: pixelWidth,
            height: pixelHeight,
            ocrText: ocrText
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(item)
        try jsonData.write(to: jsonFileURL)
        
        DispatchQueue.main.async {
            self.items.insert(item, at: 0)
        }
        
        return item
    }
    
    /// 更新某条历史记录的 OCR 文本
    public func updateOCRText(for itemId: String, ocrText: String) {
        guard let index = items.firstIndex(where: { $0.id == itemId }) else { return }
        var updatedItem = items[index]
        updatedItem.ocrText = ocrText
        items[index] = updatedItem
        
        let jsonFileURL = historyDirectory.appendingPathComponent("\(itemId).json")
        if let jsonData = try? JSONEncoder().encode(updatedItem) {
            try? jsonData.write(to: jsonFileURL)
        }
    }
    
    /// 读取本地所有历史记录
    public func loadHistory() {
        let dir = historyDirectory
        guard let fileURLs = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return
        }
        
        let jsonURLs = fileURLs.filter { $0.pathExtension == "json" }
        var loadedItems: [HistoryItem] = []
        
        for url in jsonURLs {
            if let data = try? Data(contentsOf: url),
               let item = try? JSONDecoder().decode(HistoryItem.self, from: data) {
                loadedItems.append(item)
            }
        }
        
        // 按时间倒序排序
        loadedItems.sort { $0.timestamp > $1.timestamp }
        
        DispatchQueue.main.async {
            self.items = loadedItems
        }
    }
    
    /// 删除某条历史记录
    public func deleteItem(_ item: HistoryItem) {
        let imageFileURL = imageURL(for: item)
        let jsonFileURL = historyDirectory.appendingPathComponent("\(item.id).json")
        
        try? fileManager.removeItem(at: imageFileURL)
        try? fileManager.removeItem(at: jsonFileURL)
        
        DispatchQueue.main.async {
            self.items.removeAll { $0.id == item.id }
        }
    }
    
    /// 清理所有历史记录
    public func clearAll() {
        let dir = historyDirectory
        if let files = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for file in files {
                try? fileManager.removeItem(at: file)
            }
        }
        DispatchQueue.main.async {
            self.items.removeAll()
        }
    }
    
    /// 后台定时清理过期文件
    public func startPeriodicCleanup() {
        cleanupExpiredItems()
        
        // 每 6 小时检查一次
        cleanupTimer?.invalidate()
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            self?.cleanupExpiredItems()
        }
    }
    
    /// 执行过期历史清理
    public func cleanupExpiredItems() {
        let retentionDays = SettingsManager.shared.historyRetentionDays
        guard retentionDays > 0 else { return }
        
        let expirationDate = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()
        
        let expired = items.filter { $0.timestamp < expirationDate }
        for item in expired {
            deleteItem(item)
        }
    }
}
