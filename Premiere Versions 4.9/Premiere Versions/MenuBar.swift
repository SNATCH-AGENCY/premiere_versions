import AppKit
import SwiftUI

/// An optional template mark: AppKit owns the color for the current menu bar appearance.
@MainActor
final class PVMenuBarController: NSObject {
    static let preferenceKey = "menuBarIconEnabled"
    var onOpen: (() -> Void)?
    var onQuitFully: (() -> Void)?
    var onNavigate: ((String) -> Void)?
    var onCheckUpdates: (() -> Void)?
    var onBackupModeChanged: (() -> Void)?
    var onHide: (() -> Void)?
    var updateAvailable: () -> Bool = { false }
    private(set) var backgroundOnly = false

    func enterBackground() { backgroundOnly = true; refresh() }
    func leaveBackground() { backgroundOnly = false; refresh() }
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
        let preferredDock = UserDefaults.standard.object(forKey: "showInDock") as? Bool ?? false
        let preferredMenu = UserDefaults.standard.object(forKey: Self.preferenceKey) as? Bool ?? true
        let showDock = preferredDock && !backgroundOnly
        let showMenu = backgroundOnly || preferredMenu || !showDock
        // Install the status item before hiding Dock: the app must always remain reachable.
        if !showMenu { removeItem() }
        if showMenu && item == nil { installItem() }
        let policy: NSApplication.ActivationPolicy = showDock ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
    }

    private func installItem() {
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
            let menu = makeMenu()
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY), in: sender)
        } else {
            openWindow()
        }
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector) -> NSMenuItem {
            let item = menu.addItem(withTitle: PVL(title), action: action, keyEquivalent: "")
            item.target = self; return item
        }
        _ = add("Открыть Premiere Versions", #selector(openWindow))
        _ = add("Настройки…", #selector(openSettings))
        _ = add("Резервные копии", #selector(openBackups))
        let modes = NSMenu()
        for mode in PVBackupMode.allCases {
            let option = modes.addItem(withTitle: PVL(mode.title), action: #selector(selectBackupMode(_:)), keyEquivalent: "")
            option.target = self; option.representedObject = mode.rawValue
            option.state = (UserDefaults.standard.string(forKey: "backupMode") ?? "automatic") == mode.rawValue ? .on : .off
        }
        let modeItem = menu.addItem(withTitle: PVL("Режим резервирования"), action: nil, keyEquivalent: "")
        modeItem.submenu = modes
        menu.addItem(.separator())
        let update = add("Проверить обновления", #selector(checkUpdates))
        if updateAvailable() {
            update.image = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
                NSColor(red: 0.85, green: 0.43, blue: 0.47, alpha: 1).setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill(); return true
            }
        }
        menu.addItem(.separator())
        _ = add("Скрыть окно", #selector(hideWindow))
        _ = add("Завершить полностью", #selector(quitApplication))
        return menu
    }
    @objc private func openSettings() { onNavigate?("settings") }
    @objc private func openBackups() { onNavigate?("backups") }
    @objc private func checkUpdates() { onCheckUpdates?() }
    @objc private func hideWindow() { onHide?() }
    @objc private func selectBackupMode(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, PVBackupMode(rawValue: value) != nil else { return }
        UserDefaults.standard.set(value, forKey: "backupMode")
        onBackupModeChanged?()
    }

    @objc private func openWindow() { onOpen?() }
    @objc private func quitApplication() { onQuitFully?() }

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
