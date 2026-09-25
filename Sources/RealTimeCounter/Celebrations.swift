import SwiftUI
import AppKit
import UserNotifications

// MARK: - Confetti overlay

/// Shows a click-through, full-screen confetti burst with a message for a few seconds.
enum Celebration {
    private static var window: NSWindow?

    static func show(_ message: String, sound: String = "Glass") {
        if UserDefaults.standard.object(forKey: "celebrationSound") as? Bool ?? true {
            NSSound(named: sound)?.play()
        }
        guard let screen = NSScreen.main else { return }
        window?.orderOut(nil)

        let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.isReleasedWhenClosed = false
        w.level = .statusBar
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        w.contentView = NSHostingView(rootView: ConfettiView(message: message))
        w.orderFrontRegardless()
        window = w

        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
            if window === w {
                w.orderOut(nil)
                window = nil
            }
        }
    }
}

private struct Particle {
    let x = Double.random(in: 0...1)
    let delay = Double.random(in: 0...0.8)
    let speed = Double.random(in: 0.7...1.3)
    let wobble = Double.random(in: 2...6)
    let spin = Double.random(in: -8...8)
    let size = Double.random(in: 6...11)
    let color: Color = [.green, .yellow, .orange, .pink, .blue, .purple, .mint].randomElement()!
}

struct ConfettiView: View {
    let message: String
    @State private var appeared = false
    private let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    private let particles = (0..<180).map { _ in Particle() }
    private let start = Date()

    var body: some View {
        ZStack {
            // With Reduce Motion the message simply fades in and out, no falling particles.
            if !reduceMotion {
            TimelineView(.animation) { context in
                Canvas { g, size in
                    let t = context.date.timeIntervalSince(start)
                    for p in particles {
                        let pt = t - p.delay
                        guard pt > 0 else { continue }
                        let x = p.x * size.width + sin(pt * p.wobble) * 25
                        let y = -20 + pt * p.speed * size.height / 3
                        let fade = max(0, min(1, 4.2 - t))
                        var layer = g
                        layer.translateBy(x: x, y: y)
                        layer.rotate(by: .radians(pt * p.spin))
                        layer.opacity = fade
                        let rect = CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.size / 2)
                        layer.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(p.color))
                    }
                }
            }
            }

            Text(message)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .background(.regularMaterial, in: Capsule())
                .shadow(radius: 20)
                .scaleEffect(appeared || reduceMotion ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.5, bounce: 0.45)) { appeared = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
                withAnimation(.easeIn(duration: 0.6)) { appeared = false }
            }
        }
    }
}

// MARK: - Notifications

enum Notifier {
    private static let delegate = BannerDelegate()

    static func requestAccess() {
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Sends right away if allowed. The first time, asks for permission now, in the moment the
    /// notification is useful, instead of at launch.
    static func send(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted { deliver(title: title, body: body) }
                }
            case .denied: break
            default: deliver(title: title, body: body)
            }
        }
    }

    private static func deliver(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

/// Lets banners appear even though the app is "active" as a menu bar app.
private final class BannerDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
