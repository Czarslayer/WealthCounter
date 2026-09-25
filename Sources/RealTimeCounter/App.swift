import SwiftUI
import Combine

/// Ticks once per second so the menu bar title stays live.
final class Clock: ObservableObject {
    @Published var now = Date()
    private var timer: AnyCancellable?

    init() {
        timer = Timer.publish(every: 1, tolerance: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] in self?.now = $0 }
    }
}

/// Owns the shared state and watches the clock for milestones, reached wishes and the end of the day.
final class AppModel: ObservableObject {
    let clock = Clock()
    let wishlist = Wishlist()
    let overtime = Overtime()
    private var tick: AnyCancellable?
    private var lastMilestone: (day: Date, basis: String, index: Int)?
    private let defaults = UserDefaults.standard

    init() {
        tick = clock.$now.sink { [weak self] in self?.check(at: $0) }
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
                .environmentObject(wishlist).environmentObject(overtime))
        let w = NSWindow(contentViewController: NSHostingController(rootView: root))
        w.title = "Preview"
        if CommandLine.arguments.contains("--light") { w.appearance = NSAppearance(named: .aqua) }
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        previewWindow = w
        print("PREVIEW_WINDOW \(w.windowNumber)")
        fflush(stdout)
    }

    private func check(at now: Date) {
        let e = Earnings.fromDefaults()
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
                    && e.earned(from: item.addedAt, to: now) + overtime.earned(from: item.addedAt, to: now, earnings: e) >= item.price
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
