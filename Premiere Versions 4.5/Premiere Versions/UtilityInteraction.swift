import SwiftUI
import AppKit

nonisolated struct PVEscapeGate {
    private var last = -Double.infinity
    mutating func accept(time: Double, repeated: Bool) -> Bool {
        guard !repeated, time.isFinite, time - last >= 0.4 else { return false }
        last = time
        return true
    }
}

@MainActor enum PVColorSampling {
    static var active = false
}

/// Intercepts Escape in the app window before text fields, sliders and SwiftUI consume it.
final class PVUtilityWindow: NSWindow {
    var escapeAction: (() -> Void)?
    private var escapeGate = PVEscapeGate()
    override func sendEvent(_ event: NSEvent) {
        if PVColorSampling.active {
            if event.type == .keyDown, event.keyCode == 53 {
                _ = escapeGate.accept(time: event.timestamp, repeated: event.isARepeat)
            }
            super.sendEvent(event)
            return
        }
        if event.type == .keyDown, event.keyCode == 53,
           event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
           let escapeAction {
            if escapeGate.accept(time: event.timestamp, repeated: event.isARepeat) { escapeAction() }
            return
        }
        super.sendEvent(event)
    }
}

struct PVEscapeCapture: NSViewRepresentable {
    let action: () -> Void
    func makeNSView(context: Context) -> PVEscapeView { PVEscapeView() }
    func updateNSView(_ view: PVEscapeView, context: Context) { view.action = action; view.install() }
    static func dismantleNSView(_ view: PVEscapeView, coordinator: ()) { view.stop() }
}
final class PVEscapeView: NSView {
    var action: (() -> Void)?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); install() }
    func install() { (window as? PVUtilityWindow)?.escapeAction = action }
    func stop() { (window as? PVUtilityWindow)?.escapeAction = nil }
}

/// Starts the welcome animation only after the real window is visible and active.
struct PVWindowVisibility: NSViewRepresentable {
    @Binding var visible: Bool
    func makeNSView(context: Context) -> PVVisibilityView { PVVisibilityView() }
    func updateNSView(_ view: PVVisibilityView, context: Context) {
        view.changed = { value in if visible != value { visible = value } }
        DispatchQueue.main.async { view.refresh() }
    }
    static func dismantleNSView(_ view: PVVisibilityView, coordinator: ()) { view.stop() }
}
final class PVVisibilityView: NSView {
    var changed: ((Bool) -> Void)?
    private var observers: [NSObjectProtocol] = []
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow(); stop()
        guard window != nil else { return }
        let names: [Notification.Name] = [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
            NSApplication.didHideNotification, NSApplication.didUnhideNotification, NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
            NSWindow.didChangeOcclusionStateNotification]
        for name in names {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            })
        }
        DispatchQueue.main.async { self.refresh() }
    }
    func refresh() { changed?(window?.isVisible == true && window?.isKeyWindow == true && window?.isMiniaturized == false && NSApp.isActive && window?.occlusionState.contains(.visible) == true) }
    func stop() { for observer in observers { NotificationCenter.default.removeObserver(observer) }; observers.removeAll() }
}

nonisolated enum PVUptime {
    static func label(since: Date, now: Date = Date()) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(since) / 60))
        let days = minutes / 1440, hours = (minutes / 60) % 24, remainder = minutes % 60
        return "\(days) \(days == 1 ? "day" : "days") \(hours) \(hours == 1 ? "hour" : "hours") \(remainder) \(remainder == 1 ? "minute" : "minutes")"
    }
}

/// HSV geometry independent of UI state; hue/saturation live in the circular surface.
nonisolated struct PVHSVComponents: Equatable {
    var hue: Double
    var saturation: Double
    var brightness: Double
    static func wheel(point: CGPoint, diameter: Double, brightness: Double) -> Self {
        let radius = diameter / 2
        let dx = Double(point.x) - radius, dy = Double(point.y) - radius
        var hue = atan2(dy, dx) / (2 * Double.pi)
        if hue < 0 { hue += 1 }
        return Self(hue: hue, saturation: min(1, hypot(dx, dy) / radius),
                    brightness: brightness < 0.001 ? 1 : brightness)
    }
    var color: NSColor { NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1) }
    private var rgb: (Double, Double, Double) {
        let h = (hue - floor(hue)) * 6
        let c = brightness * saturation, x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1)), m = brightness - c
        let base: (Double, Double, Double)
        switch Int(h) {
        case 0: base = (c, x, 0)
        case 1: base = (x, c, 0)
        case 2: base = (0, c, x)
        case 3: base = (0, x, c)
        case 4: base = (x, 0, c)
        default: base = (c, 0, x)
        }
        return (base.0 + m, base.1 + m, base.2 + m)
    }
    init(hue: Double, saturation: Double, brightness: Double) {
        self.hue = hue; self.saturation = saturation; self.brightness = brightness
    }
    init(color: NSColor) {
        let rgb = color.usingColorSpace(.sRGB) ?? .white
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        self.init(hue: h, saturation: s, brightness: b)
    }
    var marker: CGPoint {
        CGPoint(x: cos(hue * 2 * .pi) * saturation, y: sin(hue * 2 * .pi) * saturation)
    }
}

