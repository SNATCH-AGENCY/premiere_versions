import SwiftUI
import AppKit

nonisolated enum PVScrollPhase: Sendable {
    case began, changed, ended, cancelled, momentum, discrete
}

/// One deliberate gesture can change the compose stage once. Momentum never navigates.
nonisolated struct PVScrollGate {
    private var accumulated = 0.0
    private var tripped = false
    private var lastEvent = -Double.infinity
    private var ended = true

    mutating func direction(delta: Double, precise: Bool, phase: PVScrollPhase, time: Double) -> Int? {
        if phase == .momentum { return nil }
        if phase == .ended || phase == .cancelled {
            ended = true
            accumulated = 0
            return nil
        }
        let silence = time - lastEvent
        if phase == .began || (phase == .discrete && silence > 0.28) || (phase == .changed && ended && silence > 0.28) {
            accumulated = 0
            tripped = false
        }
        lastEvent = time
        ended = false
        guard !tripped, delta.isFinite else { return nil }
        if accumulated * delta < 0 { accumulated = 0 }
        accumulated += delta
        let threshold = precise ? 18.0 : 1.0
        guard abs(accumulated) >= threshold else { return nil }
        tripped = true
        return accumulated < 0 ? 1 : -1
    }
}

struct PVStageScrollCapture: NSViewRepresentable {
    let enabled: Bool
    let changeStage: (Int) -> Void

    func makeNSView(context: Context) -> PVStageScrollView { PVStageScrollView() }
    func updateNSView(_ view: PVStageScrollView, context: Context) {
        view.enabled = enabled
        view.changeStage = changeStage
    }
    static func dismantleNSView(_ view: PVStageScrollView, coordinator: ()) { view.stopMonitoring() }
}

final class PVStageScrollView: NSView {
    var enabled = true
    var changeStage: ((Int) -> Void)?
    private var monitor: Any?
    private var gate = PVScrollGate()
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.enabled, event.window === self.window,
                  self.bounds.contains(self.convert(event.locationInWindow, from: nil)),
                  abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) else { return event }
            let phase: PVScrollPhase
            if !event.momentumPhase.isEmpty { phase = .momentum }
            else if event.phase.contains(.began) { phase = .began }
            else if event.phase.contains(.ended) { phase = .ended }
            else if event.phase.contains(.cancelled) { phase = .cancelled }
            else if event.phase.contains(.changed) { phase = .changed }
            else { phase = .discrete }
            if let direction = self.gate.direction(delta: Double(event.scrollingDeltaY), precise: event.hasPreciseScrollingDeltas,
                                                   phase: phase, time: event.timestamp) {
                self.changeStage?(direction)
            }
            return nil
        }
    }

    func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        gate = PVScrollGate()
    }
}

/// A native, permanently visible scroller, independent of the user's auto-hide preference.
struct PVPersistentScrollView<Content: View>: NSViewRepresentable {
    let content: Content
    let scrollRequest: Int
    let memory: PVScrollMemory?
    init(scrollRequest: Int = 0, memory: PVScrollMemory? = nil, @ViewBuilder content: () -> Content) { self.scrollRequest = scrollRequest; self.memory = memory; self.content = content() }

