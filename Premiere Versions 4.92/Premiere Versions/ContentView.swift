import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Carbon

struct ContentView: View {
    @AppStorage("windowBackgroundOpacity") private var windowBackgroundOpacity = 1.0
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var backdropOpacity: Double { PVWindowAppearance.opacity(windowBackgroundOpacity, reduceTransparency: reduceTransparency) }
    @AppStorage("showInDock") private var showInDock = false
    @AppStorage("menuBarIconEnabled") private var menuBarIconEnabled = true
    @AppStorage("archivePath")
    private var archivePath = DefaultLocations.versions

    @AppStorage("defaultProjectFolder")
    private var defaultProjectFolder = ""

    @AppStorage("lastProjectFolder")
    private var lastProjectFolder = ""

    @State private var sourceProjectURL: URL?
    @State private var projectName = ""
    @State private var versionNumber = "v001"
    @State private var versionComment = ""
    @State private var statusMessage = PVL("Выбери проект Premiere")
    @State private var isError = false
    @State private var savingVersion = false
    @State private var saveGeneration = UUID()
    @State private var saveTask: Task<Void, Never>?
    @State private var didRestore = false
    private enum Panel: String, Hashable { case settings, backups, shortcut, help, logoEditor }
    @State private var activePanel: Panel?
    @State private var panelProgress = 1.0
    @State private var panelClosing = false
    @State private var panelDismissTask: Task<Void, Never>?
    private var panelStrength: Double { activePanel == nil ? 0 : panelProgress }
    @State private var panelMenuTracking = false
    @State private var panelCentered = false
    @State private var panelRouteSize: CGSize?
    @State private var utilitySize = CGSize(width: 720, height: 540)
    @State private var foldersExpanded = false
    @State private var appearanceExpanded = false
    @State private var languageHovered = false
    @State private var panelHovered = false
    @State private var panelAwaitingEntry = false
    @State private var panelTriggerFrames: [String: CGRect] = [:]
    @State private var panelAnchor = CGPoint(x: 360, y: 270)
    @State private var panelCloseTask: Task<Void, Never>?
    @State private var headerHovered = false
    @State private var visibleWindow = false
    @State private var welcomeID = UUID()
    @State private var editedLogoSlot: String?
    @StateObject private var updates = PVUpdateService.shared
    @AppStorage("interfaceLanguage") private var interfaceLanguage = "en"
    @AppStorage("experimentalHoverPanels") private var experimentalHoverPanels = false
    @State private var hoverRequest = 0
    @State private var hoverIntent: Panel?
    @State private var hoverTask: Task<Void, Never>?
    private var showingSettings: Bool {
        get { activePanel == .settings }
        nonmutating set { if newValue { openPanel(.settings) } else if activePanel == .settings { dismissPanel() } }
    }
    private var showingShortcutEditor: Bool {
        get { activePanel == .shortcut }
        nonmutating set { if newValue { openPanel(.shortcut) } else if activePanel == .shortcut { dismissPanel() } }
    }
    private var showingHelp: Bool {
        get { activePanel == .help }
        nonmutating set { if newValue { openPanel(.help) } else if activePanel == .help { dismissPanel() } }
    }
    private var showingLogoEditor: Bool {
        get { activePanel == .logoEditor }
        nonmutating set { if newValue { openPanel(.logoEditor) } else if activePanel == .logoEditor { dismissPanel() } }
    }
    @State private var showingWelcome = PVWelcomePolicy.needsPresentation()
    @State private var welcomeTransitioning = false
    @State private var welcomeTask: Task<Void, Never>?
    @State private var footerHeight: CGFloat = 50
    @State private var versionFocusRequest = 0
    @StateObject private var userLogos = PVUserLogoLibrary.shared
    @StateObject private var fileIcons = PVFileIconStore.shared
    @State private var visualsActive = false
    @State private var commentStage = false
    @State private var selectingProject = true
    @State private var missingProjectName = ""
    @StateObject private var projectWatcher = PVProjectWatcher()
    @StateObject private var settingsScroll = PVScrollMemory()
    @StateObject private var manualVersions = PVManualVersionIndex()
    @StateObject private var hotKeyHelper = PVHotKeyHelperManager.shared
    @AppStorage("hotKeyHelperEnabled") private var hotKeyHelperEnabled = true
    @State private var confirmDisableHelper = false
    @State private var stageFocusTask: Task<Void, Never>?
    @AppStorage("logoVariant") private var logoVariant = "signature-dark"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Autosave monitor settings. The user grants access to the watched folder
    // and archive destination through NSOpenPanel; bookmarks persist that access.
    @AppStorage("autosaveWatchPath")
    private var autosaveWatchPath = ""

    @AppStorage("autosaveArchivePath")
    private var autosaveArchivePath = DefaultLocations.autosaves

    @AppStorage("autosaveMonitoringEnabled")
    private var autosaveMonitoringEnabled = false

    @State private var backupDetailsExpanded = false
    @AppStorage("backupMode") private var backupMode = "automatic"
    @AppStorage("launchWithPremiere") private var launchWithPremiere = true
    @AppStorage("copyPremiereAutosave") private var copyPremiereAutosave = true
    @AppStorage("searchMode") private var searchMode = "all"

    @EnvironmentObject private var autosaveMonitor: AutosaveMonitor
    @EnvironmentObject private var hotKey: GlobalSaveHotKey

    private enum InputFocus: Hashable {
        case version
        case comment
    }

    @State private var focusedField: InputFocus?
    @FocusState private var commentHasFocus: Bool

