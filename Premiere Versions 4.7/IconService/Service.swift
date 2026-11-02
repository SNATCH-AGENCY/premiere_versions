import AppKit
import Foundation
import Security
import Darwin

/// Owning-app service: Finder metadata and one validated helper preference; no arbitrary commands, paths or project access.
final class IconService: NSObject, PVIconServiceProtocol {
    static var owner: URL {
        Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .resolvingSymlinksInPath().standardizedFileURL
    }
    static func trustedOwner(_ owner: URL) -> Bool {
        guard let bundle = Bundle(url: owner), let identifier = bundle.bundleIdentifier else { return false }
        #if PV_ICON_TESTING
        let temporaryRoot = URL(fileURLWithPath: "/private/tmp", isDirectory: true).resolvingSymlinksInPath().standardizedFileURL.path
        return owner.path.hasPrefix(temporaryRoot + "/pv-icon-service-") && identifier.hasPrefix("devplaceholder.PVIconServiceFixture.")
        #else
        guard identifier == "devplaceholder.YDHGHCQE.Premiere-Versions" else { return false }
        let roots = ["/Applications", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]
        return roots.contains {
            let root = URL(fileURLWithPath: $0, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL.path
            return owner.path.hasPrefix(root + "/")
        } &&
            !owner.pathComponents.contains { ["old versions", "archives", "archive"].contains($0.lowercased()) }
        #endif
    }
    static func validPeer(_ pid: pid_t) -> Bool {
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid: pid] as CFDictionary, [], &code) == errSecSuccess,
              let code else { return false }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return false }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let values = info as? [String: Any], let executable = values[kSecCodeInfoMainExecutable as String] as? URL,
              let expected = Bundle(url: owner)?.executableURL else { return false }
        return executable.resolvingSymlinksInPath() == expected.resolvingSymlinksInPath()
    }
    func configureHotKeyHelper(_ data: Data, reply: @escaping (Bool, String) -> Void) {
        guard Self.trustedOwner(Self.owner), data.count <= 512,
              let shortcut = try? JSONDecoder().decode(PVHelperShortcut.self, from: data), shortcut.isValid,
              let ownerID = Bundle(url: Self.owner)?.bundleIdentifier else { reply(false, "Invalid helper configuration."); return }
        let identifier = ownerID + ".HotKeyHelper"
        let helper = Self.owner.appendingPathComponent("Contents/Library/LoginItems/Premiere Versions Helper.app")
        guard Bundle(url: helper)?.bundleIdentifier == identifier else { reply(false, "Owning helper is missing."); return }
        // Exactly one fixed preference key in the owning helper's domain; no path or command is accepted.
        let key = "globalSaveShortcut" as CFString
        let domain = identifier as CFString
        CFPreferencesSetValue(key, data as CFData, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else { reply(false, "Could not save helper preferences."); return }
        DistributedNotificationCenter.default().postNotificationName(Notification.Name(identifier + ".configurationChanged"), object: nil, userInfo: nil, deliverImmediately: true)
        reply(true, "")
    }
    func applyIcon(_ png: Data, targetPath: String, reply: @escaping (Bool, String) -> Void) {
        let target = URL(fileURLWithPath: targetPath).resolvingSymlinksInPath().standardizedFileURL
        guard Self.trustedOwner(Self.owner), target == Self.owner else {
            reply(false, "Only this service's owning installed app can be personalized."); return
        }
        guard png.count <= 8_388_608, let bitmap = NSBitmapImageRep(data: png),
              bitmap.pixelsWide <= 4096, bitmap.pixelsHigh <= 4096, let image = NSImage(data: png) else {
            reply(false, "Invalid image."); return
        }
        DispatchQueue.main.async {
            // Preserve all quarantine metadata. This process is not sandboxed, so the
            // Finder API does not create the sandbox-originated quarantine mark.
            do {
                let before = try Self.quarantine(target)
                guard NSWorkspace.shared.setIcon(image, forFile: target.path, options: []) else {
                    reply(false, "Finder icon write failed."); return
                }
                guard try Self.quarantine(target) == before else {
                    reply(false, "Unexpected quarantine metadata change."); return
                }
                reply(true, "")
            } catch { reply(false, "Could not inspect icon metadata.") }
        }
    }
    static func quarantine(_ url: URL) throws -> Data? {
        let count = getxattr(url.path, "com.apple.quarantine", nil, 0, 0, 0)
        if count < 0 {
            if errno == ENOATTR { return nil }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        var data = Data(count: count)
        let read = data.withUnsafeMutableBytes { getxattr(url.path, "com.apple.quarantine", $0.baseAddress, count, 0, 0) }
        guard read >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        return Data(data.prefix(read))
    }
}

final class IconListener: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard IconService.validPeer(connection.processIdentifier) else { return false }
        connection.exportedInterface = NSXPCInterface(with: PVIconServiceProtocol.self)
        connection.exportedObject = IconService()
        connection.resume()
        return true
    }
}

@main struct ServiceMain {
    static func main() {
        let listener = NSXPCListener.service()
        let delegate = IconListener()
        listener.delegate = delegate
        listener.resume()
        withExtendedLifetime(delegate) { RunLoop.current.run() }
    }
}
