"""Exercise the release listener and XPC pairing using a local fake peer, without touching Premiere."""
from pathlib import Path
import importlib.util,plistlib,shutil,subprocess,tempfile,uuid,time
root=Path(__file__).resolve().parents[1]
def run(args,**kw):return subprocess.run(list(map(str,args)),check=True,**kw)
spec=importlib.util.spec_from_file_location('builder',root/'tools/build_icon_service.py');builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
swift='''import AppKit
@main struct Check {
 @MainActor static func main() async {
  _ = NSApplication.shared;NSApp.setActivationPolicy(.prohibited)
  let bridge=PremiereBridge.shared;bridge.start()
  let folder=Bundle.main.bundleURL.deletingLastPathComponent()
  let source=URL(fileURLWithPath:"/private/tmp/bridge-fixture.prproj")
  do {
   try await bridge.save(source)
   do {try await bridge.save(source);print("FAIL: mismatched response accepted");exit(1)}catch{}
   let task=Task{@MainActor in try await bridge.save(source)}
   for _ in 0..<200 {
    if FileManager.default.fileExists(atPath:folder.appendingPathComponent("cancel-ready").path){break}
    try await Task.sleep(for:.milliseconds(20))
   }
   task.cancel()
   do {try await task.value;print("FAIL: cancellation ignored");exit(1)}catch is CancellationError{}catch{print("FAIL: wrong cancellation error");exit(1)}
   try await Task.sleep(for:.milliseconds(600))
   try await bridge.save(source)
   do {try await bridge.save(source);print("FAIL: disconnect accepted");exit(1)}catch{}
   print("PASS: release bridge confirms matching saves, rejects wrong paths, cancels pending saves, ignores late replies and fails on disconnect")
  }catch{print("FAIL: "+error.localizedDescription);exit(1)}
 }
}
'''
js='''const fs=require('node:fs');const p=require('node:path');
const root=process.argv[2];const c=JSON.parse(fs.readFileSync(p.join(root,'bridge-home/Library/Application Support/Premiere Versions/Bridge/connection.json')));
const connect=token=>new Promise((resolve,reject)=>{const w=new WebSocket('ws://127.0.0.1:'+c.port);w.onopen=()=>{w.send(JSON.stringify({type:'hello',protocol:2,token,plugin:'dev.premiereversions.bridge',version:'4.91.1'}));resolve(w)};w.onerror=reject;});
(async()=>{const bad=await connect('0'.repeat(64));await new Promise((resolve,reject)=>{bad.onclose=resolve;bad.onmessage=()=>reject(Error('Bad credential accepted'));setTimeout(()=>reject(Error('No rejection')),3000).unref()});
const ws=await connect(c.credential);let n=0;ws.onmessage=({data})=>{const m=JSON.parse(data);if(m.type!=='request')return;n++;const reply=()=>{if(ws.readyState===1)ws.send(JSON.stringify({type:'result',id:m.id,ok:true,path:n===2?'/private/tmp/wrong.prproj':m.expectedPath}))};
if(n===3){fs.writeFileSync(p.join(root,'cancel-ready'),'ready');setTimeout(reply,250)}else if(n===5){ws.close()}else reply();};})();
setTimeout(()=>process.exit(0),25000).unref();
'''
with tempfile.TemporaryDirectory(prefix='pv-icon-service-',dir='/private/tmp') as temporary:
 temp=Path(temporary);app=temp/'Fixture.app';contents=app/'Contents';(contents/'MacOS').mkdir(parents=True)
 identifier='devplaceholder.PVIconServiceFixture.'+uuid.uuid4().hex
 (contents/'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':identifier,'CFBundleExecutable':'Fixture','CFBundleName':'Save Bridge Fixture','CFBundleVersion':'4.91.1','CFBundlePackageType':'APPL','LSUIElement':True}))
 source=temp/'Check.swift';source.write_text(swift)
 run(['xcrun','swiftc','-parse-as-library','-disable-sandbox','-swift-version','5','-default-isolation','MainActor','-module-cache-path',temp/'modules',*[root/'Premiere Versions'/f for f in ['IconServiceProtocol.swift','BridgeInstallClient.swift','PremiereBridge.swift','Localization.swift']],source,'-o',contents/'MacOS/Fixture'])
 builder.build(root,app,identifier,testing=True)
 ent=temp/'fixture.entitlements';ent.write_bytes(plistlib.dumps({'com.apple.security.app-sandbox':True,'com.apple.security.network.server':True,'com.apple.security.network.client':True,'com.apple.security.temporary-exception.files.absolute-path.read-write':[str(temp)+'/']}))
 run(['codesign','--force','--sign','-','--entitlements',ent,app])
 log=temp/'check.log';stream=log.open('w');process=subprocess.Popen([str(contents/'MacOS/Fixture')],stdout=stream,stderr=stream)
 peer=None
 try:
  config=temp/'bridge-home/Library/Application Support/Premiere Versions/Bridge/connection.json';deadline=time.monotonic()+25
  while not config.exists() and time.monotonic()<deadline and process.poll() is None:time.sleep(0.1)
  if not config.exists():raise RuntimeError('No runtime pairing; '+log.read_text())
  script=temp/'peer.cjs';script.write_text(js)
  peer=subprocess.Popen([shutil.which('node') or '/opt/homebrew/bin/node',str(script),str(temp)],stdout=stream,stderr=stream)
  process.wait(timeout=35)
  stream.flush();output=log.read_text();print(output)
  if process.returncode or 'PASS: release bridge confirms' not in output:raise RuntimeError('Release bridge fixture failed')
 finally:
  if process.poll() is None:process.kill();process.wait()
  if peer and peer.poll() is None:peer.terminate();peer.wait()
  stream.close()
