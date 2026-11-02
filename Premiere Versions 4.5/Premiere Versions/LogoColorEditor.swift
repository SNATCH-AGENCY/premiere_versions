import SwiftUI
import AppKit

struct PVLogoColorEditor: View {
    @ObservedObject var library: PVUserLogoLibrary
    let slot: String?
    let saved: () -> Void
    let close: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var editingLetters = false
    @State private var plate: Color
    @State private var letters: Color
    @State private var preview: NSImage?
    @State private var errorText: String?
    @State private var saving = false
    @State private var saveTask: Task<Void, Never>?
    private var theme: PVTheme { PVTheme(dark: colorScheme == .dark) }

    init(library: PVUserLogoLibrary, slot: String? = nil, saved: @escaping () -> Void, close: @escaping () -> Void) {
        self.slot = slot
        self.library = library
        self.saved = saved
        self.close = close
        let palette = library.palette(for: slot)
        _plate = State(initialValue: Color(red: palette.plate.r, green: palette.plate.g, blue: palette.plate.b))
        _letters = State(initialValue: Color(red: palette.letters.r, green: palette.letters.g, blue: palette.letters.b))
    }

    private var palette: PVLogoPalette {
        func rgb(_ color: Color) -> PVLogoRGB {
            let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
            return PVLogoRGB(r: ns.redComponent, g: ns.greenComponent, b: ns.blueComponent)
        }
        return PVLogoPalette(plate: rgb(plate), letters: rgb(letters))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(PVL("Свой цвет")).font(.system(size: 19, weight: .semibold, design: .rounded))
                Spacer()
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 11, weight: .medium)) }
                    .buttonStyle(PVQuietButtonStyle()).disabled(saving).accessibilityLabel(PVL("Закрыть конструктор"))
            }
            HStack(spacing: 24) {
                VStack(spacing: 10) {
                    Group {
                        if let preview { Image(nsImage: preview).resizable().scaledToFit() }
                        else { Image("PVColor3").resizable().scaledToFit() }
                    }.frame(width: 170, height: 170)
                    HStack(spacing: 6) {
                        partButton("Плашка", value: plate, letters: false)
                        partButton("Буквы", value: letters, letters: true)
                    }
                }
                PVInlineColorPicker(title: editingLetters ? "Буквы" : "Плашка",
                                    color: editingLetters ? $letters : $plate)
                    .id(editingLetters)
            }.frame(maxWidth: .infinity)
            Text(slot == nil ? PVL("Новый вариант появится в списке значков Dock. Предыдущий пользовательский цвет останется рядом.") : PVL("Изменится только этот значок. Другой пользовательский вариант останется без изменений."))
                .font(.system(size: 11)).foregroundStyle(theme.muted)
            if let errorText {
                Text(errorText).font(.system(size: 11)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                Button(PVL("Отмена"), action: close).buttonStyle(PVQuietButtonStyle()).disabled(saving)
                Spacer()
                Button(action: save) {
                    HStack(spacing: 8) {
                        if saving { ProgressView().controlSize(.small) }
                        Text(saving ? PVL("Сохранение…") : PVL("Сохранить цвет")).font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 18).frame(height: 40)
                }
                .buttonStyle(PVSaveButtonStyle()).disabled(saving || preview == nil)
            }
        }
        .padding(18).frame(width: 470)
        .foregroundStyle(theme.ink).background(theme.panel)
        .onExitCommand { close() }
        .onDisappear { saveTask?.cancel() }
        .task(id: palette) {
            guard let template = library.templateData else { errorText = PVL("Шаблон логотипа не найден."); return }
            let selected = palette
            do {
                try await Task.sleep(nanoseconds: 80_000_000)
                let data = try await Task.detached(priority: .userInitiated) {
                    try PVLogoRenderer.png(template: template, palette: selected, size: 320)
                }.value
                guard !Task.isCancelled else { return }
                preview = NSImage(data: data)
                errorText = nil
            } catch is CancellationError { }
            catch { errorText = error.localizedDescription }
        }
    }

    private func partButton(_ title: String, value: Color, letters: Bool) -> some View {
        Button { editingLetters = letters } label: {
            HStack(spacing: 5) {
                Circle().fill(value).frame(width: 10, height: 10)
                Text(PVL(title)).font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(editingLetters == letters ? theme.field : .clear, in: Capsule())
            .opacity(editingLetters == letters ? 1 : 0.6)
        }.buttonStyle(.plain)
            .accessibilityAddTraits(editingLetters == letters ? .isSelected : [])
    }

    private func save() {
        guard let template = library.templateData, !saving else { return }
        saving = true
        let selected = palette
        saveTask = Task { @MainActor in
            defer { saving = false }
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try PVLogoRenderer.png(template: template, palette: selected, size: 1024)
                }.value
                guard !Task.isCancelled else { return }
                if let slot { try library.replace(data, palette: selected, slot: slot) }
                else { try library.save(data, palette: selected) }
                saved()
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}
