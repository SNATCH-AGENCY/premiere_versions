from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
source = (root / 'Premiere Versions/MyApp.swift').read_text()
model = source[source.index('nonisolated struct SavedShortcut'):source.index('nonisolated enum PVPremiereShortcutPolicy')]
harness = r'''
let original = SavedShortcut.defaultShortcut
assert(original.isValid && original.keyCode == UInt32(kVK_ANSI_S))
assert(original.display == "⌥ S")
let edited = SavedShortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey), keyLabel: "K")
assert(edited.isValid && edited.display == "⌃ ⌥ ⇧ ⌘ K")
assert(try JSONDecoder().decode(SavedShortcut.self, from: JSONEncoder().encode(edited)) == edited)
assert(!SavedShortcut(keyCode: 1, modifiers: 0, keyLabel: "S").isValid)
assert(!SavedShortcut(keyCode: 1, modifiers: UInt32(shiftKey), keyLabel: "S").isValid)
assert(!SavedShortcut(keyCode: 1, modifiers: UInt32(optionKey | alphaLock), keyLabel: "S").isValid)
assert(!SavedShortcut(keyCode: 999, modifiers: UInt32(optionKey), keyLabel: "S").isValid)
assert(!SavedShortcut(keyCode: UInt32(kVK_Escape), modifiers: UInt32(optionKey), keyLabel: "Esc").isValid)
assert(!SavedShortcut(keyCode: 1, modifiers: UInt32(optionKey), keyLabel: "\nS").isValid)
assert(!SavedShortcut(keyCode: 1, modifiers: UInt32(optionKey), keyLabel: " ").isValid)
final class StubDefaults: UserDefaults {
    var stub: Data?
    override func data(forKey defaultName: String) -> Data? { stub }
}
let defaults = StubDefaults()
assert(SavedShortcut.load(from: defaults) == original)
defaults.stub = Data("not json".utf8)
assert(SavedShortcut.load(from: defaults) == original)
defaults.stub = try JSONEncoder().encode(edited)
assert(SavedShortcut.load(from: defaults) == edited)
defaults.stub = try JSONEncoder().encode(SavedShortcut(keyCode: 1, modifiers: 0, keyLabel: "S"))
assert(SavedShortcut.load(from: defaults) == original)
print("PASS: default and custom shortcut, display order, encoding round-trip, preference loading, invalid combination fallback")
'''
harness = harness.replace('assert(try JSONDecoder().decode(SavedShortcut.self, from: JSONEncoder().encode(edited)) == edited)', 'let decoded = try JSONDecoder().decode(SavedShortcut.self, from: JSONEncoder().encode(edited))\nassert(decoded == edited)')
with tempfile.TemporaryDirectory(prefix='premiere-shortcuts-') as check_dir:
    path = Path(check_dir)
    swift = path / 'ShortcutChecks.swift'
    swift.write_text('import Foundation\nimport Carbon\n' + model + harness)
    sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
    compiler = subprocess.check_output(['xcrun', '--find', 'swiftc'], text=True).strip()
    binary = path / 'ShortcutChecks'
    subprocess.run([compiler, '-sdk', sdk, '-module-cache-path', str(path / 'modules'), str(swift), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
