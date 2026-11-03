from pathlib import Path
import subprocess,tempfile
r=Path(__file__).resolve().parents[1]
s=(r/'Premiere Versions/MyApp.swift').read_text()
a=s.index('@MainActor\nfinal class AutosaveMonitor');b=s.index('nonisolated enum DefaultLocations',a)
monitor=s[a:b].replace('!premiereLifecycle.processes.isEmpty','fixturePremiereRunning')
source='import AppKit\nimport Combine\nimport CoreServices\nimport Carbon\nimport Darwin\nvar fixturePremiereRunning = false\n'
for name in ['Localization.swift','HelperShortcut.swift','PremiereLifecycle.swift','BackupStorage.swift','NativeAutosave.swift']:source+=(r/'Premiere Versions'/name).read_text()+'\n'
source+=s[b:]+'\n'+monitor
source+='''
@main struct Checks {
 @MainActor static func main() async throws {
  let suite="pv-mode-policy-"+UUID().uuidString
  let prefs=UserDefaults(suiteName:suite)!;defer{prefs.removePersistentDomain(forName:suite)}
  PVBackupMode.migrate(in:prefs);assert(prefs.string(forKey:"backupMode")=="automatic")
  prefs.removeObject(forKey:"backupMode");prefs.set(false,forKey:"autosaveMonitoringEnabled")
  PVBackupMode.migrate(in:prefs);assert(prefs.string(forKey:"backupMode")=="off")
  prefs.removeObject(forKey:"backupMode");prefs.set(true,forKey:"autosaveMonitoringEnabled")
  PVBackupMode.migrate(in:prefs);assert(prefs.string(forKey:"backupMode")=="automatic")
  prefs.set("always",forKey:"backupMode");PVBackupMode.migrate(in:prefs);assert(prefs.string(forKey:"backupMode")=="always")
  assert(!PVBackupMode.off.runs(premiereRunning:true));assert(!PVBackupMode.automatic.runs(premiereRunning:false))
  assert(PVBackupMode.automatic.runs(premiereRunning:true));assert(PVBackupMode.always.runs(premiereRunning:false))
  assert(PVHelperPolicy.needsRefresh(enabled:true,registeredVersion:0))
  assert(!PVHelperPolicy.needsRefresh(enabled:true,registeredVersion:PVHelperPolicy.implementationVersion))
  assert(!PVHelperPolicy.needsRefresh(enabled:false,registeredVersion:0))
  var policy=PVAutoLaunchPolicy()
  assert(!policy.shouldLaunch(processes:[],enabled:true,ownerRunning:false))
  assert(policy.shouldLaunch(processes:[10],enabled:true,ownerRunning:false))
  assert(!policy.shouldLaunch(processes:[10],enabled:true,ownerRunning:false),"Manual exit must not trigger a restart")
  assert(!policy.shouldLaunch(processes:[],enabled:true,ownerRunning:false))
  assert(policy.shouldLaunch(processes:[20],enabled:true,ownerRunning:false))
  assert(!policy.shouldLaunch(processes:[20,30],enabled:false,ownerRunning:false))
  assert(policy.shouldLaunch(processes:[20,30],enabled:true,ownerRunning:false,justEnabled:true))
  assert(!policy.shouldLaunch(processes:[40],enabled:true,ownerRunning:true))
  assert(!policy.shouldLaunch(processes:[40],enabled:true,ownerRunning:false))
  assert(PVPremiereProcess.matches("com.adobe.PremierePro.2026"));assert(!PVPremiereProcess.matches("com.adobe.AfterEffects"))
  let defaults=UserDefaults.standard
  let dir=URL(fileURLWithPath:"/private/tmp/pv-monitor-mode-"+UUID().uuidString)
  try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
  defer{try? FileManager.default.removeItem(at:dir)}
  let watch=dir.appendingPathComponent("watch"),archive=dir.appendingPathComponent("archive")
  for url in [watch,archive]{try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)}
  defaults.set("folder",forKey:"searchMode");defaults.set("automatic",forKey:"backupMode")
  defaults.set(try watch.bookmarkData(),forKey:"autosaveWatchBookmark");defaults.set(try archive.bookmarkData(),forKey:"autosaveArchiveBookmark")
  let monitor=AutosaveMonitor();assert(!monitor.isMonitoring && !monitor.isScanning)
  fixturePremiereRunning=true;monitor.reconcile();assert(monitor.isMonitoring)
  fixturePremiereRunning=false;monitor.reconcile();assert(!monitor.isMonitoring)
  defaults.set("always",forKey:"backupMode");monitor.reconcile();assert(monitor.isMonitoring)
  defaults.set("off",forKey:"backupMode");monitor.reconcile();assert(!monitor.isMonitoring)
  print("PASS: mode migration, no idle monitoring, event-driven pause/resume, Always/Off, manual-exit protection and automatic-launch policy")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='pv48-modes-') as d:
 d=Path(d);swift=d/'Checks.swift';swift.write_text(source);app=d/'Checks.app';binary=app/'Contents/MacOS/Checks';binary.parent.mkdir(parents=True)
 import plistlib
 (app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'devplaceholder.PVModeFixture.'+d.name,'CFBundleExecutable':'Checks'}))
 subprocess.run(['xcrun','swiftc','-parse-as-library','-disable-sandbox','-swift-version','5','-default-isolation','MainActor','-module-cache-path',str(d/'modules'),str(swift),'-o',str(binary)],check=True)
 subprocess.run([str(binary)],check=True)
