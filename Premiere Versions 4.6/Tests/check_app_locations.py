from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
source=(root/'Premiere Versions/AppLocations.swift').read_text()
harness=r'''
func expect(_ value: Bool, line: Int = #line) { if !value { print("FAIL: app location check at line \(line)"); exit(1) } }
let fm=FileManager.default
let fixture=URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pv-installed-"+UUID().uuidString)
defer { try? fm.removeItem(at: fixture) }
let applications=fixture.appendingPathComponent("Applications")
let apps=applications.appendingPathComponent("Premiere Versions")
let id="devplaceholder.YDHGHCQE.Premiere-Versions"
func app(_ url: URL, version: String, build: String, identifier: String = "devplaceholder.YDHGHCQE.Premiere-Versions") throws {
    try fm.createDirectory(at: url.appendingPathComponent("Contents"),withIntermediateDirectories:true)
    let data=try PropertyListSerialization.data(fromPropertyList:["CFBundleIdentifier":identifier,"CFBundleShortVersionString":version,"CFBundleVersion":build],format:.xml,options:0)
    try data.write(to:url.appendingPathComponent("Contents/Info.plist"))
}
let installed=apps.appendingPathComponent("Premiere Versions 4.1.app")
let temporary=fixture.appendingPathComponent("temporary/Premiere Versions 4.1.app")
let archived=apps.appendingPathComponent("old versions/builds/Premiere Versions 99.app")
try app(installed,version:"4.1",build:"2")
try app(temporary,version:"9.9",build:"99")
try app(archived,version:"99",build:"99")
try app(applications.appendingPathComponent("Unrelated.app"),version:"100",build:"100",identifier:"another.app")
expect(PVInstalledAppLocations.find(runtime:temporary,bundleID:id,roots:[applications])?.path == installed.resolvingSymlinksInPath().standardizedFileURL.path)
expect(PVInstalledAppLocations.find(runtime:archived,bundleID:id,roots:[applications])?.path == installed.resolvingSymlinksInPath().standardizedFileURL.path)
expect(PVInstalledAppLocations.find(runtime:installed,bundleID:id,roots:[applications])?.path == installed.resolvingSymlinksInPath().standardizedFileURL.path)
let newer=applications.appendingPathComponent("Premiere Versions 4.10.app")
try app(newer,version:"4.10",build:"1")
expect(PVInstalledAppLocations.find(runtime:temporary,bundleID:id,roots:[applications])?.path == newer.resolvingSymlinksInPath().standardizedFileURL.path)
expect(PVInstalledAppLocations.find(runtime:installed,bundleID:id,roots:[applications])?.path == installed.resolvingSymlinksInPath().standardizedFileURL.path)
expect(PVInstalledAppLocations.find(runtime:temporary,bundleID:"missing.id",roots:[applications])==nil)
let custom=applications.appendingPathComponent("User Tools/Premiere Versions 4.2.app")
try app(custom,version:"4.2",build:"3")
expect(PVInstalledAppLocations.find(runtime:custom,bundleID:id,roots:[applications])?.path == custom.resolvingSymlinksInPath().standardizedFileURL.path)
print("PASS: temporary/archived copies excluded, installed matching identity selected, numeric version order and running installed copy preferred")
'''
with tempfile.TemporaryDirectory(prefix='pv-app-location-check-') as folder:
    folder=Path(folder);swift=folder/'Checks.swift';swift.write_text(source+'\n'+harness)
    compiler=subprocess.check_output(['xcrun','--find','swiftc'],text=True).strip()
    sdk=subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip()
    subprocess.run([compiler,'-sdk',sdk,'-module-cache-path',str(folder/'modules'),str(swift),'-o',str(folder/'checks')],check=True)
    subprocess.run([str(folder/'checks')],check=True)
