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
        let translucent = UserDefaults.standard.double(forKey: "windowBackgroundOpacity") > 0 && UserDefaults.standard.double(forKey: "windowBackgroundOpacity") < 1
        let defaultModes = translucent ? ["version", "comment", "settings"] : ["version", "comment", "settings", "settings-folders", "settings-appearance", "settings-centered", "backups", "backups-details", "shortcut", "help", "logoEditor", "welcome", "welcome-hidden", "project", "project-ready", "project-missing"]
        let modes = ProcessInfo.processInfo.environment["PV_RENDER_MODES"]?.components(separatedBy: ",") ?? defaultModes
        for mode in modes {
            var panelBounds: NSRect?
            let observer = NotificationCenter.default.addObserver(forName: Notification.Name("PVPanelBounds"), object: nil, queue: .main) { note in
                panelBounds = (note.object as? NSValue)?.rectValue
            }
            let content = ContentView(previewPanel: mode).environmentObject(AutosaveMonitor()).environmentObject(GlobalSaveHotKey())
            let host = NSHostingView(rootView: content)
            let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: size.width, height: size.height), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = host
            if mode == "help" { window.orderFront(nil) }
            let end = Date().addingTimeInterval(mode == "welcome" ? 2.5 : 0.4)
            while Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
            host.layoutSubtreeIfNeeded()
            if translucent {
                func effectViews(_ view: NSView) -> [NSVisualEffectView] {
                    (view as? NSVisualEffectView).map { [$0] } ?? view.subviews.flatMap { effectViews($0) }
                }
                guard effectViews(host).contains(where: { $0.blendingMode == .behindWindow }) else { print("FAIL: native frosted backdrop missing"); exit(1) }
            }
            if mode.hasPrefix("settings") || mode == "help" {
                func scrollViews(_ view: NSView) -> [NSScrollView] {
                    (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews($0) }
                }
                let scrolls = scrollViews(host)
                guard let scroll = scrolls.first(where: { !$0.autohidesScrollers && $0.scrollerStyle == .legacy }) else { print("FAIL: persistent scroller missing"); exit(1) }
                print(mode, "flipped", scroll.documentView!.isFlipped, "origin", scroll.contentView.bounds.origin, "SETTINGS", scroll.frame, "document", scroll.documentView?.frame ?? .zero, "thumb", scroll.verticalScroller?.frame ?? .zero, "proportion", scroll.verticalScroller?.knobProportion ?? 0, "hidden", scroll.verticalScroller?.isHidden ?? true)
                if ["settings-folders", "settings-appearance"].contains(mode) {
                    if scroll.documentView!.frame.height <= scroll.contentView.bounds.height { print("FAIL: expanded settings did not extend document"); exit(1) }
                    scroll.contentView.scroll(to: NSPoint(x: 0, y: 100))
                    scroll.reflectScrolledClipView(scroll.contentView)
                    if scroll.documentVisibleRect.origin.y <= 0 { print("FAIL: expanded settings cannot scroll"); exit(1) }
                }
                if mode != "help" {
                    scroll.contentView.scroll(to: .zero)
                    scroll.reflectScrolledClipView(scroll.contentView)
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
                let trigger = NSPoint(x: mode.hasPrefix("backups") ? 120 : 675, y: (mode.hasPrefix("backups") || mode == "shortcut") ? 509 : 55)
                if !["settings-centered", "logoEditor"].contains(mode) && !rect.contains(trigger) { print("FAIL: trigger not covered", mode, rect, trigger); exit(1) }
                print("ANCHORED", mode, size, rect)
            }
            NotificationCenter.default.removeObserver(observer)
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { print("FAIL: render unavailable"); exit(1) }
            host.cacheDisplay(in: host.bounds, to: rep)
            if mode == "help", let rect=panelBounds {
                var ink=0
                for y in Int(rect.minY+20)..<Int(rect.minY+65) { for x in Int(rect.minX+24)..<Int(rect.minX+240) {
                    let px=Int(CGFloat(x)*CGFloat(rep.pixelsWide)/size.width)
                    let py=Int(CGFloat(y)*CGFloat(rep.pixelsHigh)/size.height)
                    if let color=rep.colorAt(x:px,y:py)?.usingColorSpace(.deviceRGB), color.redComponent>0.65 && color.greenComponent>0.60 { ink += 1 }
                } }
                guard ink>40 else { print("FAIL: help surface exists but its content is invisible");exit(1) }
                print("PASS: help heading is visibly rendered, not an empty scroll surface")
            }
            try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: (UserDefaults.standard.string(forKey: "pvRenderOutput") ?? "/private/tmp/pv43-render") + "/" + mode + "-" + String(Int(size.width)) + "-" + (UserDefaults.standard.string(forKey: "interfaceLanguage") ?? "en") + ".png"))
            if mode == "settings-centered" {
                var panelVisible = false
                let stateObserver = NotificationCenter.default.addObserver(forName: Notification.Name("PVTestPanelState"), object: nil, queue: .main) { note in
                    panelVisible = note.userInfo?["visible"] as? Bool ?? false
                }
                var route: String = "", routeX = 0.0, routeY = 0.0
                let routeObserver = NotificationCenter.default.addObserver(forName: Notification.Name("PVTestPanelState"), object: nil, queue: .main) { note in
                    route = note.userInfo?["panel"] as? String ?? ""
                    routeX = note.userInfo?["x"] as? Double ?? 0; routeY = note.userInfo?["y"] as? Double ?? 0
                }
                for (event, expected) in [("PVTestRouteBackups", "backups"), ("PVTestRouteSettings", "settings")] {
                    NotificationCenter.default.post(name: Notification.Name(event), object: nil)
                    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
                    NotificationCenter.default.post(name: Notification.Name("PVTestInspectPanel"), object: nil)
                    guard route == expected, abs(routeX - size.width / 2) < 1, abs(routeY - size.height / 2) < 1 else {
                        print("FAIL: linked route moved away from settings", route, routeX, routeY); exit(1)
                    }
                }
                NotificationCenter.default.removeObserver(routeObserver)
                print("PASS: settings-to-backups-to-settings keeps the same panel center")
                let started = Date()
                NotificationCenter.default.post(name: Notification.Name("PVTestDismissPanel"), object: nil)
                for elapsed in [0.03, 0.12, 0.25, 0.46] {
                    while Date().timeIntervalSince(started) < elapsed { RunLoop.current.run(until: Date().addingTimeInterval(0.002)) }
                    NotificationCenter.default.post(name: Notification.Name("PVTestInspectPanel"), object: nil)
                    if elapsed < 0.38 && Date().timeIntervalSince(started) < 0.35 {
                        guard panelVisible else { print("FAIL: panel content/anchor changed before fade ended"); exit(1) }
                    }
                    if elapsed > 0.38 {
                        let deadline = Date().addingTimeInterval(1.2)
                        while panelVisible && Date() < deadline {
                            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
                            NotificationCenter.default.post(name: Notification.Name("PVTestInspectPanel"), object: nil)
                        }
                        guard !panelVisible else { print("FAIL: close animation never completed"); exit(1) }
                    }
                    host.layoutSubtreeIfNeeded()
                    host.cacheDisplay(in: host.bounds, to: rep)
                    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: UserDefaults.standard.string(forKey: "pvRenderOutput")! + "/close-" + String(Int(elapsed * 1000)) + "-" + (UserDefaults.standard.string(forKey: "interfaceLanguage") ?? "en") + ".png"))
                }
                NotificationCenter.default.removeObserver(stateObserver)
                print("PASS: actual closing animation retains content and center until fading completes")
            }
            if mode == "settings" {
                var expanded=false
                let sectionObserver = NotificationCenter.default.addObserver(forName: Notification.Name("PVTestSectionState"), object:nil, queue:.main) { note in expanded = note.object as? Bool ?? false }
                func hover(_ inside:Bool) { NotificationCenter.default.post(name:Notification.Name("PVTestSectionHover"),object:inside) }
                func settle(_ seconds:Double) { let end=Date().addingTimeInterval(seconds);while Date()<end { RunLoop.current.run(until:Date().addingTimeInterval(0.005)) };NotificationCenter.default.post(name:Notification.Name("PVTestSectionInspect"),object:nil) }
                hover(true);settle(0.5)
                guard !expanded else { print("FAIL: hovering expanded section");exit(1) }
                NotificationCenter.default.post(name: Notification.Name("PVTestSectionClick"),object:nil);settle(0.3)
                guard expanded else { print("FAIL: click did not expand section");exit(1) }
                hover(false);settle(0.8)
                guard expanded else { print("FAIL: leaving section closed it");exit(1) }
                NotificationCenter.default.post(name: Notification.Name("PVTestSectionClick"),object:nil);settle(0.3)
                guard !expanded else { print("FAIL: click did not collapse section");exit(1) }
                NotificationCenter.default.removeObserver(sectionObserver)
                print("PASS: click toggles section; hover does not change expansion")
            }
            if mode == "version" {
                var visible = false
                let stateObserver = NotificationCenter.default.addObserver(forName: Notification.Name("PVTestPanelState"), object: nil, queue: .main) { note in visible = note.userInfo?["visible"] as? Bool ?? false }
                NotificationCenter.default.post(name: Notification.Name("PVTestHoverSettings"), object: nil)
                RunLoop.current.run(until: Date().addingTimeInterval(0.04))
                // A short hover must cancel without opening; a deliberate hover opens.
                NotificationCenter.default.post(name: Notification.Name("PVTestClickSettings"), object: nil)
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                NotificationCenter.default.post(name: Notification.Name("PVTestInspectPanel"), object: nil)
                guard !visible else { print("FAIL: cancelled hover still opened"); exit(1) }
                NotificationCenter.default.post(name: Notification.Name("PVTestHoverSettings"), object: nil)
                NotificationCenter.default.post(name: Notification.Name("PVTestSpuriousExit"), object: nil)
                let end = Date().addingTimeInterval(0.65)
                while Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
                NotificationCenter.default.post(name: Notification.Name("PVTestInspectPanel"), object: nil)
                guard visible else { print("FAIL: deliberate hover did not stay open"); exit(1) }
                NotificationCenter.default.post(name: Notification.Name("PVTestPointerOutside"), object: nil)
                let gone = Date().addingTimeInterval(1.3)
                while Date() < gone { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
                NotificationCenter.default.post(name: Notification.Name("PVTestInspectPanel"), object: nil)
                guard !visible else { print("FAIL: panel did not close after pointer actually left"); exit(1) }
                NotificationCenter.default.removeObserver(stateObserver)
                print("PASS: short hover cancels; deliberate hover opens; spurious exit stays open; actual exit closes")
            }
            if mode.hasPrefix("welcome") {
                var bright = 0
                for y in 245..<295 {
                    for x in 200..<520 {
                        if let value = rep.colorAt(x: Int(CGFloat(x) * CGFloat(rep.pixelsWide) / size.width), y: Int(CGFloat(y) * CGFloat(rep.pixelsHigh) / size.height))?.usingColorSpace(.deviceRGB),
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
