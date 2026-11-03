import AppKit
import Carbon
import Foundation
import Darwin

@MainActor final class HotKeyHelper: NSObject, NSApplicationDelegate {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var preferencesObserver: NSObjectProtocol?
    private var refreshTask: Task<Void, Never>?
    private var shortcut = PVHelperShortcut.default
    private var preferencesTask: Task<Void, Never>?
    private var preferencesGeneration = 0
    private var ownerExit: DispatchSourceProcess?
    private var ownerPID: pid_t?
    private var exitedPID: pid_t?
    private var knownOwner: NSRunningApplication?
    private var launching = false
    private var autoLaunch = false
    private var backgroundEnabled = true
    private var preferencesLoaded = false
    private var autoPolicy = PVAutoLaunchPolicy()
    private var autoTask: Task<Void, Never>?
    private let premiereLifecycle = PVPremiereLifecycle()
    private var premiereProcesses: Set<Int32> { premiereLifecycle.processes }
    private func considerAutomaticLaunch(justEnabled: Bool = false) {
        guard preferencesLoaded else { return }
        let shouldLaunch = autoPolicy.shouldLaunch(processes: premiereProcesses, enabled: autoLaunch, ownerRunning: mainRunning, justEnabled: justEnabled)
        guard shouldLaunch, !launching else { return }
        launching = true; unregister()
        autoTask = Task { @MainActor in
            guard await HelperLaunchTicket.set(true) else { launching = false; refresh(); return }
            // Recheck after the asynchronous ticket write: never open a second instance or an orphaned session.
            guard !mainRunning, !premiereProcesses.isEmpty, autoLaunch else {
                _ = await HelperLaunchTicket.set(false); launching = false; refresh(); return
            }
            launchOwner(background: true)
        }
    }
    private func launchOwner(background: Bool) {
        let config = NSWorkspace.OpenConfiguration(); config.activates = !background; config.hides = background
        config.addsToRecentItems = false; config.allowsRunningApplicationSubstitution = false
        NSWorkspace.shared.openApplication(at: owner, configuration: config) { [weak self] application, error in
            Task { @MainActor in
                if let self, let application, application.bundleURL?.resolvingSymlinksInPath() == self.owner {
                    self.knownOwner = application; self.exitedPID = nil
                }
                if background, error != nil { _ = await HelperLaunchTicket.set(false) }
                self?.launching = false; self?.refresh()
            }
        }
    }
    #if PV_HELPER_TESTING
    private var testEvents: DispatchSourceFileSystemObject?
    private var testRoot: URL? {
        guard let path = Bundle(url: owner)?.object(forInfoDictionaryKey: "PVTestRoot") as? String else { return nil }
        let root = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        guard root == owner.deletingLastPathComponent(),
              root.path.hasPrefix(URL(fileURLWithPath: "/private/tmp").resolvingSymlinksInPath().path + "/pv-icon-service-") else { return nil }
        return root
    }
    private func reportTestState() {
        guard let root = testRoot else { return }
        let value: [String: Any] = ["running": true, "mainRunning": mainRunning, "registered": hotKey != nil, "key": Int(shortcut.keyCode), "pid": Int(ProcessInfo.processInfo.processIdentifier), "auto": autoLaunch, "backgroundEnabled": backgroundEnabled, "premiereCount": premiereProcesses.count, "launching": launching]
        if let data = try? JSONSerialization.data(withJSONObject: value) { try? data.write(to: root.appendingPathComponent("helper-state.json"), options: .atomic) }
    }
    #endif
    private var owner: URL {
        Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().resolvingSymlinksInPath()
    }
    private var ownerID: String { Bundle.main.object(forInfoDictionaryKey: "PVOwnerBundleIdentifier") as? String ?? "" }
    private var helperID: String { Bundle.main.bundleIdentifier ?? "" }
    private var runningOwner: NSRunningApplication? {
        func valid(_ app: NSRunningApplication) -> Bool {
            !app.isTerminated && app.processIdentifier != exitedPID && app.bundleURL?.resolvingSymlinksInPath() == owner &&
            (Darwin.kill(app.processIdentifier, 0) == 0 || errno != ESRCH)
        }
        if let knownOwner, valid(knownOwner) { return knownOwner }
        return NSRunningApplication.runningApplications(withBundleIdentifier: ownerID).first(where: valid)
    }
    private var mainRunning: Bool { runningOwner != nil }
    private var premiereActive: Bool {
        #if PV_HELPER_TESTING
        if testRoot != nil { return true }
        #endif
        guard let app = NSWorkspace.shared.frontmostApplication, !app.isHidden, !app.isTerminated,
              let id = app.bundleIdentifier?.lowercased() else { return false }
        return id == "com.adobe.premierepro" || id.hasPrefix("com.adobe.premierepro.")
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.prohibited)
        guard !ownerID.isEmpty, Bundle(url: owner)?.bundleIdentifier == ownerID else { NSApp.terminate(nil); return }
        premiereLifecycle.onChange = { [weak self] _ in self?.refresh() }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.refresh() } })
        }
        preferencesObserver = DistributedNotificationCenter.default().addObserver(forName: Notification.Name(helperID + ".configurationChanged"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.refreshTask?.cancel()
                self?.refreshTask = Task { @MainActor in
                    do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return }
                    self?.reload()
                }
            }
        }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, pointer in
            guard let pointer else { return noErr }
            MainActor.assumeIsolated { Unmanaged<HotKeyHelper>.fromOpaque(pointer).takeUnretainedValue().pressed() }
            return noErr
        }, 1, &type, context, &handler)
        #if PV_HELPER_TESTING
        if let root = testRoot {
            let fd = open(root.path, O_EVTONLY)
            if fd >= 0 {
                let events = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write], queue: .main)
                events.setEventHandler { [weak self] in
                    guard let self else { return }
                    let trigger = root.appendingPathComponent("trigger")
                    if FileManager.default.fileExists(atPath: trigger.path) {
                        try? FileManager.default.removeItem(at: trigger)
                        self.pressed()
                    }
                }
                events.setCancelHandler { close(fd) };events.resume();testEvents = events
            }
        }
        #endif
        reload()
    }
    private func reload() {
        preferencesTask?.cancel();preferencesGeneration &+= 1
        let generation=preferencesGeneration
        preferencesTask=Task{@MainActor in
            let data=await HelperPreferenceReader.read()
            guard !Task.isCancelled,generation==preferencesGeneration else{return}
            let stored=data.flatMap{try? JSONDecoder().decode(PVHelperShortcut.self,from:$0)}
            var fallback=PVHelperShortcut.default
            #if PV_HELPER_TESTING
            if testRoot != nil {fallback=PVHelperShortcut(keyCode:UInt32(kVK_F20),modifiers:UInt32(cmdKey|optionKey|controlKey|shiftKey),keyLabel:"F20")}
            #endif
            let updated=stored?.isValid==true ? stored! : fallback
            backgroundEnabled = updated.backgroundEnabled != false
            let justEnabled = !autoLaunch && updated.launchWithPremiere == true && backgroundEnabled
            autoLaunch = updated.launchWithPremiere == true && backgroundEnabled; preferencesLoaded = true
            if updated != shortcut {unregister();shortcut=updated}
            considerAutomaticLaunch(justEnabled: justEnabled)
            refresh()
        }
    }
    private func refresh() {
        #if PV_HELPER_TESTING
        defer { reportTestState() }
        #endif
        watchOwnerExit()
        considerAutomaticLaunch()
        guard !launching, PVHelperPolicy.shouldListen(mainRunning: mainRunning, premiereActive: premiereActive, enabled: backgroundEnabled) else { unregister(); return }
        guard hotKey == nil else { return }
        let id = EventHotKeyID(signature: 0x5056484B, id: 1)
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr { hotKey = nil }
    }
    private func watchOwnerExit() {
        let app = runningOwner
        guard let app else {ownerExit?.cancel();ownerExit=nil;ownerPID=nil;return}
        let pid=app.processIdentifier
        guard ownerPID != pid else{return}
        ownerExit?.cancel();ownerPID=pid
        let stream=DispatchSource.makeProcessSource(identifier:pid,eventMask:.exit,queue:.main)
        stream.setEventHandler{[weak self] in
            guard let self, self.ownerPID == pid else{return}
            self.exitedPID=pid;self.knownOwner=nil;self.ownerExit?.cancel();self.ownerExit=nil;self.ownerPID=nil;self.refresh()
        }
        ownerExit=stream;stream.resume()
    }
    private func unregister() { if let hotKey { UnregisterEventHotKey(hotKey) }; hotKey = nil }
    private func pressed() {
        guard !launching, PVHelperPolicy.shouldListen(mainRunning: mainRunning, premiereActive: premiereActive, enabled: backgroundEnabled) else { refresh(); return }
        launching = true; unregister()
        launchOwner(background: false)
    }
    func applicationWillTerminate(_ notification: Notification) {
        #if PV_HELPER_TESTING
        testEvents?.cancel()
        #endif
        premiereLifecycle.stop()
        ownerExit?.cancel(); autoTask?.cancel(); preferencesTask?.cancel(); refreshTask?.cancel(); unregister()
        if let handler { RemoveEventHandler(handler) }
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        if let preferencesObserver { DistributedNotificationCenter.default().removeObserver(preferencesObserver) }
    }
}
@main struct HelperMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = HotKeyHelper();app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