/// Embedded color wheel with a value rail and native screen eyedropper, not NSColorPanel.
struct PVInlineColorPicker: View {
    let title: String
    @Binding var color: Color
    @State private var selection: PVHSVComponents
    @State private var sampler: NSColorSampler?
    @State private var sampling = false
    private let diameter: CGFloat = 130

    init(title: String, color: Binding<Color>) {
        self.title = title; self._color = color
        self._selection = State(initialValue: PVHSVComponents(color: NSColor(color.wrappedValue)))
    }
    private var hex: String {
        let rgb = NSColor(color).usingColorSpace(.sRGB) ?? .white
        return String(format: "#%02X%02X%02X", Int((rgb.redComponent * 255).rounded()),
                      Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
    }
    var body: some View {
        VStack(spacing: 9) {
            HStack {
                Text(PVL(title)).font(.system(size: 12, weight: .medium))
                Spacer()
                Button(action: sampleScreen) {
                    Image(systemName: "eyedropper").font(.system(size: 13, weight: .light))
                }.buttonStyle(.plain).disabled(sampling)
                    .help(PVL("Выбрать цвет с экрана"))
                    .accessibilityLabel(PVL("Выбрать цвет с экрана"))
            }
            ZStack {
                Circle().fill(AngularGradient(colors: (0...6).map { Color(hue: Double($0) / 6, saturation: 1, brightness: 1) }, center: .center))
                Circle().fill(RadialGradient(colors: [.white, .white.opacity(0)], center: .center, startRadius: 0, endRadius: diameter / 2))
                Circle().fill(color).frame(width: 9, height: 9)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .offset(x: selection.marker.x * diameter / 2, y: selection.marker.y * diameter / 2)
                    .allowsHitTesting(false)
            }
            .frame(width: diameter, height: diameter).contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                selection = .wheel(point: value.location, diameter: diameter, brightness: selection.brightness)
                apply()
            })
            .accessibilityLabel(PVL("Цветовой круг"))
            .accessibilityValue(hex)
            HStack(spacing: 6) {
                Image(systemName: "sun.max").font(.system(size: 10, weight: .light)).opacity(0.6)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(LinearGradient(colors: [.black, Color(hue: selection.hue, saturation: selection.saturation, brightness: 1)], startPoint: .leading, endPoint: .trailing)).frame(height: 8)
                        Circle().fill(.white).frame(width: 11, height: 11)
                            .shadow(color: .black.opacity(0.25), radius: 2)
                            .offset(x: selection.brightness * max(0, proxy.size.width - 11))
                    }
                    .frame(height: 16).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        selection.brightness = min(1, max(0, (value.location.x - 5.5) / max(1, proxy.size.width - 11)))
                        apply()
                    })
                }.frame(height: 16)
                    .accessibilityLabel(PVL("Яркость"))
                    .accessibilityValue(String(Int(selection.brightness * 100)))
            }
            Text(hex).font(.system(size: 10, weight: .light, design: .monospaced)).opacity(0.65)
                .textSelection(.enabled)
        }.frame(width: 180)
        .onChange(of: color) { _, value in
            var incoming = PVHSVComponents(color: NSColor(value))
            if incoming.brightness < 0.001 {
                incoming.hue = selection.hue; incoming.saturation = selection.saturation
            } else if incoming.saturation < 0.001 { incoming.hue = selection.hue }
            selection = incoming
        }
    }
    private func apply() { color = Color(nsColor: selection.color) }
    private func sampleScreen() {
        guard !PVColorSampling.active else { return }
        PVColorSampling.active = true; sampling = true
        let tool = NSColorSampler(); sampler = tool
        tool.show { picked in
            PVColorSampling.active = false; sampling = false; sampler = nil
            if let picked, let rgb = picked.usingColorSpace(.sRGB) {
                color = Color(red: min(1, max(0, rgb.redComponent)),
                              green: min(1, max(0, rgb.greenComponent)),
                              blue: min(1, max(0, rgb.blueComponent)))
            }
        }
    }
}
