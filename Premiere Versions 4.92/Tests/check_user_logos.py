from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
localization = (root / "Premiere Versions/Localization.swift").read_text()
source = (root / 'Premiere Versions/LogoRenderer.swift').read_text()
harness = r'''
let template = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let redGreen = PVLogoPalette(plate: PVLogoRGB(r: 0.78, g: 0.24, b: 0.32), letters: PVLogoRGB(r: 0.20, g: 0.78, b: 0.40))
let blueYellow = PVLogoPalette(plate: PVLogoRGB(r: 0.22, g: 0.40, b: 0.80), letters: PVLogoRGB(r: 0.88, g: 0.78, b: 0.35))
let first = try PVLogoRenderer.png(template: template, palette: redGreen, size: 256)
let second = try PVLogoRenderer.png(template: template, palette: blueYellow, size: 256)
let third = try PVLogoRenderer.png(template: template, palette: .initial, size: 256)
assert(first != second && second != third)
try first.write(to: URL(fileURLWithPath: "/private/tmp/premiere-user-logo-preview.png"))
guard let imageSource = CGImageSourceCreateWithData(first as CFData, nil), let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else { fatalError("PNG decode") }
assert(image.width == 256 && image.height == 256)
var pixels = [UInt8](repeating: 0, count: 256 * 256 * 4)
let info = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
pixels.withUnsafeMutableBytes { raw in
    let ctx = CGContext(data: raw.baseAddress, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 1024, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: 256, height: 256))
}
func sample(_ x: Double, _ y: Double) -> [UInt8] {
    let offset = (Int(y * 255) * 256 + Int(x * 255)) * 4
    return Array(pixels[offset..<(offset + 4)])
}
assert(sample(0, 0)[3] == 0, "Transparency must survive recoloring")
let glyph = sample(0.34, 0.70)
let body = sample(0.70, 0.35)
assert(glyph[1] > glyph[0], "P glyph must use the letter color")
assert(body[0] > body[1], "Tile must use the plate color")
let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pv-logo-history-" + UUID().uuidString)
defer { try? FileManager.default.removeItem(at: folder) }
let current = folder.appendingPathComponent(PVUserLogoFiles.currentName)
let previous = folder.appendingPathComponent(PVUserLogoFiles.previousName)
try PVUserLogoFiles.save(first, in: folder)
let a = try Data(contentsOf: current)
assert(a == first && !FileManager.default.fileExists(atPath: previous.path))
try PVUserLogoFiles.save(second, in: folder)
let b = try Data(contentsOf: current); let c = try Data(contentsOf: previous)
assert(b == second && c == first)
try PVUserLogoFiles.save(third, in: folder)
let d = try Data(contentsOf: current); let e = try Data(contentsOf: previous)
assert(d == third && e == second)
do { try PVUserLogoFiles.save(Data("invalid".utf8), in: folder); fatalError("Invalid image must be rejected") } catch { }
let f = try Data(contentsOf: current); let g = try Data(contentsOf: previous)
assert(f == third && g == second, "Failed save must not rotate either slot")
let importedFolder = folder.appendingPathComponent("migrated")
let imported = try PVUserLogoFiles.importHistory(from: folder, to: importedFolder)
assert(imported)
let importedData0 = try Data(contentsOf: importedFolder.appendingPathComponent(PVUserLogoFiles.currentName))
assert(importedData0 == third)
let importedData1 = try Data(contentsOf: importedFolder.appendingPathComponent(PVUserLogoFiles.previousName))
assert(importedData1 == second)
let importedData2 = try Data(contentsOf: current)
assert(importedData2 == third, "Import must preserve originals")
try PVUserLogoFiles.save(first, in: importedFolder)
let repeatedImport = try PVUserLogoFiles.importHistory(from: folder, to: importedFolder)
assert(repeatedImport)
let importedData3 = try Data(contentsOf: importedFolder.appendingPathComponent(PVUserLogoFiles.currentName))
assert(importedData3 == first, "Repeated migration must not replace user's newer icon")
let importedData4 = try Data(contentsOf: importedFolder.appendingPathComponent(PVUserLogoFiles.previousName))
assert(importedData4 == third)
print("PASS: upgrade imports both logo history slots, preserves originals and never overwrites newer user data")
try PVUserLogoFiles.replace(first, previous: false, in: folder)
let currentAfterEdit = try Data(contentsOf: current)
let previousAfterEdit = try Data(contentsOf: previous)
assert(currentAfterEdit == first && previousAfterEdit == second, "Editing current must preserve previous")
try PVUserLogoFiles.replace(third, previous: true, in: folder)
let currentAfterPreviousEdit = try Data(contentsOf: current)
let previousAfterPreviousEdit = try Data(contentsOf: previous)
assert(currentAfterPreviousEdit == first && previousAfterPreviousEdit == third, "Editing previous must preserve current")
do { try PVUserLogoFiles.replace(Data("invalid".utf8), previous: false, in: folder); fatalError("Invalid replacement accepted") } catch { }
let currentAfterFailure = try Data(contentsOf: current)
let previousAfterFailure = try Data(contentsOf: previous)
assert(currentAfterFailure == first && previousAfterFailure == third)
print("PASS: editing either slot does not rotate history; invalid replacement preserves both slots")
let emptySlots = folder.appendingPathComponent("empty-slots")
try FileManager.default.createDirectory(at: emptySlots, withIntermediateDirectories: true)
try PVUserLogoFiles.replace(first, previous: true, in: emptySlots, allowCreating: true)
try PVUserLogoFiles.replace(second, previous: false, in: emptySlots, allowCreating: true)
let independent = try Data(contentsOf: emptySlots.appendingPathComponent(PVUserLogoFiles.previousName))
assert(independent == first, "Filling an empty slot must not rotate the other slot")
print("PASS: empty current and previous slots can be filled independently")
let invalid = PVLogoPalette(plate: PVLogoRGB(r: .nan, g: 0, b: 0), letters: redGreen.letters)
do { _ = try PVLogoRenderer.png(template: template, palette: invalid, size: 256); fatalError("Invalid color accepted") } catch { }
print("PASS: two-color material masks, alpha, PNG output, two-generation history, invalid-save preservation")
'''
with tempfile.TemporaryDirectory(prefix='pv-logo-checks-') as check_dir:
    path = Path(check_dir)
    swift = path / 'LogoChecks.swift'
    swift.write_text(localization + '\n' + source + '\n' + harness)
    sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
    compiler = subprocess.check_output(['xcrun', '--find', 'swiftc'], text=True).strip()
    binary = path / 'LogoChecks'
    subprocess.run([compiler, '-O', '-sdk', sdk, '-module-cache-path', str(path/'modules'), str(swift), '-o', str(binary)], check=True)
    template = root / 'Premiere Versions/Assets.xcassets/PVColor3.imageset/logo.png'
    subprocess.run([str(binary), str(template)], check=True)
