import Foundation
import AppKit
import Vision

public enum OCRError: LocalizedError {
    case invalidImage
    case recognitionFailed(String)
    case noTextFound
    
    public var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "无效的图像数据，无法进行文字识别。"
        case .recognitionFailed(let msg):
            return "文字识别失败: \(msg)"
        case .noTextFound:
            return "未识别到任何文本内容。"
        }
    }
}

public final class OCRManager {
    public static let shared = OCRManager()
    
    private init() {}
    
    /// 从 NSImage 中安全提取 CGImage (线程安全且兼容所有裁剪图)
    private func getCGImage(from image: NSImage) -> CGImage? {
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return cgImage
        }
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let cgImage = bitmap.cgImage else {
            return nil
        }
        return cgImage
    }
    
    /// 从 NSImage 中离线识别文字 (支持中英文)
    public func recognizeText(from image: NSImage) async throws -> String {
        guard let cgImage = getCGImage(from: image) else {
            throw OCRError.invalidImage
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: OCRError.recognitionFailed(error.localizedDescription))
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(throwing: OCRError.noTextFound)
                    return
                }
                
                let recognizedStrings = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }
                
                let fullText = recognizedStrings.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                
                if fullText.isEmpty {
                    continuation.resume(throwing: OCRError.noTextFound)
                } else {
                    continuation.resume(returning: fullText)
                }
            }
            
            // 配置识别参数
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: OCRError.recognitionFailed(error.localizedDescription))
            }
        }
    }
}
