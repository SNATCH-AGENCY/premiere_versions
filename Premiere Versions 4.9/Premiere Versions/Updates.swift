import SwiftUI
import Foundation
import Combine
#if canImport(Sparkle)
import Sparkle
#endif

nonisolated struct PVUpdateRelease: Equatable, Sendable {
    let version: String
    let build: String
    let minimumSystemVersion: String?
    let download: URL
}

nonisolated enum PVReleaseOrder {
    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        a.compare(b, options: .numeric)
    }
    static func newer(_ item: PVUpdateRelease, version: String, build: String) -> Bool {
        let order = compare(item.version, version)
        return order == .orderedDescending || (order == .orderedSame && compare(item.build, build) == .orderedDescending)
    }
}

/// Read-only metadata parser. Installation and archive validation belong to Sparkle.
nonisolated final class PVAppcastReader: NSObject, XMLParserDelegate {
    private(set) var releases: [PVUpdateRelease] = []
    private var values: [String: String] = [:]
    private var element = ""
    private var inItem = false
    private var sawRSS = false
    private var sawChannel = false
    static func parse(_ data: Data) throws -> [PVUpdateRelease] {
        guard data.count <= 1_048_576 else { throw URLError(.dataLengthExceedsMaximum) }
        let reader = PVAppcastReader(), parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        guard parser.parse(), reader.sawRSS, reader.sawChannel else { throw parser.parserError ?? URLError(.cannotParseResponse) }
        return reader.releases
    }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        element = name
        if name == "rss" { sawRSS = true }
        if name == "channel" { sawChannel = true }
        if name == "item" { inItem = true; values = [:] }
        if name == "enclosure", inItem {
            values["url"] = attributes["url"]
            if let value = attributes["sparkle:version"] { values["sparkle:version"] = value }
            if let value = attributes["sparkle:shortVersionString"] { values["sparkle:shortVersionString"] = value }
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inItem { values[element, default: ""] += string }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard name == "item" else { return }
        inItem = false
        guard let full = values["sparkle:version"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              let version = values["sparkle:shortVersionString"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              let rawURL = values["url"], let url = URL(string: rawURL), url.scheme == "https",
              url.host == "github.com", url.path.hasPrefix("/pewakkk/premiere_versions/releases/download/"),
              full.range(of: #"^\d+(?:\.\d+)*$"#, options: .regularExpression) != nil,
              version.range(of: #"^\d+(?:\.\d+)*$"#, options: .regularExpression) != nil else { return }
        // Feed versions are full version.build so minor releases may reset their displayed build.
        let prefix = version + "."
        let build = full.hasPrefix(prefix) ? String(full.dropFirst(prefix.count)) : full
        releases.append(PVUpdateRelease(version: version, build: build,
                                       minimumSystemVersion: values["sparkle:minimumSystemVersion"]?.trimmingCharacters(in: .whitespacesAndNewlines), download: url))
    }
}

@MainActor final class PVUpdateService: ObservableObject {
    static let shared = PVUpdateService()
    private var automaticTimer: Timer?
    private var lastAttempt: Date?
    private var wakeObserver: NSObjectProtocol?
    nonisolated static let feed = URL(string: "https://raw.githubusercontent.com/pewakkk/premiere_versions/main/docs/appcast.xml")!
    nonisolated static let releases = URL(string: "https://github.com/pewakkk/premiere_versions/releases")!
    @Published private(set) var checking = false
    @Published private(set) var available: PVUpdateRelease?
    @Published private(set) var status = PVL("Обновления ещё не проверялись")
    @Published private(set) var lastCheck: Date?
    private let feedURL: URL
    private let session: URLSession
    private let defaults: UserDefaults
    init(feedURL: URL = PVUpdateService.feed, session: URLSession? = nil, defaults: UserDefaults = .standard) {
        self.feedURL = feedURL
        self.defaults = defaults
        self.lastCheck = defaults.object(forKey: "lastSuccessfulUpdateCheck") as? Date
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieStorage = nil
            config.urlCache = nil
            self.session = URLSession(configuration: config)
        }
    }
    private var task: Task<Void, Never>?
    #if canImport(Sparkle)
    private let relaunchDelegate = PVUpdateRelaunchDelegate()
    private lazy var sparkle = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: relaunchDelegate, userDriverDelegate: nil)
    #endif
    var canInstall: Bool {
        #if canImport(Sparkle)
        return !(Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? "").isEmpty
        #else
        return false
        #endif
    }
    func startAutomaticChecks() {
        guard automaticTimer == nil else { return }
        let timer = Timer(timeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.performCheck(background: true) }
        }
        timer.tolerance = 300
        automaticTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, Date().timeIntervalSince(self.lastAttempt ?? .distantPast) >= 6 * 60 * 60 else { return }
                self.performCheck(background: true)
            }
        }
        performCheck(background: true)
    }
    func check() { performCheck(background: false) }
    private func performCheck(background: Bool) {
        guard !checking else { return }
        checking = true
        lastAttempt = Date()
        if !background { available = nil }
        status = PVL("Проверка обновлений…")
        task = Task {
            defer { checking = false }
            do {
                var request = URLRequest(url: feedURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
                request.setValue("application/xml", forHTTPHeaderField: "Accept")
                let (data, response) = try await session.data(for: request)
                guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                if response.statusCode == 404 { status = PVL("Источник обновлений ещё не опубликован"); return }
                guard response.statusCode == 200 else { throw URLError(.badServerResponse) }
                let items = try PVAppcastReader.parse(data)
                let candidates = items.filter { item in
                    guard let required = item.minimumSystemVersion else { return true }
                    let current = ProcessInfo.processInfo.operatingSystemVersion
                    return PVReleaseOrder.compare(required, "\(current.majorVersion).\(current.minorVersion).\(current.patchVersion)") != .orderedDescending
                }
                available = candidates.filter { PVReleaseOrder.newer($0, version: AppRelease.version, build: AppRelease.build) }
                    .sorted { PVReleaseOrder.newer($0, version: $1.version, build: $1.build) }.first
                let date = Date()
                lastCheck = date
                defaults.set(date, forKey: "lastSuccessfulUpdateCheck")
                if items.isEmpty { status = PVL("Публичных выпусков пока нет") }
                else if candidates.isEmpty { status = PVL("Нет выпусков для этой версии macOS") }
                else { status = available == nil ? PVL("Установлена актуальная версия") : PVL("Доступно обновление") }
            } catch {
                status = PVL("Не удалось проверить обновления: \(error.localizedDescription)")
            }
        }
    }
    func install() {
        guard available != nil, !checking else { return }
        #if canImport(Sparkle)
        guard canInstall else { NSWorkspace.shared.open(Self.releases); return }
        sparkle.startUpdater()
        sparkle.checkForUpdates(nil)
        #else
        NSWorkspace.shared.open(Self.releases)
        #endif
    }
}

