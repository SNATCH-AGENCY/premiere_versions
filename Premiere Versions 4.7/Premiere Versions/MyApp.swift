import SwiftUI
import AppKit
import Combine
import Carbon
import CoreServices
import Darwin

@main
struct PremiereVersionsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                CommandGroup(after: .newItem) {
                    Button(PVL("Показать окно сохранения")) {
                        appDelegate.showSaveWindow()
                    }
                }
            }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let autosaveMonitor = AutosaveMonitor()
    private let hotKey = GlobalSaveHotKey()
    private var saveWindow: NSWindow?
    private let menuBar = PVMenuBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        hotKey.onPress = { [weak self] in self?.showSaveWindow() }
        hotKey.start()
        PVHotKeyHelperManager.shared.start()
        PVUpdateService.shared.startAutomaticChecks()
        menuBar.onOpen = { [weak self] in self?.showSaveWindow() }
        menuBar.start()
        PVBrand.applySelectedIcon()
        // An explicit launch must always reveal the utility, including its unfinished welcome.
        NSApp.setActivationPolicy(UserDefaults.standard.object(forKey: "showInDock") as? Bool == false ? .accessory : .regular)
        DispatchQueue.main.async { self.showSaveWindow() }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    func showSaveWindow() {
        if saveWindow == nil {
            let content = ContentView()
                .environmentObject(autosaveMonitor)
                .environmentObject(hotKey)
            let controller = NSHostingController(rootView: content.preferredColorScheme(.dark))
            let window = PVUtilityWindow(contentViewController: controller)
            window.title = PVL("Premiere Versions — Сохранить версию")
            window.titlebarAppearsTransparent = true
            window.appearance = NSAppearance(named: .darkAqua)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.collectionBehavior = [.fullScreenNone]
            window.standardWindowButton(.zoomButton)?.isEnabled = false
            window.setContentSize(NSSize(width: 720, height: 540))
            window.minSize = window.frame.size
            window.maxSize = window.frame.size
            window.isRestorable = false
            window.isReleasedWhenClosed = false
            window.center()
            saveWindow = window
        }
        guard let window = saveWindow else { return }
        NSApp.unhide(nil)
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.deminiaturize(nil)
        // Raise immediately even when Launch Services has not handed activation to us yet.
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // Launch Services may finish activating Finder after applicationDidFinishLaunching.
        // A bounded follow-up wins that race without keeping the utility always on top.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak window] in
            guard let window, window.isVisible, !window.isMiniaturized, !NSApp.isHidden else { return }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
        NotificationCenter.default.post(name: .showVersionSaveWindow, object: nil)
        NSLog("Premiere Versions: save window shown")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSaveWindow()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        hotKey.stop()
        menuBar.stop()
    }
}

extension Notification.Name {
    static let showVersionSaveWindow = Notification.Name("PremiereVersions.showVersionSaveWindow")
}

nonisolated struct SavedShortcut: Codable, Equatable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyLabel: String
    static let preferenceKey = "globalSaveShortcut"
    static let defaultShortcut = SavedShortcut(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(optionKey), keyLabel: "S")

    var isValid: Bool {
        let allowed = UInt32(cmdKey | controlKey | optionKey | shiftKey)
        let primary = UInt32(cmdKey | controlKey | optionKey)
        return keyCode <= 127 && keyCode != UInt32(kVK_Escape) && modifiers & primary != 0 && modifiers & ~allowed == 0 &&
            !keyLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && keyLabel.count <= 12 && !keyLabel.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    var display: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        return (parts + [keyLabel]).joined(separator: " ")
    }

    static func load(from defaults: UserDefaults = .standard) -> SavedShortcut {
        guard let data = defaults.data(forKey: preferenceKey),
              let shortcut = try? JSONDecoder().decode(SavedShortcut.self, from: data), shortcut.isValid else { return defaultShortcut }
        return shortcut
    }
}

