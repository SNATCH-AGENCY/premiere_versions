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
        guard UserDefaults.standard.object(forKey: "hotKeyHelperEnabled") as? Bool ?? true else { refresh(); return }
        Task { await enable(true) }
    }
    func refresh() {
        guard installed else { enabled = false; needsApproval = false; message = PVL("Помощник доступен после установки в «Программы»"); return }
        enabled = service.status == .enabled
        needsApproval = service.status == .requiresApproval
        message = PVL(needsApproval ? "Разреши фоновую работу в настройках macOS" : enabled ? "Сочетание работает и после полного выхода" : "Для вызова после выхода нужен фоновый помощник")
    }
    func enable(_ value: Bool) async {
        UserDefaults.standard.set(value, forKey: "hotKeyHelperEnabled")
        guard installed else { refresh(); return }
        do {
            if value {
                if service.status == .notRegistered || service.status == .notFound { try service.register() }
                if service.status == .enabled {
                    UserDefaults.standard.set(currentBuild, forKey: "hotKeyHelperRegisteredBuild")
                    await syncShortcut()
                }
            } else if service.status == .enabled || service.status == .requiresApproval { try await service.unregister() }
            refresh()
        } catch {
            UserDefaults.standard.set(service.status == .enabled || service.status == .requiresApproval, forKey: "hotKeyHelperEnabled")
            refresh(); message = PVL("Не удалось изменить работу помощника: ") + error.localizedDescription
        }
    }
    func syncShortcut() async {
        guard installed, let data = try? JSONEncoder().encode(SavedShortcut.load()) else { return }
        let success = await PVHelperPreferencesWriter.configure(data)
        if !success { message = PVL("Не удалось сохранить сочетание для помощника") }
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
