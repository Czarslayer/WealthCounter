import SwiftUI

/// Quiet, menu-like button: highlights on hover, darkens the instant the pointer goes down.
struct SubtleButtonStyle: ButtonStyle {
    var horizontalPadding: CGFloat = 8
    var minHeight: CGFloat = 28

    func makeBody(configuration: Configuration) -> some View {
        SubtleButton(configuration: configuration, horizontalPadding: horizontalPadding, minHeight: minHeight)
    }

    private struct SubtleButton: View {
        let configuration: Configuration
        let horizontalPadding: CGFloat
        let minHeight: CGFloat
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .padding(.horizontal, horizontalPadding)
                .frame(minHeight: minHeight)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.primary.opacity(configuration.isPressed ? 0.12 : hovering ? 0.06 : 0))
                )
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)   // press feedback stays instant
        }
    }
}

/// Title bar for a sub-page, with a back button that also answers to Esc.
struct PageHeader: View {
    let title: String
    var escapeGoesBack = true   // off while a nested task (like editing) owns Esc
    let back: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: back) {
                Image(systemName: "chevron.left")
                    .fontWeight(.semibold)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(SubtleButtonStyle(horizontalPadding: 0))
            .keyboardShortcut(escapeGoesBack ? .cancelAction : nil)
            .help("Back")
            .accessibilityLabel("Back")

            Text(title).font(.headline)
            Spacer()
        }
    }
}

/// Small section label, like the headers in Control Center.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

/// A money value where the fast-moving extra decimals are dimmed, so the eye rests on the
/// stable part: "US$15,36" in full strength, the trailing "25" in secondary.
func liveMoneyText(_ value: Double, currency: String) -> Text {
    let full = Array(value.money(currency, decimals: 4))
    let short = Array(value.money(currency, decimals: 2))
    var p = 0
    while p < short.count, full[p] == short[p] { p += 1 }
    var s = 0
    while s < short.count - p, full[full.count - 1 - s] == short[short.count - 1 - s] { s += 1 }
    let head = String(full[..<p])
    let tail = String(full[p..<(full.count - s)])
    let end = String(full[(full.count - s)...])
    return Text(head) + Text(tail).foregroundStyle(.secondary) + Text(end)
}

/// Reports whether the hosting window is actually on screen, so animation can stop the moment
/// the panel closes (a closed menu bar panel is ordered out, not destroyed).
struct WindowVisibilityReader: NSViewRepresentable {
    @Binding var isVisible: Bool

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onChange = { visible in
            DispatchQueue.main.async { if isVisible != visible { isVisible = visible } }
        }
        return view
    }

    func updateNSView(_ nsView: ReaderView, context: Context) {}

    final class ReaderView: NSView {
        var onChange: ((Bool) -> Void)?
        private var observer: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            guard let window else { onChange?(false); return }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self, weak window] _ in
                self?.onChange?(window?.occlusionState.contains(.visible) ?? false)
            }
            onChange?(window.occlusionState.contains(.visible))
        }
    }
}
