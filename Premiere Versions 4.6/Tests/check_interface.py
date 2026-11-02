from pathlib import Path
import subprocess
root=Path(__file__).resolve().parents[1]
import tempfile
out=Path(tempfile.mkdtemp(prefix="pv43-interface-"))
files=[]
for p in (root/'Premiere Versions').glob('*.swift'):
    s=p.read_text()
    if p.name=='MyApp.swift':
        s=s.replace('@main\nstruct PremiereVersionsApp','struct PremiereVersionsApp')
        a=s.index('    init() {',s.index('final class AutosaveMonitor'));b=s.index('    func start()',a)
        s=s[:a]+'    init() {}\n\n'+s[b:]
    if p.name=='ContentView.swift':
        s=s.replace('struct ContentView: View {', 'struct ContentView: View {\n    @State private var pvTestPointerInside = true')
        a=s.index('    private func pointerIsInsidePanel(');b=s.index('    private func schedulePanelClose(',a)
        s=s[:a]+'    private func pointerIsInsidePanel(_ panel: Panel) -> Bool { pvTestPointerInside }\n\n'+s[b:]
        s=s.replace('        .onChange(of: logoVariant) {', '        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PVTestHoverSettings"))) { _ in schedulePanel(.settings, hovering: true) }\n        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PVTestClickSettings"))) { _ in openPanelImmediately(.settings) }\n        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PVTestSpuriousExit"))) { _ in schedulePanelClose(.settings) }\n        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PVTestPointerOutside"))) { _ in pvTestPointerInside = false; schedulePanelClose(.settings) }\n        .onChange(of: logoVariant) {')
        s=s.replace('        .onChange(of: logoVariant) {', '        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PVTestDismissPanel"))) { _ in dismissPanel() }\n        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PVTestInspectPanel"))) { _ in\n            NotificationCenter.default.post(name: Notification.Name("PVTestPanelState"), object: nil, userInfo: ["visible": activePanel != nil, "centered": panelCentered])\n        }\n        .onChange(of: logoVariant) {')
        s=s.replace('struct ContentView: View {','''struct ContentView: View {
    init(previewPanel: String = "version") {
        _sourceProjectURL = State(initialValue: URL(fileURLWithPath: "/private/tmp/project.prproj"))
        _projectName = State(initialValue: "Project")
        _versionNumber = State(initialValue: "v014")
        _versionComment = State(initialValue: "")
        _didRestore = State(initialValue: true)
        _showingWelcome = State(initialValue: previewPanel.hasPrefix("welcome"))
        _visibleWindow = State(initialValue: previewPanel != "welcome-hidden")
        _panelPinned = State(initialValue: true)
        _panelCentered = State(initialValue: previewPanel == "settings-centered" || previewPanel == "logoEditor")
        _updateScrollRequest = State(initialValue: previewPanel == "settings-centered" ? 1 : 0)
        _panelAnchor = State(initialValue: CGPoint(x: previewPanel == "backups" ? 120 : 675, y: ["backups", "shortcut"].contains(previewPanel) ? 509 : 55))
        _commentStage = State(initialValue: previewPanel == "comment")
        _selectingProject = State(initialValue: ["project", "project-ready", "project-missing"].contains(previewPanel))
        if ["project", "project-missing"].contains(previewPanel) { _sourceProjectURL = State(initialValue: nil) }
        _missingProjectName = State(initialValue: previewPanel == "project-missing" ? "Монтаж" : "")
        let selected: Panel? = previewPanel == "backups" ? .backups : ["settings", "settings-centered"].contains(previewPanel) ? .settings : previewPanel == "shortcut" ? .shortcut : previewPanel == "help" ? .help : previewPanel == "logoEditor" ? .logoEditor : nil
        _activePanel = State(initialValue: selected)
    }
''')
        s=s.replace('        .modifier(PVFloatingSurface())\n        .onExitCommand { dismissPanel() }', '''        .modifier(PVFloatingSurface())
        .background {
            GeometryReader { proxy in
                Color.clear.task(id: proxy.frame(in: .global)) {
                    let rect = proxy.frame(in: .global)
                    NotificationCenter.default.post(name: Notification.Name("PVPanelBounds"), object: NSValue(rect: rect))
                }
            }
        }
        .onExitCommand { dismissPanel() }''')
        a=s.index('    private var previousVersionLabel: String {');b=s.index('    private func suggestedVersionNumber()',a)
        s=s[:a]+'    private var previousVersionLabel: String { "v013" }\n\n'+s[b:]
    if p.name=='UtilityInteraction.swift':
        s=s.replace('view.changed = { value in if visible != value { visible = value } }', 'view.changed = { _ in }')
    if p.name=='UserLogoLibrary.swift':
        a=s.index('    private func migrateLegacyHistory() {');b=s.index('    func importLegacyFolder()',a)
        s=s[:a]+'    private func migrateLegacyHistory() {}\n\n'+s[b:]
        a=s.index('    private var suggestedFolder: URL {');b=s.index('    private func resolve(',a)
        s=s[:a]+'    private var suggestedFolder: URL { URL(fileURLWithPath: "/private/tmp/pv43-interface-logo-fixture") }\n\n'+s[b:]
    if p.name=='FileIconStore.swift':
        s=s.replace('    func apply(_ image: NSImage, allowPrompt: Bool = false) {', '    func apply(_ image: NSImage, allowPrompt: Bool = false) {\n        return;')
    f=out/p.name;f.write_text(s);files.append(str(f))
sdk=subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip()
compiler=subprocess.check_output(['xcrun','--find','swiftc'],text=True).strip()
subprocess.run([compiler,'-disable-sandbox','-sdk',sdk,'-swift-version','5','-default-isolation','MainActor','-module-cache-path',str(out/'modules'),*files,str(root/'Tests/NativeRenderChecks.swift'),'-o',str(out/'PV43RenderChecks')],check=True)

import shutil
shutil.copy(root / "Premiere Versions/Translations.json", out / "Translations.json")

for language in ["en", "ru"]:
    subprocess.run([str(out/'PV43RenderChecks'), '-interfaceLanguage', language, '-pvRenderOutput', str(out), '-pvRenderAssets', str(root/'Premiere Versions/Assets.xcassets')], check=True)
translucent=out/'opacity-15';translucent.mkdir()
subprocess.run([str(out/'PV43RenderChecks'), '-interfaceLanguage', 'en', '-windowBackgroundOpacity', '0.15', '-pvRenderOutput', str(translucent), '-pvRenderAssets', str(root/'Premiere Versions/Assets.xcassets')], check=True)
print('Native interface snapshots:', out)

# Keep the review snapshots, not another copy of compiler caches.
shutil.rmtree(out/'modules', ignore_errors=True)
(out/'PV43RenderChecks').unlink(missing_ok=True)
