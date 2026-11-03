import SwiftUI
import AppKit
import CoreText

/// Native editor bridge: on programmatic focus, place a blinking caret at the end,
/// rather than using NSTextField's default select-all behavior.
struct PVVersionInput: NSViewRepresentable {
    @Binding var text: String
    let isFocused: Bool
    let focusRequest: Int
    let enabled: Bool
    let color: NSColor
    var fontSize: CGFloat = 42
    var caret: NSColor? = nil
    var centered = false
    var placeholder = "v001"
    var accessibilityTitle = PVL("Номер сохраняемой версии")
    let focused: () -> Void
    let blurred: () -> Void
    let submitted: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> PVAxisInputHost {
        let field = PVVersionNSTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.isEditable = true
        field.isSelectable = true
        field.maximumNumberOfLines = 1
        field.lineBreakMode = .byClipping
        field.font = NSFont.systemFont(ofSize: fontSize, weight: .light)
        field.alignment = centered ? .center : .left
        field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [.foregroundColor: NSColor(red: 0.80, green: 0.75, blue: 0.88, alpha: 1), .font: field.font!])
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setAccessibilityLabel(accessibilityTitle)
        context.coordinator.lastRequest = focusRequest
        return PVAxisInputHost(field: field, sample: placeholder)
    }
    func updateNSView(_ host: PVAxisInputHost, context: Context) {
        let field = host.field
        host.sample = placeholder == "comment" ? "comment" : text
        host.needsLayout = true
        context.coordinator.parent = self
        field.isEnabled = enabled
        field.isEditable = enabled
        field.textColor = color
        field.caretColor = caret ?? color
        if field.stringValue != text {
            field.stringValue = text
            if let editor = field.currentEditor() as? NSTextView {
                editor.string = text
                editor.setSelectedRange(NSRange(location: text.utf16.count, length: 0))
            }
        }
        if let editor = field.currentEditor() as? NSTextView {
            editor.textColor = color
            editor.insertionPointColor = caret ?? color
        }
        field.wantsEditingFocus = isFocused && enabled
        if isFocused && enabled && (context.coordinator.lastRequest != focusRequest || field.currentEditor() == nil) {
            context.coordinator.lastRequest = focusRequest
            DispatchQueue.main.async { [weak field] in field?.placeCaretAtEnd() }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PVVersionInput
        var lastRequest = 0
        init(_ parent: PVVersionInput) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
        func controlTextDidBeginEditing(_ notification: Notification) { parent.focused() }
        func controlTextDidEndEditing(_ notification: Notification) { parent.blurred() }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.submitted()
                return true
            }
            return false
        }
    }
}

final class PVVersionNSTextField: NSTextField {
    var wantsEditingFocus = false
    var caretColor = NSColor.controlAccentColor
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if wantsEditingFocus {
            DispatchQueue.main.async { [weak self] in self?.placeCaretAtEnd() }
        }
    }
    func placeCaretAtEnd() {
        guard wantsEditingFocus, isEnabled, let window, window.isVisible, window.isKeyWindow else { return }
        window.makeFirstResponder(self)
        selectText(nil)
        if let editor = currentEditor() as? NSTextView {
            editor.insertionPointColor = caretColor
            editor.setSelectedRange(NSRange(location: stringValue.utf16.count, length: 0))
            editor.isAutomaticSpellingCorrectionEnabled = false
        }
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        if isEnabled { addCursorRect(bounds, cursor: .iBeam) }
    }
}

/// Center the visible letter shapes, rather than the font's asymmetric line box.
final class PVAxisInputHost: NSView {
    let field: PVVersionNSTextField
    var sample: String
    override var isFlipped: Bool { true }
    init(field: PVVersionNSTextField, sample: String) {
        self.field = field
        self.sample = sample
        super.init(frame: .zero)
        addSubview(field)
    }
    required init?(coder: NSCoder) { nil }
    override func layout() {
        super.layout()
        guard let font = field.font else { return }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: sample.isEmpty ? "v001" : sample, attributes: [.font: font]))
        let ink = CTLineGetImageBounds(line, nil)
        let height = ceil(font.ascender - font.descender + font.leading + 8)
        field.frame = NSRect(x: 0, y: 0, width: bounds.width, height: height)
        let inkCenterFromTop = field.firstBaselineOffsetFromTop - ink.midY
        field.frame.origin.y = bounds.midY - inkCenterFromTop
    }
}

struct PVAxisLabel: NSViewRepresentable {
    let text: String
    let color: NSColor
    func makeNSView(context: Context) -> PVAxisInputHost {
        let field = PVVersionNSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 16, weight: .light)
        field.isBordered = false
        field.drawsBackground = false
        return PVAxisInputHost(field: field, sample: text)
    }
    func updateNSView(_ host: PVAxisInputHost, context: Context) {
        host.field.stringValue = text
        host.field.textColor = color
        host.sample = text
        host.needsLayout = true
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PVAxisInputHost, context: Context) -> CGSize? {
        CGSize(width: (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 16, weight: .light)]).width + 6, height: 24)
    }
}