    private let fileManager = FileManager.default
    @Environment(\.colorScheme) private var colorScheme
    private var theme: PVTheme { PVTheme(dark: true) }
    private var blue: Color { theme.accent }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if backdropOpacity < 1 {
                    PVFrostedBackdrop().allowsHitTesting(false)
                }
                PVAnimatedBackdrop(active: visualsActive && visibleWindow)
                    .opacity(backdropOpacity)
                    .blur(radius: reduceMotion ? 0 : 3 * panelStrength)
                if showingWelcome {
                    welcomePage
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -60)))
                } else {
                    ZStack {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: 84)
                        projectCard.opacity(selectingProject ? 0 : 1).allowsHitTesting(!selectingProject)
                        stagedComposer
                        Color.clear.frame(height: footerHeight)
                    }
                    .blur(radius: reduceMotion ? 0 : 3 * panelStrength)
                    .opacity(1 - 0.3 * panelStrength)
                    .allowsHitTesting(activePanel == nil && !welcomeTransitioning)
                    VStack(spacing: 0) {
                        header.padding(.top, 28)
                        Spacer(minLength: 0)
                        footer.background {
                            GeometryReader { proxy in
                                Color.clear.preference(key: PVFooterHeight.self, value: proxy.size.height)
                            }
                        }
                    }
                    .blur(radius: reduceMotion ? 0 : 3 * panelStrength)
                    .opacity(1 - 0.3 * panelStrength)
                    .allowsHitTesting(activePanel == nil && !welcomeTransitioning)
                    if let activePanel {
                        Color.clear.contentShape(Rectangle())
                            .onTapGesture { dismissPanel() }
                        panelBody(panel: activePanel, maxHeight: max(260, geometry.size.height - 32))
                            .contentShape(RoundedRectangle(cornerRadius: 18))
                            .onTapGesture { }
                            .onHover { inside in
                                panelHovered = inside
                                if inside { panelAwaitingEntry = false }
                                panelCloseTask?.cancel()
                                if inside && panelClosing {
                                    panelDismissTask?.cancel(); panelClosing = false
                                    withAnimation(.easeInOut(duration: 0.24)) { panelProgress = 1 }
                                } else if !inside && !panelClosing && !panelAwaitingEntry { schedulePanelClose(activePanel) }
                            }
                            .position(panelPosition(for: activePanel, in: geometry.size))
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: backupDetailsExpanded)
                            .compositingGroup()
                            .blur(radius: reduceMotion ? 0 : (1 - panelProgress) * 12)
                            .opacity(panelProgress)
                            .allowsHitTesting(true)
                            .zIndex(2)
                    }
                    }
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 80)))
                }
            }
            .onAppear { utilitySize = geometry.size }
            .onChange(of: geometry.size) { _, size in utilitySize = size }
            .coordinateSpace(name: "PVUtilityContent")
            .onPreferenceChange(PVPanelTriggerFrames.self) { frames in
                panelTriggerFrames = frames.filter { $0.value.width > 0 && $0.value.height > 0 && $0.value.midX.isFinite && $0.value.midY.isFinite }
            }
            .overlay(alignment: .top) { PVWindowDragRegion().frame(height: 26).padding(.horizontal, 80) }
            .onPreferenceChange(PVFooterHeight.self) { footerHeight = $0 }
        }
        .disabled(savingVersion)
        .overlay(alignment: .bottom) {
            if savingVersion { Text(PVL("Сохранение в Premiere Pro…")).font(.system(size: 11)).foregroundStyle(theme.muted).padding(.bottom, 9).allowsHitTesting(false) }
        }
        .ignoresSafeArea()
        .foregroundStyle(theme.ink)
        .tint(theme.accent)
        .preferredColorScheme(.dark)
        .background { PVEscapeCapture(action: handleEscape) }
        .background { PVWindowVisibility(visible: $visibleWindow) }
        .environment(\.locale, Locale(identifier: interfaceLanguage == "ru" ? "ru" : "en"))
        .onReceive(PVPanelNavigation.shared.$request) { request in
            guard let request, let panel = Panel(rawValue: request) else { return }
            PVPanelNavigation.shared.request = nil
            if showingWelcome { PVWelcomePolicy.complete() }
            welcomeTask?.cancel(); showingWelcome = false; welcomeTransitioning = false
            openPanel(panel, centered: true)
        }
        .onChange(of: sourceProjectURL) { _, url in autosaveMonitor.selectProject(url) }
        .onChange(of: backupMode) { _, _ in autosaveMonitor.reconcile() }
        .onChange(of: interfaceLanguage) { _, _ in PremiereBridge.shared.languageChanged() }
        .onChange(of: launchWithPremiere) { _, _ in Task { await hotKeyHelper.syncShortcut() } }
        .onChange(of: hotKey.shortcut) { _, _ in Task { await hotKeyHelper.syncShortcut() } }
        .onChange(of: logoVariant) { _, _ in PVBrand.applySelectedIcon(allowIconAccessPrompt: true) }
        .onChange(of: userLogos.revision) { _, _ in PVBrand.applySelectedIcon(allowIconAccessPrompt: true) }
        .onChange(of: focusedField) { _, target in
            if target == .comment { commentHasFocus = true }
            else if target == .version { commentHasFocus = false }
        }
        .onChange(of: commentHasFocus) { _, focused in
            if focused { focusedField = .comment }
            else if focusedField == .comment { focusedField = nil }
        }
        .onChange(of: activePanel) { _, panel in
            if panel != nil { clearTextFocus() }
            else if panel == nil { restoreComposerFocus() }
        }
        .onDisappear { hoverTask?.cancel(); stageFocusTask?.cancel(); welcomeTask?.cancel(); panelCloseTask?.cancel(); panelDismissTask?.cancel() }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
            if activePanel != nil { panelMenuTracking = true; panelCloseTask?.cancel() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
            panelMenuTracking = false
            if !panelMenuTracking && !panelHovered && !panelAwaitingEntry, let panel = activePanel { schedulePanelClose(panel) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didHideNotification)) { _ in visualsActive = false; stageFocusTask?.cancel(); hoverTask?.cancel(); hoverIntent = nil }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { note in
            if let window = note.object as? NSWindow, window.title.hasPrefix("Premiere Versions") { visualsActive = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            if let window = note.object as? NSWindow, window.title.hasPrefix("Premiere Versions") { visualsActive = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            if let window = note.object as? NSWindow, window.title.hasPrefix("Premiere Versions") {
                visualsActive = false
                if welcomeTransitioning {
                    welcomeTask?.cancel()
                    welcomeTransitioning = false
                    openPanel(.settings)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showVersionSaveWindow)) { note in
            guard !savingVersion else { return }
            visualsActive = true
            guard !showingWelcome, !welcomeTransitioning, !showingShortcutEditor && !showingLogoEditor else { return }
            dismissPanel()
            refreshProjectSelection()
            if note.userInfo?["fromPremiere"] as? Bool == true { chooseActivePremiereProject() }
            commentStage = false
            versionNumber = suggestedVersionNumber() ?? versionNumber
            if !showingLogoEditor { restoreVersionFocus() }
        }
        .onChange(of: archivePath) { _, _ in refreshArchivedVersionNumbers() }
        .onChange(of: projectWatcher.revision) { _, _ in refreshProjectSelection() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if didRestore, NSApp.keyWindow is PVUtilityWindow { refreshProjectSelection() }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in refreshProjectSelection() }
        .onDisappear { projectWatcher.stop() }
        .onAppear {
            guard !didRestore else { return }
            didRestore = true
            visualsActive = NSApp.isActive
            userLogos.reload()
            // Never discard a saved custom choice if its file needs migration or access.
            PVBrand.applySelectedIcon()

            guard !showingWelcome else { return }
            restoreSavedProject()

            selectingProject = sourceProjectURL == nil
            if !selectingProject { DispatchQueue.main.async { restoreComposerFocus() } }
        }
    }

    @ViewBuilder
    private func panelBody(panel: Panel, maxHeight: CGFloat) -> some View {
        let dimensions = panelDimensions(panel, in: utilitySize)
        ZStack {
            theme.panel
            Group {
            switch panel {
            case .settings:
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(PVL("Настройки")).font(.system(size: 20, weight: .medium))
                        Spacer()
                        Button { interfaceLanguage = interfaceLanguage == "ru" ? "en" : "ru" } label: {
                            Text(interfaceLanguage == "ru" ? "Ru" : "En")
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 38, height: 32).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .scaleEffect(languageHovered && !reduceMotion ? 1.10 : 1)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: languageHovered)
                            .onHover { languageHovered = $0 }
                            .help(interfaceLanguage == "ru" ? "Switch to English" : "Переключить на русский")
                            .accessibilityLabel(interfaceLanguage == "ru" ? "Switch to English" : "Переключить на русский")
                    }.padding(.horizontal, 24)
                    PVPersistentScrollView(memory: settingsScroll) {
                        settingsContent
                            .padding(.trailing, 18).padding(.top, 2).padding(.bottom, 16)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(theme.ink).tint(theme.accent).preferredColorScheme(.dark)
                    }.padding(.leading, 24).padding(.trailing, 12)
                }.padding(.vertical, 20)
            case .backups:
                PVPersistentScrollView {
                    VStack(alignment: .leading, spacing: 17) {
                        panelHeading(PVL("Резервные копии"))
                        backupCard
                    }.padding(24).padding(.trailing, 10)
                }.padding(.trailing, 10)
            case .help:
                VStack(alignment: .leading, spacing: 12) {
                    panelHeading("Premiere Versions").padding(.horizontal, 18)
                    PVPersistentScrollView {
                        PVHelpView(replayWelcome: replayWelcome, updates: updates)
                            .padding(.leading, 24).padding(.trailing, 28).padding(.bottom, 20)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(theme.ink).tint(theme.accent).preferredColorScheme(.dark)
                    }.padding(.trailing, 10)
                }.padding(.top, 16)
            case .shortcut:
                PVPersistentScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        panelHeading(PVL("Сочетание клавиш"))
                        ShortcutEditor { dismissPanel() }.environmentObject(hotKey)
                    }.padding(22).padding(.trailing, 10)
                }.padding(.trailing, 10)
            case .logoEditor:
                PVPersistentScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        panelHeading(PVL("Свой цвет"))
                        PVLogoColorEditor(library: userLogos, slot: editedLogoSlot, showsHeading: false, saved: {
                            logoVariant = editedLogoSlot ?? "custom"
                            openLinkedPanel(.settings)
                        }, close: { openLinkedPanel(.settings) })
                    }.padding(.top, 20).padding(.horizontal, 18)
                }.padding(.trailing, 10)
            }
        }
        }
        .frame(width: dimensions.width, height: dimensions.height)
        .modifier(PVFloatingSurface())
        .onExitCommand { dismissPanel() }
    }

    private func panelHeading(_ title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "gearshape").font(.system(size: 14, weight: .regular))
                .frame(width: 36, height: 36).contentShape(Rectangle())
                .onTapGesture { openLinkedPanel(.settings) }
                .onHover { schedulePanel(.settings, hovering: $0, linked: true) }
                .accessibilityLabel(PVL("Вернуться в настройки"))
                .accessibilityAction { openLinkedPanel(.settings) }
            Text(title).font(.system(size: 19, weight: .medium))
            Spacer(minLength: 0)
        }
    }

    private var welcomePage: some View {
        PVWelcomeScreen(ink: theme.ink, muted: theme.muted, visible: visibleWindow, continueAction: finishWelcome).id(welcomeID)
    }

    private func finishWelcome() {
        guard showingWelcome else { return }
        PVWelcomePolicy.complete()
        clearTextFocus()
        restoreSavedProject()
        selectingProject = sourceProjectURL == nil
        welcomeTransitioning = true
        withAnimation(reduceMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 1.15)) { showingWelcome = false }
        welcomeTask?.cancel()
        welcomeTask = Task { @MainActor in
            if !reduceMotion {
                do { try await Task.sleep(nanoseconds: 1_170_000_000) } catch { return }
            }
            welcomeTransitioning = false
            restoreComposerFocus()
        }
    }

    private func openPanel(_ panel: Panel, centered: Bool = false, inherited: Bool = false) {
        let wasOpen = activePanel != nil
        let previousCenter = activePanel.map { panelPosition(for: $0, in: utilitySize) }
        let fromSettings = activePanel == .settings
        panelDismissTask?.cancel()
        panelClosing = false
        if activePanel == .settings && panel != .settings { settingsScroll.closedAt = Date() }
        if panel == .settings && activePanel != .settings { settingsScroll.prepareToOpen() }
        if inherited, let previousCenter {
            if fromSettings || panel == .settings { panelRouteSize = CGSize(width: 510, height: 420) }
            panelAnchor = previousCenter
            panelCentered = false
        } else {
            panelRouteSize = nil
            panelCentered = centered || panel == .logoEditor
        }
        panelHovered = false
        panelAwaitingEntry = centered && !inherited
        panelCloseTask?.cancel()
        panelMenuTracking = false
        if !inherited, let frame = panelTriggerFrames[panel.rawValue] {
            panelAnchor = CGPoint(x: frame.midX, y: frame.midY)
        }
        hoverTask?.cancel()
        hoverIntent = nil
        if !wasOpen { panelProgress = 0 }
        activePanel = panel
        panelDismissTask = Task { @MainActor in
            // Install the surface at zero opacity before starting its reveal.
            do { try await Task.sleep(nanoseconds: 16_000_000) } catch { return }
            guard !Task.isCancelled, activePanel == panel, !panelClosing else { return }
            withAnimation(.easeInOut(duration: reduceMotion ? 0.15 : 0.36)) { panelProgress = 1 }
        }
    }

    private func dismissPanel() {
        guard activePanel != nil, !panelClosing else { return }
        if activePanel == .settings { settingsScroll.closedAt = Date() }
        panelCloseTask?.cancel()
        panelDismissTask?.cancel()
        hoverTask?.cancel()
        hoverIntent = nil
        panelClosing = true
        let duration = reduceMotion ? 0.15 : 0.36
        withAnimation(.easeInOut(duration: duration)) { panelProgress = 0 }
        panelDismissTask = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: UInt64((duration + 0.02) * 1_000_000_000)) } catch { return }
            guard !Task.isCancelled, panelClosing else { return }
            // Keep content, anchor and color intact until the fade has completed.
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) {
                activePanel = nil
                panelClosing = false
                panelHovered = false
                panelMenuTracking = false
            }
        }
    }

    private func openLinkedPanel(_ panel: Panel) {
        hoverRequest &+= 1
        hoverTask?.cancel(); hoverIntent = nil
        panelCloseTask?.cancel()
        guard activePanel != panel || panelClosing else { return }
        openPanel(panel, inherited: true)
    }

    private func schedulePanel(_ panel: Panel, hovering: Bool, linked: Bool = false) {
        guard experimentalHoverPanels else { return }
        if !hovering {
            if hoverIntent == panel { hoverRequest &+= 1; hoverTask?.cancel(); hoverIntent = nil }
            return
        }
        guard !showingWelcome, !welcomeTransitioning, activePanel != panel else { return }
        hoverTask?.cancel()
        hoverRequest &+= 1
        let request = hoverRequest
        hoverIntent = panel
        hoverTask = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: PVPanelTiming.open) } catch { return }
            guard !Task.isCancelled, request == hoverRequest, hoverIntent == panel,
                  !showingWelcome, !welcomeTransitioning else { return }
            if PVPanelInteraction.isScrolling() { schedulePanel(panel, hovering: true, linked: linked); return }
            openPanel(panel, inherited: linked)
        }
    }

    private func panelDimensions(_ panel: Panel, in size: CGSize) -> CGSize {
        let dimensions: CGSize
        let available = size.height - 32
        if let route = panelRouteSize { return CGSize(width: route.width, height: min(route.height, available)) }
        switch panel {
        case .settings: dimensions = CGSize(width: 510, height: min(420, available))
        case .backups: dimensions = CGSize(width: 510, height: min(backupDetailsExpanded ? 420 : 340, available))
        case .help: dimensions = CGSize(width: 440, height: min(420, available))
        case .shortcut: dimensions = CGSize(width: 380, height: min(350, available))
        case .logoEditor: dimensions = CGSize(width: 470, height: min(420, available))
        }
        return dimensions
    }

    private func panelPosition(for panel: Panel, in size: CGSize) -> CGPoint {
        if panelCentered { return CGPoint(x: size.width / 2, y: size.height / 2) }
        return PVPanelPlacement.center(anchor: panelAnchor, dimensions: panelDimensions(panel, in: size), available: size)
    }

    private func pointerIsInsidePanel(_ panel: Panel) -> Bool {
        guard let window = NSApp.windows.first(where: { $0 is PVUtilityWindow && $0.isVisible }), let content = window.contentView else { return false }
        let point = content.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        let local = CGPoint(x: point.x, y: content.isFlipped ? point.y : content.bounds.height - point.y)
        let size = content.bounds.size
        let center = panelPosition(for: panel, in: size)
        let dimensions = panelDimensions(panel, in: size)
        return CGRect(x: center.x - dimensions.width / 2, y: center.y - dimensions.height / 2,
                      width: dimensions.width, height: dimensions.height).contains(local)
    }

    private func schedulePanelClose(_ panel: Panel) {
        guard experimentalHoverPanels else { return }
        panelCloseTask?.cancel()
        panelCloseTask = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: PVPanelTiming.close) } catch { return }
            guard !Task.isCancelled, activePanel == panel, !panelClosing, !panelAwaitingEntry else { return }
            if panelMenuTracking || hotKey.isRecording || PVPanelInteraction.isBusy(window: NSApp.windows.first(where: { $0 is PVUtilityWindow && $0.isVisible })) {
                schedulePanelClose(panel)
            } else if !pointerIsInsidePanel(panel) { dismissPanel() }
        }
    }

    private func returnHome() {
        welcomeTask?.cancel()
        welcomeTransitioning = false
        if showingWelcome { PVWelcomePolicy.complete() }
        showingWelcome = false
        dismissPanel()
        showVersionStage()
    }

    private func handleEscape() {
        if savingVersion {
            saveGeneration = UUID(); saveTask?.cancel(); saveTask = nil; savingVersion = false
            statusMessage = PVL("Создание копии отменено. Premiere может завершить сохранение проекта."); isError = false
            return
        }
        if activePanel != nil { dismissPanel() }
        else if showingWelcome { finishWelcome() }
        else if commentStage { showVersionStage() }
        else { NSApp.hide(nil) }
    }

    private func replayWelcome() {
        dismissPanel()
        clearTextFocus()
        welcomeID = UUID()
        showingWelcome = true
    }

    private func clearTextFocus() {
        stageFocusTask?.cancel()
        focusedField = nil
        commentHasFocus = false
        if NSApp.keyWindow is PVUtilityWindow, let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.isFieldEditor {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }

    private func restoreVersionFocus() {
        guard sourceProjectURL != nil, !selectingProject else { return }
        focusedField = .version
        versionFocusRequest &+= 1
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: returnHome) {
                HStack(spacing: 10) {
                    PVHeaderMark(tint: theme.muted).frame(width: 25, height: 25)
                        .scaleEffect(headerHovered && !reduceMotion ? 1.10 : 1)
                    Text("Premiere Versions").font(.system(size: 12, weight: .medium))
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).help(PVL("На главный экран"))
                .onHover { inside in
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { headerHovered = inside }
                }
            Spacer()
            HStack(spacing: 9) {
                Text(AppRelease.label).font(.system(size: 10, design: .monospaced))
                if updates.available != nil { Circle().fill(Color(red: 0.85, green: 0.43, blue: 0.47)).frame(width: 5, height: 5) }
            }.frame(height: 28).contentShape(Rectangle())
                .help(PVL("Информация о программе"))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(PVL("Информация: ") + AppRelease.label)
                .accessibilityAction { openPanel(.help, centered: true) }
                .modifier(PVPanelTrigger(id: "help"))
                .modifier(PVHoverResponse())
                .onTapGesture { openPanel(.help) }
                .onHover { schedulePanel(.help, hovering: $0) }
                    
            Image(systemName: "gearshape")
                .padding(.leading, 14).frame(width: 40, height: 40).contentShape(Rectangle())
                .help(PVL("Настройки")).accessibilityLabel(PVL("Настройки"))
                .accessibilityAction { openPanel(.settings, centered: true) }
                .modifier(PVPanelTrigger(id: "settings"))
                .modifier(PVHoverResponse())
                .onTapGesture { openPanel(.settings) }
                .onHover { schedulePanel(.settings, hovering: $0) }
                    

        }
        .foregroundStyle(theme.muted)
        .padding(.horizontal, 28).padding(.top, 14).padding(.bottom, 14)
    }

    private var projectCard: some View {
        Button(action: showProjectStage) {
            HStack(spacing: 8) {
                Text(projectName.isEmpty ? PVL("Выбрать проект") : projectName)
                    .font(.system(size: 20, weight: .regular)).lineLimit(1).truncationMode(.middle)
                Image(systemName: "chevron.up").font(.system(size: 11, weight: .light))
            }.padding(.horizontal, 30).padding(.vertical, 14)
                .frame(minWidth: 240).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(sourceProjectURL?.path ?? PVL("Выбрать проект Premiere Pro"))
        .accessibilityLabel(PVL("Текущий проект: ") + (projectName.isEmpty ? PVL("не выбран") : projectName) + PVL(". Изменить проект"))
    }

    private var stagedComposer: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                projectSelectionCard.frame(width: geometry.size.width, height: geometry.size.height)
                    .allowsHitTesting(selectingProject).accessibilityHidden(!selectingProject)
                versionCard.frame(width: geometry.size.width, height: geometry.size.height)
                    .allowsHitTesting(!selectingProject && !commentStage).accessibilityHidden(selectingProject || commentStage)
                commentCard.frame(width: geometry.size.width, height: geometry.size.height)
                    .allowsHitTesting(commentStage).accessibilityHidden(!commentStage)
            }
            .offset(y: selectingProject ? 0 : -(commentStage ? 2 : 1) * geometry.size.height)
            .animation(reduceMotion ? nil : .timingCurve(0.42, 0, 0.35, 1, duration: 0.86), value: commentStage)
        }
        .animation(reduceMotion ? nil : .timingCurve(0.42, 0, 0.35, 1, duration: 0.86), value: selectingProject)
        .clipped()
        .background {
            PVStageScrollCapture(enabled: activePanel == nil && !showingWelcome && !welcomeTransitioning) { direction in
                if selectingProject { if direction > 0 { continueFromProject() } }
                else if direction > 0 && !commentStage { showCommentStage() }
                else if direction < 0 && commentStage { showVersionStage() }
            }
        }
        .overlay {
            GeometryReader { geometry in
                scrollHint.opacity(selectingProject && sourceProjectURL == nil ? 0 : 1)
                    .blur(radius: selectingProject && sourceProjectURL == nil ? 7 : 0)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.55), value: sourceProjectURL)
                    .position(x: geometry.size.width - 42,
                                    y: composerAxis(geometry.size.height, comment: commentStage))
                    .animation(reduceMotion ? nil : .timingCurve(0.42, 0, 0.35, 1, duration: 0.86), value: commentStage)
            }
        }
    }

    private var scrollHint: some View {
        Button { if selectingProject { continueFromProject() } else if commentStage { showVersionStage() } else { showCommentStage() } } label: {
            ZStack {
                Text("SCROLL").fixedSize().rotationEffect(.degrees(-90))
                Image(systemName: "arrow.down")
                    .opacity(commentStage ? 0 : 1)
                    .animation(reduceMotion ? nil : (commentStage ? .easeOut(duration: 0.10) : .easeIn(duration: 0.18).delay(0.56)), value: commentStage)
                    .offset(y: commentStage ? -8 : 48)
                Image(systemName: "arrow.up")
                    .opacity(commentStage ? 1 : 0)
                    .animation(reduceMotion ? nil : (commentStage ? .easeIn(duration: 0.18).delay(0.56) : .easeOut(duration: 0.10)), value: commentStage)
                    .offset(y: commentStage ? -48 : 8)
            }
            .font(.system(size: 13, weight: .light))
            .foregroundStyle(theme.muted.opacity(0.55))
            .frame(width: 28, height: 132).contentShape(Rectangle())
            .animation(reduceMotion ? nil : .timingCurve(0.42, 0, 0.35, 1, duration: 0.86), value: commentStage)
        }
        .buttonStyle(.plain)
        .disabled(activePanel != nil || sourceProjectURL == nil)
        .accessibilityLabel(commentStage ? PVL("Прокрутить вверх к версии") : PVL("Прокрутить вниз к комментарию"))
    }

    private func composerAxis(_ height: CGFloat, comment: Bool) -> CGFloat {
        height / 2 - 20 + (comment ? 18 : 0)
    }

    private var projectSelectionCard: some View {
        GeometryReader { geometry in
            let axis = composerAxis(geometry.size.height, comment: false)
            ZStack {
                if sourceProjectURL == nil && !missingProjectName.isEmpty {
                    Text(PVL("Проект недоступен")).font(.system(size: 12, weight: .light)).foregroundStyle(theme.muted)
                        .position(x: geometry.size.width / 2, y: axis - 52)
                }
                Text(sourceProjectURL == nil ? (missingProjectName.isEmpty ? PVL("Выбери проект") : missingProjectName) : projectName)
                    .font(.system(size: 38, weight: .light)).lineLimit(2).multilineTextAlignment(.center)
                    .frame(maxWidth: geometry.size.width - 120)
                    .position(x: geometry.size.width / 2, y: axis)
                if sourceProjectURL == nil && missingProjectName.isEmpty {
                    Text(PVL("файл .prproj")).font(.system(size: 13, weight: .light)).foregroundStyle(theme.muted.opacity(0.55))
                        .position(x: geometry.size.width / 2, y: axis + 42)
                }
                Button(action: chooseProject) {
                    Label(sourceProjectURL == nil ? PVL("Выбрать файл") : PVL("Другой проект"), systemImage: "folder")
                        .font(.system(size: 13, weight: .light))
                }.buttonStyle(.plain).position(x: geometry.size.width / 2, y: axis + (sourceProjectURL == nil ? 88 : 54))
                Button(action: continueFromProject) {
                    Text("press return").font(.system(size: 13, weight: .light)).foregroundStyle(theme.muted.opacity(0.55))
                }.buttonStyle(.plain).keyboardShortcut(.defaultAction)
                    .disabled(sourceProjectURL == nil || !selectingProject)
                    .opacity(sourceProjectURL == nil ? 0 : 1).blur(radius: sourceProjectURL == nil ? 8 : 0)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.55), value: sourceProjectURL)
                    .position(x: geometry.size.width / 2, y: axis + 88)
            }.foregroundStyle(theme.ink)
        }
    }
    private func showProjectStage() {
        clearTextFocus(); refreshProjectSelection()
        commentStage = false; selectingProject = true
    }
    private func continueFromProject() {
        guard selectingProject, validateCurrentProject() else { return }
        selectingProject = false; commentStage = false; scheduleStageFocus()
    }
    private func refreshProjectSelection() {
        let wasSelected = sourceProjectURL != nil
        let number = versionNumber
        restoreSavedProject()
        if sourceProjectURL == nil {
            projectWatcher.stop(); selectingProject = true; commentStage = false; clearTextFocus()
        } else if wasSelected { versionNumber = number }
    }
    private func validateCurrentProject() -> Bool {
        refreshProjectSelection()
        return sourceProjectURL != nil
    }

    private var versionCard: some View {
        GeometryReader { geometry in
            let axis = composerAxis(geometry.size.height, comment: false)
            ZStack {
            PVVersionInput(text: $versionNumber,
                           isFocused: focusedField == .version && !selectingProject && !commentStage,
                           focusRequest: versionFocusRequest,
                           enabled: sourceProjectURL != nil,
                           color: NSColor(theme.ink),
                           fontSize: 82, caret: NSColor(theme.accent), centered: true,
                           focused: { focusedField = .version },
                           blurred: { if focusedField == .version { focusedField = nil } },
                           submitted: showCommentStage)
                .frame(width: min(400, max(100, (versionNumber as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 82, weight: .light)]).width + 8)), height: 108)
                .overlay(alignment: .leading) {
                    HStack(spacing: 9) {
                        PVAxisLabel(text: previousVersionLabel, color: NSColor(theme.muted))
                        Image(systemName: "arrow.right").font(.system(size: 13, weight: .light))
                    }
                    .font(.system(size: 16, weight: .light)).foregroundStyle(theme.muted)
                    .fixedSize()
                    .alignmentGuide(.leading) { $0[.trailing] + 24 }
                    .allowsHitTesting(false)
                    .accessibilityLabel(PVL("Прошлая версия: ") + previousVersionLabel)
                }
                .accessibilityLabel(PVL("Следующая версия"))
                .position(x: geometry.size.width / 2, y: axis)
                Button(action: showCommentStage) {
                    Text("press return").font(.system(size: 13, weight: .light))
                        .foregroundStyle(theme.muted.opacity(0.55))
                }.buttonStyle(.plain).disabled(sourceProjectURL == nil)
                    .position(x: geometry.size.width / 2, y: axis + 74)
            }
        }
    }

    private var commentCard: some View {
        GeometryReader { geometry in
            let axis = composerAxis(geometry.size.height, comment: true)
            ZStack {
                Text(versionNumber).font(.system(size: 16, weight: .light)).foregroundStyle(theme.muted)
                    .position(x: geometry.size.width / 2, y: axis - 72)
            PVVersionInput(text: $versionComment,
                           isFocused: focusedField == .comment && commentStage,
                           focusRequest: versionFocusRequest,
                           enabled: sourceProjectURL != nil,
                           color: NSColor(theme.ink),
                           fontSize: 48, caret: NSColor(theme.accent), centered: false,
                           placeholder: "comment", accessibilityTitle: PVL("Комментарий к версии, необязательно"),
                           focused: { focusedField = .comment },
                           blurred: { if focusedField == .comment { focusedField = nil } },
                           submitted: createVersion)
                .frame(width: min(540, max(32, ((versionComment.isEmpty ? "comment" : versionComment) as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 48, weight: .light)]).width + 6))).frame(height: 88)
                .position(x: geometry.size.width / 2, y: axis)
                Button(action: createVersion) {
                    Text("press return to save").font(.system(size: 13, weight: .light))
                        .foregroundStyle(theme.muted.opacity(0.55))
                }.buttonStyle(.plain).disabled(sourceProjectURL == nil)
                    .position(x: geometry.size.width / 2, y: axis + 64)
            }
        }
        .overlay(alignment: .bottomLeading) {
            Button(action: showVersionStage) { Text("← version").font(.system(size: 12, weight: .light)) }
                .buttonStyle(.plain).foregroundStyle(theme.muted).padding(.leading, 30).padding(.bottom, 12)
        }
    }

    private func showCommentStage() {
        guard validateCurrentProject(), !selectingProject, !commentStage else { return }
        let trimmed = versionNumber.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.range(of: #"^v\d{3,}$"#, options: .regularExpression) != nil else {
            statusMessage = PVL("Номер версии должен быть в формате v008")
            isError = true
            restoreVersionFocus()
            return
        }
        versionNumber = trimmed
        isError = false
        clearTextFocus()
        commentStage = true
        scheduleStageFocus()
    }

    private func showVersionStage() {
        clearTextFocus()
        selectingProject = sourceProjectURL == nil
        commentStage = false
        scheduleStageFocus()
    }

    private func scheduleStageFocus() {
        stageFocusTask?.cancel()
        stageFocusTask = Task { @MainActor in
            if !reduceMotion {
                do { try await Task.sleep(nanoseconds: 880_000_000) } catch { return }
            }
            guard activePanel == nil, !showingWelcome else { return }
            restoreComposerFocus()
        }
    }

    private func restoreComposerFocus() {
        guard sourceProjectURL != nil, !selectingProject, activePanel == nil, !showingWelcome else { return }
        focusedField = commentStage ? .comment : .version
        versionFocusRequest &+= 1
    }

    private var needsSearchAccess: Bool {
        UserDefaults.standard.data(forKey: searchMode == "folder" ? "autosaveWatchBookmark" : "computerSearchBookmark") == nil || UserDefaults.standard.data(forKey: "autosaveArchiveBookmark") == nil
    }

    private var needsArchiveAccess: Bool {
        UserDefaults.standard.data(forKey: "autosaveArchiveBookmark") == nil || UserDefaults.standard.data(forKey: "archiveBookmark") == nil
    }

    private var backupProblem: PVBackupIssue? {
        if needsArchiveAccess { return .archiveAccess }
        if needsSearchAccess { return .searchAccess }
        return autosaveMonitor.issue
    }
    private var compactBackupStatus: String {
        if let problem = backupProblem { return PVL(problem.title) }
        if autosaveMonitor.isScanning { return PVL("Создаём копию…") }
        if autosaveMonitor.manualCopyUnchanged { return PVL("Изменений нет — копия актуальна") }
        if backupMode == "off" { return PVL("Резервирование выключено") }
        if backupMode == "automatic", !autosaveMonitor.premiereRunning { return PVL("Ожидание запуска Premiere Pro") }
        return PVL("Резервирование работает")
    }
    private var backupCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text(PVL("Режим")).font(.system(size: 12)).foregroundStyle(theme.muted)
                Spacer()
                HStack(spacing: 2) {
                    ForEach(PVBackupMode.allCases, id: \.rawValue) { mode in
                        Button { backupMode = mode.rawValue } label: {
                            Text(PVL(mode.title)).font(.system(size: 12, weight: backupMode == mode.rawValue ? .medium : .regular))
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                .background { if backupMode == mode.rawValue { RoundedRectangle(cornerRadius: 9).fill(theme.accent.opacity(0.40)) } }
                        }.buttonStyle(.plain)
                            .accessibilityAddTraits(backupMode == mode.rawValue ? .isSelected : [])
                    }
                }.padding(3).background(RoundedRectangle(cornerRadius: 12).fill(theme.ink.opacity(0.045)))
            }
            HStack(alignment: .top, spacing: 10) {
                Circle().fill(backupProblem != nil ? Color(red: 0.86, green: 0.68, blue: 0.73) : autosaveMonitor.isMonitoring ? theme.mint : theme.muted.opacity(0.5))
                    .frame(width: 7, height: 7).padding(.top, 5)
                VStack(alignment: .leading, spacing: 5) {
                    Text(compactBackupStatus).font(.system(size: 14, weight: .medium))
                    Text(PVL(backupMode == "automatic" ? "Пока открыт Premiere Pro" : backupMode == "always" ? "Пока работает Premiere Versions" : "Ручное создание копий доступно"))
                        .font(.system(size: 11)).foregroundStyle(theme.muted)
                    if let problem = backupProblem {
                        Button(PVL(problem == .searchAccess || problem == .archiveAccess ? "Разрешить доступ" : problem == .sourceMissing ? "Выбрать проект" : "Проверить снова")) {
                                    switch problem {
                            case .searchAccess: if searchMode == "folder" { chooseAutosaveWatchFolder() } else { autosaveMonitor.authorizeComputer() }
                            case .archiveAccess: autosaveMonitor.authorizeArchives()
                            case .sourceMissing: dismissPanel(); chooseProject()
                            default: autosaveMonitor.checkNow()
                            }
                        }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(theme.accent)
                    }
                }
            }
            HStack(spacing: 9) {
                Image(systemName: "clock").font(.system(size: 13))
                if sourceProjectURL == nil {
                    Text(PVL("Выбери проект, чтобы увидеть его последнюю копию"))
                } else if let latest = autosaveMonitor.latestBackup {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        Text(PVL("Последняя копия проекта — ") + PVBackupRelativeTime.label(latest.captured, now: context.date))
                    }
                } else { Text(PVL("У этого проекта пока нет резервных копий")) }
            }.font(.system(size: 11)).foregroundStyle(theme.muted)
                .help(PVL("Если проект не менялся, одинаковые копии не создаются"))
            HStack(spacing: 12) {
                Button { autosaveMonitor.checkNow() } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "square.and.arrow.down")
                        Text(PVL(autosaveMonitor.isScanning ? "Создаём копию…" : "Создать копию сейчас"))
                        Spacer(minLength: 0)
                    }.frame(maxWidth: .infinity)
                }.buttonStyle(PVQuietButtonStyle()).disabled(autosaveMonitor.isScanning || sourceProjectURL == nil || needsArchiveAccess)
                Button { autosaveMonitor.revealLatest() } label: { Image(systemName: "folder") }
                    .buttonStyle(PVQuietButtonStyle()).disabled(autosaveMonitor.latestBackup == nil)
                    .help(PVL("Показать последнюю копию")).accessibilityLabel(PVL("Показать последнюю копию"))
            }
            PVHoverSection(title: PVL("Подробнее"), symbol: "", expanded: $backupDetailsExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(PVL("\(BackupPolicy.recentCount) недавних состояний · \(BackupPolicy.hourlyHours) часовых · \(BackupPolicy.dailyDays) дневных"))
                        .font(.system(size: 10)).foregroundStyle(theme.muted)
                    Toggle(PVL("Копировать последний автосейв Premiere"), isOn: $copyPremiereAutosave)
                        .toggleStyle(PVSwitchStyle()).font(.system(size: 11))
                    Button(PVL("Открыть весь архив"), action: openAutosaveArchive)
                        .buttonStyle(PVQuietButtonStyle())
                }
            }

        }
    }

    private func openAutosaveArchive() {
        do {
            let url = try resolveBookmark(forKey: "autosaveArchiveBookmark")
            try withScopedAccess(to: url) {
                if !NSWorkspace.shared.open(url) { autosaveMonitor.status = PVL("Не удалось открыть архив") }
            }
        } catch {
            autosaveMonitor.status = PVL("Сначала разреши доступ к папке архива")
        }
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Toggle(PVL("Работа в фоне"), isOn: Binding(get: { hotKeyHelperEnabled }, set: { value in
                    if value { Task { await hotKeyHelper.enable(true) } }
                    else { confirmDisableHelper = true }
                })).toggleStyle(PVSwitchStyle())
                Text(PVL(hotKeyHelperEnabled ? "После завершения продолжает работать в строке меню" : "Завершение программы отключает все фоновые функции"))
                    .font(.system(size: 10)).foregroundStyle(theme.muted)
                HStack(spacing: 8) {
                    Text(PVL("Значок программы")).font(.system(size: 11))
                    Spacer()
                    visibilityChoice("Dock", selected: showInDock) {
                        if !showInDock || menuBarIconEnabled { showInDock.toggle() }
                    }
                    visibilityChoice(PVL("Строка меню"), selected: menuBarIconEnabled) {
                        if !menuBarIconEnabled || showInDock { menuBarIconEnabled.toggle() }
                    }
                }.padding(.top, 5)
            }
            .alert(PVL("Отключить работу в фоне?"), isPresented: $confirmDisableHelper) {
                Button(PVL("Отмена"), role: .cancel) { }
                Button(PVL("Подтвердить"), role: .destructive) { Task { await hotKeyHelper.enable(false) } }
            } message: { Text(PVL("После завершения резервирование и горячая клавиша будут недоступны до ручного запуска программы.")) }
            Toggle(PVL("Запускать с Premiere Pro"), isOn: $launchWithPremiere)
                .toggleStyle(PVSwitchStyle()).disabled(!hotKeyHelperEnabled)
            if hotKeyHelper.needsApproval {
                Button(PVL("Разрешить в macOS")) { hotKeyHelper.openApproval() }.buttonStyle(PVQuietButtonStyle())
            }
            if !hotKeyHelper.message.isEmpty && (!hotKeyHelper.enabled || hotKeyHelper.needsApproval) {
                Text(PVL(hotKeyHelper.message)).font(.system(size: 10)).foregroundStyle(theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider().overlay(theme.border)
            settingsDestination(.backups, title: PVL("Резервные копии"), symbol: "externaldrive", detail: PVL((PVBackupMode(rawValue: backupMode) ?? .automatic).title))
            settingsDestination(.shortcut, title: PVL("Сочетание клавиш"), symbol: "keyboard", detail: hotKey.shortcut.display)
            settingsDestination(.help, title: PVL("Обновления"), symbol: "arrow.down", detail: updates.available == nil ? "" : PVL("Доступно"))
            Divider().overlay(theme.border)
            PVHoverSection(title: PVL("Расположение папок"), symbol: "folder", expanded: $foldersExpanded) { locationSettings }
            PVHoverSection(title: PVL("Внешний вид"), symbol: "paintbrush", expanded: $appearanceExpanded) { appearanceSettings }
            Divider().overlay(theme.border)
            Toggle(PVL("Открывать окна при наведении · экспериментально"), isOn: $experimentalHoverPanels)
                .toggleStyle(PVSwitchStyle()).font(.system(size: 10))
        }.font(.system(size: 12))
    }

    private func visibilityChoice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 10, weight: selected ? .medium : .regular))
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(Capsule().fill(theme.accent.opacity(selected ? 0.25 : 0.04)))
                .contentShape(Capsule())
        }.buttonStyle(.plain).accessibilityValue(PVL(selected ? "Выбрано" : "Не выбрано"))
    }

    private func settingsDestination(_ panel: Panel, title: String, symbol: String, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).frame(width: 17)
            Text(title)
            Spacer()
            if panel == .help && updates.available != nil { Circle().fill(Color(red: 0.85, green: 0.43, blue: 0.47)).frame(width: 5, height: 5) }
            Text(detail).font(.system(size: 10)).foregroundStyle(theme.muted)
            Image(systemName: "chevron.right").font(.system(size: 9, weight: .light))
        }.frame(minHeight: 32).contentShape(Rectangle())
            .modifier(PVHoverResponse())
            .onTapGesture { openLinkedPanel(panel) }
            .onHover { schedulePanel(panel, hovering: $0, linked: true) }
            .accessibilityElement(children: .combine)
            .accessibilityAction { openLinkedPanel(panel) }
    }

    private var locationSettings: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(PVL("Где искать проекты")).font(.system(size: 11))
                Spacer()
                visibilityChoice(PVL("Все диски"), selected: searchMode == "all") { searchMode = "all" }
                visibilityChoice(PVL("Папка"), selected: searchMode == "folder") { searchMode = "folder" }
            }.onChange(of: searchMode) { _, _ in autosaveMonitor.configurationChanged() }
            if searchMode == "folder" {
                settingPathRow(title: PVL("Папка поиска"), path: autosaveWatchPath.isEmpty ? PVL("Не выбрана") : autosaveWatchPath,
                    buttonTitle: PVL("Изменить…"), action: chooseAutosaveWatchFolder)
            }
            settingPathRow(title: PVL("Куда сохранять версии"), path: archivePath, buttonTitle: PVL("Изменить…"), action: chooseArchiveFolder)
            settingPathRow(title: PVL("Куда сохранять автосейвы"), path: autosaveArchivePath, buttonTitle: PVL("Изменить…"), action: chooseAutosaveArchiveFolder)
        }
    }

    private var appearanceSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(PVL("Непрозрачность фона")).font(.system(size: 11))
                Spacer()
                Text("\(Int((backdropOpacity * 100).rounded()))%").font(.system(size: 10, design: .monospaced)).foregroundStyle(theme.muted)
            }
            Slider(value: Binding(get: { PVWindowAppearance.opacity(windowBackgroundOpacity) }, set: { windowBackgroundOpacity = $0 }), in: 0.15...1)
                .controlSize(.small).tint(theme.muted).disabled(reduceTransparency).accessibilityLabel(PVL("Непрозрачность фона"))
            if reduceTransparency { Text(PVL("В macOS включено уменьшение прозрачности")).font(.system(size: 10)).foregroundStyle(theme.muted) }
            Text(PVL("Значок Dock")).font(.system(size: 12, weight: .medium))
            logoChoices
            persistentIconAccess
            if let notice = userLogos.storageNotice {
                Text(PVL(notice)).font(.system(size: 10)).foregroundStyle(theme.muted)
                Button(PVL("Восстановить прежний значок…")) { userLogos.importLegacyFolder() }.buttonStyle(PVQuietButtonStyle())
            }
        }
    }

    @ViewBuilder
    private var persistentIconAccess: some View {
        if let notice = fileIcons.notice {
            VStack(alignment: .leading, spacing: 8) {
                Text(PVL(notice)).font(.system(size: 11)).foregroundStyle(theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button(PVL("Разрешить")) {
                    if let image = userLogos.image(for: logoVariant) { fileIcons.authorizeAndApply(image) }
                }
                .buttonStyle(PVQuietButtonStyle())
                .disabled(fileIcons.isApplying)
            }
        }
    }

    private var availableLogoIDs: [String] {
        var ids = PVBrand.variants.map(\.id)
        if userLogos.currentImage != nil { ids.append("custom") }
        if userLogos.previousImage != nil { ids.append("previous") }
        return ids
    }

    private func logoTitle(_ id: String) -> String {
        if id == "custom" { return PVL("Пользовательский цвет") }
        if id == "previous" { return PVL("Предыдущий пользовательский цвет") }
        return PVL(PVBrand.variants.first(where: { $0.id == id })?.title ?? PVL("Логотип"))
    }

    private var logoChoices: some View {
        let builtins = PVBrand.variants.map(\.id).filter { $0 != logoVariant }
        let columns = builtins.count > 6 ? 4 : 3
        let width: CGFloat = columns == 4 ? 44 : 56
        return HStack(spacing: 16) {
            Group { if let image = userLogos.image(for: logoVariant) { Image(nsImage: image).resizable().scaledToFit() } }
                .frame(width: 128, height: 128)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(width), spacing: 8), count: columns), spacing: 12) {
                ForEach(builtins, id: \.self) { id in logoOption(id, width: width) }
            }.frame(width: CGFloat(columns) * width + CGFloat(columns - 1) * 8, height: 128)
            Rectangle().fill(theme.border).frame(width: 1, height: 122)
            VStack(spacing: 12) {
                logoOption("custom", width: width)
                logoOption("previous", width: width)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func logoOption(_ id: String, width: CGFloat) -> some View {
        let custom = ["custom", "previous"].contains(id)
        let image = userLogos.image(for: id)
        return ZStack(alignment: .topTrailing) {
            Button {
                if custom && (image == nil || logoVariant == id) {
                    editedLogoSlot = id; openLinkedPanel(.logoEditor)
                } else { logoVariant = id }
            } label: {
                Group {
                    if let image { Image(nsImage: image).resizable().scaledToFit() }
                    else { Image(systemName: "pencil").font(.system(size: 22, weight: .light)).foregroundStyle(theme.muted.opacity(0.65)) }
                }.frame(width: width, height: 58)
                    .overlay {
                        if custom { RoundedRectangle(cornerRadius: 11).strokeBorder(theme.border, style: StrokeStyle(lineWidth: 1, dash: image == nil ? [4, 4] : [])) }
                    }
            }.buttonStyle(.plain).accessibilityLabel(custom && image == nil ? PVL("Создать свой значок") : logoTitle(id))
            if custom && image != nil {
                Button {
                    do {
                        try userLogos.remove(slot: id)
                        if logoVariant == id { logoVariant = "signature-dark" }
                    } catch { statusMessage = error.localizedDescription; isError = true }
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(theme.muted, theme.panel)
                }.buttonStyle(.plain).offset(x: 4, y: -4).accessibilityLabel(PVL("Удалить пользовательский значок"))
            }
        }.frame(width: width, height: 58)
    }

    private func settingPathRow(
        title: String,
        path: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Button(buttonTitle, action: action)
                    .buttonStyle(PVQuietButtonStyle())
                    .controlSize(.small)
            }
            Text(path)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if isError {
                Label(PVL(statusMessage), systemImage: "exclamationmark.circle")
                    .font(.system(size: 12)).foregroundStyle(Color(red: 1, green: 0.72, blue: 0.76))
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            if PVL(hotKey.status).localizedCaseInsensitiveContains(PVL("недоступно")) || PVL(hotKey.status).localizedCaseInsensitiveContains(PVL("не удалось")) {
                Text(PVL(hotKey.status)).font(.system(size: 11)).foregroundStyle(theme.muted)
            }
            HStack {
                Label(compactBackupStatus,
                      systemImage: needsSearchAccess || needsArchiveAccess ? "exclamationmark.circle" : "checkmark.circle")
                    .font(.system(size: 11, weight: .regular))
                    .contentShape(Rectangle())
                    .modifier(PVPanelTrigger(id: "backups"))
                .modifier(PVHoverResponse())
                .onTapGesture { openPanel(.backups) }
                .onHover { schedulePanel(.backups, hovering: $0) }
                    
                    .accessibilityAction { openPanel(.backups, centered: true) }
                    .help(PVL(autosaveMonitor.status) + PVL("\nОткрыть резервное копирование"))
                Spacer()
                Text(hotKey.shortcut.display).font(.system(size: 12, weight: .light))
                    .frame(minWidth: 40, minHeight: 40)
                    .contentShape(Rectangle()).help(PVL("Изменить сочетание клавиш"))
                    .accessibilityAction { openPanel(.shortcut, centered: true) }
                    .modifier(PVPanelTrigger(id: "shortcut"))
                .modifier(PVHoverResponse())
                .onTapGesture { openPanel(.shortcut) }
                .onHover { schedulePanel(.shortcut, hovering: $0) }
                    

            }
        }
        .foregroundStyle(theme.muted)
        .padding(.horizontal, 28).padding(.top, 12).padding(.bottom, 24)
    }

    private var nextVersionLabel: String {
        guard sourceProjectURL != nil else { return "—" }
        return suggestedVersionNumber() ?? PVL("Недоступна")
    }

    // MARK: - Security-scoped bookmarks

    private func makeBookmark(for url: URL, key: String) throws {
        let data = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(data, forKey: key)
    }

    private func resolveBookmark(forKey key: String) throws -> URL {
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
            try makeBookmark(for: url, key: key)
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

    // MARK: - Project restore / selection

    private func restoreSavedProject() {
        guard UserDefaults.standard.data(forKey: "savedProjectBookmark") != nil else {
            statusMessage = PVL("Выбери проект Premiere")
            return
        }

        do {
            let url = try resolveBookmark(forKey: "savedProjectBookmark")
            try withScopedAccess(to: url) {
                guard fileManager.fileExists(atPath: url.path), fileManager.isReadableFile(atPath: url.path),
                      (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                    throw NSError(
                        domain: "PremiereVersions",
                        code: 11,
                        userInfo: [NSLocalizedDescriptionKey: PVL("Сохранённый проект не найден.")]
                    )
                }
            }

            sourceProjectURL = url
            projectWatcher.watch(url)
            lastProjectFolder = url.deletingLastPathComponent().path
            UserDefaults.standard.set(url.lastPathComponent, forKey: "lastProjectName")
            missingProjectName = ""
            projectName = url.deletingPathExtension().lastPathComponent
            refreshArchivedVersionNumbers()
            versionNumber = suggestedVersionNumber() ?? "v001"
            statusMessage = PVL("Последний проект восстановлен")
            isError = false
        } catch {
            missingProjectName = projectName.isEmpty ? (UserDefaults.standard.string(forKey: "lastProjectName") ?? "") : projectName
            sourceProjectURL = nil
            manualVersions.invalidate()
            projectName = ""
            statusMessage = PVL("Выбери проект Premiere")
            isError = false
        }
    }

    private func chooseActivePremiereProject() {
        let original = sourceProjectURL
        Task { @MainActor in
            do {
                let url = try await PremiereBridge.shared.inspectActiveProject()
                guard !savingVersion, sourceProjectURL == original else { return }
                let key = searchMode == "folder" ? "autosaveWatchBookmark" : "computerSearchBookmark"
                let root = try resolveBookmark(forKey: key)
                try withScopedAccess(to: root) {
                    guard fileManager.isReadableFile(atPath: url.path) else { throw PremiereBridge.Failure(message: "Cannot access active Premiere project") }
                    try makeBookmark(for: url, key: "savedProjectBookmark")
                }
                restoreSavedProject()
                selectingProject = false
                restoreVersionFocus()
            } catch {
                guard !savingVersion, sourceProjectURL == original else { return }
                sourceProjectURL = nil; projectName = ""; selectingProject = true
                isError = true; statusMessage = PVL("Не удалось выбрать активный проект Premiere. Выбери файл вручную.")
            }
        }
    }

    private func chooseProject() {
        panelMenuTracking = true
        clearTextFocus()
        defer { restoreComposerFocus() }
        let panel = NSOpenPanel()
        panel.title = PVL("Выбрать проект Premiere")
        panel.message = PVL("Выбери файл .prproj")
        panel.allowedContentTypes = [UTType(filenameExtension: "prproj") ?? .data]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        let startPath = !lastProjectFolder.isEmpty ? lastProjectFolder :
            (!defaultProjectFolder.isEmpty ? defaultProjectFolder : DefaultLocations.home.appendingPathComponent("Desktop").path)

        let startURL = URL(fileURLWithPath: startPath, isDirectory: true)
        panel.directoryURL = PVProjectLocation.nearestFolder(to: startURL)

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            // The panel grants access to the selected file. Save a bookmark for that file,
            // not for its parent directory (the latter is not separately authorized).
            try withScopedAccess(to: url) {
                try makeBookmark(for: url, key: "savedProjectBookmark")
            }

            sourceProjectURL = url
            projectWatcher.watch(url)
            lastProjectFolder = url.deletingLastPathComponent().path
            UserDefaults.standard.set(url.lastPathComponent, forKey: "lastProjectName")
            missingProjectName = ""
            commentStage = false
            versionComment = ""
            projectName = url.deletingPathExtension().lastPathComponent
            refreshArchivedVersionNumbers()
            versionNumber = suggestedVersionNumber() ?? "v001"
            statusMessage = PVL("Проект выбран и сохранён для следующего запуска")
            isError = false
        } catch {
            sourceProjectURL = nil
            manualVersions.invalidate()
            projectName = ""
            statusMessage = PVL("Не удалось сохранить доступ к проекту: \(error.localizedDescription)")
            isError = true
        }
    }

    // MARK: - Folder selection

    private func chooseArchiveFolder() {
        panelMenuTracking = true
        let panel = NSOpenPanel()
        panel.title = PVL("Выбрать папку архива")
        panel.message = PVL("Выбери корневую папку Premiere_Versions")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        let current = URL(fileURLWithPath: archivePath, isDirectory: true)
        if fileManager.fileExists(atPath: current.path) {
            panel.directoryURL = current
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try withScopedAccess(to: url) {
                try makeBookmark(for: url, key: "archiveBookmark")
            }
            archivePath = url.path
            autosaveMonitor.configurationChanged()
            statusMessage = PVL("Папка архива и доступ сохранены")
            isError = false
        } catch {
            statusMessage = PVL("Не удалось сохранить доступ к архиву: \(error.localizedDescription)")
            isError = true
        }
    }

    private func chooseDefaultProjectFolder() {
        panelMenuTracking = true
        let panel = NSOpenPanel()
        panel.title = PVL("Папка проекта по умолчанию")
        panel.message = PVL("Эта папка будет открываться при выборе проекта")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        let startPath = !defaultProjectFolder.isEmpty ? defaultProjectFolder :
            (!lastProjectFolder.isEmpty ? lastProjectFolder : DefaultLocations.home.appendingPathComponent("Desktop").path)
        let startURL = URL(fileURLWithPath: startPath, isDirectory: true)
        panel.directoryURL = PVProjectLocation.nearestFolder(to: startURL)

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try withScopedAccess(to: url) {
                try makeBookmark(for: url, key: "defaultProjectFolderBookmark")
            }
            defaultProjectFolder = url.path
            statusMessage = PVL("Папка по умолчанию сохранена")
            isError = false
        } catch {
            statusMessage = PVL("Не удалось сохранить папку: \(error.localizedDescription)")
            isError = true
        }
    }

    // MARK: - Autosave monitoring

    private func chooseAutosaveWatchFolder() {
        panelMenuTracking = true
        chooseAutosaveFolder(
            title: PVL("Папка наблюдения"),
            message: PVL("Выбери папку, внутри которой Premiere хранит проекты и Adobe Premiere Pro Auto-Save"),
            bookmarkKey: "autosaveWatchBookmark"
        ) { url in
            autosaveWatchPath = url.path
            autosaveMonitor.status = PVL("Папка наблюдения выбрана")
        }
    }

    private func chooseAutosaveArchiveFolder() {
        panelMenuTracking = true
        chooseAutosaveFolder(
            title: PVL("Архив автосейвов"),
            message: PVL("Выбери папку, куда копировать резервные автосейвы"),
            bookmarkKey: "autosaveArchiveBookmark"
        ) { url in
            autosaveArchivePath = url.path
            autosaveMonitor.status = PVL("Папка архива автосейвов выбрана")
        }
    }

    private func chooseAutosaveFolder(
        title: String,
        message: String,
        bookmarkKey: String,
        completion: (URL) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = message
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        let initial = bookmarkKey == "autosaveWatchBookmark" ? autosaveWatchPath : autosaveArchivePath
        if !initial.isEmpty {
            let url = URL(fileURLWithPath: initial, isDirectory: true)
            if fileManager.fileExists(atPath: url.path) {
                panel.directoryURL = url
            }
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try withScopedAccess(to: url) {
                try makeBookmark(for: url, key: bookmarkKey)
            }
            completion(url)
            autosaveMonitor.configurationChanged()
        } catch {
            autosaveMonitor.status = PVL("Не удалось сохранить доступ: \(error.localizedDescription)")
        }
    }

    // MARK: - Archive version numbering

    private func withArchiveAccess<T>(operation: (URL) throws -> T) throws -> T {
        let archiveURL = try resolveBookmark(forKey: "archiveBookmark")
        return try withScopedAccess(to: archiveURL) {
            try operation(archiveURL)
        }
    }

    private var previousVersionLabel: String {
        guard sourceProjectURL != nil else { return "—" }
        guard let versions = archivedVersionNumbers() else { return PVL("Нет доступа") }
        guard let latest = versions.max() else { return PVL("Ещё нет") }
        return String(format: "v%03d", latest)
    }

    private func suggestedVersionNumber() -> String? {
        guard let versions = archivedVersionNumbers(), (versions.max() ?? 0) < Int.max else { return nil }
        return String(format: "v%03d", (versions.max() ?? 0) + 1)
    }

    /// Display reads are memory-only; refresh explicitly after selecting or saving.
    private func archivedVersionNumbers() -> [Int]? { manualVersions.numbers }

    private func refreshArchivedVersionNumbers() {
        guard !projectName.isEmpty else { manualVersions.invalidate(); return }
        do {
            try withArchiveAccess { archiveURL in
                guard let source = sourceProjectURL else { manualVersions.invalidate(); return }
                let folder = try PVProjectFolders.shared.folder(for: source, archive: archiveURL, create: false, allowLegacyClaim: true)
                try manualVersions.refresh(project: projectName, archive: archiveURL, directory: folder)
            }
        } catch { manualVersions.invalidate() }
    }

    // MARK: - Save version

    private func createVersion() {
        guard !savingVersion else { return }
        guard validateCurrentProject(), let source = sourceProjectURL else {
            statusMessage = PVL("Сначала выбери проект .prproj"); isError = true; return
        }
        let version = versionNumber.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard version.range(of: #"^v\d{3,}$"#, options: .regularExpression) != nil else {
            statusMessage = PVL("Номер версии должен быть в формате v008"); isError = true; return
        }
        let name = projectName, comment = versionComment, originalVersion = versionNumber, generation = UUID()
        saveGeneration = generation; savingVersion = true
        saveTask = Task { @MainActor in
            defer { if saveGeneration == generation { savingVersion = false; saveTask = nil } }
            do {
                let archive = try resolveBookmark(forKey: "archiveBookmark")
                let sourceAccess = source.startAccessingSecurityScopedResource()
                let archiveAccess = archive.startAccessingSecurityScopedResource()
                defer {
                    if sourceAccess { source.stopAccessingSecurityScopedResource() }
                    if archiveAccess { archive.stopAccessingSecurityScopedResource() }
                }
                try await PremiereBridge.shared.save(source)
                try Task.checkCancellation()
                guard saveGeneration == generation, sourceProjectURL == source, versionNumber == originalVersion, versionComment == comment else {
                    throw PremiereBridge.Failure(message: "The selection changed; no archive copy was created.")
                }
                let folder = try PVProjectFolders.shared.folder(for: source, archive: archive, allowLegacyClaim: true)
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
                let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = .current
                formatter.dateFormat = "dd-MM-yyyy-HH-mm-ss"
                let cleanComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: "\\", with: "-")
                var filename = "\(name)_\(version)_\(formatter.string(from: Date()))"
                if !cleanComment.isEmpty { filename += "_" + cleanComment }
                let destination = folder.appendingPathComponent(filename + ".prproj")
                let staged = try await Task.detached(priority: .userInitiated) {
                    try PVSafeCopy.stage(source, in: folder, now: Date(), stableDelay: 0)
                }.value
                defer { try? fileManager.removeItem(at: staged.file) }
                try Task.checkCancellation()
                guard saveGeneration == generation, sourceProjectURL == source else { throw CancellationError() }
                try PVSafeCopy.install(staged.file, at: destination)
                statusMessage = PVL("Версия \(version) сохранена"); isError = false; versionComment = ""
                refreshArchivedVersionNumbers(); versionNumber = suggestedVersionNumber() ?? versionNumber
                NSApp.hide(nil)
            } catch {
                guard saveGeneration == generation else { return }
                if error is CancellationError { statusMessage = PVL("Создание копии отменено. Premiere может завершить сохранение проекта."); isError = false }
                else { statusMessage = PVL("Ошибка сохранения: \(PVL(error.localizedDescription))"); isError = true }
            }
        }
    }
}

