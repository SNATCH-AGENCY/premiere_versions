import SwiftUI
import AppKit
@main struct RenderChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        guard let mark = PVMenuBarController.templateImage(), mark.isTemplate,
              mark.size == NSSize(width: 18, height: 18), let data = mark.tiffRepresentation,
              let pixels = NSBitmapImageRep(data: data) else { print("FAIL: menu bar template missing"); exit(1) }
        var transparent = false, visible = false
        for y in 0..<pixels.pixelsHigh { for x in 0..<pixels.pixelsWide {
            let alpha = pixels.colorAt(x: x, y: y)?.alphaComponent ?? 0
            transparent = transparent || alpha < 0.05
            visible = visible || alpha > 0.8
        } }
        guard transparent && visible else { print("FAIL: menu bar template alpha"); exit(1) }
        print("PASS: monochrome menu bar template is 18pt with visible artwork and transparent cutouts")
        var images: [NSImage] = []
        guard let assetsPath = UserDefaults.standard.string(forKey: "pvRenderAssets") else { print("FAIL: missing test asset path"); exit(1) }
        let assets = URL(fileURLWithPath: assetsPath)
        for name in ["PVPearl", "PVGraphite", "PVColor3", "PVColor", "PVColor2", "PVSignatureDark", "PVSignatureLight"] {
            if let image = NSImage(contentsOf: assets.appendingPathComponent(name + ".imageset/logo.png")) {
                image.setName(NSImage.Name(name)); images.append(image)
            }
        }
        for size in [NSSize(width: 720, height: 540)] {
        for mode in ["version", "comment", "settings", "settings-centered", "backups", "shortcut", "help", "logoEditor", "welcome", "welcome-hidden", "project", "project-ready", "project-missing"] {
            var panelBounds: NSRect?
            let observer = NotificationCenter.default.addObserver(forName: Notification.Name("PVPanelBounds"), object: nil, queue: .main) { note in
                panelBounds = (note.object as? NSValue)?.rectValue
            }
            let content = ContentView(previewPanel: mode).environmentObject(AutosaveMonitor()).environmentObject(GlobalSaveHotKey())
            let host = NSHostingView(rootView: content)
            let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: size.width, height: size.height), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = host
            let end = Date().addingTimeInterval(mode == "welcome" ? 2.5 : 0.4)
            while Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
            host.layoutSubtreeIfNeeded()
            if ["settings", "help"].contains(mode) {
                func scrollViews(_ view: NSView) -> [NSScrollView] {
                    (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews($0) }
                }
                let scrolls = scrollViews(host)
                guard let scroll = scrolls.first(where: { !$0.autohidesScrollers && $0.scrollerStyle == .legacy }) else { print("FAIL: persistent scroller missing"); exit(1) }
                print(mode, "flipped", scroll.documentView!.isFlipped, "origin", scroll.contentView.bounds.origin, "SETTINGS", scroll.frame, "document", scroll.documentView?.frame ?? .zero, "thumb", scroll.verticalScroller?.frame ?? .zero, "proportion", scroll.verticalScroller?.knobProportion ?? 0, "hidden", scroll.verticalScroller?.isHidden ?? true)
                if scroll.documentView!.frame.height <= scroll.contentView.bounds.height { print("FAIL: settings document is too short"); exit(1) }
                scroll.contentView.scroll(to: NSPoint(x: 0, y: 100))
                scroll.reflectScrolledClipView(scroll.contentView)
                if scroll.documentVisibleRect.origin.y <= 0 { print("FAIL: settings cannot scroll"); exit(1) }
                scroll.contentView.scroll(to: .zero)
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            if mode == "settings-centered" {
                func findScroll(_ view: NSView) -> NSScrollView? {
                    if let scroll = view as? NSScrollView, !scroll.autohidesScrollers { return scroll }
                    return view.subviews.compactMap { findScroll($0) }.first
                }
                guard let scroll = findScroll(host),
                      scroll.documentVisibleRect.maxY >= (scroll.documentView?.bounds.height ?? .infinity) - 1 else {
                    print("FAIL: Check updates destination did not scroll to Updates"); exit(1)
                }
            }
            let settle = Date().addingTimeInterval(0.2)
            while Date() < settle { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
            if !["version", "comment", "welcome", "welcome-hidden", "project", "project-ready", "project-missing"].contains(mode) {
                guard let rect = panelBounds else { print("FAIL: missing panel bounds", mode); exit(1) }
                if rect.minX < 15 || rect.minY < 15 || rect.maxX > size.width - 15 || rect.maxY > size.height - 15 {
                    print("FAIL: panel outside window", mode, rect); exit(1)
                }
                if ["settings-centered", "logoEditor"].contains(mode) {
                    if abs(rect.midX - size.width / 2) > 0.5 || abs(rect.midY - size.height / 2) > 0.5 {
                        print("FAIL: expected centered panel", mode, rect); exit(1)
                    }
                }
                let trigger = NSPoint(x: mode == "backups" ? 120 : 675, y: ["backups", "shortcut"].contains(mode) ? 509 : 55)
                if !["settings-centered", "logoEditor"].contains(mode) && !rect.contains(trigger) { print("FAIL: trigger not covered", mode, rect, trigger); exit(1) }
                print("ANCHORED", mode, size, rect)
            }
            NotificationCenter.default.removeObserver(observer)
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { print("FAIL: render unavailable"); exit(1) }
            host.cacheDisplay(in: host.bounds, to: rep)
            try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: (UserDefaults.standard.string(forKey: "pvRenderOutput") ?? "/private/tmp/pv43-render") + "/" + mode + "-" + String(Int(size.width)) + "-" + (UserDefaults.standard.string(forKey: "interfaceLanguage") ?? "en") + ".png"))
            if mode.hasPrefix("welcome") {
                var bright = 0
                for y in 245..<295 {
                    for x in 200..<520 {
                        if let value = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                           value.redComponent > 0.65 && value.greenComponent > 0.65 { bright += 1 }
                    }
                }
                if (mode == "welcome-hidden" && bright != 0) || (mode == "welcome" && bright < 20) {
                    print("FAIL: welcome visibility gate", mode, bright); exit(1)
                }
            }
            window.close()
        }
        }
        print("PASS: hover panels cover their trigger; explicit Settings and logo editor are centered; all panels fit; native rendering of version/comment/settings/shortcut/help; persistent settings scrollbar and scrolling verified")
    }
}
