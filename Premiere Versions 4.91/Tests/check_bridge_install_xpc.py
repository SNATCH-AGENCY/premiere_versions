"""Real sandboxed client -> owning XPC installer, isolated from the user's Adobe folders."""
from pathlib import Path
import importlib.util,json,plistlib,shutil,subprocess,tempfile,uuid,hashlib
root=Path(__file__).resolve().parents[1]
def run(args,**kw):return subprocess.run(list(map(str,args)),check=True,**kw)
spec=importlib.util.spec_from_file_location('builder',root/'tools/build_icon_service.py');builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
swift='''import AppKit
@main struct Check {
 @MainActor static func main() async {
  _ = NSApplication.shared;NSApp.setActivationPolicy(.prohibited)
  for phase in 0..<2 {
   let config: [String:Any] = ["protocolVersion":2,"port":49833,"credential":String(repeating:phase==0 ? "a":"b",count:64)]
   do {
    let data=try JSONSerialization.data(withJSONObject:config)
    let result=try await PVBridgeInstallClient.install(data)
    let object=try JSONSerialization.jsonObject(with:Data(result.utf8)) as! [String:Any]
    guard object["changed"] as? Bool == (phase==0) else {exit(1)}
   }catch{print("FAIL: "+error.localizedDescription);exit(1)}
  }
  print("PASS: real sandboxed XPC plugin install and idempotent relaunch")
 }
}
// The installer client only requires the same localized error wrapper, not the network listener.
enum PremiereBridge { struct Failure: LocalizedError { let message:String;var errorDescription:String?{message} } }
'''
with tempfile.TemporaryDirectory(prefix='pv-icon-service-',dir='/private/tmp') as temporary:
 temp=Path(temporary);app=temp/'Fixture.app';contents=app/'Contents';(contents/'MacOS').mkdir(parents=True)
 identifier='devplaceholder.PVIconServiceFixture.'+uuid.uuid4().hex
 (contents/'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':identifier,'CFBundleExecutable':'Fixture','CFBundleName':'Bridge Installer Fixture','CFBundleVersion':'4.91.1','CFBundlePackageType':'APPL','LSUIElement':True}))
 source=temp/'Check.swift';source.write_text(swift)
 run(['xcrun','swiftc','-parse-as-library','-disable-sandbox','-swift-version','5','-default-isolation','MainActor','-module-cache-path',temp/'modules',root/'Premiere Versions/IconServiceProtocol.swift',root/'Premiere Versions/BridgeInstallClient.swift',source,'-o',contents/'MacOS/Fixture'])
 builder.build(root,app,identifier,testing=True)
 ent=temp/'fixture.entitlements';ent.write_bytes(plistlib.dumps({'com.apple.security.app-sandbox':True,'com.apple.security.temporary-exception.files.absolute-path.read-write':[str(temp)+'/']}))
 run(['codesign','--force','--sign','-','--entitlements',ent,app])
 run([contents/'MacOS/Fixture'],timeout=45)
 home=temp/'bridge-home/Library/Application Support'
 receipt=json.loads((home/'Premiere Versions/Bridge/installed.json').read_text())
 config=home/'Premiere Versions/Bridge/connection.json'
 assert config.stat().st_mode&0o777==0o600
 assert json.loads(config.read_text())['credential']=='b'*64
 payload=home/'Adobe/CEP/extensions/dev.premiereversions.bridge'
 for relative,digest in receipt['files'].items():assert hashlib.sha256((payload/relative).read_bytes()).hexdigest()==digest
 assert 'credential' not in (payload/'bridge.js').read_text() or 'config.credential' in (payload/'bridge.js').read_text()
 run(['codesign','--verify','--deep','--strict',app])
 print('PASS: installed payload hashes, private pairing permissions and pristine owning app signature')