struct PVTheme {
    let dark: Bool
    var canvas: Color { Color(red: 0.09, green: 0.075, blue: 0.22) }
    var panel: Color { Color(red: 0.14, green: 0.105, blue: 0.255) }
    var field: Color { Color.white.opacity(0.055) }
    var ink: Color { Color(red: 0.93, green: 0.91, blue: 0.96) }
    var muted: Color { Color(red: 0.80, green: 0.75, blue: 0.88) }
    var border: Color { Color.white.opacity(0.09) }
    var accent: Color { Color(red: 0.84, green: 0.71, blue: 0.93) }
    var rose: Color { accent }
    var mint: Color { accent }
    var actionGradient: LinearGradient {
        LinearGradient(colors: [canvas, Color(red: 0.395, green: 0.24, blue: 0.57)], startPoint: .bottomLeading, endPoint: .topTrailing)
    }
}

struct PVQuietButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        let theme = PVTheme(dark: colorScheme == .dark)
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(theme.muted)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(theme.field.opacity(configuration.isPressed ? 0.65 : 1), in: RoundedRectangle(cornerRadius: 9))
            .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(theme.border) }
            .opacity(enabled ? 1 : 0.4)
    }
}

struct PVSaveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PVGlowSaveButton(label: configuration.label, pressed: configuration.isPressed)
    }
}

