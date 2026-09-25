import SwiftUI
import Combine

/// The time the menu bar shows. AppModel advances it only when something visible changes.
final class Clock: ObservableObject {
    @Published var now = Date()
}

/// Owns the shared state and watches the clock for milestones, reached wishes and the end of the day.
final class AppModel: ObservableObject {
    let clock = Clock()
    let wishlist = Wishlist()
    let overtime = Overtime()
    private var timer: Timer?
    private var tickQueued = false
    private var observers: [Any] = []
    private var lastMilestone: (day: Date, basis: String, index: Int)?
    private let defaults = UserDefaults.standard

    init() {
        // Anything that can change what the menu bar should say gets an immediate re-check:
        // settings edits, overtime or wishlist changes, waking from sleep, clock or day changes.
        let center = NotificationCenter.default
        for name in [UserDefaults.didChangeNotification, .NSSystemClockDidChange, .NSCalendarDayChanged] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.queueTick() })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.queueTick() })
        observers.append(overtime.objectWillChange.sink { [weak self] in self?.queueTick() })
        observers.append(wishlist.objectWillChange.sink { [weak self] in self?.queueTick() })
        tick()

        if let i = CommandLine.arguments.firstIndex(of: "--preview") {
            let page = CommandLine.arguments.dropFirst(i + 1).first ?? "dashboard"
            DispatchQueue.main.async { self.openPreview(page) }
        }
    }

    /// Developer aid: `RealTimeCounter --preview [dashboard|wishlist|settings] [--light]` shows a page in a
    /// normal window (and prints its window number) so the design can be screenshotted.
    private var previewWindow: NSWindow?
    private func openPreview(_ page: String) {
        let root: AnyView = page == "settings"
            ? AnyView(SettingsView().environmentObject(wishlist).environmentObject(overtime))
            : AnyView(ContentView(initialPage: ContentView.Page(rawValue: page) ?? .dashboard)
                .environmentObject(clock).environmentObject(wishlist).environmentObject(overtime))
        let w = NSWindow(contentViewController: NSHostingController(rootView: root))
        w.title = "Preview"
        if CommandLine.arguments.contains("--light") { w.appearance = NSAppearance(named: .aqua) }
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        previewWindow = w
        print("PREVIEW_WINDOW \(w.windowNumber)")
        fflush(stdout)
    }

    // MARK: Scheduling
    //
    // Instead of waking every second, the app sleeps until the next moment the menu bar text can
    // change: the next cent while money is coming in, or the next transition (work starting, lunch,
    // end of day, midnight). Evenings and weekends mean roughly one wake-up per day.

    private func queueTick() {
        guard !tickQueued else { return }
        tickQueued = true
        DispatchQueue.main.async { [weak self] in
            self?.tickQueued = false
            self?.tick()
        }
    }

    private func tick() {
        let now = Date()
        clock.now = now
        let e = Earnings.fromDefaults()
        check(at: now, earnings: e)

        let next = nextTick(after: now, earnings: e)
        let wait = next.timeIntervalSince(now)
        timer?.invalidate()
        let t = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in self?.tick() }
        t.tolerance = min(max(wait * 0.1, 0.1), 60)   // lets macOS batch our wake-ups with others
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func nextTick(after now: Date, earnings e: Earnings) -> Date {
        let midnight = Calendar.current.startOfDay(for: now)
        var candidates = [Calendar.current.date(byAdding: .day, value: 1, to: midnight)!]
        if e.isWorkday(now) {
            for seg in e.segments {
                candidates.append(midnight.addingTimeInterval(Double(seg.start) * 60))
                candidates.append(midnight.addingTimeInterval(Double(seg.end) * 60))
            }
        }

        // Money per second right now: regular pay during work hours, the overtime rate outside them.
        let perSecond: Double = {
            if e.status(at: now) == .working { return e.dailyRate(on: now) / e.workSeconds }
            if overtime.isActive, let s = overtime.sessions.last { return s.hourlyRate / 3600 }
            return 0
        }()
        if perSecond > 0 {
            let total = e.earnedToday(at: now) + overtime.earnedToday(at: now, earnings: e)
            let nextCent = ((total * 100).rounded(.down) + 1) / 100
            candidates.append(now.addingTimeInterval(max((nextCent - total) / perSecond, 1)))
        }
        return candidates.filter { $0 > now.addingTimeInterval(0.05) }.min() ?? now.addingTimeInterval(60)
    }

    // MARK: Milestones, wishes and the end-of-day summary

    private func check(at now: Date, earnings e: Earnings) {
        let currency = defaults.string(forKey: "currency") ?? "MAD"
        let today = Calendar.current.startOfDay(for: now)

        // Daily milestones. The first check after launch or midnight only records where we are.
        if defaults.object(forKey: "celebrate") as? Bool ?? true {
            let step = max(defaults.object(forKey: "milestoneStep") as? Double ?? 100, 1)
            let total = e.earnedToday(at: now) + overtime.earnedToday(at: now, earnings: e)
            let index = Int(total / step)
            let basis = "\(currency)|\(e.salary)|\(step)"
            if let last = lastMilestone, last.day == today, last.basis == basis, index > last.index {
                Celebration.show("💰 \((Double(index) * step).money(currency, decimals: 0)) today!")
            }
            lastMilestone = (today, basis, index)

            // Wishlist items that just became affordable.
            var celebrated = Set(defaults.stringArray(forKey: "celebratedWishes") ?? [])
            let reached = wishlist.items.filter { item in
                !celebrated.contains(item.id.uuidString)
                    && e.earnedUntil(now, since: item.addedAt) + overtime.earned(from: item.addedAt, to: now, earnings: e) >= item.price
            }
            if !reached.isEmpty {
                reached.forEach { celebrated.insert($0.id.uuidString) }
                defaults.set(Array(celebrated), forKey: "celebratedWishes")
                Celebration.show("🎁 You've earned your \(reached.map(\.name).joined(separator: " & "))!", sound: "Hero")
            }
        }

        // End-of-day summary, sent once within the hour after work ends.
        if defaults.object(forKey: "notifyEndOfDay") as? Bool ?? true,
           e.isWorkday(now),
           now >= e.workEnd(on: now), now < e.workEnd(on: now).addingTimeInterval(3600),
           (defaults.object(forKey: "lastEndOfDayNotice") as? Date).map({ $0 < today }) ?? true {
            defaults.set(now, forKey: "lastEndOfDayNotice")
            let todayTotal = e.earnedToday(at: now) + overtime.earnedToday(at: now, earnings: e)
            let month = e.earnedThisMonth(at: now)
                + overtime.earned(from: Calendar.current.dateInterval(of: .month, for: now)!.start, to: now, earnings: e)
            Notifier.send(title: "Workday done 🎉",
                          body: "You earned \(todayTotal.money(currency)) today. This month: \(month.money(currency)).")
        }
    }
}

