import AppKit
import Combine
import ServiceManagement

@MainActor final class PVHotKeyHelperManager: ObservableObject {
    static let shared = PVHotKeyHelperManager()
    static let identifier = "devplaceholder.YDHGHCQE.Premiere-Versions.HotKeyHelper"
    @Published private(set) var message = ""
    @Published private(set) var needsApproval = false
    @Published private(set) var enabled = false
    private var observer: NSObjectProtocol?
    private var operation: Task<Void, Never>?
    private var currentBuild: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "" }
    private var installed: Bool {
        let parent = Bundle.main.bundleURL.resolvingSymlinksInPath().deletingLastPathComponent()
        return PVInstalledAppLocations.standardRoots.map { $0.resolvingSymlinksInPath() }.contains(parent)
    }
    private var service: SMAppService { .loginItem(identifier: Self.identifier) }
    func start() {
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.refresh() } }
        }
        guard UserDefaults.standard.object(forKey: "hotKeyHelperEnabled") as? Bool ?? true else { Task { await enable(false) }; return }
        Task { await enable(true) }
    }
    func refresh() {
        guard installed else { enabled = false; needsApproval = false; message = PVL("Помощник доступен после установки в «Программы»"); return }
        enabled = service.status == .enabled
        needsApproval = service.status == .requiresApproval
        message = PVL(needsApproval ? "Разреши фоновую работу в настройках macOS" : enabled ? "Помощник активен" : "Помощник отключён")
    }
    func enable(_ value: Bool) async {
        UserDefaults.standard.set(value, forKey: "hotKeyHelperEnabled")
        let previous = operation
        let task = Task { @MainActor in
            await previous?.value
            guard (UserDefaults.standard.object(forKey: "hotKeyHelperEnabled") as? Bool ?? true) == value else { return }
            await applyEnabled(value)
        }
        operation = task
        await task.value
    }
    private func applyEnabled(_ value: Bool) async {
        guard installed else { refresh(); return }
        do {
            if value {
                if PVHelperPolicy.needsRefresh(enabled: service.status == .enabled,
                    registeredVersion: UserDefaults.standard.integer(forKey: "hotKeyHelperImplementationVersion")) {
                    try await service.unregister()
                }
                // Store the policy before registration so a newly started helper cannot read stale settings.
                guard await writeConfiguration(enabled: true) else { refresh(); message = PVL("Не удалось изменить работу в фоне"); return }
                if service.status == .notRegistered || service.status == .notFound { try service.register() }
                if service.status == .enabled || service.status == .requiresApproval {
                    UserDefaults.standard.set(PVHelperPolicy.implementationVersion, forKey: "hotKeyHelperImplementationVersion")
                    UserDefaults.standard.set(currentBuild, forKey: "hotKeyHelperRegisteredBuild")
                }
            } else {
                _ = await writeConfiguration(enabled: false)
                if service.status == .enabled || service.status == .requiresApproval { try await service.unregister() }
            }
            refresh()
        } catch {
            refresh(); message = PVL("Не удалось изменить работу в фоне") + ": " + error.localizedDescription
        }
    }
    /// Full exit suspends the helper without discarding the saved background preference.
    func suspendForTermination() async -> Bool {
        await operation?.value
        guard installed else { return true }
        let disabled = await writeConfiguration(enabled: false)
        do {
            if service.status == .enabled || service.status == .requiresApproval { try await service.unregister() }
            return true
        } catch {
            refresh(); message = PVL("Не удалось завершить фоновую работу")
            return disabled
        }
    }
    func syncShortcut() async {
        let enabled = UserDefaults.standard.object(forKey: "hotKeyHelperEnabled") as? Bool ?? true
        if !enabled { await enable(false); return }
        guard await writeConfiguration(enabled: enabled) else { message = PVL("Не удалось сохранить сочетание для помощника"); return }
    }
    private func writeConfiguration(enabled: Bool) async -> Bool {
        guard installed, let encoded = try? JSONEncoder().encode(SavedShortcut.load()),
              var config = try? JSONDecoder().decode(PVHelperShortcut.self, from: encoded) else { return false }
        config.backgroundEnabled = enabled
        config.launchWithPremiere = enabled && (UserDefaults.standard.object(forKey: "launchWithPremiere") as? Bool ?? true)
        guard let data = try? JSONEncoder().encode(config) else { return false }
        return await PVHelperPreferencesWriter.configure(data)
    }
    func openApproval() { SMAppService.openSystemSettingsLoginItems() }
}

@MainActor private enum PVHelperPreferencesWriter {
    static func configure(_ data: Data) async -> Bool {
        await withCheckedContinuation { continuation in
            let request = PVHelperPreferenceRequest(continuation)
            request.start(data)
        }
    }
}
@MainActor private final class PVHelperPreferenceRequest {
    private var continuation: CheckedContinuation<Bool, Never>?
    private var connection: NSXPCConnection?
    private var timeout: Task<Void, Never>?
    init(_ continuation: CheckedContinuation<Bool, Never>) { self.continuation = continuation }
    func start(_ data: Data) {
        let connection = NSXPCConnection(serviceName: (Bundle.main.bundleIdentifier ?? "") + ".IconService")
        self.connection = connection
        connection.remoteObjectInterface = NSXPCInterface(with: PVIconServiceProtocol.self)
        connection.invalidationHandler = { Task { @MainActor in self.finish(false) } }
        connection.interruptionHandler = { Task { @MainActor in self.finish(false) } }
        connection.resume()
        timeout = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 8_000_000_000) } catch { return }
            finish(false)
        }
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in Task { @MainActor in self.finish(false) } }) as? PVIconServiceProtocol else { finish(false); return }
        proxy.configureHotKeyHelper(data) { success, _ in Task { @MainActor in self.finish(success) } }
    }
    private func finish(_ success: Bool) {
        guard let continuation else { return }
        self.continuation = nil;timeout?.cancel();timeout = nil
        connection?.invalidationHandler = nil;connection?.interruptionHandler = nil;connection?.invalidate();connection = nil
        continuation.resume(returning: success)
    }
}

@MainActor enum PVHelperLaunchIntent {
    static func consume() async -> Bool {
        await withCheckedContinuation { continuation in
            let request = PVLaunchIntentRequest(continuation); request.start()
        }
    }
}
@MainActor private final class PVLaunchIntentRequest {
    private var continuation: CheckedContinuation<Bool, Never>?
    private var connection: NSXPCConnection?
    private var timeout: Task<Void, Never>?
    init(_ continuation: CheckedContinuation<Bool, Never>) { self.continuation = continuation }
    func start() {
        let connection = NSXPCConnection(serviceName: (Bundle.main.bundleIdentifier ?? "") + ".IconService")
        self.connection = connection; connection.remoteObjectInterface = NSXPCInterface(with: PVIconServiceProtocol.self)
        connection.invalidationHandler = { Task { @MainActor in self.finish(false) } }
        connection.interruptionHandler = { Task { @MainActor in self.finish(false) } }
        connection.resume()
        timeout = Task { @MainActor in try? await Task.sleep(nanoseconds: 2_000_000_000); self.finish(false) }
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in Task { @MainActor in self.finish(false) } }) as? PVIconServiceProtocol else { finish(false); return }
        proxy.consumeBackgroundLaunch { result in Task { @MainActor in self.finish(result) } }
    }
    private func finish(_ value: Bool) {
        guard let continuation else { return }; self.continuation = nil
        timeout?.cancel(); timeout = nil
        connection?.invalidationHandler = nil; connection?.interruptionHandler = nil; connection?.invalidate(); connection = nil
        continuation.resume(returning: value)
    }
}
