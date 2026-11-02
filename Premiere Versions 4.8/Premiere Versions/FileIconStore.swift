import AppKit
import Combine
import CryptoKit
import Foundation
import UniformTypeIdentifiers

/// Finder personalization. Only an installed matching app is a target; old app bookmarks
/// cannot make a new release rewrite an archived app's icon.
@MainActor
final class PVFileIconStore: ObservableObject {
    static let shared = PVFileIconStore()
    @Published private(set) var notice: String?
    @Published private(set) var isApplying = false
    private let defaults = UserDefaults.standard
    private let bookmarkKey = "persistentAppIconAccess"
    private var pending: Task<Void, Never>?
    private var pendingPrompt = false

    func apply(_ image: NSImage, allowPrompt: Bool = false) {
        pendingPrompt = pendingPrompt || allowPrompt
        pending?.cancel()
        pending = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 80_000_000) } catch { return }
            let shouldPrompt = pendingPrompt
            pendingPrompt = false
            guard let target = installedTarget() else {
                notice = PVL("Установи программу в Applications, чтобы значок сохранялся после закрытия.")
                if shouldPrompt { await authorizeAndApplyNow(image) }
                return
            }
            if !shouldPrompt, defaults.string(forKey: "lastPersistentIconFingerprint") == fingerprint(image, target: target),
               FileManager.default.fileExists(atPath: target.appendingPathComponent("Icon\r").path) {
                notice = nil
                return
            }
            if await applyUsingSavedAccess(image, target: target) { return }
            if await write(image, target: target) { return }
            notice = PVL("Разреши сохранять выбранный значок после закрытия программы.")
            if shouldPrompt { await authorizeAndApplyNow(image) }
        }
    }

    func authorizeAndApply(_ image: NSImage) {
        pending?.cancel()
        pending = Task { @MainActor in await self.authorizeAndApplyNow(image) }
    }

    private func authorizeAndApplyNow(_ image: NSImage) async {
        pendingPrompt = false
        let suggested = installedTarget()
        let panel = NSOpenPanel()
        panel.title = PVL("Разрешить сохранение значка")
        panel.message = PVL("Нажми «Разрешить», чтобы значок сохранялся после закрытия программы. Нужная папка уже открыта.")
        let appFolder = URL(fileURLWithPath: "/Applications/Premiere Versions", isDirectory: true)
        panel.directoryURL = suggested?.deletingLastPathComponent() ?? (FileManager.default.fileExists(atPath: appFolder.path) ? appFolder : URL(fileURLWithPath: "/Applications", isDirectory: true))
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [.folder]
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = PVL("Разрешить")
        guard panel.runModal() == .OK, let scope = panel.url else { return }
        let started = scope.startAccessingSecurityScopedResource()
        defer { if started { scope.stopAccessingSecurityScopedResource() } }
        guard let target = installedTarget(extraFolders: [scope]), PVFileIconPaths.covers(scope, target: target) else {
            notice = PVL("Разреши доступ к папке установленной программы в Applications.")
            return
        }
        do {
            let data = try scope.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(data, forKey: bookmarkKey)
            _ = await write(image, target: target)
        } catch { notice = PVL("Не удалось сохранить доступ для значка: ") + error.localizedDescription }
    }

    private func installedTarget(extraFolders: [URL] = []) -> URL? {
        let runtime = Bundle.main.bundleURL
        let identifier = Bundle.main.bundleIdentifier ?? "devplaceholder.YDHGHCQE.Premiere-Versions"
        if let target = PVInstalledAppLocations.find(runtime: runtime, bundleID: identifier, extraFolders: extraFolders) { return target }
        for key in [bookmarkKey, "computerSearchBookmark"] {
            guard let data = defaults.data(forKey: key) else { continue }
            var stale = false
            guard let scope = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) else { continue }
            let started = scope.startAccessingSecurityScopedResource()
            defer { if started { scope.stopAccessingSecurityScopedResource() } }
            if let target = PVInstalledAppLocations.find(runtime: runtime, bundleID: identifier, extraFolders: extraFolders + [scope]) { return target }
        }
        return nil
    }

    private func applyUsingSavedAccess(_ image: NSImage, target: URL) async -> Bool {
        for key in [bookmarkKey, "computerSearchBookmark"] {
            guard let data = defaults.data(forKey: key) else { continue }
            do {
                var stale = false
                let scope = try URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
                guard PVFileIconPaths.covers(scope, target: target) else { continue }
                let started = scope.startAccessingSecurityScopedResource()
                defer { if started { scope.stopAccessingSecurityScopedResource() } }
                if stale, let renewed = try? scope.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
                    defaults.set(renewed, forKey: key)
                }
                if await write(image, target: target) { return true }
            } catch { continue }
        }
        return false
    }

    private func fingerprint(_ image: NSImage, target: URL) -> String {
        let info = (try? Data(contentsOf: target.appendingPathComponent("Contents/Info.plist"))).flatMap {
            try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any]
        }
        let build = info?["CFBundleVersion"] as? String ?? ""
        let digest = SHA256.hash(data: image.tiffRepresentation ?? Data()).map { String(format: "%02x", $0) }.joined()
        return target.path + "#" + build + "#" + digest
    }

    private func write(_ image: NSImage, target: URL) async -> Bool {
        isApplying = true
        defer { isApplying = false }
        if await PVFinderIconWriter.apply(image, to: target) {
            defaults.set(fingerprint(image, target: target), forKey: "lastPersistentIconFingerprint")
            notice = nil
            return true
        }
        notice = PVL("Разреши сохранять значок после закрытия программы.")
        return false
    }
}

nonisolated enum PVFileIconPaths {
    static func covers(_ scope: URL, target: URL) -> Bool {
        let path = scope.resolvingSymlinksInPath().standardizedFileURL.path
        let targetPath = target.resolvingSymlinksInPath().standardizedFileURL.path
        return path == "/" || path == targetPath || targetPath.hasPrefix(path + "/")
    }
}

