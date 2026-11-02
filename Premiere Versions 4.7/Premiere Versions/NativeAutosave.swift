import Foundation

/// Mirrors one matching native Premiere autosave. Original files are read-only.
nonisolated final class PVLatestNativeAutosave {
    enum Outcome { case copied, unchanged, missing, waiting }
    private struct State: Codable {
        var source: String
        var filename: String
        var fingerprint: PVSourceFingerprint
    }
    private struct Candidate { let file: URL; let modified: Date }
    private struct Listing { let modified: Date?; let candidate: URL? }
    private var listings: [String: Listing] = [:]
    private let fm = FileManager.default
    static let directoryName = "Adobe Premiere Pro Auto-Save"
    static func matches(_ file: URL, project: String) -> Bool {
        guard file.pathExtension.lowercased() == "prproj" else { return false }
        let stem = file.deletingPathExtension().lastPathComponent
        if stem == project { return true }
        guard stem.lowercased().hasPrefix(project.lowercased() + "-") else { return false }
        let prefix = NSRegularExpression.escapedPattern(for: project)
        let uuid = #"--[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}-\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}"#
        let dated = #"-\d{2,4}-\d{2}-\d{2}[_-]\d{2}-\d{2}-\d{2}"#
        return stem.range(of: "(?i)^" + prefix + "(?:" + uuid + "|" + dated + ")$", options: .regularExpression) != nil
    }
    func process(project source: URL, archiveFolder: URL, now: Date, afterCopy: (() throws -> Void)? = nil) throws -> Outcome {
        let native = source.deletingLastPathComponent().appendingPathComponent(Self.directoryName, isDirectory: true)
        let directoryValues: URLResourceValues
        do { directoryValues = try native.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey]) }
        catch let error as NSError where error.code == NSFileReadNoSuchFileError { return .missing }
        guard directoryValues.isDirectory == true else { return .missing }
        let project = source.deletingPathExtension().lastPathComponent
        let key = PVProjectFolders.canonical(native) + "#" + project
        var candidates = [Candidate]()
        let cached = listings[key]
        var rescan = cached == nil || cached?.modified != directoryValues.contentModificationDate
        if !rescan, let file = cached?.candidate {
            if let stamp = try? PVSourceFingerprint.read(file) { candidates.append(Candidate(file: file, modified: stamp.modified)) }
            else { rescan = true }
        }
        if rescan {
            for file in try fm.contentsOfDirectory(at: native, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) {
                guard Self.matches(file, project: project), let stamp = try? PVSourceFingerprint.read(file) else { continue }
                candidates.append(Candidate(file: file, modified: stamp.modified))
            }
        }
        // This emergency file may be overwritten in place without changing the folder date.
        let emergency = native.appendingPathComponent(source.lastPathComponent)
        if let stamp = try? PVSourceFingerprint.read(emergency) { candidates.append(Candidate(file: emergency, modified: stamp.modified)) }
        guard let newest = candidates.max(by: { $0.modified == $1.modified ? $0.file.path < $1.file.path : $0.modified < $1.modified }) else {
            listings[key] = Listing(modified: directoryValues.contentModificationDate, candidate: nil)
            return .missing
        }
        listings[key] = Listing(modified: directoryValues.contentModificationDate, candidate: newest.file)
        let fingerprint = try PVSourceFingerprint.read(newest.file)
        guard now.timeIntervalSince(fingerprint.modified) >= BackupPolicy.stableDelay else { return .waiting }
        let targetFolder = archiveFolder.appendingPathComponent(Self.directoryName, isDirectory: true)
        guard PVProjectFolders.canonical(native) != PVProjectFolders.canonical(targetFolder) else { return .missing }
        let stateURL = targetFolder.appendingPathComponent(".pv-latest.json")
        var previous: State?
        if fm.fileExists(atPath: stateURL.path) {
            guard let data = try? Data(contentsOf: stateURL), let state = try? JSONDecoder().decode(State.self, from: data),
                  state.filename == URL(fileURLWithPath: state.filename).lastPathComponent,
                  Self.matches(URL(fileURLWithPath: state.filename), project: project) else { throw PVBackupFailure.invalidState }
            previous = state
        }
        if let previous, fm.fileExists(atPath: targetFolder.appendingPathComponent(previous.filename).path) {
            if previous.fingerprint.modified > fingerprint.modified { return .unchanged }
            if previous.source == newest.file.path && previous.fingerprint == fingerprint { return .unchanged }
        }
        try fm.createDirectory(at: targetFolder, withIntermediateDirectories: true)
        let staged = try PVSafeCopy.stage(newest.file, in: targetFolder, now: now, afterCopy: afterCopy)
        defer { try? fm.removeItem(at: staged.file) }
        let destination = targetFolder.appendingPathComponent(newest.file.lastPathComponent)
        if fm.fileExists(atPath: destination.path), previous?.filename != destination.lastPathComponent { throw PVBackupFailure.occupiedName }
        try PVSafeCopy.install(staged.file, at: destination, replacing: previous?.filename == destination.lastPathComponent)
        let state = State(source: newest.file.path, filename: destination.lastPathComponent, fingerprint: fingerprint)
        try JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
        if let previous, previous.filename != state.filename {
            let old = targetFolder.appendingPathComponent(previous.filename)
            if fm.fileExists(atPath: old.path) { try fm.removeItem(at: old) }
        }
        return .copied
    }
}
