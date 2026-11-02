import Foundation
import Darwin

/// Resolve installed copies explicitly. Launch Services may cache a development build,
/// so it must not decide which app receives a persistent Finder icon.
nonisolated enum PVInstalledAppLocations {
    static var standardRoots: [URL] {
        var roots = [URL(fileURLWithPath: "/Applications", isDirectory: true)]
        if let home = getpwuid(getuid())?.pointee.pw_dir {
            roots.append(URL(fileURLWithPath: String(cString: home)).appendingPathComponent("Applications", isDirectory: true))
        }
        return roots
    }

    static func find(runtime: URL, bundleID: String, roots: [URL] = standardRoots, extraFolders: [URL] = []) -> URL? {
        let fm = FileManager.default
        let excluded = Set(["old versions", "old_versions", "archive", "archives", "builds"])
        func candidate(_ url: URL) -> (URL, String, String)? {
            let url = url.resolvingSymlinksInPath().standardizedFileURL
            guard url.pathExtension.lowercased() == "app",
                  roots.contains(where: { root in
                      let path = root.resolvingSymlinksInPath().standardizedFileURL.path
                      return url.path.hasPrefix(path + "/")
                  }),
                  !url.pathComponents.contains(where: { excluded.contains($0.lowercased()) }),
                  let data = try? Data(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
                  let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  info["CFBundleIdentifier"] as? String == bundleID else { return nil }
            return (url, info["CFBundleShortVersionString"] as? String ?? "0", info["CFBundleVersion"] as? String ?? "0")
        }
        if let installed = candidate(runtime) { return installed.0 }
        var candidates: [(URL, String, String)] = []
        for folder in roots + roots.map({ $0.appendingPathComponent("Premiere Versions", isDirectory: true) }) + extraFolders {
            if let app = candidate(folder) { candidates.append(app); continue }
            for app in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [] {
                if let app = candidate(app) { candidates.append(app) }
            }
        }
        return candidates.sorted {
            let versionOrder = $0.1.compare($1.1, options: .numeric)
            if versionOrder != .orderedSame { return versionOrder == .orderedDescending }
            let buildOrder = $0.2.compare($1.2, options: .numeric)
            if buildOrder != .orderedSame { return buildOrder == .orderedDescending }
            return $0.0.path < $1.0.path
        }.first?.0
    }
}