private struct PVGlowSaveButton: View {
    let label: ButtonStyleConfiguration.Label
    let pressed: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    private var theme: PVTheme { PVTheme(dark: true) }
    var body: some View {
        label
            .foregroundStyle(.white)
            .background(theme.actionGradient, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17).fill(
                    RadialGradient(colors: [.white.opacity(hovered ? 0.20 : 0.07), .clear], center: .topLeading, startRadius: 0, endRadius: hovered ? 460 : 220)
                ).allowsHitTesting(false)
            }
            .overlay { RoundedRectangle(cornerRadius: 17).strokeBorder(Color.white.opacity(hovered ? 0.35 : 0.16)) }
            .shadow(color: theme.accent.opacity(enabled ? (hovered ? 0.32 : 0.14) : 0), radius: hovered ? 23 : 10, y: hovered ? 8 : 4)
            .scaleEffect(reduceMotion ? 1 : (pressed ? 0.987 : hovered ? 1.006 : 1))
            .opacity(enabled ? 1 : 0.4)
            .onHover { hovered = $0 && enabled }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: hovered)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8), value: pressed)
    }
}

private struct ShortcutEditor: View {
    @EnvironmentObject private var hotKey: GlobalSaveHotKey
    @Environment(\.colorScheme) private var colorScheme
    @State private var errorMessage: String?
    @State private var recording = false
    @StateObject private var inputSource = PVShortcutInput()
    let close: () -> Void
    private var theme: PVTheme { PVTheme(dark: true) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(PVL("для открытия из Premiere Pro")).font(.system(size: 11, weight: .light)).foregroundStyle(theme.muted)
            Text(PVL("Сейчас используется: ") + hotKey.shortcut.display)
                .font(.system(size: 12)).foregroundStyle(theme.muted)
            ZStack {
                RoundedRectangle(cornerRadius: 13).fill(theme.accent.opacity(0.07))
                RoundedRectangle(cornerRadius: 13).strokeBorder(theme.accent.opacity(0.5))
                VStack(spacing: 5) {
                    Image(systemName: "keyboard").font(.system(size: 20))
                    Text(recording ? PVL("Нажми новое сочетание") : PVL("Изменить сочетание"))
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(theme.accent).allowsHitTesting(false)
                if recording {
                    ShortcutCaptureView(onKey: record)
                } else {
                    Button {
                        inputSource.begin()
                        recording = true
                        errorMessage = nil
                        hotKey.beginRecording()
                    } label: {
                        Color.clear.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(PVL("Начать запись нового сочетания"))
                }
            }
            .frame(height: 76)
            Text(errorMessage ?? PVL("Esc — отменить."))
                .font(.system(size: 11))
                .foregroundStyle(errorMessage == nil ? theme.muted : .red)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(PVL("Вернуть Option+S")) { apply(.defaultShortcut) }
                    .buttonStyle(PVQuietButtonStyle())
                Spacer()
                Button(PVL("Отмена"), action: close)
                    .buttonStyle(PVQuietButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(theme.ink).background(theme.panel)
        .onDisappear { inputSource.end(); hotKey.endRecording() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            inputSource.end(); hotKey.endRecording(); recording = false
        }
    }

    private func apply(_ shortcut: SavedShortcut) {
        if let error = hotKey.setShortcut(shortcut) { errorMessage = error }
        else { inputSource.end(); close() }
    }

    private func record(_ event: NSEvent) {
        guard recording, !event.isARepeat else { return }
        if event.keyCode == UInt16(kVK_Escape) { close(); return }
        var modifiers: UInt32 = 0
        if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
        if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
        if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        let special: [UInt16: String] = [
            UInt16(kVK_Return): "↩", UInt16(kVK_Tab): "⇥", UInt16(kVK_Space): "Space",
            UInt16(kVK_Delete): "⌫", UInt16(kVK_ForwardDelete): "⌦", UInt16(kVK_ANSI_KeypadEnter): "⌤",
            UInt16(kVK_LeftArrow): "←", UInt16(kVK_RightArrow): "→", UInt16(kVK_UpArrow): "↑", UInt16(kVK_DownArrow): "↓",
            UInt16(kVK_Home): "↖", UInt16(kVK_End): "↘", UInt16(kVK_PageUp): "⇞", UInt16(kVK_PageDown): "⇟",
            UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3", UInt16(kVK_F4): "F4",
            UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6", UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8",
            UInt16(kVK_F9): "F9", UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
            UInt16(kVK_F13): "F13", UInt16(kVK_F14): "F14", UInt16(kVK_F15): "F15", UInt16(kVK_F16): "F16",
            UInt16(kVK_F17): "F17", UInt16(kVK_F18): "F18", UInt16(kVK_F19): "F19", UInt16(kVK_F20): "F20"
        ]
        let raw = (event.charactersIgnoringModifiers ?? "").unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let printable = String(String.UnicodeScalarView(raw)).prefix(1).uppercased()
        let keyLabel = special[event.keyCode] ?? PVShortcutInput.latinLabel(code: event.keyCode, fallback: printable.isEmpty ? "Key \(event.keyCode)" : printable)
        apply(SavedShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, keyLabel: keyLabel))
    }
}

private struct ShortcutCaptureView: NSViewRepresentable {
    let onKey: (NSEvent) -> Void
    func makeNSView(context: Context) -> ShortcutCaptureNSView {
        let view = ShortcutCaptureNSView()
        view.onKey = onKey
        view.setAccessibilityLabel(PVL("Нажмите новое сочетание клавиш. Escape — отменить."))
        view.setAccessibilityRole(.textField)
        return view
    }
    func updateNSView(_ nsView: ShortcutCaptureNSView, context: Context) { nsView.onKey = onKey }
}

private final class ShortcutCaptureNSView: NSView {
    var onKey: (NSEvent) -> Void = { _ in }
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
    override func keyDown(with event: NSEvent) { onKey(event) }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return false }
        onKey(event)
        return true
    }
}