nonisolated enum PVPremiereShortcutPolicy {
    static func allows(bundleIdentifier: String?, hidden: Bool, terminated: Bool) -> Bool {
        guard !hidden, !terminated, let identifier = bundleIdentifier?.lowercased() else { return false }
        return identifier == "com.adobe.premierepro" || identifier.hasPrefix("com.adobe.premierepro.")
    }
}

/// Register only while Premiere Pro is frontmost; no global keyboard monitoring.
@MainActor
final class GlobalSaveHotKey: ObservableObject {
    @Published private(set) var shortcut = SavedShortcut.load()
    @Published private(set) var status = PVL("Подключение сочетания…")
    @Published private(set) var isRecording = false
    var onPress: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var activationObserver: NSObjectProtocol?

    private let isPremiereActive: () -> Bool
    init(isPremiereActive: @escaping () -> Bool = {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        return PVPremiereShortcutPolicy.allows(bundleIdentifier: app.bundleIdentifier,
                                              hidden: app.isHidden, terminated: app.isTerminated)
    }) {
        self.isPremiereActive = isPremiereActive
    }
    private var premiereIsFrontmost: Bool { isPremiereActive() }

    private func observeActivation() {
        guard activationObserver == nil else { return }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshRegistration() }
        }
    }

    private func refreshRegistration() {
        guard !isRecording else { return }
        if !premiereIsFrontmost {
            if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
            hotKeyRef = nil
            status = shortcut.display + PVL(" — доступно в активном Premiere Pro")
            return
        }
        guard hotKeyRef == nil, installHandler() else { return }
        let (result, reference) = register(shortcut)
        if result == noErr, let reference {
            hotKeyRef = reference
            status = shortcut.display + PVL(" — открыть окно сохранения")
        } else {
            status = shortcut.display + PVL(" недоступно: сочетание может быть занято")
            NSLog("Premiere Versions: shortcut registration failed (%d)", result)
        }
    }

    private func installHandler() -> Bool {
        if handlerRef != nil { return true }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard result == noErr, identifier.signature == 0x50565253, identifier.id == 1 else {
                return OSStatus(eventNotHandledErr)
            }
            let controller = Unmanaged<GlobalSaveHotKey>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in
                guard controller.premiereIsFrontmost, !controller.isRecording else { return }
                controller.onPress?()
            }
            return noErr
        }, 1, &eventType, context, &handlerRef)
        guard handlerStatus == noErr else {
            status = PVL("Не удалось подключить обработчик сочетания")
            NSLog("Premiere Versions: hotkey handler failed (%d)", handlerStatus)
            return false
        }
        return true
    }

    private func register(_ candidate: SavedShortcut) -> (OSStatus, EventHotKeyRef?) {
        let identifier = EventHotKeyID(signature: 0x50565253, id: 1)
        var reference: EventHotKeyRef?
        let result = RegisterEventHotKey(candidate.keyCode, candidate.modifiers, identifier, GetApplicationEventTarget(), 0, &reference)
        return (result, reference)
    }

    func start() {
        observeActivation()
        refreshRegistration()
    }

    func beginRecording() {
        guard !isRecording else { return }
        isRecording = true
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    func endRecording() {
        guard isRecording else { return }
        isRecording = false
        start()
    }

    /// Persist only after macOS accepts the new shortcut.
    func setShortcut(_ candidate: SavedShortcut) -> String? {
        guard candidate.isValid else { return PVL("Добавь Command, Option или Control к выбранной клавише.") }
        guard installHandler() else { return PVL("Не удалось подключить сочетание. Попробуй ещё раз.") }
        if candidate == shortcut, hotKeyRef != nil { isRecording = false; return nil }
        let (result, reference) = register(candidate)
        guard result == noErr, let reference else {
            return PVL("Это сочетание занято или недоступно. Выбери другое.")
        }
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = reference
        shortcut = candidate
        isRecording = false
        if let data = try? JSONEncoder().encode(candidate) { UserDefaults.standard.set(data, forKey: SavedShortcut.preferenceKey) }
        refreshRegistration()
        return nil
    }

    func stop() {
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
        isRecording = false
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }
}

