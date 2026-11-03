from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
source=(root/'Premiere Versions/ManualVersionIndex.swift').read_text()
harness=r"""
@main struct Checks {
 @MainActor static func main() throws {
  let fm=FileManager.default,root=URL(fileURLWithPath:"/private/tmp/pv-manual-index-"+UUID().uuidString)
  defer {try? fm.removeItem(at:root)}
  let project="Example (cut)";let folder=root.appendingPathComponent(project)
  try fm.createDirectory(at:folder,withIntermediateDirectories:true)
  try Data("file".utf8).write(to:folder.appendingPathComponent(project+"_v013_date.prproj"))
  try Data("file".utf8).write(to:folder.appendingPathComponent("Other_v999_date.prproj"))
  let index=PVManualVersionIndex();try index.refresh(project:project,archive:root)
  precondition(index.numbers == [13]);precondition(index.directoryReads == 1)
  for _ in 0..<1000 {precondition(index.numbers?.max() == 13)}
  precondition(index.directoryReads == 1,"Rendering must not enumerate the directory")
  try Data("file".utf8).write(to:folder.appendingPathComponent(project+"_v014_date.prproj"))
  try index.refresh(project:project,archive:root)
  precondition(index.numbers == [13,14] && index.directoryReads == 2)
  index.invalidate();precondition(index.numbers == nil)
  print("PASS: archive snapshot excludes other projects; 1000 display reads cause zero additional disk scans; explicit refresh sees new versions")
 }
}
"""
with tempfile.TemporaryDirectory(prefix='pv-index-check-') as temp:
 p=Path(temp);f=p/'Checks.swift';f.write_text(source+harness)
 subprocess.run(['xcrun','swiftc','-parse-as-library','-disable-sandbox','-module-cache-path',str(p/'modules'),str(f),'-o',str(p/'Checks')],check=True)
 subprocess.run([str(p/'Checks')],check=True)
