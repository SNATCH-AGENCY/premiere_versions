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
    private var launching = false
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
        let value: [String: Any] = ["running": true, "mainRunning": mainRunning, "registered": hotKey != nil, "key": Int(shortcut.keyCode), "pid": Int(ProcessInfo.processInfo.processIdentifier)]
        if let data = try? JSONSerialization.data(withJSONObject: value) { try? data.write(to: root.appendingPathComponent("helper-state.json"), options: .atomic) }
    }
    #endif
    private var owner: URL {
        Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().resolvingSymlinksInPath()
    }
    private var ownerID: String { Bundle.main.object(forInfoDictionaryKey: "PVOwnerBundleIdentifier") as? String ?? "" }
    private var helperID: String { Bundle.main.bundleIdentifier ?? "" }
    private var mainRunning: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: ownerID).contains {
            !$0.isTerminated && $0.processIdentifier != exitedPID && $0.bundleURL?.resolvingSymlinksInPath() == owner &&
            (Darwin.kill($0.processIdentifier, 0) == 0 || errno != ESRCH)
        }
    }
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
            if updated != shortcut {unregister();shortcut=updated}
            refresh()
        }
    }
    private func refresh() {
        #if PV_HELPER_TESTING
        defer { reportTestState() }
        #endif
        watchOwnerExit()
        guard !launching, PVHelperPolicy.shouldListen(mainRunning: mainRunning, premiereActive: premiereActive) else { unregister(); return }
        guard hotKey == nil else { return }
        let id = EventHotKeyID(signature: 0x5056484B, id: 1)
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr { hotKey = nil }
    }
    private func watchOwnerExit() {
        let app=NSRunningApplication.runningApplications(withBundleIdentifier:ownerID).first {
            !$0.isTerminated && $0.processIdentifier != exitedPID && $0.bundleURL?.resolvingSymlinksInPath()==owner
        }
        guard let app else {ownerExit?.cancel();ownerExit=nil;ownerPID=nil;return}
        let pid=app.processIdentifier
        guard ownerPID != pid else{return}
        ownerExit?.cancel();ownerPID=pid
        let stream=DispatchSource.makeProcessSource(identifier:pid,eventMask:.exit,queue:.main)
        stream.setEventHandler{[weak self] in
            guard let self, self.ownerPID == pid else{return}
            self.exitedPID=pid;self.ownerExit?.cancel();self.ownerExit=nil;self.ownerPID=nil;self.refresh()
        }
        ownerExit=stream;stream.resume()
    }
    private func unregister() { if let hotKey { UnregisterEventHotKey(hotKey) }; hotKey = nil }
    private func pressed() {
        guard !launching, PVHelperPolicy.shouldListen(mainRunning: mainRunning, premiereActive: premiereActive) else { refresh(); return }
        launching = true; unregister()
        let config = NSWorkspace.OpenConfiguration(); config.activates = true; config.addsToRecentItems = false; config.allowsRunningApplicationSubstitution = false
        NSWorkspace.shared.openApplication(at: owner, configuration: config) { [weak self] _, _ in
            Task { @MainActor in self?.launching = false; self?.refresh() }
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        #if PV_HELPER_TESTING
        testEvents?.cancel()
        #endif
        ownerExit?.cancel(); preferencesTask?.cancel(); refreshTask?.cancel(); unregister()
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