    final class Coordinator {
        var hosting: NSHostingView<Content>?
        var controller: NSHostingController<Content>?
        var heightConstraint: NSLayoutConstraint?
        var lastScrollRequest = 0
        var memory: PVScrollMemory?
        var restored = false
        var observer: NSObjectProtocol?
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
        func resize(_ scroll: NSScrollView) {
            guard let controller, scroll.contentView.bounds.width > 0 else { return }
            let size = controller.sizeThatFits(in: CGSize(width: scroll.contentView.bounds.width, height: 100_000))
            if let constraint = heightConstraint, abs(constraint.constant - size.height) > 0.5 {
                constraint.constant = ceil(size.height)
            }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = PVLayoutScrollView()
        scroll.onLayout = { [weak coordinator = context.coordinator, weak scroll] in
            if let scroll { coordinator?.resize(scroll) }
        }
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.verticalScroller = PVPersistentScroller()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = false
        scroll.scrollerStyle = .legacy
        scroll.scrollerKnobStyle = .light
        scroll.horizontalScrollElasticity = .none
        let controller = NSHostingController(rootView: content)
        let hosting = controller.view as! NSHostingView<Content>
        context.coordinator.controller = controller
        hosting.safeAreaRegions = []
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.sizingOptions = []
        hosting.setContentHuggingPriority(.required, for: .vertical)
        hosting.setContentCompressionResistancePriority(.required, for: .vertical)
        scroll.documentView = hosting
        context.coordinator.memory = memory
        scroll.contentView.postsBoundsChangedNotifications = true
        context.coordinator.observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak coordinator = context.coordinator, weak scroll] _ in
            MainActor.assumeIsolated {
                guard let coordinator, coordinator.restored, let scroll else { return }
                coordinator.memory?.offset = scroll.contentView.bounds.origin.y
            }
        }
        let height = hosting.heightAnchor.constraint(equalToConstant: 1)
        context.coordinator.heightConstraint = height
        NSLayoutConstraint.activate([
            height,
            hosting.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            hosting.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            hosting.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        ])
        context.coordinator.hosting = hosting
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.controller?.rootView = content
        context.coordinator.resize(scroll)
        DispatchQueue.main.async {
            context.coordinator.resize(scroll)
            if !context.coordinator.restored {
                scroll.layoutSubtreeIfNeeded()
                let limit = max(0, (scroll.documentView?.bounds.height ?? 0) - scroll.contentView.bounds.height)
                scroll.contentView.scroll(to: NSPoint(x: 0, y: min(limit, max(0, memory?.offset ?? 0))))
                scroll.reflectScrolledClipView(scroll.contentView)
                context.coordinator.restored = true
            }
        }
        if context.coordinator.lastScrollRequest != scrollRequest {
            context.coordinator.lastScrollRequest = scrollRequest
            DispatchQueue.main.async {
                scroll.documentView?.layoutSubtreeIfNeeded()
                let height = scroll.documentView?.bounds.height ?? 0
                scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, height - scroll.contentView.bounds.height)))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        }
    }
}

/// Draw a quiet, visible thumb even while the panel/window is inactive.
final class PVPersistentScroller: NSScroller {
    override func draw(_ dirtyRect: NSRect) {
        let track = NSRect(x: bounds.midX - 2, y: 2, width: 4, height: max(0, bounds.height - 4))
        NSColor.white.withAlphaComponent(0.06).setFill()
        NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill()
        drawKnob()
    }
    override func drawKnob() {
        let native = rect(for: .knob)
        let thumb = NSRect(x: bounds.midX - 2, y: native.minY, width: 4, height: max(12, native.height))
        NSColor(red: 0.80, green: 0.75, blue: 0.88, alpha: 0.65).setFill()
        NSBezierPath(roundedRect: thumb, xRadius: 2, yRadius: 2).fill()
    }
}

/// Monochrome stack in the title's tone. Pv removes alpha from every layer,
/// revealing the actual moving window gradient rather than a painted flat color.
struct PVHeaderMark: View {
    let tint: Color
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).frame(width: 19, height: 19).offset(x: -3, y: -3).opacity(0.45)
            RoundedRectangle(cornerRadius: 4).frame(width: 19, height: 19).offset(x: -1, y: -1).opacity(0.70)
            RoundedRectangle(cornerRadius: 4).frame(width: 19, height: 19).offset(x: 2, y: 2)
            Text("Pv").font(.system(size: 14, weight: .bold)).tracking(-0.7)
                .foregroundStyle(.black).offset(x: 2, y: 2)
                .blendMode(.destinationOut)
        }
        .foregroundStyle(tint)
        .compositingGroup()
        .accessibilityHidden(true)
    }
}

