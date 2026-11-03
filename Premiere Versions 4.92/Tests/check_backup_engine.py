from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
worker=(root/'Premiere Versions/MyApp.swift').read_text().split('nonisolated enum DefaultLocations',1)[1]
source='import Foundation\nimport Darwin\n'+(root/'Premiere Versions/Localization.swift').read_text()+'nonisolated enum DefaultLocations'+worker+'\n'+(root/'Premiere Versions/BackupStorage.swift').read_text()+'\n'+(root/'Premiere Versions/NativeAutosave.swift').read_text()
harness=r'''
setbuf(stdout,nil)
let fm=FileManager.default
let root=URL(fileURLWithPath:"/private/tmp/pv47-storage-"+UUID().uuidString)
try fm.createDirectory(at:root,withIntermediateDirectories:true)
defer {try? fm.removeItem(at:root)}
let start=Date()
func make(_ url:URL,_ value:String,_ modified:Date) throws {
 try fm.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
 try Data(value.utf8).write(to:url)
 try fm.setAttributes([.modificationDate:modified],ofItemAtPath:url.path)
}
func copies(_ folder:URL) throws -> [URL] {try fm.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil).filter{$0.pathExtension=="prproj"}}
func state(_ folder:URL) throws -> PVBackupState {try JSONDecoder().decode(PVBackupState.self,from:Data(contentsOf:folder.appendingPathComponent(".pv-backups.json")))}
let archive=root.appendingPathComponent("archive")
try fm.createDirectory(at:archive,withIntermediateDirectories:true)
let store=PVProjectFolders()
var projects=[URL](),folders=[URL]()
for i in 0..<3 {
 let file=root.appendingPathComponent("source-\(i)/Project.prproj")
 try make(file,"source-\(i)",start.addingTimeInterval(-60));projects.append(file)
 folders.append(try store.folder(for:file,archive:archive))
}
assert(folders.map(\.lastPathComponent)==["Project","Project_1","Project_2"])
assert(try store.folder(for:projects[1],archive:archive)==folders[1])
let freshStore=PVProjectFolders()
assert(try freshStore.folder(for:projects[2],archive:archive)==folders[2])
let moved=root.appendingPathComponent("source-1/renamed.prproj")
try fm.moveItem(at:projects[1],to:moved)
assert(try freshStore.folder(for:moved,archive:archive)==folders[1])
print("PASS: same-name projects receive persistent numbered folders; source rename retains its binding")
let file=root.appendingPathComponent("work/Example.prproj")
try make(file,"A",start.addingTimeInterval(-60))
let folder=try store.folder(for:file,archive:archive)
let engine=PVBackupArchive()
if case .copied = try engine.process(source:file,folder:folder,now:start) {} else {fatalError("First snapshot not immediate")}
let original=try copies(folder)[0]
try make(file,"B",start.addingTimeInterval(100))
if case .unchanged = try engine.process(source:file,folder:folder,now:start.addingTimeInterval(299)) {} else {fatalError("Five-minute throttle failed")}
assert(try copies(folder).count==1)
if case .copied = try engine.process(source:file,folder:folder,now:start.addingTimeInterval(300)) {} else {fatalError("Changed state not copied when due")}
try make(file,"B",start.addingTimeInterval(500))
if case .unchanged = try engine.process(source:file,folder:folder,now:start.addingTimeInterval(600)) {} else {fatalError("Identical bytes consumed a history slot")}
assert(try copies(folder).count==2)
print("PASS: immediate first snapshot; five-minute interval; content hash skips metadata-only changes")
let unrelated=folder.appendingPathComponent("Unrelated.prproj");try make(unrelated,"keep me",start)
for i in 1...40 {
 let now=start.addingTimeInterval(600+Double(i)*301)
 try make(file,"revision-\(i)",now.addingTimeInterval(-60))
 _=try engine.process(source:file,folder:folder,now:now)
}
let retained=try state(folder)
assert(retained.records.count<=27)
assert(retained.retained().values.filter{$0 == .recent}.count==10)
assert(fm.fileExists(atPath:unrelated.path))
print("PASS: recent/hourly/daily share physical snapshots; bounded retention leaves unrelated project files untouched")
let idleFile=root.appendingPathComponent("idle/Idle.prproj");try make(idleFile,"idle",start.addingTimeInterval(-60))
let idleFolder=try store.folder(for:idleFile,archive:archive);let idle=PVBackupArchive()
_=try idle.process(source:idleFile,folder:idleFolder,now:start)
for i in 1...12 {_=try idle.process(source:idleFile,folder:idleFolder,now:start.addingTimeInterval(Double(i)*3600))}
let idleState=try state(idleFolder)
assert(try copies(idleFolder).count==1)
assert(Set(idleState.hourly.map(\.record)).count==1 && idleState.hourly.count==12)
print("PASS: twelve hourly checkpoints can reference one unchanged physical file")
let safeFile=root.appendingPathComponent("safe/Safe.prproj");try make(safeFile,"old",start.addingTimeInterval(-60))
let safeFolder=try store.folder(for:safeFile,archive:archive);let safe=PVBackupArchive()
_=try safe.process(source:safeFile,folder:safeFolder,now:start)
let safeOld=try copies(safeFolder)[0]
try make(safeFile,"new",start.addingTimeInterval(200))
do {
 _=try safe.process(source:safeFile,folder:safeFolder,now:start.addingTimeInterval(301),afterCopy:{try make(safeFile,"changing while copying",start.addingTimeInterval(250))})
 fatalError("Changing source was accepted")
} catch PVBackupFailure.changingSource {}
assert(fm.fileExists(atPath:safeOld.path) && (try copies(safeFolder).count)==1)
assert(try fm.contentsOfDirectory(atPath:safeFolder.path).allSatisfy{!$0.hasPrefix(".pv-copy-")})
print("PASS: changing-source failure preserves old snapshot, does not rotate, cleans temporary copy")
let native=idleFile.deletingLastPathComponent().appendingPathComponent(PVLatestNativeAutosave.directoryName)
let native1=native.appendingPathComponent("Idle--7b4d1031-f239-3490-2a37-b636f999dd21-2026-11-02_15-00-00.prproj")
let wrong=native.appendingPathComponent("Other--7b4d1031-f239-3490-2a37-b636f999dd21-2026-11-02_16-00-00.prproj")
try make(native1,"native1",start.addingTimeInterval(-60));try make(wrong,"other project",start.addingTimeInterval(-20))
let mirror=PVLatestNativeAutosave()
if case .copied = try mirror.process(project:idleFile,archiveFolder:idleFolder,now:start) {} else {fatalError("Native copy missing")}
let nativeDest=idleFolder.appendingPathComponent(PVLatestNativeAutosave.directoryName)
assert(try copies(nativeDest).map(\.lastPathComponent)==[native1.lastPathComponent])
let native2=native.appendingPathComponent("Idle-2026-11-02_17-00-00.prproj")
try make(native2,"native2",start.addingTimeInterval(30))
_=try mirror.process(project:idleFile,archiveFolder:idleFolder,now:start.addingTimeInterval(60))
assert(try copies(nativeDest).map(\.lastPathComponent)==[native2.lastPathComponent])
assert(fm.fileExists(atPath:native1.path) && fm.fileExists(atPath:wrong.path))
let emergency=native.appendingPathComponent("Idle.prproj");try make(emergency,"emergency",start.addingTimeInterval(100))
_=try mirror.process(project:idleFile,archiveFolder:idleFolder,now:start.addingTimeInterval(150))
assert(try copies(nativeDest).map(\.lastPathComponent)==[emergency.lastPathComponent])
print("PASS: latest native autosave matched to its project, one mirror retained, native originals untouched, emergency save supported")
let repairState=try state(folder)
let latestFile=folder.appendingPathComponent(repairState.records.last!.filename)
try fm.removeItem(at:latestFile)
_=try engine.process(source:file,folder:folder,now:start.addingTimeInterval(600+40*301+60))
let repaired=try state(folder)
assert(fm.fileExists(atPath:folder.appendingPathComponent(repaired.records.last!.filename).path))
assert(try! PVSafeCopy.digest(folder.appendingPathComponent(repaired.records.last!.filename)) == PVSafeCopy.digest(file))
print("PASS: a manually deleted latest backup is recreated even without a source change")
let manualFile=root.appendingPathComponent("manual/Manual.prproj")
try make(manualFile,"first manual state",start.addingTimeInterval(-60))
let manualFolder=try store.folder(for:manualFile,archive:archive);let manualEngine=PVBackupArchive()
_=try manualEngine.process(source:manualFile,folder:manualFolder,now:start)
try make(manualFile,"second manual state",start.addingTimeInterval(10))
_=try manualEngine.process(source:manualFile,folder:manualFolder,now:start.addingTimeInterval(60))
assert(try copies(manualFolder).count==1)
_=try manualEngine.process(source:manualFile,folder:manualFolder,now:start.addingTimeInterval(60),forceSnapshot:true)
assert(try copies(manualFolder).count==2)
let summary=try manualEngine.latest(source:manualFile,folder:manualFolder)!
assert(summary.captured==start.addingTimeInterval(60))
assert(try String(contentsOf:summary.file,encoding:.utf8)=="second manual state")
_=try manualEngine.process(source:manualFile,folder:manualFolder,now:start.addingTimeInterval(61),forceSnapshot:true)
assert(try copies(manualFolder).count==2,"Manual action must not duplicate unchanged content")
try make(manualFile,"second manual state",Date().addingTimeInterval(-60))
let direct=try AutosaveWorker().scanSelected(project:manualFile,archive:archive)
assert(direct.found==1 && direct.failed==0 && direct.unchanged==1)
print("PASS: manual snapshot bypasses interval but deduplicates; latest file/date match; selected-only copy needs no computer search grant")
let sameA=root.appendingPathComponent("sameA/Same.prproj"),sameB=root.appendingPathComponent("sameB/Same.prproj")
try make(sameA,"first source",Date().addingTimeInterval(-60));try make(sameB,"second source",Date().addingTimeInterval(-60))
let separate=AutosaveWorker()
_=try separate.scanSelected(project:sameA,archive:archive);_=try separate.scanSelected(project:sameB,archive:archive)
let latestStore=PVProjectFolders()
let folderA=latestStore.existing(for:sameA,archive:archive)!,folderB=latestStore.existing(for:sameB,archive:archive)!
assert(folderA != folderB)
let latestA=try PVBackupArchive().latest(source:sameA,folder:folderA)!,latestB=try PVBackupArchive().latest(source:sameB,folder:folderB)!
assert(try String(contentsOf:latestA.file,encoding:.utf8)=="first source")
assert(try String(contentsOf:latestB.file,encoding:.utf8)=="second source")
assert(PVBackupIssue.classify(PVBackupIssue.searchAccess,project:sameA,archive:archive)==PVBackupIssue.searchAccess)
assert(PVBackupIssue.classify(NSError(domain:NSCocoaErrorDomain,code:NSFileReadNoPermissionError),project:sameA,archive:archive)==PVBackupIssue.searchAccess)
assert(PVBackupIssue.classify(PVBackupIssue.copyFailed,project:sameA,archive:URL(fileURLWithPath:"/Volumes/PV-Missing-Fixture-Volume/backups"))==PVBackupIssue.diskUnavailable)
print("PASS: same-name latest snapshots stay source-specific; permission and missing-drive problems have actionable classifications")
print("PASS: new hybrid backup engine checks completed")
'''
# Throwing expressions cannot appear in Swift assert's non-throwing autoclosure.
import re
harness=re.sub(r'assert\(try (.+)\)',r'assert(try! \1)',harness)
harness=harness.replace('(try copies(safeFolder).count)','(try! copies(safeFolder).count)')
with tempfile.TemporaryDirectory(prefix='pv47-engine-check-') as temp:
 p=Path(temp);f=p/'Checks.swift';f.write_text(source+harness)
 subprocess.run(['xcrun','swiftc','-disable-sandbox','-module-cache-path',str(p/'modules'),str(f),'-o',str(p/'Checks')],check=True)
 subprocess.run([str(p/'Checks')],check=True)