/// Owned by the app, so closing a window does not stop backups.
@MainActor
final class AutosaveMonitor: ObservableObject {
    @Published private(set) var monitoringSince: Date?
    @Published var status = PVL("Мониторинг не настроен")
    private var timer: Timer?
    @Published private(set) var isScanning = false
    private var generation = 0
    private var activeScan: ScanCancellation?
    private let queue = DispatchQueue(label: "PremiereVersions.autosaves", qos: .utility)
    private let worker = AutosaveWorker()
    private var eventStream: FSEventStreamRef?
    private var accessURL: URL?
    private var volumeObservers: [NSObjectProtocol] = []

    init() {
        DefaultLocations.refreshMovedFolders()
        DefaultLocations.install()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            volumeObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let path = (notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL)?.path
                Task { @MainActor [weak self] in
                    guard let self, self.timer != nil else { return }
                    self.startWatching()
                    if let path {
                        self.queue.async { [worker = self.worker] in worker.index.invalidate(paths: [path]) }
                    }
                    self.scan()
                }
            })
        }
        if UserDefaults.standard.bool(forKey: "autosaveMonitoringEnabled") {
            start()
        }
    }

    func start() {
        stop()
        guard UserDefaults.standard.bool(forKey: "autosaveMonitoringEnabled"),
              UserDefaults.standard.data(forKey: searchBookmarkKey) != nil,
              UserDefaults.standard.data(forKey: "autosaveArchiveBookmark") != nil else {
            status = PVL("Разреши доступ для поиска и сохранения копий")
            return
        }
        monitoringSince = Date()
        status = PVL("Мониторинг включён · проверка каждые \(Int(BackupPolicy.checkInterval)) секунд")
        let timer = Timer(timeInterval: BackupPolicy.checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.scan() }
        }
        self.timer = timer
        startWatching()
        RunLoop.main.add(timer, forMode: .common)
        scan()
    }

    func stop() {
        activeScan?.cancel()
        generation += 1
        timer?.invalidate()
        timer = nil
        monitoringSince = nil
        stopWatching()
        status = PVL("Мониторинг выключен")
    }

    func checkNow() {
        guard UserDefaults.standard.data(forKey: searchBookmarkKey) != nil,
              UserDefaults.standard.data(forKey: "autosaveArchiveBookmark") != nil else {
            status = PVL("Сначала разреши доступ для поиска и сохранения копий")
            return
        }
        guard !isScanning else { return }
        queue.async { [worker] in worker.index.reset() }
        scan(manual: true)
    }

    private var searchBookmarkKey: String {
        UserDefaults.standard.string(forKey: "searchMode") == "folder" ? "autosaveWatchBookmark" : "computerSearchBookmark"
    }

    func configurationChanged() {
        queue.async { [worker] in worker.index.reset() }
        if UserDefaults.standard.bool(forKey: "autosaveMonitoringEnabled") { start() }
        else { status = PVL("Настройки поиска изменены") }
    }

    func authorizeComputer() {
        let panel = NSOpenPanel()
        panel.title = PVL("Разрешить поиск проектов")
        panel.message = PVL("Выбери системный диск Macintosh HD для поиска проектов на компьютере и подключённых дисках. macOS может отдельно запросить доступ к защищённым папкам и внешним дискам.")
        panel.directoryURL = URL(fileURLWithPath: "/", isDirectory: true)
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = PVL("Разрешить доступ")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard url.resolvingSymlinksInPath().standardizedFileURL.path == "/" else {
            status = PVL("Для общего поиска выбери системный диск. Для одной папки используй режим «Выбранная папка».")
            return
        }
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        do {
            let defaults = UserDefaults.standard
            let data = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(data, forKey: "computerSearchBookmark")
            for (pathKey, bookmarkKey, fallback) in [
                ("archivePath", "archiveBookmark", DefaultLocations.versions),
                ("autosaveArchivePath", "autosaveArchiveBookmark", DefaultLocations.autosaves)
            ] {
                let destination = URL(fileURLWithPath: defaults.string(forKey: pathKey) ?? fallback, isDirectory: true)
                if defaults.data(forKey: bookmarkKey) == nil {
                    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                    let bookmark = try destination.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                    defaults.set(bookmark, forKey: bookmarkKey)
                }
            }
            configurationChanged()
            if !defaults.bool(forKey: "autosaveMonitoringEnabled") { status = PVL("Доступ сохранён. Можно включить резервное копирование.") }
        } catch {
            status = PVL("Не удалось настроить доступ: \(error.localizedDescription). Папку сохранения можно выбрать в дополнительных настройках.")
        }
    }

    func authorizeArchives() {
        let panel = NSOpenPanel()
        panel.title = PVL("Разрешить сохранение резервных копий")
        panel.message = PVL("Для папок по умолчанию выбери Рабочий стол своего пользователя. Программа создаст Premiere_Versions с разделами Premiere_Saves и Premiere_AutoSaves. Другие места можно выбрать в дополнительных настройках.")
        panel.directoryURL = DefaultLocations.home.appendingPathComponent("Desktop")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = PVL("Разрешить сохранение")
        guard panel.runModal() == .OK, let root = panel.url else { return }
        let started = root.startAccessingSecurityScopedResource()
        defer { if started { root.stopAccessingSecurityScopedResource() } }
        do {
            let defaults = UserDefaults.standard
            for (pathKey, bookmarkKey, fallback) in [
                ("archivePath", "archiveBookmark", DefaultLocations.versions),
                ("autosaveArchivePath", "autosaveArchiveBookmark", DefaultLocations.autosaves)
            ] {
                if defaults.data(forKey: bookmarkKey) != nil { continue }
                let folder = URL(fileURLWithPath: defaults.string(forKey: pathKey) ?? fallback, isDirectory: true)
                let path = folder.standardizedFileURL.path
                let parent = root.standardizedFileURL.path
                guard path == parent || path.hasPrefix(parent + "/") else {
                    throw NSError(domain: "PremiereVersions", code: 31, userInfo: [NSLocalizedDescriptionKey: PVL("Выбранная папка не содержит место сохранения. Выбери Рабочий стол или измени расположение архива в настройках.")])
                }
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let bookmark = try folder.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                defaults.set(bookmark, forKey: bookmarkKey)
            }
            configurationChanged()
        } catch {
            status = PVL("Не удалось настроить сохранение: \(error.localizedDescription)")
        }
    }

    private func stopWatching() {
        if let eventStream {
            FSEventStreamStop(eventStream)
            FSEventStreamInvalidate(eventStream)
            FSEventStreamRelease(eventStream)
        }
        eventStream = nil
        if let accessURL { accessURL.stopAccessingSecurityScopedResource() }
        accessURL = nil
    }

    private func startWatching() {
        stopWatching()
        guard let root = try? worker.resolveBookmark(forKey: searchBookmarkKey) else { return }
        if root.startAccessingSecurityScopedResource() { accessURL = root }
        var paths = [root.path]
        if root.path == "/" {
            paths += (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? [])
                .filter { $0.path.hasPrefix("/Volumes/") }.map(\.path)
        }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        eventStream = FSEventStreamCreate(nil, { _, info, count, rawPaths, flags, _ in
            guard let info else { return }
            let monitor = Unmanaged<AutosaveMonitor>.fromOpaque(info).takeUnretainedValue()
            let allPaths = unsafeBitCast(rawPaths, to: NSArray.self) as? [String] ?? []
            var changed: [String] = []
            for i in 0..<min(count, allPaths.count) {
                let path = allPaths[i]
                let isProject = (path as NSString).pathExtension.lowercased() == "prproj"
                let isChangedDirectory = (flags[i] & FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs) != 0) || (flags[i] & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir) != 0 && flags[i] & FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRenamed) != 0)
                if isProject || isChangedDirectory { changed.append(path) }
            }
            let changedPaths = changed
            guard !changedPaths.isEmpty else { return }
            Task { @MainActor in
                monitor.queue.async { [worker = monitor.worker] in worker.index.invalidate(paths: changedPaths) }
            }
        }, &context, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 2,
        FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot))
        if let eventStream {
            FSEventStreamSetDispatchQueue(eventStream, DispatchQueue.main)
            if !FSEventStreamStart(eventStream) {
                stopWatching()
                status = PVL("Не удалось включить отслеживание изменений. Проверь доступ к диску.")
            }
        }
    }

    private func scan(manual: Bool = false) {
        guard (manual || timer != nil), !isScanning else { return }
        isScanning = true
        status = PVL("Проверяю проекты и автосейвы…")
        let currentGeneration = generation
        let cancellation = ScanCancellation()
        activeScan = cancellation
        let worker = self.worker
        queue.async { [weak self] in
            let message: String
            do {
                let result = try worker.scanAutosaves(cancellation: cancellation)
                message = PVL("Найдено: \(result.found) · скопировано: \(result.copied) · уже в архиве: \(result.unchanged) · ожидают стабильности: \(result.waiting)") + (result.outsideCreationWindow == 0 ? "" : PVL(" · вне окна 48 ч: \(result.outsideCreationWindow)")) + (result.nativeCopied == 0 ? "" : PVL(" · копий Premiere: \(result.nativeCopied)")) + (result.failed == 0 ? "" : PVL(" · ошибок копирования: \(result.failed)")) + (result.inaccessible == 0 ? "" : PVL(" · нет доступа к папкам: \(result.inaccessible)"))
            } catch {
                message = PVL("Ошибка мониторинга: \(error.localizedDescription)")
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isScanning = false
                self.activeScan = nil
                guard self.generation == currentGeneration else { return }
                self.status = message
                if self.timer != nil && self.eventStream == nil {
                    self.status += PVL("\nОтслеживание новых файлов недоступно. Используй «Проверить сейчас» или выдай доступ заново.")
                }
            }
        }
    }
}

