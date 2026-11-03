from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
source = (root/'Premiere Versions/Welcome.swift').read_text().split('struct PVWelcomeScreen: View')[0]
source = source.replace('import SwiftUI', 'import Foundation')
stub = 'nonisolated enum AppRelease { static let version = "4.2"; static let build = "1" }\n'
harness = '''
@main struct WelcomeChecks {
 static func main() {
  let name = "pv42-welcome-" + UUID().uuidString
  let defaults = UserDefaults(suiteName: name)!
  defer { defaults.removePersistentDomain(forName: name) }
  func check(_ value: Bool, _ reason: String) { if !value { print("FAIL: " + reason); exit(1) } }
  defaults.set("custom", forKey: "logoVariant")
  defaults.set("/custom/archive", forKey: "archivePath")
  defaults.set(Data([1,2,3]), forKey: "archiveBookmark")
  check(PVWelcomePolicy.needsPresentation(defaults: defaults), "fresh launch")
  check(PVWelcomePolicy.needsPresentation(defaults: defaults), "unacknowledged welcome must return")
  PVWelcomePolicy.complete(defaults: defaults)
  check(!PVWelcomePolicy.needsPresentation(defaults: defaults), "repeat launch")
  check(PVWelcomePolicy.needsPresentation(version: "4.2", build: "2", defaults: defaults), "build update")
  check(PVWelcomePolicy.needsPresentation(version: "4.3", build: "1", defaults: defaults), "version update")
  check(defaults.string(forKey: "logoVariant") == "custom", "custom icon preserved")
  check(defaults.string(forKey: "archivePath") == "/custom/archive", "path preserved")
  check(defaults.data(forKey: "archiveBookmark") == Data([1,2,3]), "bookmark preserved")
  print("PASS: welcome once per acknowledged release/build; unfinished welcome returns; icon, path and bookmark preserved")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='pv42-welcome-') as temp:
 p=Path(temp); swift=p/'Checks.swift';swift.write_text(source+'\n'+stub+harness)
 subprocess.run(['xcrun','swiftc','-parse-as-library','-module-cache-path',str(p/'modules'),str(swift),'-o',str(p/'Checks')],check=True)
 subprocess.run([str(p/'Checks')],check=True)
