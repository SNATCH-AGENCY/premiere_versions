import AppKit
import Foundation
import Sparkle

@MainActor func root() -> URL { URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "PVFixtureRoot") as! String) }
@MainActor func record(_ stage: String, _ details: [String: Any] = [:]) {
    var result = details; result["stage"] = stage
    result["version"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]) {
        try? data.write(to: root().appendingPathComponent("result.json"), options: .atomic)
    }
}
@MainActor func fail(_ error: Error) {
    let phase = Bundle.main.object(forInfoDictionaryKey: "PVFixturePhase") as? String
    var cursor: NSError? = error as NSError
    var codes: [Int] = []; var messages: [String] = []
    while let current = cursor {
        codes.append(current.code); messages.append(current.localizedDescription)
        cursor = current.userInfo[NSUnderlyingErrorKey] as? NSError
    }
    let rejected = phase == "bad" && codes.contains(where: { $0 == 3001 || $0 == 3002 })
    record(rejected ? "tamper-rejected" : "failed", ["codes": codes, "messages": messages])
    NSApp.terminate(nil)
}
@MainActor final class Driver: NSObject, SPUUserDriver {
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}
    func showUpdateFound(with item: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard item.versionString == "4.3.2" else { reply(.dismiss); fail(NSError(domain:"Fixture",code:1)); return }
        reply(.install)
    }
    func showUpdateReleaseNotes(with data: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) { acknowledgement(); fail(error) }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) { acknowledgement(); fail(error) }
    func showDownloadInitiated(cancellation: @escaping () -> Void) {}
    func showDownloadDidReceiveExpectedContentLength(_ length: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() {}
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) { reply(.install) }
    func showInstallingUpdate(withApplicationTerminated terminated: Bool, retryTerminatingApplication: @escaping () -> Void) {}
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func dismissUpdateInstallation() {}
}
@MainActor final class Delegate: NSObject, NSApplicationDelegate {
    let driver = Driver()
    var updater: SPUUpdater?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let defaults = UserDefaults.standard
        if Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String == "4.3.2" {
            let support = root().appendingPathComponent("Support")
            let bookmark = defaults.data(forKey: "archiveBookmark")
            var stale = false
            let resolved = bookmark.flatMap { try? URL(resolvingBookmarkData: $0, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) }
            let preserved = defaults.string(forKey: "archivePath") == root().appendingPathComponent("Saves").path &&
                defaults.string(forKey: "interfaceLanguage") == "ru" && defaults.string(forKey: "logoVariant") == "custom" &&
                defaults.data(forKey: "globalSaveShortcut") == Data("fixture-hotkey".utf8) &&
                resolved?.path == root().appendingPathComponent("Saves").path &&
                (try? Data(contentsOf: support.appendingPathComponent("usercolor.png"))) == (try? Data(contentsOf: root().appendingPathComponent("current.png"))) &&
                (try? Data(contentsOf: support.appendingPathComponent("userprevcolor.png"))) == (try? Data(contentsOf: root().appendingPathComponent("previous.png")))
            guard preserved else { record("failed", ["reason": "preferences or custom history changed"]); NSApp.terminate(nil); return }
            let image = NSImage(contentsOf: support.appendingPathComponent("usercolor.png"))!
            let icon = NSWorkspace.shared.setIcon(image, forFile: Bundle.main.bundlePath, options: [])
            record("updated", ["preserved": true, "finderIcon": icon])
            NSApp.terminate(nil)
            return
        }
        do {
            let saves = root().appendingPathComponent("Saves")
            try FileManager.default.createDirectory(at: saves, withIntermediateDirectories: true)
            let bookmark = try saves.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(bookmark, forKey: "archiveBookmark")
            defaults.set(saves.path, forKey: "archivePath")
            defaults.set("ru", forKey: "interfaceLanguage")
            defaults.set("custom", forKey: "logoVariant")
            defaults.set(Data("fixture-hotkey".utf8), forKey: "globalSaveShortcut")
            defaults.synchronize()
            let support = root().appendingPathComponent("Support")
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            for (source, target) in [("current.png", "usercolor.png"), ("previous.png", "userprevcolor.png")] {
                try Data(contentsOf: root().appendingPathComponent(source)).write(to: support.appendingPathComponent(target), options: .atomic)
            }
            updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: nil)
            try updater!.start()
            updater!.checkForUpdates()
        } catch { fail(error) }
    }
}
@main struct Fixture {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let delegate = Delegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
