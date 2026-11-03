from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
app = (root/'Premiere Versions/MyApp.swift').read_text()
source = app[app.index('nonisolated struct SavedShortcut'):app.index('/// Owned by the app')]
# Isolate Carbon registration from the real user's configured shortcut/preferences.
source = source.replace('SavedShortcut.load()', 'SavedShortcut(keyCode: UInt32(kVK_F19), modifiers: UInt32(controlKey | cmdKey | shiftKey), keyLabel: "F19")')
# The tool host cannot register system hotkeys (Carbon -9868). Stub only the
# OS boundary; exercise the production observer/recording/registration state machine.
a=source.index('    private func register(_ candidate: SavedShortcut)')
b=source.index('\n    func start()',a)
source=source[:a]+'''    private func register(_ candidate: SavedShortcut) -> (OSStatus, EventHotKeyRef?) {
        return (noErr, OpaquePointer(bitPattern: 1))
    }
'''+source[b:]
source=source.replace('UnregisterEventHotKey(', 'testUnregisterEventHotKey(')
harness = '''
extension GlobalSaveHotKey { var registeredForTest: Bool { hotKeyRef != nil } }
@main struct Checks {
 @MainActor static func main() async {
  _ = NSApplication.shared
  func check(_ ok: Bool, _ message: String) { if !ok { print("FAIL:",message);exit(1) } }
  for id in ["com.adobe.PremierePro", "com.adobe.PremierePro.26"] {
   check(PVPremiereShortcutPolicy.allows(bundleIdentifier:id,hidden:false,terminated:false), "Premiere allowed")
   check(!PVPremiereShortcutPolicy.allows(bundleIdentifier:id,hidden:true,terminated:false), "hidden denied")
   check(!PVPremiereShortcutPolicy.allows(bundleIdentifier:id,hidden:false,terminated:true), "terminated denied")
  }
  for id in [nil,"com.apple.finder","devplaceholder.YDHGHCQE.Premiere-Versions","com.adobe.AfterEffects","com.adobe.PremiereProFake"] {
   check(!PVPremiereShortcutPolicy.allows(bundleIdentifier:id,hidden:false,terminated:false), "other app denied")
  }
  var active=false
  let hotkey=GlobalSaveHotKey(isPremiereActive:{ active })
  hotkey.start();check(!hotkey.registeredForTest,"not reserved outside Premiere")
  func switchApp(_ value:Bool) async {
   active=value
   NSWorkspace.shared.notificationCenter.post(name:NSWorkspace.didActivateApplicationNotification,object:nil)
   try? await Task.sleep(nanoseconds:150_000_000)
  }
  await switchApp(true);check(hotkey.registeredForTest,"registered on activation")
  await switchApp(false);check(!hotkey.registeredForTest,"released on switch away")
  await switchApp(true);check(hotkey.registeredForTest,"registered on return")
  hotkey.beginRecording();check(!hotkey.registeredForTest,"released during recording")
  await switchApp(false);hotkey.endRecording();check(!hotkey.registeredForTest,"not restored outside Premiere")
  await switchApp(true);check(hotkey.registeredForTest,"restored on return after recording")
  hotkey.stop();await switchApp(true);check(!hotkey.registeredForTest,"observer and registration removed on stop")
  print("PASS: Premiere identity/visibility policy and registration state machine (OS registration stubbed), switching, recording and cleanup")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='pv433-hotkey-') as temp:
 p=Path(temp); swift=p/'Checks.swift'
 swift.write_text('import SwiftUI\nimport AppKit\nimport Carbon\nimport Combine\nfunc testUnregisterEventHotKey(_ ref:EventHotKeyRef)->OSStatus { noErr }\nfunc PVL(_ value:String)->String { value }\n'+source+harness)
 subprocess.run(['xcrun','swiftc','-parse-as-library','-disable-sandbox','-swift-version','5','-default-isolation','MainActor','-module-cache-path',str(p/'modules'),str(swift),'-o',str(p/'Checks')],check=True)
 subprocess.run([str(p/'Checks')],check=True)