struct PVUpdateSettings: View {
    @ObservedObject var service: PVUpdateService
    var showRelease = true
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showRelease { VStack(alignment: .leading, spacing: 4) {
                Text(AppRelease.label).font(.system(size: 12, design: .monospaced))
                Text(PVL("Дата сборки: ") + PVBuildDate.label)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } }
            Button(PVL("Проверить обновления"), action: service.check)
                .buttonStyle(PVQuietButtonStyle()).disabled(service.checking)
            HStack(spacing: 6) {
                if service.available != nil { Circle().fill(Color(red: 0.85, green: 0.43, blue: 0.47)).frame(width: 5, height: 5) }
                Text(PVL(service.available != nil ? "Доступно обновление" : service.status)).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
            }
            Text(PVL("Последняя проверка: ") + (service.lastCheck.map(PVBuildDate.format) ?? "—"))
                .font(.system(size: 10)).foregroundStyle(.secondary)
            if let release = service.available {
                Text(release.version + " · Build " + release.build).font(.system(size: 11, design: .monospaced))
                Button(PVL(service.canInstall ? PVL("Установить и перезапустить") : PVL("Открыть страницу загрузки")), action: service.install)
                    .buttonStyle(PVQuietButtonStyle())
            }
        }
    }
}

nonisolated enum PVBuildDate {
    static var label: String {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "PVBuildDate") as? String,
              let date = ISO8601DateFormatter().date(from: raw) else { return "—" }
        return format(date)
    }
    static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: UserDefaults.standard.string(forKey: "interfaceLanguage") ?? "en")
        formatter.dateStyle = .medium; formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#if canImport(Sparkle)
@MainActor private final class PVUpdateRelaunchDelegate: NSObject, SPUUpdaterDelegate {
    func updaterWillRelaunchApplication(_ updater: SPUUpdater) { PVTerminationContext.updating = true }
}
#endif
