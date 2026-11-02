"""Real sandboxed client -> embedded icon XPC service check. Normal Terminal only."""
from pathlib import Path
import hashlib, importlib.util, plistlib, shutil, subprocess, sys, tempfile, uuid, time
root=Path(__file__).resolve().parents[1]
pristine=Path(sys.argv[1]).resolve()
spec=importlib.util.spec_from_file_location('icon_builder',root/'tools/build_icon_service.py')
builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
def run(args):subprocess.run(list(map(str,args)),check=True)
def quarantine(app):
 result=subprocess.run(['/usr/bin/xattr','-p','com.apple.quarantine',str(app)],capture_output=True)
 return result.stdout if result.returncode==0 else None
def manifest(app):
 return {str(p.relative_to(app)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (app/'Contents').rglob('*') if p.is_file() and not p.is_symlink()}
harness='''import AppKit
@main struct Check {
 @MainActor static func main() async {
  _ = NSApplication.shared
  NSApp.setActivationPolicy(.prohibited)
  guard let image=NSImage(contentsOfFile:CommandLine.arguments[1]) else { exit(1) }
  let app=Bundle.main.bundleURL
  let outside=app.deletingLastPathComponent().appendingPathComponent("Untouched.app")
  guard !(await PVFinderIconWriter.apply(image,to:outside)) else {
   print("FAIL: service accepted another target");exit(1)
  }
  guard await PVFinderIconWriter.apply(image,to:app) else {
   print("FAIL: sandboxed client could not apply its icon through XPC");exit(1)
  }
  let phase1=app.deletingLastPathComponent().appendingPathComponent("phase1")
  let phase2=app.deletingLastPathComponent().appendingPathComponent("phase2")
  try! Data("ready".utf8).write(to:phase1)
  for _ in 0..<200 {
   if FileManager.default.fileExists(atPath:phase2.path) { break }
   try? await Task.sleep(nanoseconds:100_000_000)
  }
  guard FileManager.default.fileExists(atPath:phase2.path), await PVFinderIconWriter.apply(image,to:app) else {
   print("FAIL: second icon write with an existing download mark");exit(1)
  }
  print("PASS: real sandboxed XPC client; unrelated target rejected; owning app icon applied twice")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='pv-icon-service-',dir='/private/tmp') as temp:
 temp=Path(temp);fixture=temp/'Fixture.app'
 shutil.copytree(pristine,fixture,symlinks=True)
 shutil.rmtree(fixture/'Contents/MacOS');(fixture/'Contents/MacOS').mkdir()
 identifier='devplaceholder.PVIconServiceFixture.'+uuid.uuid4().hex
 info=plistlib.loads((fixture/'Contents/Info.plist').read_bytes())
 info.update(CFBundleIdentifier=identifier,CFBundleExecutable='Fixture',CFBundleName='Premiere Versions',LSUIElement=True)
 (fixture/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
 source=temp/'Check.swift';source.write_text(harness)
 binary=fixture/'Contents/MacOS/Fixture'
 run(['xcrun','swiftc','-parse-as-library','-disable-sandbox','-swift-version','5','-default-isolation','MainActor','-module-cache-path',temp/'modules',root/'Premiere Versions/IconServiceProtocol.swift',root/'Premiere Versions/IconServiceClient.swift',source,'-o',binary])
 builder.build(root,fixture,identifier,testing=True)
 ent=temp/'entitlements.plist'
 ent.write_bytes(plistlib.dumps({'com.apple.security.app-sandbox':True,'com.apple.security.temporary-exception.files.absolute-path.read-write':[str(temp)+'/']}))
 run(['codesign','--force','--sign','-','--entitlements',ent,fixture])
 image=temp/'icon.png';shutil.copy2(root/'Premiere Versions/Assets.xcassets/PVColor3.imageset/logo.png',image)
 outside=temp/'Untouched.app';outside.mkdir();(outside/'sentinel').write_text('untouched')
 before=quarantine(fixture);contents=manifest(fixture)
 log=Path('/private/tmp/pv442-icon-service-debug.log')
 with log.open('w') as stream:
  process=subprocess.Popen([str(binary),str(image)],stdout=stream,stderr=stream)
  try:
   deadline=time.monotonic()+25
   while not (temp/'phase1').exists() and process.poll() is None and time.monotonic()<deadline:
    time.sleep(0.1)
   if not (temp/'phase1').exists():
    print(log.read_text());raise RuntimeError('First sandboxed XPC icon check failed; see '+str(log))
   assert quarantine(fixture)==before,'Icon write added quarantine'
   assert manifest(fixture)==contents,'Signed Contents changed'
   assert (fixture/'Icon\r').exists(),'Persistent icon missing'
   assert not (outside/'Icon\r').exists(),'Unrelated target modified'
   # Mark the already-running fixture, so Gatekeeper/translocation is not part of this test.
   run(['/usr/bin/xattr','-w','com.apple.quarantine','0083;12345678;Safari;fixture',fixture])
   expected=quarantine(fixture)
   (temp/'phase2').write_text('continue')
   if process.wait(timeout=25)!=0:
    print(log.read_text());raise RuntimeError('Second sandboxed XPC icon check failed')
   assert quarantine(fixture)==expected,'Existing download quarantine changed'
   assert manifest(fixture)==contents,'Signed Contents changed'
   run(['codesign','--verify','--deep',fixture])
   print(log.read_text())
  finally:
   if process.poll() is None:process.terminate();process.wait(timeout=5)
 print('PASS: real embedded XPC icon service; quarantine preserved with/without download mark; signed Contents intact; other targets rejected')
