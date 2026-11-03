import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

nonisolated struct PVLogoRGB: Codable, Equatable, Sendable {
    let r: Double
    let g: Double
    let b: Double
    var isValid: Bool { [r, g, b].allSatisfy { $0.isFinite && (0...1).contains($0) } }
}

nonisolated struct PVLogoPalette: Codable, Equatable, Sendable {
    let plate: PVLogoRGB
    let letters: PVLogoRGB
    var isValid: Bool { plate.isValid && letters.isValid }
    static let initial = PVLogoPalette(
        plate: PVLogoRGB(r: 0.34, g: 0.52, b: 0.80),
        letters: PVLogoRGB(r: 0.91, g: 0.92, b: 0.97)
    )
}

nonisolated enum PVLogoRenderError: LocalizedError {
    case invalidTemplate, invalidColor, invalidPNG, cannotRender
    var errorDescription: String? {
        switch self {
        case .invalidTemplate: return PVL("Не удалось прочитать шаблон логотипа.")
        case .invalidColor: return PVL("Выбран некорректный цвет.")
        case .invalidPNG: return PVL("Не удалось сохранить изображение: некорректный PNG.")
        case .cannotRender: return PVL("Не удалось создать изображение логотипа.")
        }
    }
}

/// Deterministic two-material recoloring for the in-app color constructor.
/// The bundled Color 3 is the template; its geometry and alpha are preserved.
nonisolated enum PVLogoRenderer {
    static func png(template: Data, palette: PVLogoPalette, size: Int) throws -> Data {
        guard palette.isValid else { throw PVLogoRenderError.invalidColor }
        guard (32...2048).contains(size),
              let source = CGImageSourceCreateWithData(template as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw PVLogoRenderError.invalidTemplate }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let decoded = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: size, height: size,
                                          bitsPerComponent: 8, bytesPerRow: size * 4,
                                          space: space, bitmapInfo: info) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard decoded else { throw PVLogoRenderError.cannotRender }
        let plate = [palette.plate.r, palette.plate.g, palette.plate.b]
        let letters = [palette.letters.r, palette.letters.g, palette.letters.b]
        for y in 0..<size {
            for x in 0..<size {
                let i = (y * size + x) * 4
                let alpha = Double(pixels[i + 3]) / 255
                guard alpha > 0 else { continue }
                let r = min(1, Double(pixels[i]) / 255 / alpha)
                let g = min(1, Double(pixels[i + 1]) / 255 / alpha)
                let b = min(1, Double(pixels[i + 2]) / 255 / alpha)
                let light = 0.2126 * r + 0.7152 * g + 0.0722 * b
                let nx = Double(x) / Double(size)
                let ny = Double(y) / Double(size)
                // Restrict the luminance mask to the Pv glyph area, excluding the rear sheets.
                let glyphRegion = nx >= 0.26 && nx <= 0.87 && ny >= 0.385 && ny <= 0.78
                let t = min(1, max(0, (light - 0.50) / 0.32))
                let mask = glyphRegion ? t * t * (3 - 2 * t) : 0
                let plateShade = 0.76 + min(1, light / 0.60) * 0.24
                let letterShade = 0.78 + light * 0.22
                let plateHighlight = max(0, (light - 0.35) / 0.65) * 0.04
                let letterHighlight = pow(light, 5) * 0.035
                for c in 0..<3 {
                    let base = plate[c] * plateShade + (1 - plate[c]) * plateHighlight
                    let mark = letters[c] * letterShade + (1 - letters[c]) * letterHighlight
                    let value = min(1, max(0, base * (1 - mask) + mark * mask))
                    pixels[i + c] = UInt8((value * alpha * 255).rounded())
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let output = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
                                   bytesPerRow: size * 4, space: space,
                                   bitmapInfo: CGBitmapInfo(rawValue: info), provider: provider,
                                   decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { throw PVLogoRenderError.cannotRender }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw PVLogoRenderError.cannotRender }
        CGImageDestinationAddImage(destination, output, nil)
        guard CGImageDestinationFinalize(destination) else { throw PVLogoRenderError.cannotRender }
        return data as Data
    }
}

/// Exactly two user-history slots. An invalid image never rotates existing files.
nonisolated enum PVUserLogoFiles {
    static let currentName = "usercolor.png"
    static let previousName = "userprevcolor.png"

    /// Import both slots without rotating history, deleting originals, or replacing existing data.
    static func importHistory(from sourceFolder: URL, to destinationFolder: URL) throws -> Bool {
        let fm = FileManager.default
        let current = destinationFolder.appendingPathComponent(currentName)
        if fm.fileExists(atPath: current.path) { return true }
        let source = sourceFolder.appendingPathComponent(currentName)
        guard fm.fileExists(atPath: source.path) else { return false }
        let png = try Data(contentsOf: source)
        func validate(_ data: Data) throws {
            guard let image = CGImageSourceCreateWithData(data as CFData, nil),
                  CGImageSourceGetType(image) as String? == UTType.png.identifier,
                  CGImageSourceCreateImageAtIndex(image, 0, nil) != nil else { throw PVLogoRenderError.invalidPNG }
        }
        try validate(png)
        let oldPreviousURL = sourceFolder.appendingPathComponent(previousName)
        let oldPrevious = fm.fileExists(atPath: oldPreviousURL.path) ? try Data(contentsOf: oldPreviousURL) : nil
        if let oldPrevious { try validate(oldPrevious) }
        try fm.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        let previous = destinationFolder.appendingPathComponent(previousName)
        var wrotePrevious = false
        do {
            if let oldPrevious, !fm.fileExists(atPath: previous.path) {
                try oldPrevious.write(to: previous, options: .atomic)
                wrotePrevious = true
            }
            try png.write(to: current, options: .atomic)
        } catch {
            if wrotePrevious { try? fm.removeItem(at: previous) }
            throw error
        }
        return true
    }

    /// Replace one existing slot atomically without rotating the other slot.
    static func replace(_ png: Data, previous: Bool, in folder: URL, allowCreating: Bool = false) throws {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              CGImageSourceGetType(source) as String? == UTType.png.identifier,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { throw PVLogoRenderError.invalidPNG }
        let target = folder.appendingPathComponent(previous ? previousName : currentName)
        guard allowCreating || FileManager.default.fileExists(atPath: target.path) else { throw PVLogoRenderError.invalidPNG }
        try png.write(to: target, options: .atomic)
    }

    static func save(_ png: Data, in folder: URL) throws {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              CGImageSourceGetType(source) as String? == UTType.png.identifier,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { throw PVLogoRenderError.invalidPNG }
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let current = folder.appendingPathComponent(currentName)
        let previous = folder.appendingPathComponent(previousName)
        let oldCurrent = fm.fileExists(atPath: current.path) ? try Data(contentsOf: current) : nil
        let oldPrevious = fm.fileExists(atPath: previous.path) ? try Data(contentsOf: previous) : nil
        do {
            if let oldCurrent { try oldCurrent.write(to: previous, options: .atomic) }
            try png.write(to: current, options: .atomic)
        } catch {
            // Restore the prior two slots if either atomic write failed.
            if let oldCurrent { try? oldCurrent.write(to: current, options: .atomic) }
            if let oldPrevious { try? oldPrevious.write(to: previous, options: .atomic) }
            else if oldCurrent != nil { try? fm.removeItem(at: previous) }
            throw error
        }
    }
}
