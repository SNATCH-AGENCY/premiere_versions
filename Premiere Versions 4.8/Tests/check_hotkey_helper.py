"""Isolated real login-item test. Run in normal Terminal; production preferences and app are untouched."""
from pathlib import Path
import hashlib,importlib.util,json,plistlib,shutil,subprocess,sys,tempfile,time,uuid
root=Path(__file__).resolve().parents[1];candidate=Path(sys.argv[1]).resolve()
def run(args,**kwargs):return subprocess.run(list(map(str,args)),check=True,**kwargs)
harness='''import AppKit
import ServiceManagement
import Carbon
@MainActor final class Delegate: NSObject, NSApplicationDelegate {
 var task: Task<Void,Never>?
 var root: URL { URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "PVTestRoot") as! String) }
 var service: SMAppService { .loginItem(identifier: Bundle.main.bundleIdentifier! + ".HotKeyHelper") }
 func write(_ name:String,_ value:[String:Any]) { try! JSONSerialization.data(withJSONObject:value).write(to:root.appendingPathComponent(name),options:.atomic) }
 func helperState() -> [String:Any] { ((try? Data(contentsOf:root.appendingPathComponent("helper-state.json"))).flatMap { try? JSONSerialization.jsonObject(with:$0) }) as? [String:Any] ?? [:] }
 func configure(_ data:Data) async -> Bool {
  let connection=NSXPCConnection(serviceName:Bundle.main.bundleIdentifier!+".IconService")
  connection.remoteObjectInterface=NSXPCInterface(with:PVIconServiceProtocol.self);connection.resume()
  defer {connection.invalidate()}
  return await withCheckedContinuation { completion in
   let proxy=connection.remoteObjectProxyWithErrorHandler{_ in completion.resume(returning:false)} as! PVIconServiceProtocol
   proxy.configureHotKeyHelper(data){success,_ in completion.resume(returning:success)}
  }
 }
 func applicationDidFinishLaunching(_ notification:Notification) {
  NSApp.setActivationPolicy(.prohibited)
  task=Task { @MainActor in
   do {
    if CommandLine.arguments.contains("--cleanup") { try? await service.unregister(); NSApp.terminate(nil); return }
    if FileManager.default.fileExists(atPath:root.appendingPathComponent("phase1.json").path) {
     let previous=helperState()["pid"] as? Int
     try await service.unregister();try service.register()
     var restored=false
     for _ in 0..<100 {
      let value=helperState()
      if value["key"] as? Int == Int(kVK_F19), value["pid"] as? Int != previous {restored=true;break}
      try await Task.sleep(nanoseconds:100_000_000)
     }
     try await service.unregister()
     write("result.json",["passed":restored,"relaunchedByHelper":true,"customShortcutRestored":restored]);NSApp.terminate(nil);return
    }
    try service.register()
    guard service.status == .enabled else {throw NSError(domain:"HelperTest",code:1,userInfo:[NSLocalizedDescriptionKey:"Login item requires manual macOS approval; fixture was unregistered."])}
    let rejected=await configure(Data("{}".utf8))
    guard !rejected else {throw NSError(domain:"HelperTest",code:2)}
    let shortcut=PVHelperShortcut(keyCode:UInt32(kVK_F19),modifiers:UInt32(cmdKey|controlKey|optionKey|shiftKey),keyLabel:"F19")
    guard await configure(try JSONEncoder().encode(shortcut)) else {throw NSError(domain:"HelperTest",code:3)}
    var synchronized=false
    for _ in 0..<100 {
     if helperState()["key"] as? Int == Int(kVK_F19) {synchronized=true;break}
     try await Task.sleep(nanoseconds:100_000_000)
    }
    guard synchronized else {throw NSError(domain:"HelperTest",code:4)}
    write("phase1.json",["configured":true,"invalidPayloadRejected":true]);NSApp.terminate(nil)
   } catch {
    try? await service.unregister()
    write("result.json",["passed":false,"error":error.localizedDescription,"domain":(error as NSError).domain,"code":(error as NSError).code,"details":String(describing:(error as NSError).userInfo)]);NSApp.terminate(nil)
   }
  }
 }
}
@main struct Main {
 @MainActor static func main(){let app=NSApplication.shared;let delegate=Delegate();app.delegate=delegate;withExtendedLifetime(delegate){app.run()}}
}
'''
with tempfile.TemporaryDirectory(prefix='pv-icon-service-helper-',dir='/private/tmp') as temp:
 temp=Path(temp);fixture=temp/'Fixture.app';shutil.copytree(candidate,fixture,symlinks=True)
 identifier='devplaceholder.PVIconServiceFixture.'+uuid.uuid4().hex
 info=plistlib.loads((fixture/'Contents/Info.plist').read_bytes());info.update(CFBundleIdentifier=identifier,CFBundleExecutable='Fixture',CFBundleName='Hotkey Fixture',LSUIElement=True,PVTestRoot=str(temp))
 (fixture/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
 shutil.rmtree(fixture/'Contents/MacOS');(fixture/'Contents/MacOS').mkdir()
 source=temp/'Main.swift';source.write_text(harness)
 run(['xcrun','swiftc','-parse-as-library','-disable-sandbox','-swift-version','5','-default-isolation','MainActor','-module-cache-path',temp/'modules',root/'Premiere Versions/HelperShortcut.swift',root/'Premiere Versions/IconServiceProtocol.swift',source,'-o',fixture/'Contents/MacOS/Fixture'])
 spec=importlib.util.spec_from_file_location('icon_builder',root/'tools/build_icon_service.py');builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder);builder.build(root,fixture,identifier,testing=True)
 ent=temp/'entitlements.plist';ent.write_bytes(plistlib.dumps({'com.apple.security.app-sandbox':True,'com.apple.security.temporary-exception.files.absolute-path.read-write':[str(temp)+'/']}))
 run(['codesign','--force','--sign','-','--entitlements',ent,fixture]);run(['codesign','--verify','--deep','--strict',fixture])
 process=None
 with (temp/'fixture.log').open('w') as log:
  try:
   process=subprocess.Popen(['/usr/bin/open','-n','-g','-W',str(fixture)],stdout=log,stderr=log)
   deadline=time.monotonic()+40
   while time.monotonic()<deadline and not (temp/'phase1.json').exists() and not (temp/'result.json').exists():time.sleep(.1)
   if (temp/'result.json').exists():raise RuntimeError(json.loads((temp/'result.json').read_text()))
   if not (temp/'phase1.json').exists():raise RuntimeError('First phase timed out')
   process.wait(timeout=10);process=None
   registered=False;deadline=time.monotonic()+20
   while time.monotonic()<deadline:
    try:state=json.loads((temp/'helper-state.json').read_text())
    except (OSError,ValueError):time.sleep(.1);continue
    if state.get('registered') and not state.get('mainRunning'):registered=True;break
    time.sleep(.1)
   if not registered:raise RuntimeError('Helper did not take over after main exit: '+str(state))
   (temp/'trigger').write_text('simulate the fixture hotkey without injecting keyboard input')
   deadline=time.monotonic()+40
   while time.monotonic()<deadline and not (temp/'result.json').exists():time.sleep(.1)
   if not (temp/'result.json').exists():raise RuntimeError('Helper did not relaunch its owner')
   result=json.loads((temp/'result.json').read_text())
   if not result.get('passed'):raise RuntimeError(result)
   print('PASS: real sandboxed owner registered its login item, synchronized a custom shortcut through validated XPC, exited; helper took over, relaunched the owner, retained its shortcut after restart, and was unregistered. No real keystrokes or installed working app were used.')
  except Exception:
   print((temp/'fixture.log').read_text());raise
  finally:
   if process is not None and process.poll() is None:process.terminate();process.wait(timeout=5)
   # Always unregister only this fixture's service before its directory is removed.
   try:subprocess.run(['/usr/bin/open','-n','-g','-W',str(fixture),'--args','--cleanup'],stdout=log,stderr=log,timeout=20)
   except subprocess.TimeoutExpired:pass
   subprocess.run(['/usr/bin/defaults','delete',identifier+'.HotKeyHelper'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