nonisolated enum AppRelease {
    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "4.9" }
    static var build: String { Bundle.main.infoDictionary?["PVBuildNumber"] as? String ?? Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1" }
    static var label: String { version + " · Build " + build }
    static let author = "pewakkk"
}

nonisolated enum PVBrand {
    struct Variant: Sendable {
        let id: String
        let asset: String
        let title: String
    }
    static let variants = [
        Variant(id: "pearl", asset: "PVPearl", title: PVL("Чёрный на белом")),
        Variant(id: "graphite", asset: "PVGraphite", title: PVL("Белый на чёрном")),
        Variant(id: "color3", asset: "PVColor3", title: "Color 3"),
        Variant(id: "color", asset: "PVColor", title: "Color"),
        Variant(id: "color2", asset: "PVColor2", title: "Color 2"),
        Variant(id: "signature-dark", asset: "PVSignatureDark", title: PVL("Индиго")),
        Variant(id: "signature-light", asset: "PVSignatureLight", title: PVL("Лаванда"))
    ]
    static func asset(for variant: String) -> String {
        variants.first(where: { $0.id == variant })?.asset ?? "PVColor3"
    }
    @MainActor static func applySelectedIcon(allowIconAccessPrompt: Bool = false) {
        let variant = UserDefaults.standard.string(forKey: "logoVariant") ?? "signature-dark"
        let selected = PVUserLogoLibrary.shared.image(for: variant)
        NSApp.applicationIconImage = selected ?? NSImage(named: NSImage.Name("PVSignatureDark"))
        // An unavailable custom file must not replace an existing Finder icon with a fallback.
        if let selected { PVFileIconStore.shared.apply(selected, allowPrompt: allowIconAccessPrompt) }
    }
}

