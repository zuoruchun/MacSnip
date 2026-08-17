import AppKit

enum ImageExportManager {
    static func bitmapRepresentation(from image: NSImage) -> NSBitmapImageRep? {
        guard image.size.width > 0,
              image.size.height > 0,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        // Preserve the point size so a 2x bitmap is encoded as a 144-DPI image.
        bitmapRep.size = image.size
        return bitmapRep
    }

    static func pngData(from image: NSImage) -> Data? {
        return bitmapRepresentation(from: image)?.representation(using: .png, properties: [:])
    }

    private static func clipboardBitmapRepresentation(from image: NSImage) -> NSBitmapImageRep? {
        let pixelWidth = max(1, Int(round(image.size.width)))
        let pixelHeight = max(1, Int(round(image.size.height)))

        guard image.size.width > 0,
              image.size.height > 0,
              let bitmapRep = NSBitmapImageRep(
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
            return nil
        }

        bitmapRep.size = image.size

        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: bitmapRep) else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }

        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: image.size),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1.0
        )
        NSGraphicsContext.restoreGraphicsState()
        return bitmapRep
    }

    @discardableResult
    static func writeToPasteboard(_ image: NSImage, pasteboard: NSPasteboard = .general) -> Bool {
        guard let bitmapRep = clipboardBitmapRepresentation(from: image),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return false
        }

        let item = NSPasteboardItem()
        item.setData(pngData, forType: .png)
        if let tiffData = bitmapRep.representation(using: .tiff, properties: [:]) {
            item.setData(tiffData, forType: .tiff)
        }

        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }
}