@main
struct RealTimeCounterApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(model.clock)
                .environmentObject(model.wishlist)
                .environmentObject(model.overtime)
        } label: {
            MenuBarLabel(clock: model.clock, overtime: model.overtime)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(model.wishlist)
                .environmentObject(model.overtime)
        }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var clock: Clock
    @ObservedObject var overtime: Overtime
    @AppStorage("salary") private var salary = 10_000.0
    @AppStorage("period") private var period = SalaryPeriod.monthly.rawValue
    @AppStorage("currency") private var currency = "MAD"
    @AppStorage("startMinutes") private var startMinutes = 9 * 60
    @AppStorage("endMinutes") private var endMinutes = 18 * 60
    @AppStorage("lunchEnabled") private var lunchEnabled = true
    @AppStorage("lunchStartMinutes") private var lunchStartMinutes = 13 * 60
    @AppStorage("lunchEndMinutes") private var lunchEndMinutes = 14 * 60

    var body: some View {
        let e = Earnings(salary: salary, period: SalaryPeriod(rawValue: period) ?? .monthly,
                         startMinutes: startMinutes, endMinutes: endMinutes,
                         lunchEnabled: lunchEnabled, lunchStartMinutes: lunchStartMinutes, lunchEndMinutes: lunchEndMinutes)
        let total = e.earnedToday(at: clock.now) + overtime.earnedToday(at: clock.now, earnings: e)
        if UserDefaults.standard.object(forKey: "salary") == nil {
            Text("Set Salary")
        } else {
            Text(total.money(currency))
                .monospacedDigit()
                .accessibilityLabel("WealthCounter, earned today \(total.money(currency))")
        }
    }
}