nonisolated enum DefaultLocations {
    static var home: URL {
        if let path = getpwuid(getuid())?.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: path), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
    static var versions: String { home.appendingPathComponent("Desktop/Premiere_Versions/Premiere_Saves").path }
    static var autosaves: String { home.appendingPathComponent("Desktop/Premiere_Versions/Premiere_AutoSaves").path }
    /// Bookmark identity follows a moved folder; synchronize display paths without changing user choices.
    static func refreshMovedFolders(in defaults: UserDefaults = .standard) {
        for (bookmarkKey, pathKey) in [
            ("archiveBookmark", "archivePath"),
            ("autosaveArchiveBookmark", "autosaveArchivePath"),
            ("autosaveWatchBookmark", "autosaveWatchPath"),
            ("defaultProjectFolderBookmark", "defaultProjectFolder")
        ] {
            guard let data = defaults.data(forKey: bookmarkKey) else { continue }
            do {
                var stale = false
                let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
                let started = url.startAccessingSecurityScopedResource()
                defer { if started { url.stopAccessingSecurityScopedResource() } }
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                if stale, let renewed = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
                    defaults.set(renewed, forKey: bookmarkKey)
                }
                defaults.set(url.path, forKey: pathKey)
            } catch { /* Keep the saved location and bookmark when a disk is unavailable. */ }
        }
    }

    static func install(in defaults: UserDefaults = .standard) {
        if defaults.string(forKey: "logoVariant") == nil { defaults.set("signature-dark", forKey: "logoVariant") }
        if (defaults.string(forKey: "archivePath") ?? "").isEmpty { defaults.set(versions, forKey: "archivePath") }
        if (defaults.string(forKey: "autosaveArchivePath") ?? "").isEmpty { defaults.set(autosaves, forKey: "autosaveArchivePath") }
        if defaults.string(forKey: "searchMode") == nil { defaults.set("all", forKey: "searchMode") }
        if defaults.object(forKey: "copyPremiereAutosave") == nil { defaults.set(true, forKey: "copyPremiereAutosave") }
        if defaults.object(forKey: "autosaveMonitoringEnabled") == nil { defaults.set(true, forKey: "autosaveMonitoringEnabled") }
    }
}

