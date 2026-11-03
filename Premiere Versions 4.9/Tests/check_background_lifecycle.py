"""Exercise production AppDelegate and status controller in an isolated native app.
Helper IPC is replaced here; check_hotkey_helper covers the real sandboxed service.
"""
from pathlib import Path
import subprocess,tempfile,plistlib,json
root=Path(__file__).resolve().parents[1]
app=(root/'Premiere Versions/MyApp.swift').read_text()
app=app[app.index('@MainActor\nfinal class AppDelegate'):app.index('nonisolated struct SavedShortcut')]
app=app.replace('private let menuBar =','let menuBar =').replace('private var saveWindow:','var saveWindow:').replace('private var systemShutdown =','var systemShutdown =')
stubs='''import AppKit
import SwiftUI
import Combine
import Carbon
@MainActor final class AutosaveMonitor: ObservableObject { func reconcile() {};func stop() { TestState.monitorStopped = true } }
@MainActor final class GlobalSaveHotKey: ObservableObject {
 var onPress:(()->Void)?;func start() {};func stop() { TestState.shortcutStopped = true }
}
@MainActor final class PVHotKeyHelperManager {
 static let shared = PVHotKeyHelperManager()
 func start() {}
 func suspendForTermination() async -> Bool { TestState.helperSuspended = true;return true }
}
@MainActor final class PVUpdateService { static let shared = PVUpdateService();var available: String? = nil;func check() {};func startAutomaticChecks() {} }
@MainActor enum PVBrand { static func applySelectedIcon() {} }
@MainActor enum PVHelperLaunchIntent { static func consume() async -> Bool { false } }
@MainActor final class PVPanelNavigation { static let shared = PVPanelNavigation();var request:String? }
@MainActor enum PVTerminationContext { static var updating = false }
func PVL(_ value:String)->String { value }
struct PVHeaderMark: View { let tint:Color;var body:some View { Text("Pv").foregroundStyle(tint) } }
struct ContentView: View {
 @State var color=Color.purple
 var body:some View { VStack { Text("Isolated 4.9 interaction check");PVInlineColorPicker(title:"Color", color:$color) }
 .overlay(alignment:.top){PVWindowDragRegion().frame(height:26).padding(.horizontal,80)} }
}
@MainActor enum TestState {
 static var helperSuspended=false, monitorStopped=false, shortcutStopped=false
 static var transferred=false, restored=false
 static func save() {
  let report:[String:Bool] = ["transferred":transferred,"restored":restored,"helperSuspended":helperSuspended,
    "monitorStopped":monitorStopped,"shortcutStopped":shortcutStopped]
  let path=CommandLine.arguments[2]
  try! JSONSerialization.data(withJSONObject:report).write(to:URL(fileURLWithPath:path),options:.atomic)
 }
}
'''
app=app.replace('        Task { @MainActor in\n            let canQuit', '        print("STAGE schedule termination")\n        Task { @MainActor in\n            print("STAGE suspend helper")\n            let canQuit').replace('            sender.reply(toApplicationShouldTerminate: canQuit)', '            print("STAGE reply", canQuit)\n            sender.reply(toApplicationShouldTerminate: canQuit)')
app=app.replace('        hotKey.stop()\n        menuBar.stop()', '        TestState.save()\n        hotKey.stop()\n        menuBar.stop()')
harness='''
@main struct Main {
 @MainActor static func main() {
  setbuf(stdout,nil)
  print("STAGE started")
  let app=NSApplication.shared
  let defaults=UserDefaults.standard
  defaults.set(true,forKey:"hotKeyHelperEnabled")
  defaults.set(true,forKey:"showInDock");defaults.set(false,forKey:"menuBarIconEnabled")
  let delegate=AppDelegate();app.delegate=delegate
  DispatchQueue.main.asyncAfter(deadline:.now()+0.8) {
   print("STAGE checking window")
   guard let window=delegate.saveWindow else { fatalError("No utility window") }
   precondition(!window.isMovableByWindowBackground,"Controls must not drag the window")
   precondition(window.isVisible)
   // Quit from Dock/Cmd+Q goes through the actual native termination event.
   print("STAGE quit to background")
   app.terminate(nil)
   print("STAGE quit returned")
   precondition(delegate.menuBar.backgroundOnly && !window.isVisible)
   precondition(app.activationPolicy() == .accessory)
   precondition(defaults.bool(forKey:"showInDock") && !defaults.bool(forKey:"menuBarIconEnabled"),"Temporary transfer overwrote preferences")
   precondition(!TestState.helperSuspended && !TestState.monitorStopped && !TestState.shortcutStopped,"Background quit stopped protection")
   TestState.transferred=true
   delegate.showSaveWindow()
   precondition(!delegate.menuBar.backgroundOnly && window.isVisible)
   precondition(app.activationPolicy() == .regular)
   TestState.restored=true
   let menu=delegate.menuBar.makeMenu()
   precondition(menu.items.filter { !$0.isSeparatorItem }.count == 7)
   precondition(menu.items.contains { $0.submenu?.items.count == 3 })
   delegate.menuBar.onNavigate?("settings")
   precondition(PVPanelNavigation.shared.request == "settings")
   delegate.systemShutdown=true
   precondition(delegate.applicationShouldTerminate(app) == .terminateNow)
   delegate.systemShutdown=false
   PVTerminationContext.updating=true
   precondition(delegate.applicationShouldTerminate(app) == .terminateNow)
   PVTerminationContext.updating=false
   if CommandLine.arguments[1] == "disabled" {
    defaults.set(false,forKey:"hotKeyHelperEnabled");app.terminate(nil)
   } else { print("STAGE full quit");delegate.menuBar.onQuitFully?() }
  }
  withExtendedLifetime(delegate) { app.run() }
 }
}
'''
with tempfile.TemporaryDirectory(prefix='pv49-native-lifecycle-') as temp:
 temp=Path(temp)
 source=temp/'Check.swift';source.write_text(stubs+app+(root/'Premiere Versions/UtilityInteraction.swift').read_text()+(root/'Premiere Versions/HelperShortcut.swift').read_text()+(root/'Premiere Versions/MenuBar.swift').read_text()+harness)
 bundle=temp/'Fixture.app';binary=bundle/'Contents/MacOS/Fixture';binary.parent.mkdir(parents=True)
 (bundle/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'devplaceholder.PVLifecycleFixture.'+temp.name,'CFBundleExecutable':'Fixture','CFBundleName':'PV isolated lifecycle fixture','LSUIElement':True}))
 subprocess.run(['xcrun','swiftc','-parse-as-library','-disable-sandbox','-swift-version','5','-default-isolation','MainActor','-module-cache-path',str(temp/'modules'),str(source),'-o',str(binary)],check=True)
 for mode in ['full','disabled']:
  report=temp/(mode+'.json')
  subprocess.run([str(binary),mode,str(report)],check=True,timeout=25)
  result=json.loads(report.read_text());assert all(result.values()),result
 print('PASS: actual AppKit quit hides in menu, preserves visibility preferences and running services, manual open restores Dock; full/disabled quit suspends helper; shutdown/update bypass; controls cannot drag background')
