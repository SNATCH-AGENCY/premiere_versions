import AppKit
import SwiftUI

/// An optional template mark: AppKit owns the color for the current menu bar appearance.
@MainActor
final class PVMenuBarController: NSObject {
    static let preferenceKey = "menuBarIconEnabled"
    var onOpen: (() -> Void)?
    private var item: NSStatusItem?
    private var observer: NSObjectProtocol?

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        refresh()
    }

    private func refresh() {
        let showDock = UserDefaults.standard.object(forKey: "showInDock") as? Bool ?? false
        if !showDock && !UserDefaults.standard.bool(forKey: Self.preferenceKey) { UserDefaults.standard.set(true, forKey: Self.preferenceKey) }
        let policy: NSApplication.ActivationPolicy = showDock ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
        guard UserDefaults.standard.bool(forKey: Self.preferenceKey) else {
            removeItem()
            return
        }
        guard item == nil else { return }
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item = status
        if let button = status.button {
            button.image = Self.templateImage()
            button.toolTip = "Premiere Versions"
            button.setAccessibilityLabel("Premiere Versions")
            button.target = self
            button.action = #selector(activate(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    static func templateImage() -> NSImage? {
        let content = PVHeaderMark(tint: .black)
            .frame(width: 25, height: 25).scaleEffect(0.72)
            .frame(width: 18, height: 18)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage else { return nil }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }

    @objc private func activate(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let open = menu.addItem(withTitle: PVL("Открыть Premiere Versions"), action: #selector(openWindow), keyEquivalent: "")
            open.target = self
            menu.addItem(.separator())
            let quit = menu.addItem(withTitle: PVL("Завершить Premiere Versions"), action: #selector(quitApplication), keyEquivalent: "")
            quit.target = self
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY), in: sender)
        } else {
            openWindow()
        }
    }

    @objc private func openWindow() { onOpen?() }
    @objc private func quitApplication() { NSApp.terminate(nil) }

    private func removeItem() {
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        removeItem()
    }
}
