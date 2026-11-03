import AppKit
import Combine
import Foundation

@MainActor
final class PVUserLogoLibrary: ObservableObject {
    static let shared = PVUserLogoLibrary()
    @Published private(set) var currentImage: NSImage?
    @Published private(set) var previousImage: NSImage?
    @Published private(set) var revision = 0
    @Published private(set) var folderPath = ""
    @Published private(set) var storageNotice: String?
    private(set) var currentPalette = PVLogoPalette.initial
    private var cachedTemplate: Data?
    private let defaults = UserDefaults.standard
    private static let bookmarkKey = "customLogoFolderBookmark"
    private static let paletteKey = "customLogoPalette"
    private static let previousPaletteKey = "previousCustomLogoPalette"

    private init() { reload() }

    var templateData: Data? {
        if let cachedTemplate { return cachedTemplate }
        cachedTemplate = NSImage(named: NSImage.Name("PVColor3"))?.tiffRepresentation
        return cachedTemplate
    }

    func image(for id: String) -> NSImage? {
        if id == "custom" { return currentImage }
        if id == "previous" { return previousImage }
        return NSImage(named: NSImage.Name(PVBrand.asset(for: id)))
    }

    func isAvailable(_ id: String) -> Bool {
        if id == "custom" { return currentImage != nil }
        if id == "previous" { return previousImage != nil }
        return PVBrand.variants.contains(where: { $0.id == id })
    }

    func reload() {
        migrateLegacyHistory()
        do {
            try perform() { folder in
                folderPath = folder.path
                let current = try? Data(contentsOf: folder.appendingPathComponent(PVUserLogoFiles.currentName))
                let previous = try? Data(contentsOf: folder.appendingPathComponent(PVUserLogoFiles.previousName))
                currentImage = current.flatMap { NSImage(data: $0) }
                previousImage = previous.flatMap { NSImage(data: $0) }
            }
        } catch {
            currentImage = nil
            previousImage = nil
        }
        if let data = defaults.data(forKey: Self.paletteKey),
           let palette = try? JSONDecoder().decode(PVLogoPalette.self, from: data), palette.isValid {
            currentPalette = palette
        }
        revision &+= 1
    }

    func palette(for slot: String?) -> PVLogoPalette {
        let key = slot == "previous" ? Self.previousPaletteKey : Self.paletteKey
        guard let data = defaults.data(forKey: key),
              let palette = try? JSONDecoder().decode(PVLogoPalette.self, from: data), palette.isValid else { return .initial }
        return palette
    }

    func replace(_ png: Data, palette: PVLogoPalette, slot: String) throws {
        guard ["custom", "previous"].contains(slot), palette.isValid else { throw PVLogoRenderError.invalidColor }
        let encoded = try JSONEncoder().encode(palette)
        try perform { folder in try PVUserLogoFiles.replace(png, previous: slot == "previous", in: folder, allowCreating: true) }
        defaults.set(true, forKey: "didMigrateLogoHistory")
        defaults.set(encoded, forKey: slot == "previous" ? Self.previousPaletteKey : Self.paletteKey)
        reload()
    }

    func save(_ png: Data, palette: PVLogoPalette) throws {
        let oldPalette = currentImage == nil ? nil : defaults.data(forKey: Self.paletteKey)
        try perform() { folder in
            try PVUserLogoFiles.save(png, in: folder)
            folderPath = folder.path
        }
        if let oldPalette { defaults.set(oldPalette, forKey: Self.previousPaletteKey) }
        else { defaults.removeObject(forKey: Self.previousPaletteKey) }
        defaults.set(try JSONEncoder().encode(palette), forKey: Self.paletteKey)
        currentPalette = palette
        reload()
    }

    func remove(slot: String) throws {
        guard ["custom", "previous"].contains(slot) else { return }
        try perform { folder in
            let url = folder.appendingPathComponent(slot == "previous" ? PVUserLogoFiles.previousName : PVUserLogoFiles.currentName)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
        }
        defaults.removeObject(forKey: slot == "previous" ? Self.previousPaletteKey : Self.paletteKey)
        defaults.set(true, forKey: "didMigrateLogoHistory")
        reload()
    }

    private var suggestedFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Premiere Versions/logos", isDirectory: true)
    }

    private func resolve(_ key: String) throws -> URL? {
        guard let data = defaults.data(forKey: key) else { return nil }
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
        if stale {
            let started = url.startAccessingSecurityScopedResource()
            defer { if started { url.stopAccessingSecurityScopedResource() } }
            if let renewed = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
                defaults.set(renewed, forKey: key)
            }
        }
        return url
    }

    private func scoped<T>(_ scope: URL, _ operation: () throws -> T) rethrows -> T {
        let started = scope.startAccessingSecurityScopedResource()
        defer { if started { scope.stopAccessingSecurityScopedResource() } }
        return try operation()
    }

    private func perform<T>(operation: (URL) throws -> T) throws -> T {
        let folder = suggestedFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try operation(folder)
    }

    private func migrateLegacyHistory() {
        if defaults.bool(forKey: "didMigrateLogoHistory") { return }
        if FileManager.default.fileExists(atPath: suggestedFolder.appendingPathComponent(PVUserLogoFiles.currentName).path) {
            defaults.set(true, forKey: "didMigrateLogoHistory")
            storageNotice = nil
            return
        }
        do {
            if let bookmarked = try resolve(Self.bookmarkKey) {
                let imported = try scoped(bookmarked) {
                    try PVUserLogoFiles.importHistory(from: bookmarked, to: suggestedFolder)
                }
                if imported { storageNotice = nil; return }
            }
            let parent = Bundle.main.bundleURL.deletingLastPathComponent()
            var candidates = [parent.appendingPathComponent("assets/logos"), parent.appendingPathComponent("logo"),
                              parent.deletingLastPathComponent().appendingPathComponent("assets/logos")]
            if let selected = defaults.string(forKey: "customLogoFolderPath"), !selected.isEmpty {
                candidates.insert(URL(fileURLWithPath: selected, isDirectory: true), at: 0)
            }
            let root = try? resolve("computerSearchBookmark")
            for candidate in candidates {
                let imported: Bool
                if let root {
                    imported = try scoped(root) { try PVUserLogoFiles.importHistory(from: candidate, to: suggestedFolder) }
                } else {
                    imported = try PVUserLogoFiles.importHistory(from: candidate, to: suggestedFolder)
                }
                if imported { storageNotice = nil; return }
            }
        } catch { /* Legacy files are never modified or discarded if access has changed. */ }
        let choice = defaults.string(forKey: "logoVariant") ?? "graphite"
        storageNotice = ["custom", "previous"].contains(choice) ? PVL("Нужен доступ к прежней папке пользовательского значка. Выбор сохранён.") : nil
    }

    func importLegacyFolder() {
        let panel = NSOpenPanel()
        panel.title = PVL("Восстановить пользовательские значки")
        panel.message = PVL("Выбери прежнюю папку с usercolor.png. Значки будут скопированы в данные приложения; оригиналы останутся на месте.")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do {
            let imported = try scoped(folder) { try PVUserLogoFiles.importHistory(from: folder, to: suggestedFolder) }
            guard imported else { storageNotice = PVL("В папке не найден usercolor.png"); return }
            reload()
        } catch { storageNotice = PVL("Не удалось восстановить значки: ") + error.localizedDescription }
    }
}
