import Foundation
import CryptoKit
import Darwin

nonisolated struct PVSourceFingerprint: Codable, Equatable {
    let modified: Date
    let size: UInt64
    let identity: String
    static func read(_ url: URL, fileManager: FileManager = .default) throws -> Self {
        let a = try fileManager.attributesOfItem(atPath: url.path)
        guard a[.type] as? FileAttributeType == .typeRegular,
              let date = a[.modificationDate] as? Date, let size = a[.size] as? NSNumber, size.uint64Value > 0 else {
            throw PVBackupFailure.invalidSource
        }
        let device = (a[.systemNumber] as? NSNumber)?.stringValue ?? ""
        let inode = (a[.systemFileNumber] as? NSNumber)?.stringValue ?? ""
        let birth = (a[.creationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return Self(modified: date, size: size.uint64Value, identity: "\(device):\(inode):\(birth)")
    }
}

nonisolated enum PVBackupFailure: Error, LocalizedError {
    case invalidSource, changingSource, invalidState, occupiedName
    var errorDescription: String? {
        switch self {
        case .invalidSource: return "The project file is empty or unavailable."
        case .changingSource: return "The project changed during copying; the previous backup was kept."
        case .invalidState: return "Backup metadata is unreadable; existing copies were left untouched."
        case .occupiedName: return "A backup filename is already occupied; no copy was replaced."
        }
    }
}

nonisolated enum PVSafeCopy {
    struct Staged { let file: URL; let digest: String; let fingerprint: PVSourceFingerprint }
    static func digest(_ file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func stage(_ source: URL, in directory: URL, now: Date, stableDelay: TimeInterval = 12,
                      afterCopy: (() throws -> Void)? = nil) throws -> Staged {
        let before = try PVSourceFingerprint.read(source)
        guard now.timeIntervalSince(before.modified) >= stableDelay else { throw PVBackupFailure.changingSource }
        let temp = directory.appendingPathComponent(".pv-copy-" + UUID().uuidString + ".prproj")
        do {
            try FileManager.default.copyItem(at: source, to: temp)
            try afterCopy?()
            let copied = try PVSourceFingerprint.read(temp)
            guard copied.size == before.size else { throw PVBackupFailure.changingSource }
            let hash = try digest(temp)
            guard try PVSourceFingerprint.read(source) == before else { throw PVBackupFailure.changingSource }
            let output = try FileHandle(forWritingTo: temp)
            try output.synchronize(); try output.close()
            return Staged(file: temp, digest: hash, fingerprint: before)
        } catch { try? FileManager.default.removeItem(at: temp); throw error }
    }
    static func install(_ staged: URL, at destination: URL, replacing: Bool = false) throws {
        if !replacing && FileManager.default.fileExists(atPath: destination.path) { throw PVBackupFailure.occupiedName }
        if replacing {
            guard Darwin.rename(staged.path, destination.path) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        } else { try FileManager.default.moveItem(at: staged, to: destination) }
    }
}

/// Separate archives use the same binding format. A folder is never assigned to two sources.
nonisolated final class PVProjectFolders: @unchecked Sendable {
    static let shared = PVProjectFolders()
    struct Binding: Codable, Equatable {
        var source: String
        var identity: String?
        var names: [String]
        func matches(_ source: String, _ identity: String?) -> Bool {
            self.source == source || (identity != nil && self.identity == identity)
        }
    }
    private let lock = NSRecursiveLock()
    private var catalogs: [String: [String: Binding]] = [:]
    private let fm = FileManager.default
    static func canonical(_ url: URL) -> String { url.resolvingSymlinksInPath().standardizedFileURL.path }
    private func readBinding(_ folder: URL) -> Binding? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(".pv-source.json")) else { return nil }
        if let value = try? JSONDecoder().decode(Binding.self, from: data) { return value }
        if let source = try? JSONDecoder().decode(String.self, from: data) {
            return Binding(source: source, identity: nil, names: [URL(fileURLWithPath: source).deletingPathExtension().lastPathComponent])
        }
        return nil
    }
    private func catalog(_ root: URL) -> [String: Binding] {
        let key = Self.canonical(root)
        if let existing = catalogs[key] { return existing }
        var found = [String: Binding]()
        for folder in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? [] {
            if let value = readBinding(folder) { found[folder.lastPathComponent] = value }
        }
        catalogs[key] = found
        return found
    }
    func existing(for source: URL, archive: URL) -> URL? {
        lock.lock(); defer { lock.unlock() }
        let path = Self.canonical(source), identity = try? PVSourceFingerprint.read(source).identity
        for (name, binding) in catalog(archive) where binding.matches(path, identity) {
            let folder = archive.appendingPathComponent(name, isDirectory: true)
            if fm.fileExists(atPath: folder.path), let actual = readBinding(folder), actual.matches(path, identity) { return folder }
        }
        let legacy = archive.appendingPathComponent(source.deletingPathExtension().lastPathComponent, isDirectory: true)
        if let binding = readBinding(legacy), binding.matches(path, identity) { return legacy }
        return nil
    }
    func folder(for source: URL, archive: URL, create: Bool = true, allowLegacyClaim: Bool = false) throws -> URL {
        lock.lock(); defer { lock.unlock() }
        let path = Self.canonical(source), identity = try? PVSourceFingerprint.read(source).identity
        let name = source.deletingPathExtension().lastPathComponent
        var bindings = catalog(archive)
        func commit(_ folder: URL) throws -> URL {
            let previous = readBinding(folder)
            var binding = previous ?? Binding(source: path, identity: identity, names: [])
            if let previous, !previous.matches(path, identity) { throw PVBackupFailure.occupiedName }
            if previous == nil && fm.fileExists(atPath: folder.appendingPathComponent(".pv-source.json").path) { throw PVBackupFailure.invalidState }
            binding.source = path; binding.identity = identity
            if !binding.names.contains(name) { binding.names.append(name) }
            if create || fm.fileExists(atPath: folder.path) {
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                let metadata = folder.appendingPathComponent(".pv-source.json")
                let encoded = try JSONEncoder().encode(binding)
                if previous != binding {
                    do { try encoded.write(to: metadata, options: previous == nil ? .withoutOverwriting : .atomic) }
                    catch let error as NSError where error.code == NSFileWriteFileExistsError { throw PVBackupFailure.occupiedName }
                }
                bindings[folder.lastPathComponent] = binding
                catalogs[Self.canonical(archive)] = bindings
            }
            return folder
        }
        if let folder = existing(for: source, archive: archive) { return try commit(folder) }
        let stem = name.isEmpty || name == "." || name == ".." ? "Project" : name.replacingOccurrences(of: ":", with: "-")
        for suffix in 0..<1_000_000 {
            let folder = archive.appendingPathComponent(stem + (suffix == 0 ? "" : "_\(suffix)"), isDirectory: true)
            if !fm.fileExists(atPath: folder.path) {
                do { return try commit(folder) } catch PVBackupFailure.occupiedName { continue }
            }
            if (try? folder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { continue }
            if let binding = readBinding(folder), binding.matches(path, identity) { return try commit(folder) }
            if suffix == 0 && allowLegacyClaim && !fm.fileExists(atPath: folder.appendingPathComponent(".pv-source.json").path) {
                return try commit(folder)
            }
        }
        throw PVBackupFailure.occupiedName
    }
}

nonisolated struct PVBackupRecord: Codable, Equatable {
    var id: String
    var filename: String
    let captured: Date
    let sourceModified: Date
    var digest: String?
}
nonisolated struct PVBackupCheckpoint: Codable, Equatable {
    let period: Date
    var record: String
}
nonisolated struct PVBackupState: Codable, Equatable {
    var version = 1
    var records: [PVBackupRecord] = []
    var hourly: [PVBackupCheckpoint] = []
    var daily: [PVBackupCheckpoint] = []
    var observed: PVSourceFingerprint?
    mutating func checkpoint(now: Date, record: String, calendar: Calendar = .current) {
        func update(_ points: [PVBackupCheckpoint], component: Calendar.Component, maximum: Int, cutoff: Date) -> [PVBackupCheckpoint] {
            guard let period = calendar.dateInterval(of: component, for: now)?.start else { return points }
            var values = points.filter { $0.period != period && $0.period >= cutoff && $0.period <= period }
            values.append(PVBackupCheckpoint(period: period, record: record))
            return Array(values.sorted { $0.period < $1.period }.suffix(maximum))
        }
        hourly = update(hourly, component: .hour, maximum: 12, cutoff: now.addingTimeInterval(-12 * 3600))
        daily = update(daily, component: .day, maximum: 5, cutoff: now.addingTimeInterval(-5 * 86400))
    }
    func retained() -> [String: BackupStatus] {
        var result = [String: BackupStatus]()
        for record in records.suffix(BackupPolicy.recentCount) { result[record.id] = .recent }
        for point in hourly where result[point.record] == nil { result[point.record] = .hourly }
        for point in daily where result[point.record] == nil { result[point.record] = .daily }
        return result
    }
}

nonisolated final class PVBackupArchive {
    enum Outcome { case copied, unchanged, waiting }
    private let fm = FileManager.default
    private var states: [String: PVBackupState] = [:]
    private func location(_ folder: URL) -> URL { folder.appendingPathComponent(".pv-backups.json") }
    private func load(_ folder: URL, project: String) throws -> PVBackupState {
        if var state = states[folder.path] {
            let count = state.records.count
            state.records.removeAll { !fm.fileExists(atPath: folder.appendingPathComponent($0.filename).path) }
            if state.records.count != count { state.observed = nil }
            let ids = Set(state.records.map(\.id)); state.hourly.removeAll { !ids.contains($0.record) }; state.daily.removeAll { !ids.contains($0.record) }
            return state
        }
        let url = location(folder)
        if fm.fileExists(atPath: url.path) {
            guard let data = try? Data(contentsOf: url), var state = try? JSONDecoder().decode(PVBackupState.self, from: data), state.version == 1 else { throw PVBackupFailure.invalidState }
            let aliases = ((try? Data(contentsOf: folder.appendingPathComponent(".pv-source.json"))).flatMap { try? JSONDecoder().decode(PVProjectFolders.Binding.self, from: $0) })?.names ?? [project]
            guard state.records.allSatisfy({ record in
                record.filename == URL(fileURLWithPath: record.filename).lastPathComponent &&
                aliases.contains { BackupNaming.isManaged(record.filename, project: $0) }
            }) else { throw PVBackupFailure.invalidState }
            // Resolve a status rename interrupted between the file move and metadata commit.
            for i in state.records.indices where !fm.fileExists(atPath: folder.appendingPathComponent(state.records[i].filename).path) {
                for status in [BackupStatus.recent, .hourly, .daily] {
                    let candidate = BackupNaming.filename(project: project, modified: state.records[i].captured, status: status)
                    if fm.fileExists(atPath: folder.appendingPathComponent(candidate).path) { state.records[i].filename = candidate; break }
                }
            }
            let count = state.records.count
            state.records.removeAll { !fm.fileExists(atPath: folder.appendingPathComponent($0.filename).path) }
            if state.records.count != count { state.observed = nil }
            let ids = Set(state.records.map(\.id)); state.hourly.removeAll { !ids.contains($0.record) }; state.daily.removeAll { !ids.contains($0.record) }
            return state
        }
        var state = PVBackupState()
        let names = ((try? Data(contentsOf: folder.appendingPathComponent(".pv-source.json"))).flatMap { try? JSONDecoder().decode(PVProjectFolders.Binding.self, from: $0) })?.names ?? [project]
        for file in try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) {
            guard names.contains(where: { BackupNaming.isManaged(file.lastPathComponent, project: $0) }),
                  let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { continue }
            let pattern = #"_(?:recent|hourly|daily)_(\d{2}-\d{2}-\d{4}-\d{2}-\d{2}-\d{2})_autosave\.prproj$"#
            let regex = try NSRegularExpression(pattern: pattern)
            let name = file.lastPathComponent
            let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..<name.endIndex, in: name))
            let timestamp = match.flatMap { Range($0.range(at: 1), in: name).map { String(name[$0]) } }
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "dd-MM-yyyy-HH-mm-ss"
            let captured = timestamp.flatMap { formatter.date(from: $0) } ?? modified
            state.records.append(PVBackupRecord(id: UUID().uuidString, filename: name, captured: captured, sourceModified: modified, digest: nil))
        }
        state.records.sort { $0.captured < $1.captured }
        for record in state.records { state.checkpoint(now: record.captured, record: record.id) }
        return state
    }
    private func save(_ state: PVBackupState, in folder: URL) throws {
        try JSONEncoder().encode(state).write(to: location(folder), options: .atomic)
        states[folder.path] = state
    }
    func process(source: URL, folder: URL, now: Date, afterCopy: (() throws -> Void)? = nil) throws -> Outcome {
        var state = try load(folder, project: source.deletingPathExtension().lastPathComponent)
        let previous = state
        let fingerprint = try PVSourceFingerprint.read(source)
        guard now.timeIntervalSince(fingerprint.modified) >= BackupPolicy.stableDelay else { return .waiting }
        let latest = state.records.last
        var outcome = Outcome.unchanged
        let due = latest.map { now.timeIntervalSince($0.captured) >= BackupPolicy.snapshotInterval || now < $0.captured } ?? true
        if latest == nil || state.observed == nil || (state.observed != fingerprint && due) {
            let staged = try PVSafeCopy.stage(source, in: folder, now: now, afterCopy: afterCopy)
            defer { try? fm.removeItem(at: staged.file) }
            var lastDigest = latest?.digest
            if let latest, lastDigest == nil { lastDigest = try PVSafeCopy.digest(folder.appendingPathComponent(latest.filename)) }
            if staged.digest != lastDigest {
                let name = BackupNaming.filename(project: source.deletingPathExtension().lastPathComponent, modified: now, status: .recent)
                try PVSafeCopy.install(staged.file, at: folder.appendingPathComponent(name))
                state.records.append(PVBackupRecord(id: UUID().uuidString, filename: name, captured: now, sourceModified: fingerprint.modified, digest: staged.digest))
                outcome = .copied
            } else if let index = state.records.firstIndex(where: { $0.id == latest?.id }) { state.records[index].digest = staged.digest }
            state.observed = fingerprint
        }
        if let last = state.records.last { state.checkpoint(now: now, record: last.id) }
        let keep = state.retained()
        // Record the completed new copy before any rename or deletion.
        if state != previous { try save(state, in: folder) }
        for index in state.records.indices {
            guard let status = keep[state.records[index].id] else { continue }
            let record = state.records[index]
            let name = BackupNaming.filename(project: source.deletingPathExtension().lastPathComponent, modified: record.captured, status: status)
            let statusSuffix = "_" + status.rawValue + #"_\d{2}-\d{2}-\d{4}-\d{2}-\d{2}-\d{2}_autosave\.prproj$"#
            if record.filename.range(of: statusSuffix, options: .regularExpression) == nil && name != record.filename {
                try PVSafeCopy.install(folder.appendingPathComponent(record.filename), at: folder.appendingPathComponent(name))
                state.records[index].filename = name
                try save(state, in: folder)
            }
        }
        let expired = state.records.filter { keep[$0.id] == nil }
        if case .copied = outcome, !expired.isEmpty {
            state.records.removeAll { keep[$0.id] == nil }
            try save(state, in: folder)
            for record in expired { try fm.removeItem(at: folder.appendingPathComponent(record.filename)) }
        }
        return outcome
    }
}