final class PVLayoutScrollView: NSScrollView {
    var onLayout: (() -> Void)?
    override func layout() { super.layout(); onLayout?() }
}

/// Independent state-driven switches avoid AppKit tint reuse across hosted controls.
struct PVSwitchStyle: ToggleStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.label
            Spacer(minLength: 8)
            Button { configuration.isOn.toggle() } label: {
                Capsule().fill(configuration.isOn ? Color(red: 0.70, green: 0.48, blue: 0.84) : Color.white.opacity(0.13))
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(Color(red: 0.92, green: 0.87, blue: 0.97))
                            .padding(2)
                    }
                    .frame(width: 32, height: 18)
                    .frame(minWidth: 40, minHeight: 28)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
                .opacity(enabled ? 1 : 0.4)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: configuration.isOn)
                .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
        }
    }
}

/// Trigger geometry is captured in the utility's coordinate space, never a transient key window.
struct PVPanelTrigger: ViewModifier {
    let id: String
    func body(content: Content) -> some View {
        content.background {
            GeometryReader { proxy in
                Color.clear.preference(key: PVPanelTriggerFrames.self,
                    value: [id: proxy.frame(in: .named("PVUtilityContent"))])
            }
        }
    }
}
struct PVPanelTriggerFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
nonisolated enum PVPanelTiming {
    static let open: UInt64 = 150_000_000
    static let close: UInt64 = 350_000_000
}
nonisolated enum PVPanelPlacement {
    static func center(anchor: CGPoint, dimensions: CGSize, available: CGSize) -> CGPoint {
        let half = CGSize(width: dimensions.width / 2, height: dimensions.height / 2)
        func clamp(_ value: CGFloat, _ half: CGFloat, _ size: CGFloat) -> CGFloat {
            guard value.isFinite, half.isFinite, size.isFinite else { return size / 2 }
            return min(max(value, half + 16), max(half + 16, size - half - 16))
        }
        return CGPoint(x: clamp(anchor.x, half.width, available.width),
                       y: clamp(anchor.y, half.height, available.height))
    }
}

/// Click toggles expansion; hovering only provides visual feedback.
struct PVHoverSection<Content: View>: View {
    let title: String
    let symbol: String
    @Binding var expanded: Bool
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    @State private var pending: Task<Void, Never>?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                if !symbol.isEmpty { Image(systemName: symbol).frame(width: 17) }
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .light))
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }.frame(minHeight: 40).contentShape(Rectangle())
                .scaleEffect(hovered && !reduceMotion ? 1.01 : 1)
                .onTapGesture { change(!expanded) }
                .accessibilityElement(children: .combine)
                .accessibilityValue(PVL(expanded ? "Развёрнуто" : "Свёрнуто"))
                .accessibilityAction { change(!expanded) }
            if expanded {
                content().padding(.top, 7).padding(.bottom, 10)
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onHover { inside in
            hovered = inside
        }
        .onDisappear { pending?.cancel() }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: expanded)
    }
    private func change(_ value: Bool) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) { expanded = value }
    }
    private func schedule(_ opening: Bool) {
        pending?.cancel()
        guard opening != expanded else { return }
        pending = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: opening ? PVPanelTiming.open : PVPanelTiming.close) } catch { return }
            guard !Task.isCancelled, hovered == opening else { return }
            if opening && PVPanelInteraction.isScrolling() { schedule(true); return }
            if !opening && PVPanelInteraction.isBusy(window: NSApp.windows.first(where: { $0 is PVUtilityWindow && $0.isVisible })) {
                schedule(false)
            } else { change(opening) }
        }
    }
}


/// A quiet visual response without changing layout or opening a panel.
struct PVHoverResponse: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    func body(content: Content) -> some View {
        content.scaleEffect(hovered && !reduceMotion ? 1.04 : 1)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: hovered)
            .onHover { hovered = $0 }
    }
}