nonisolated enum BackupPolicy {
    static let checkInterval: TimeInterval = 30
    static let snapshotInterval: TimeInterval = 5 * 60
    static let stableDelay: TimeInterval = 12
    static let newProjectHours = 48
    static func acceptsCreation(_ date: Date?, now: Date) -> Bool {
        guard let date else { return false }
        let age = now.timeIntervalSince(date)
        return age >= -300 && age <= Double(newProjectHours) * 60 * 60
    }
    static let recentCount = 10
    static let hourlyHours = 12
    static let dailyDays = 5
    static let minimumHourlyAge: TimeInterval = 10 * 60
}

nonisolated final class ScanCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func check() throws {
        lock.lock(); let stopped = cancelled; lock.unlock()
        if stopped { throw CancellationError() }
    }
}

/// Native Premiere autosaves and already archived snapshots are never backup sources.
nonisolated enum ProjectSourceFilter {
    private static let excludedFolders: Set<String> = [
        "adobe premiere pro auto-save", "adobe premiere pro auto save",
        "auto-save", "auto save", "autosave", "autosaves",
        "premiere_autosaves", "premiere_versions",
        "автосохранение", "автосохранения",
        "adobe premiere pro автосохранение", "adobe premiere pro автосохранения"
    ]
    private static let nativeSnapshot = try! NSRegularExpression(
        pattern: #"(?i)--[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}-\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}$"#
    )
    private static let archivedSnapshot = try! NSRegularExpression(pattern: #"(?i)(?:_autosave_\d+|_AUTO_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}|_(?:recent|hourly|daily)_\d{2}-\d{2}-\d{4}-\d{2}-\d{2}-\d{2}_autosave)$"#)

    static func isExcluded(_ url: URL) -> Bool {
        // Check the supplied path as well as its resolved location (for moved/symlinked files).
        for candidate in [url.standardizedFileURL, url.resolvingSymlinksInPath().standardizedFileURL] {
            if candidate.pathComponents.contains(where: { component in
                let normalized = component.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                    .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
                return String(String.UnicodeScalarView(normalized)).contains("autosave") || excludedFolders.contains(component.lowercased())
            }) { return true }
            let name = candidate.deletingPathExtension().lastPathComponent
            let range = NSRange(name.startIndex..<name.endIndex, in: name)
            if nativeSnapshot.firstMatch(in: name, range: range) != nil || archivedSnapshot.firstMatch(in: name, range: range) != nil { return true }
        }
        return false
    }
}

/// Accessed only on the monitor's serial utility queue.
nonisolated final class ProjectFileIndex {
    private var rootPath = ""
    private var files = Set<URL>()
    private var pending = Set<String>()
    private let fm = FileManager.default
    private(set) var inaccessible = Set<String>()
    func reset() { rootPath = ""; files.removeAll(); pending.removeAll(); inaccessible.removeAll() }
    func invalidate(paths: [String]) { pending.formUnion(paths) }

    func projects(in root: URL, excluding archives: [URL], cancellation: ScanCancellation? = nil) throws -> [URL] {
        let root = root.resolvingSymlinksInPath().standardizedFileURL
        let excluded = archives.map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
        func allowed(_ url: URL) -> Bool {
            guard !ProjectSourceFilter.isExcluded(url) else { return false }
            let path = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard path == root.path || root.path == "/" || path.hasPrefix(root.path + "/") else { return false }
            if excluded.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return false }
            let systemPaths = ["/System", "/Library", "/private", "/usr", "/bin", "/sbin", "/dev", "/cores", "/Network", "/net"]
            if root.path == "/", systemPaths.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return false }
            if path.contains("/Library/") || path.hasSuffix("/Library") { return false }
            return true
        }
        if rootPath != root.path {
            rootPath = root.path
            files.removeAll()
            inaccessible.removeAll()
            pending = [root.path]
        }
        let changes = pending
        pending.removeAll()
        for path in changes {
            try cancellation?.check()
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            guard allowed(directory) else { continue }
            var isDir: ObjCBool = false
            if !fm.fileExists(atPath: path, isDirectory: &isDir) {
                files = files.filter { $0.path != path && !$0.path.hasPrefix(path + "/") }
                continue
            }
            if !isDir.boolValue {
                if directory.pathExtension.lowercased() == "prproj" { files.insert(directory) }
                continue
            }
            guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { url, _ in
                self.inaccessible.insert(url.path)
                return true
            }) else {
                throw NSError(domain: "PremiereVersions", code: 30, userInfo: [NSLocalizedDescriptionKey: PVL("Нет доступа к папке поиска: \(path)")])
            }
            for case let item as URL in enumerator {
                try cancellation?.check()
                let values = try? item.resourceValues(forKeys: [.isSymbolicLinkKey])
                if !allowed(item) || values?.isSymbolicLink == true {
                    enumerator.skipDescendants()
                    continue
                }
                if item.pathExtension.lowercased() == "prproj" { files.insert(item) }
            }
        }
        files = files.filter { fm.fileExists(atPath: $0.path) && allowed($0) }
        return Array(files)
    }
}