/// Only this background subtree ticks; it pauses whenever the save window is hidden.
private struct PVAnimatedBackdrop: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !active || reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            ZStack {
                Color(red: 0.09, green: 0.075, blue: 0.22)
                RadialGradient(colors: [Color(red: 0.395, green: 0.24, blue: 0.57), .clear],
                               center: UnitPoint(x: 0.50 + sin(t * 0.12) * 0.035, y: 0.46 + cos(t * 0.09) * 0.035),
                               startRadius: 0, endRadius: 370)
            }
        }.allowsHitTesting(false)
    }
}

private struct PVHeroArtwork: View {
    let asset: String
    let active: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !active || reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            ZStack {
                Ellipse()
                    .fill(Color(red: 0.36, green: 0.65, blue: 0.86).opacity(colorScheme == .dark ? 0.22 : 0.10))
                    .frame(width: hovered ? 115 : 95, height: 40).blur(radius: 20).offset(y: 36)
                Image(asset).resizable().scaledToFit().frame(width: 134, height: 134)
                    .id(asset).transition(.opacity)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.13), radius: hovered ? 17 : 12, y: hovered ? 13 : 8)
                    .offset(y: reduceMotion ? 0 : sin(t * 0.65) * 2.4)
                    .rotationEffect(.degrees(reduceMotion ? 0 : sin(t * 0.35) * 0.7))
                    .rotation3DEffect(.degrees(reduceMotion ? 0 : hovered ? 7 : sin(t * 0.30) * 1.2), axis: (x: 0.3, y: 1, z: 0), perspective: 0.5)
                    .scaleEffect(reduceMotion ? 1 : hovered ? 1.045 : 1)
            }
        }
        .onHover { hovered = $0 }
        .onChange(of: active) { _, active in if !active { hovered = false } }
        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.8), value: hovered)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: asset)
        .accessibilityHidden(true)
    }
}

