import AppKit
import Darwin

/// Observe system inventory changes, including background launches, without polling.
@MainActor final class PVPremiereLifecycle {
    private(set) var processes = Set<Int32>()
    var onChange: ((Set<Int32>) -> Void)?
    private var observation: NSKeyValueObservation?
    private var exits: [Int32: DispatchSourceProcess] = [:]
    private var tokens: [Int32: UUID] = [:]
    init() {
        synchronize(Self.identifiers(NSWorkspace.shared.runningApplications))
        observation = NSWorkspace.shared.observe(\.runningApplications, options: [.initial, .new]) { [weak self] _, change in
            guard let applications = change.newValue else { return }
            let pids = Self.identifiers(applications)
            Task { @MainActor in self?.synchronize(pids) }
        }
    }
    nonisolated private static func identifiers(_ apps: [NSRunningApplication]) -> Set<Int32> {
        Set(apps.filter { !$0.isTerminated && PVPremiereProcess.matches($0.bundleIdentifier) }.map(\.processIdentifier))
    }
    private func synchronize(_ current: Set<Int32>) {
        let previous = processes
        for pid in processes.subtracting(current) { remove(pid) }
        for pid in current.subtracting(processes) { insert(pid) }
        if previous != processes { onChange?(processes) }
    }
    private func insert(_ pid: Int32) {
        guard pid > 0, Darwin.kill(pid, 0) == 0 || errno != ESRCH, processes.insert(pid).inserted else { return }
        let token = UUID(); tokens[pid] = token
        let stream = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        stream.setEventHandler { [weak self] in
            guard let self, self.tokens[pid] == token else { return }
            self.remove(pid); self.onChange?(self.processes)
        }
        exits[pid] = stream; stream.resume()
    }
    private func remove(_ pid: Int32) {
        processes.remove(pid); tokens.removeValue(forKey: pid); exits.removeValue(forKey: pid)?.cancel()
    }
    func stop() {
        onChange = nil; observation?.invalidate(); observation = nil
        for stream in exits.values { stream.cancel() }; exits.removeAll(); tokens.removeAll(); processes.removeAll()
    }
}
