import Foundation
import CryptoKit
import Darwin

/// Fixed destinations only. Payload and file list come from the owning signed app, never an XPC argument.
enum PVBridgeInstaller {
    struct Index: Codable { let identifier: String; let version: String; let files: [String: String] }
    struct Configuration: Codable { let protocolVersion: Int; let port: UInt16; let credential: String }
    struct Receipt: Codable { let identifier: String; let version: String; let files: [String: String] }
    struct Failure: LocalizedError { let message: String; var errorDescription: String? { message } }
    static let identifier = "dev.premiereversions.bridge"
    static func install(owner: URL, configuration data: Data, home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> String {
        let fm = FileManager.default
        guard data.count <= 1024, let config = try? JSONDecoder().decode(Configuration.self, from: data),
              config.protocolVersion == 2, config.port >= 1024,
              config.credential.count == 64, config.credential.allSatisfy({ $0.isHexDigit && $0.isASCII }) else {
            throw Failure(message: "Invalid local bridge configuration.")
        }
        let resources = owner.appendingPathComponent("Contents/Resources", isDirectory: true)
        let source = resources.appendingPathComponent("PremiereBridge", isDirectory: true)
        let index = try JSONDecoder().decode(Index.self, from: Data(contentsOf: resources.appendingPathComponent("BridgePayload.json")))
        guard index.identifier == identifier, !index.version.isEmpty, index.files.count >= 5, index.files.count <= 32,
              index.files["META-INF/signatures.xml"] != nil,
              try validatedFiles(source, index.files) else { throw Failure(message: "Bundled Premiere plugin is invalid.") }
        let support = home.appendingPathComponent("Library/Application Support", isDirectory: true)
        let root = support.appendingPathComponent("Adobe/CEP/extensions", isDirectory: true)
        let target = root.appendingPathComponent(identifier, isDirectory: true)
        let state = support.appendingPathComponent("Premiere Versions/Bridge", isDirectory: true)
        try ensureDirectory(root, home: home)
        try ensureDirectory(state, home: home)
        try noSymlinks(target, home: home)
        let receiptURL = state.appendingPathComponent("installed.json")
        try noSymlinks(receiptURL, home: home)
        try noSymlinks(state.appendingPathComponent("connection.json"), home: home)
        let receipt = (try? Data(contentsOf: receiptURL)).flatMap { try? JSONDecoder().decode(Receipt.self, from: $0) }
        if fm.fileExists(atPath: target.path) {
            guard let receipt, receipt.identifier == identifier,
                  let existingManifest = try? String(contentsOf: target.appendingPathComponent("CSXS/manifest.xml"), encoding: .utf8),
                  existingManifest.contains("ExtensionBundleId=\"" + identifier + "\"") else {
                throw Failure(message: "An unmanaged plugin occupies the installation folder; nothing was replaced.")
            }
            if receipt.version.compare(index.version, options: .numeric) == .orderedDescending {
                throw Failure(message: "A newer Premiere plugin is installed; no downgrade was performed.")
            }
        }
        let unchanged = receipt?.version == index.version && receipt?.files == index.files && (try? validatedFiles(target, index.files)) == true
        if !unchanged {
            let stage = root.appendingPathComponent(".pv-bridge-stage-" + UUID().uuidString, isDirectory: true)
            let backup = root.appendingPathComponent(".pv-bridge-backup-" + UUID().uuidString, isDirectory: true)
            defer { try? fm.removeItem(at: stage) }
            try fm.copyItem(at: source, to: stage)
            guard try validatedFiles(stage, index.files) else { throw Failure(message: "Staged Premiere plugin failed validation.") }
            var movedOld = false
            do {
                if fm.fileExists(atPath: target.path) { try fm.moveItem(at: target, to: backup); movedOld = true }
                try fm.moveItem(at: stage, to: target)
                try atomic(JSONEncoder().encode(Receipt(identifier: identifier, version: index.version, files: index.files)), to: receiptURL)
                if movedOld { try? fm.removeItem(at: backup) }
            } catch {
                if movedOld {
                    try? fm.removeItem(at: target)
                    try? fm.moveItem(at: backup, to: target)
                } else { try? fm.removeItem(at: target) }
                throw error
            }
        }
        // Pairing is per-user, outside the signed extension. No signed file is personalized.
        try atomic(data, to: state.appendingPathComponent("connection.json"))
        let result: [String: Any] = ["changed": !unchanged, "version": index.version]
        return String(data: try JSONSerialization.data(withJSONObject: result), encoding: .utf8)!
    }
    static func atomic(_ data: Data, to url: URL) throws {
        let temp = url.deletingLastPathComponent().appendingPathComponent(".pv-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        guard FileManager.default.createFile(atPath: temp.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw Failure(message: "Could not write local plugin configuration.")
        }
        let file = try FileHandle(forWritingTo: temp); try file.synchronize(); try file.close()
        guard Darwin.rename(temp.path, url.path) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }
    static func noSymlinks(_ path: URL, home: URL) throws {
        let base = home.standardizedFileURL.path, full = path.standardizedFileURL.path
        guard full.hasPrefix(base + "/") else { throw Failure(message: "Invalid plugin destination.") }
        var current = home
        for component in full.dropFirst(base.count + 1).split(separator: "/") {
            current.appendPathComponent(String(component))
            if let type = try? FileManager.default.attributesOfItem(atPath: current.path)[.type] as? FileAttributeType, type == .typeSymbolicLink {
                throw Failure(message: "The plugin destination contains a symbolic link; nothing was replaced.")
            }
        }
    }
    static func ensureDirectory(_ url: URL, home: URL) throws {
        try noSymlinks(url, home: home)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    static func validatedFiles(_ root: URL, _ expected: [String: String]) throws -> Bool {
        guard let resolved = realpath(root.path, nil) else { return false }
        let rootPath = String(cString: resolved); free(resolved)
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
        var found = Set<String>()
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { return false }
            guard values.isRegularFile == true else { continue }
            guard file.path.hasPrefix(rootPath + "/") else { return false }
            let relative = String(file.path.dropFirst(rootPath.count + 1))
            guard let digest = expected[relative], !relative.contains(".."), digest.count == 64,
                  (try file.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0 <= 1_048_576 else { return false }
            let hash = SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined()
            guard hash == digest else { return false }; found.insert(relative)
        }
        return found == Set(expected.keys)
    }
}
