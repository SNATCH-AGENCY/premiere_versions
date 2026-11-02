from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
source=(root/'Premiere Versions/WindowAppearance.swift').read_text()
harness="""
@main struct Checks {
 @MainActor static func main() {
  _ = NSApplication.shared
  precondition(PVWindowAppearance.opacity(-1) == 0.15)
  precondition(PVWindowAppearance.opacity(2) == 1)
  precondition(PVWindowAppearance.opacity(.nan) == 1)
  precondition(PVWindowAppearance.opacity(0.15) == 0.15)
  precondition(PVWindowAppearance.opacity(0.42) == 0.42)
  precondition(PVWindowAppearance.opacity(0.15, reduceTransparency: true) == 1)
  let host = NSHostingView(rootView: PVFrostedBackdrop())
  host.frame = NSRect(x: 0, y: 0, width: 720, height: 540)
  host.layoutSubtreeIfNeeded()
  func materials(_ view: NSView) -> [NSVisualEffectView] {
    (view as? NSVisualEffectView).map { [$0] } ?? view.subviews.flatMap { materials($0) }
  }
  let effects = materials(host)
  precondition(effects.count == 1)
  precondition(effects[0].blendingMode == .behindWindow && effects[0].state == .active)
  precondition(effects[0].alphaValue == 1)
  print("PASS: 15–100 percent clamp, invalid values, Reduce Transparency override and real behind-window native material")
 }
}
"""
with tempfile.TemporaryDirectory(prefix='pv46-appearance-') as temp:
 p=Path(temp);f=p/'Checks.swift';f.write_text(source+harness)
 subprocess.run(['xcrun','swiftc','-parse-as-library','-disable-sandbox','-swift-version','5','-default-isolation','MainActor','-module-cache-path',str(p/'modules'),str(f),'-o',str(p/'Checks')],check=True)
 subprocess.run([str(p/'Checks')],check=True)
