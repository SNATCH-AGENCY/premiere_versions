from pathlib import Path
import subprocess
import tempfile
s = (Path(__file__).resolve().parents[1] / 'Premiere Versions/MyApp.swift').read_text()
localization = (Path(__file__).resolve().parents[1] / "Premiere Versions/Localization.swift").read_text()
worker = s[s.index('nonisolated enum DefaultLocations'):]
harness = r'''
let fm = FileManager.default
let root = URL(fileURLWithPath: "/private/tmp/premiere-backup-fixture-" + UUID().uuidString, isDirectory: true)
try fm.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: root) }
let watch = root.appendingPathComponent("watch")
let archive = watch.appendingPathComponent("archive")
try fm.createDirectory(at: archive, withIntermediateDirectories: true)
let now = Date()
func file(_ url: URL, age: TimeInterval) throws {
    try Data("test project".utf8).write(to: url)
    try fm.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: url.path)
}
let source = watch.appendingPathComponent("Example.prproj")
try file(source, age: 75)
try file(watch.appendingPathComponent("StillWriting.prproj"), age: 0)
let projectFolder = archive.appendingPathComponent("Example")
try fm.createDirectory(at: projectFolder, withIntermediateDirectories: true)
for i in 1...30 {
    try file(projectFolder.appendingPathComponent("Example_autosave_\(i).prproj"), age: Double(i * 60))
}
try file(projectFolder.appendingPathComponent("Example_autosave_hourly.prproj"), age: 7200)
try file(projectFolder.appendingPathComponent("Example_autosave_daily.prproj"), age: 172800)
try file(projectFolder.appendingPathComponent("Example_autosave_expired.prproj"), age: 604800)
// A normal project may have many old Premiere autosaves; none is a new backup source.
let nativeFolder = watch.appendingPathComponent("Adobe Premiere Pro Auto-Save")
try fm.createDirectory(at: nativeFolder, withIntermediateDirectories: true)
for i in 1...15 {
    try file(nativeFolder.appendingPathComponent("Example--7b4d1031-f239-3490-2a37-b636f999dd21-2026-05-05_15-\(String(format: "%02d", i))-00.prproj"), age: Double(i * 60))
}
let looseAutosave = watch.appendingPathComponent("Example--7b4d1031-f239-3490-2a37-b636f999dd21-2026-05-05_16-00-00.prproj")
try file(looseAutosave, age: 60)
let movedSnapshot = watch.appendingPathComponent("Example_autosave_1793535213.prproj")
try file(movedSnapshot, age: 60)
let classifiedSnapshot = watch.appendingPathComponent("Example_daily_27-10-2026-18-30-37_autosave.prproj")
try file(classifiedSnapshot, age: 60)
var excludedExamples = [URL]()
for marker in ["autosave", "AUTO-SAVE", "auto save", "auto_save", "Auto–Save"] {
    let nested = watch.appendingPathComponent("old " + marker + " projects").appendingPathComponent("nested")
    try fm.createDirectory(at: nested, withIntermediateDirectories: true)
    let inside = nested.appendingPathComponent("PlainProject.prproj")
    let named = watch.appendingPathComponent("Example_" + marker + "_backup.prproj")
    try file(inside, age: 60)
    try file(named, age: 60)
    excludedExamples += [inside, named]
    assert(ProjectSourceFilter.isExcluded(inside))
    assert(ProjectSourceFilter.isExcluded(named))
}
assert(!ProjectSourceFilter.isExcluded(watch.appendingPathComponent("Automotive main.prproj")))
let readableSnapshot = watch.appendingPathComponent("Example_AUTO_2026-11-01_22-45-30.prproj")
try file(readableSnapshot, age: 60)
let originalZone = NSTimeZone.default
NSTimeZone.default = TimeZone(secondsFromGMT: 10800)!
defer { NSTimeZone.default = originalZone }
let worker = AutosaveWorker()
let injected = try worker.scanAutosaves(watchURL: watch, archiveURL: archive, indexedFiles: [looseAutosave, movedSnapshot, readableSnapshot, classifiedSnapshot] + excludedExamples)
assert(injected.found == 0 && injected.copied == 0, "Cached or supplied autosaves must also be excluded")
let report = try worker.scanAutosaves(watchURL: watch, archiveURL: archive)
assert(report.found == 2 && report.copied == 1 && report.waiting == 1)
let first = try fm.contentsOfDirectory(atPath: projectFolder.path)
assert(first.count == 13, "Expected 10 recent + 1 older hourly + hourly + daily, got \(first.count)")
assert(!first.contains("Example_autosave_expired.prproj"))
assert(!fm.fileExists(atPath: archive.appendingPathComponent("StillWriting").path))
assert(try Data(contentsOf: source) == Data("test project".utf8))
assert(first.contains { $0.range(of: #"^Example_recent_\d{2}-\d{2}-\d{4}-\d{2}-\d{2}-\d{2}_autosave\.prproj$"#, options: .regularExpression) != nil }, "Backup names must include readable local date/time")
NSTimeZone.default = TimeZone(secondsFromGMT: 0)!
let directoryReads = worker.archiveDirectoryReads
let repeated = try worker.scanAutosaves(watchURL: watch, archiveURL: archive)
assert(repeated.copied == 0 && repeated.unchanged == 1)
assert(worker.archiveDirectoryReads == directoryReads, "Unchanged sources must not enumerate the archive again")
let second = try fm.contentsOfDirectory(atPath: projectFolder.path)
assert(first.sorted() == second.sorted(), "Time-zone change must not duplicate backups")
let folders = try fm.contentsOfDirectory(atPath: archive.path)
assert(folders == ["Example"], "Archive must not be scanned recursively")

do {
    try worker.scanAutosaves(watchURL: archive, archiveURL: archive)
    fatalError("Equal watch/archive must be rejected")
} catch { }
let index = ProjectFileIndex()
let initial = try index.projects(in: watch, excluding: [archive])
assert(initial.count == 2, "Only the two main project files should be indexed")
index.invalidate(paths: [looseAutosave.path, nativeFolder.path])
let afterAutosaveEvent = try index.projects(in: watch, excluding: [archive])
assert(afterAutosaveEvent.count == 2, "Autosave events must not reintroduce excluded sources")
assert(!ProjectSourceFilter.isExcluded(watch.appendingPathComponent("Project_2026-05-05.prproj")))
assert(!ProjectSourceFilter.isExcluded(watch.appendingPathComponent("Project--7b4d1031-f239-3490-2a37-b636f999dd21.prproj")))
print("PASS: autosave/auto-save/auto save folders and filenames excluded recursively, native snapshots and cached events excluded, normal projects retained")
let another = watch.appendingPathComponent("New.prproj")
try file(another, age: 60)
let cached = try index.projects(in: watch, excluding: [archive])
assert(cached.count == 2, "Cached scan must not re-enumerate the root")
index.invalidate(paths: [another.path])
let updated = try index.projects(in: watch, excluding: [archive])
assert(updated.count == 3, "New file event must update the index")
let external = watch.appendingPathComponent("NewDisk")
try fm.createDirectory(at: external, withIntermediateDirectories: true)
try file(external.appendingPathComponent("External.prproj"), age: 60)
index.invalidate(paths: [external.path])
let mounted = try index.projects(in: watch, excluding: [archive])
assert(mounted.count == 4, "New volume directory must be discovered")
try fm.removeItem(at: external)
index.invalidate(paths: [external.path])
let unmounted = try index.projects(in: watch, excluding: [archive])
assert(unmounted.count == 3, "Disconnected source must be removed")
let outside = root.appendingPathComponent("Outside")
try fm.createDirectory(at: outside, withIntermediateDirectories: true)
try file(outside.appendingPathComponent("Outside.prproj"), age: 60)
let link = watch.appendingPathComponent("Link")
try fm.createSymbolicLink(at: link, withDestinationURL: outside)
index.invalidate(paths: [link.path])
let safe = try index.projects(in: watch, excluding: [archive])
assert(safe.count == 3, "Symlinks outside the search scope must not be followed")
let expectedHome = URL(fileURLWithPath: String(cString: getpwuid(getuid())!.pointee.pw_dir))
assert(DefaultLocations.versions == expectedHome.appendingPathComponent("Desktop/Premiere_Versions/Premiere_Saves").path)
assert(DefaultLocations.autosaves == expectedHome.appendingPathComponent("Desktop/Premiere_Versions/Premiere_AutoSaves").path)
// Classify a real archive, including legacy filenames, without duplicate category files.
let historyWatch = root.appendingPathComponent("history-watch")
let historyArchive = root.appendingPathComponent("history-archive")
let historyFolder = historyArchive.appendingPathComponent("History")
try fm.createDirectory(at: historyWatch, withIntermediateDirectories: true)
try fm.createDirectory(at: historyFolder, withIntermediateDirectories: true)
try file(historyWatch.appendingPathComponent("History.prproj"), age: 75)
for i in 1...12 {
    let age = Double(1800 + i * 120)
    let stamp = Int(now.addingTimeInterval(-age).timeIntervalSince1970)
    try file(historyFolder.appendingPathComponent("History_autosave_\(stamp).prproj"), age: age)
}
try file(historyFolder.appendingPathComponent("History_autosave_\(Int(now.addingTimeInterval(-7200).timeIntervalSince1970)).prproj"), age: 7200)
try file(historyFolder.appendingPathComponent("History_autosave_\(Int(now.addingTimeInterval(-172800).timeIntervalSince1970)).prproj"), age: 172800)
let historyResult = try AutosaveWorker().scanAutosaves(watchURL: historyWatch, archiveURL: historyArchive)
assert(historyResult.copied == 1)
let classified = try fm.contentsOfDirectory(atPath: historyFolder.path)
assert(classified.filter { $0.contains("_recent_") }.count == 10)
assert(classified.filter { $0.contains("_hourly_") }.count == 1)
assert(classified.filter { $0.contains("_daily_") }.count == 1)
assert(classified.allSatisfy { $0.hasSuffix("_autosave.prproj") })
assert(Set(classified).count == 12)
let historyRepeat = try AutosaveWorker().scanAutosaves(watchURL: historyWatch, archiveURL: historyArchive)
assert(historyRepeat.unchanged == 1)
print("PASS: readable recent/hourly/daily filenames, legacy rename, category priority and deduplication")
let suite = "pv-default-checks-" + UUID().uuidString
let preferences = UserDefaults(suiteName: suite)!
defer { preferences.removePersistentDomain(forName: suite) }
DefaultLocations.install(in: preferences)
assert(preferences.string(forKey: "archivePath") == DefaultLocations.versions)
assert(preferences.string(forKey: "autosaveArchivePath") == DefaultLocations.autosaves)
preferences.set("/external/My Versions", forKey: "archivePath")
preferences.set("/external/My Backups", forKey: "autosaveArchivePath")
preferences.set("folder", forKey: "searchMode")
preferences.set(false, forKey: "autosaveMonitoringEnabled")
let bookmark = Data([1, 2, 3, 4])
preferences.set(bookmark, forKey: "archiveBookmark")
preferences.set("custom", forKey: "logoVariant")
preferences.set(0.37, forKey: "windowBackgroundOpacity")
DefaultLocations.install(in: preferences)
assert(preferences.string(forKey: "archivePath") == "/external/My Versions")
assert(preferences.string(forKey: "autosaveArchivePath") == "/external/My Backups")
assert(preferences.string(forKey: "searchMode") == "folder")
assert(!preferences.bool(forKey: "autosaveMonitoringEnabled"))
assert(preferences.data(forKey: "archiveBookmark") == bookmark)
assert(preferences.string(forKey: "logoVariant") == "custom")
assert(preferences.double(forKey: "windowBackgroundOpacity") == 0.37)
print("PASS: fresh defaults and existing paths, bookmarks, icon choice preserved on upgrade")
let cancellation = ScanCancellation()
cancellation.cancel()
do {
    _ = try ProjectFileIndex().projects(in: watch, excluding: [archive], cancellation: cancellation)
    fatalError("Cancelled discovery must stop")
} catch is CancellationError { }
print("PASS: cancellation")
print("PASS: incremental discovery, simulated disk attach/detach, scope boundaries, user-relative default paths")
print("PASS: stable copy, recent-file skip, retention, source preservation, deduplication, archive exclusion, invalid folder rejection")
'''
harness = harness.replace('assert(try Data(contentsOf: source) == Data("test project".utf8))', 'let sourceData = try Data(contentsOf: source)\nassert(sourceData == Data("test project".utf8))')
with tempfile.TemporaryDirectory(prefix="premiere-checks-") as check_dir:
    source = Path(check_dir) / "PremiereWorkerCheck.swift"
    source.write_text("import Foundation\nimport Darwin\n" + localization + worker + harness)
    sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
    compiler = subprocess.check_output(["xcrun", "--find", "swiftc"], text=True).strip()
    binary = Path(check_dir) / "PremiereWorkerCheck"
    subprocess.run([compiler, "-sdk", sdk, "-module-cache-path", str(Path(check_dir) / "modules"), str(source), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
