from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
source=(root/'Premiere Versions/ProjectSelection.swift').read_text()+'\n'+(root/'Premiere Versions/PresentationPolicy.swift').read_text()+'\n'+(root/'Premiere Versions/ShortcutInput.swift').read_text()
harness='''
@main struct Checks {
 @MainActor static func main() async throws {
  let fm=FileManager.default
  let root=URL(fileURLWithPath:"/private/tmp/pv45-project-"+UUID().uuidString,isDirectory:true)
  try fm.createDirectory(at:root,withIntermediateDirectories:true)
  defer { try? fm.removeItem(at:root) }
  let missing=root.appendingPathComponent("deleted/sub/project.prproj")
  precondition(PVProjectLocation.nearestFolder(to:missing).resolvingSymlinksInPath().path==root.resolvingSymlinksInPath().path)
  let file=root.appendingPathComponent("Project.prproj")
  try Data("project".utf8).write(to:file)
  let watcher=PVProjectWatcher();watcher.watch(file)
  try fm.removeItem(at:file)
  for _ in 0..<30 { if watcher.revision>0 {break};try await Task.sleep(nanoseconds:50_000_000) }
  precondition(watcher.revision>0,"Deletion must notify without polling")
  watcher.stop()
  let memory=PVScrollMemory();let now=Date()
  memory.offset=142;memory.closedAt=now;memory.prepareToOpen(now:now.addingTimeInterval(9.9))
  precondition(memory.offset==142)
  memory.closedAt=now;memory.prepareToOpen(now:now.addingTimeInterval(10))
  precondition(memory.offset==0)
  precondition(PVShortcutInput.latinLabel(code:1,fallback:"Ы")=="S")
  precondition(PVShortcutInput.latinLabel(code:12,fallback:"Й")=="Q")
  precondition(PVShortcutInput.latinLabel(code:40,fallback:"Л")=="K")
  print("PASS: nearest existing parent; actual file deletion event; settings scroll before/after ten seconds; Latin shortcut labels under Russian layout")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='pv45-checks-') as temp:
 p=Path(temp);f=p/'Checks.swift';f.write_text(source+harness)
 subprocess.run(['xcrun','swiftc','-parse-as-library','-disable-sandbox','-swift-version','5','-default-isolation','MainActor','-module-cache-path',str(p/'modules'),str(f),'-o',str(p/'Checks')],check=True)
 subprocess.run([str(p/'Checks')],check=True)
