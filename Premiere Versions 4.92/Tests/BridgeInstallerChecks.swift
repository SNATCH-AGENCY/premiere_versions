import Foundation
import CryptoKit

@main struct Checks {
    static func main() throws {
        func check(_ value: @autoclosure () throws -> Bool) throws { if try !value() { fatalError("Check failed") } }
        let root = URL(fileURLWithPath: CommandLine.arguments[1]), fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("pv-bridge-check-" + UUID().uuidString)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }
        let owner = temp.appendingPathComponent("Owner.app"), resources = owner.appendingPathComponent("Contents/Resources")
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        try fm.copyItem(at: root.appendingPathComponent("BridgePlugin"), to: resources.appendingPathComponent("PremiereBridge"))
        try fm.copyItem(at: root.appendingPathComponent("BridgePayload.json"), to: resources.appendingPathComponent("BridgePayload.json"))
        let home = temp.appendingPathComponent("home")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        func config(_ char: String = "a") throws -> Data { try JSONEncoder().encode(PVBridgeInstaller.Configuration(protocolVersion: 2, port: 49833, credential: String(repeating: char, count: 64))) }
        func install(_ destination: URL = home) throws -> [String:Any] {
            let result = try PVBridgeInstaller.install(owner: owner, configuration: config(), home: destination)
            return try JSONSerialization.jsonObject(with: Data(result.utf8)) as! [String:Any]
        }
        func rejects(_ action: () throws -> Void) { do { try action(); fatalError("Unsafe installation accepted") } catch {} }
        let target = home.appendingPathComponent("Library/Application Support/Adobe/CEP/extensions/" + PVBridgeInstaller.identifier)
        try check(try install()["changed"] as? Bool == true)
        try check(try install()["changed"] as? Bool == false)
        let connection = home.appendingPathComponent("Library/Application Support/Premiere Versions/Bridge/connection.json")
        let mode = try fm.attributesOfItem(atPath: connection.path)[.posixPermissions] as! NSNumber
        assert(mode.intValue == 0o600)
        let oldSignature = try Data(contentsOf: target.appendingPathComponent("META-INF/signatures.xml"))
        _ = try PVBridgeInstaller.install(owner: owner, configuration: config("b"), home: home)
        try check(try Data(contentsOf: target.appendingPathComponent("META-INF/signatures.xml")) == oldSignature)
        try check(try JSONDecoder().decode(PVBridgeInstaller.Configuration.self, from: Data(contentsOf: connection)).credential == String(repeating:"b",count:64))
        print("PASS: fresh install, idempotence, private runtime config, signed payload untouched")
        try Data("damaged".utf8).write(to: target.appendingPathComponent("core.js"))
        try check(try install()["changed"] as? Bool == true)
        print("PASS: managed damaged payload repaired")
        let indexURL = resources.appendingPathComponent("BridgePayload.json")
        let index = try JSONDecoder().decode(PVBridgeInstaller.Index.self, from: Data(contentsOf:indexURL))
        try JSONEncoder().encode(PVBridgeInstaller.Index(identifier: index.identifier, version:"4.92.1", files:index.files)).write(to:indexURL)
        try check(try install()["changed"] as? Bool == true)
        try JSONEncoder().encode(index).write(to:indexURL)
        rejects { _ = try install() }
        print("PASS: plugin update and downgrade refusal")
        let foreignHome = temp.appendingPathComponent("foreign")
        let foreign = foreignHome.appendingPathComponent("Library/Application Support/Adobe/CEP/extensions/" + PVBridgeInstaller.identifier)
        try fm.createDirectory(at:foreign,withIntermediateDirectories:true)
        try Data("keep me".utf8).write(to:foreign.appendingPathComponent("unrelated.txt"))
        rejects { _ = try install(foreignHome) }
        assert(fm.fileExists(atPath:foreign.appendingPathComponent("unrelated.txt").path))
        let linkedHome = temp.appendingPathComponent("linked")
        try fm.createDirectory(at:linkedHome.appendingPathComponent("Library"),withIntermediateDirectories:true)
        try fm.createSymbolicLink(at:linkedHome.appendingPathComponent("Library/Application Support"),withDestinationURL:temp)
        rejects { _ = try install(linkedHome) }
        print("PASS: unrelated folder and symlink destinations protected")
        try Data("tampered".utf8).write(to:resources.appendingPathComponent("PremiereBridge/core.js"))
        rejects { _ = try install(temp.appendingPathComponent("clean")) }
        print("PASS: tampered bundled payload refused")
    }
}