private struct PVHelpView: View {
    let replayWelcome: () -> Void
    @ObservedObject var updates: PVUpdateService
    private var theme: PVTheme { PVTheme(dark: true) }
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(spacing: 12) {
                Button(action: replayWelcome) {
                    PVHeaderMark(tint: theme.muted).scaleEffect(1.5).frame(width: 42, height: 42)
                }.buttonStyle(.plain).accessibilityLabel(PVL("Посмотреть приветствие"))
                VStack(alignment: .leading, spacing: 3) {
                    Text(AppRelease.label).font(.system(size: 12, design: .monospaced))
                    Text(PVL("Дата сборки: ") + PVBuildDate.label).font(.system(size: 10)).foregroundStyle(theme.muted)
                }
            }
            PVUpdateSettings(service: updates, showRelease: false)
            Divider().overlay(theme.border)
            section(PVL("Версии"), PVL("Отдельные копии важных этапов монтажа. Комментарий необязателен. Ручные версии не удаляются автоматически."))
            section(PVL("Резервирование"), PVL("Авто сохраняет изменения, пока работает Premiere Pro. Всегда — пока открыта утилита. Выкл. оставляет только ручное копирование."))
            section(PVL("История копий"), PVL("\(BackupPolicy.recentCount) недавних состояний, \(BackupPolicy.hourlyHours) часовых и \(BackupPolicy.dailyDays) дневных копий. Неизменённые проекты не дублируются."))
            section(PVL("Перед копированием"), PVL("Невидимый плагин сохраняет открытый проект в Premiere Pro. Копия создаётся только после подтверждения. Выбранный проект должен совпадать с активным проектом Premiere."))
            Button(PVL("История изменений")) { NSWorkspace.shared.open(PVUpdateService.releases) }.buttonStyle(.plain).font(.system(size: 10))
        }
    }
    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12, weight: .medium))
            Text(text).font(.system(size: 11)).foregroundStyle(theme.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PVFloatingSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(PVTheme(dark: colorScheme == .dark).border) }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.32 : 0.13), radius: 24, y: 8)
    }
}

private struct PVFooterHeight: PreferenceKey {
    static let defaultValue: CGFloat = 50
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private enum PVBackupRelativeTime {
    static func label(_ date: Date, now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: UserDefaults.standard.string(forKey: "interfaceLanguage") == "ru" ? "ru" : "en")
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