nonisolated enum BackupStatus: String, Sendable {
    case recent, hourly, daily
}

nonisolated enum BackupNaming {
    static func filename(project: String, modified: Date, status: BackupStatus) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd-MM-yyyy-HH-mm-ss"
        return "\(project)_\(status.rawValue)_\(formatter.string(from: modified))_autosave.prproj"
    }

    static func isManaged(_ filename: String, project: String) -> Bool {
        let prefix = NSRegularExpression.escapedPattern(for: project)
        let suffix = #"(?:_autosave_\d+|_AUTO_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}|_(?:recent|hourly|daily)_\d{2}-\d{2}-\d{4}-\d{2}-\d{2}-\d{2}_autosave)\.prproj$"#
        return filename.range(of: "(?i)^" + prefix + suffix, options: .regularExpression) != nil
    }
}

nonisolated struct AutosaveScanResult: Sendable {
    var found = 0
    var copied = 0
    var unchanged = 0
    var waiting = 0
    var inaccessible = 0
    var outsideCreationWindow = 0
    var nativeCopied = 0
    var nativeWaiting = 0
    var failed = 0
}

/// All filesystem work runs on a serial utility queue, never on the UI thread.
nonisolated final class AutosaveWorker: @unchecked Sendable {
    private let fileManager = FileManager.default
    let index = ProjectFileIndex()
    private let archiveEngine = PVBackupArchive()
    private let nativeEngine = PVLatestNativeAutosave()
    @discardableResult
    func scanAutosaves(cancellation: ScanCancellation? = nil) throws -> AutosaveScanResult {
        let key = UserDefaults.standard.string(forKey: "searchMode") == "folder" ? "autosaveWatchBookmark" : "computerSearchBookmark"
        let root = try resolveBookmark(forKey: key)
        let archive = try resolveBookmark(forKey: "autosaveArchiveBookmark")
        do {
        return try withScopedAccess(to: root) {
            try withScopedAccess(to: archive) {
                let versions = URL(fileURLWithPath: UserDefaults.standard.string(forKey: "archivePath") ?? DefaultLocations.versions)
                var files = try index.projects(in: root, excluding: [archive, versions], cancellation: cancellation)
                let selected = try? resolveBookmark(forKey: "savedProjectBookmark")
                let selectedAccess = selected?.startAccessingSecurityScopedResource() ?? false
                defer { if selectedAccess { selected?.stopAccessingSecurityScopedResource() } }
                if let selected, FileManager.default.fileExists(atPath: selected.path), !files.contains(selected), !ProjectSourceFilter.isExcluded(selected) { files.append(selected) }
                var result = try scanAutosaves(watchURL: root, archiveURL: archive, indexedFiles: files,
                    selectedProject: selected, copyNative: UserDefaults.standard.object(forKey: "copyPremiereAutosave") as? Bool ?? true, cancellation: cancellation)
                result.inaccessible = index.inaccessible.count
                return result
            }
        }
        } catch {
            index.reset()
            throw error
        }
    }

    @discardableResult
    func scanAutosaves(watchURL: URL, archiveURL: URL, indexedFiles: [URL]? = nil,
                      selectedProject: URL? = nil, copyNative: Bool = true, now: Date = Date(),
                      cancellation: ScanCancellation? = nil) throws -> AutosaveScanResult {
        var result = AutosaveScanResult()
        return try withScopedAccess(to: watchURL) {
            try withScopedAccess(to: archiveURL) {
                let watchPath = PVProjectFolders.canonical(watchURL), archivePath = PVProjectFolders.canonical(archiveURL)
                guard watchPath != archivePath, !watchPath.hasPrefix(archivePath + "/") else {
                    throw NSError(domain: "PremiereVersions", code: 20, userInfo: [NSLocalizedDescriptionKey: PVL("Папка наблюдения не должна совпадать с архивом или находиться внутри него.")])
                }
                let candidates = try (indexedFiles ?? ProjectFileIndex().projects(in: watchURL, excluding: [archiveURL], cancellation: cancellation)).filter { !ProjectSourceFilter.isExcluded($0) }
                result.found = candidates.count
                for source in candidates {
                    try cancellation?.check()
                    do {
                        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .creationDateKey, .contentModificationDateKey, .fileSizeKey])
                        guard values.isRegularFile == true, let modified = values.contentModificationDate,
                              (values.fileSize ?? 0) > 0, now.timeIntervalSince(modified) >= BackupPolicy.stableDelay else { result.waiting += 1; continue }
                        let selected = selectedProject.map { PVProjectFolders.canonical($0) == PVProjectFolders.canonical(source) } ?? false
                        let known = PVProjectFolders.shared.existing(for: source, archive: archiveURL) != nil
                        let legacy = archiveURL.appendingPathComponent(source.deletingPathExtension().lastPathComponent)
                        let unclaimed = !fileManager.fileExists(atPath: legacy.appendingPathComponent(".pv-source.json").path)
                        let hasLegacy = unclaimed && ((try? fileManager.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []).contains { BackupNaming.isManaged($0.lastPathComponent, project: source.deletingPathExtension().lastPathComponent) }
                        guard selected || known || hasLegacy || BackupPolicy.acceptsCreation(values.creationDate, now: now) else { result.outsideCreationWindow += 1; continue }
                        let folder = try PVProjectFolders.shared.folder(for: source, archive: archiveURL, allowLegacyClaim: hasLegacy)
                        switch try archiveEngine.process(source: source, folder: folder, now: now) {
                        case .copied: result.copied += 1
                        case .unchanged: result.unchanged += 1
                        case .waiting: result.waiting += 1
                        }
                        if copyNative {
                            do {
                                switch try nativeEngine.process(project: source, archiveFolder: folder, now: now) {
                                case .copied: result.nativeCopied += 1
                                case .waiting: result.nativeWaiting += 1
                                case .missing, .unchanged: break
                                }
                            } catch PVBackupFailure.changingSource { result.nativeWaiting += 1 }
                            catch { result.failed += 1 }
                        }
                    } catch PVBackupFailure.changingSource { result.waiting += 1 }
                    catch { result.failed += 1 }
                }
                return result
            }
        }
    }

    func resolveBookmark(forKey key: String) throws -> URL {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            throw NSError(
                domain: "PremiereVersions",
                code: 10,
                userInfo: [NSLocalizedDescriptionKey: PVL("Сохранённый доступ отсутствует. Выбери папку или проект заново.")]
            )
        }

        var stale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )

        if stale {
            try withScopedAccess(to: url) {
                let refreshed = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                UserDefaults.standard.set(refreshed, forKey: key)
            }
        }
        return url
    }

    private func withScopedAccess<T>(to url: URL, operation: () throws -> T) throws -> T {
        let started = url.startAccessingSecurityScopedResource()
        defer {
            if started {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try operation()
    }

}
