import SwiftUI

struct ContentView: View {
    @AppStorage("salary") private var salary = 10_000.0
    @AppStorage("period") private var period = SalaryPeriod.monthly.rawValue
    @AppStorage("currency") private var currency = "MAD"
    @AppStorage("startMinutes") private var startMinutes = 9 * 60
    @AppStorage("endMinutes") private var endMinutes = 18 * 60
    @AppStorage("lunchEnabled") private var lunchEnabled = true
    @AppStorage("lunchStartMinutes") private var lunchStartMinutes = 13 * 60
    @AppStorage("lunchEndMinutes") private var lunchEndMinutes = 14 * 60
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject private var clock: Clock
    @State private var page: Page
    @State private var isVisible = true

    enum Page: String { case dashboard, wishlist }

    init(initialPage: Page = .dashboard) {
        _page = State(initialValue: initialPage)
    }

    private var earnings: Earnings {
        Earnings(salary: salary, period: SalaryPeriod(rawValue: period) ?? .monthly,
                 startMinutes: startMinutes, endMinutes: endMinutes,
                 lunchEnabled: lunchEnabled, lunchStartMinutes: lunchStartMinutes, lunchEndMinutes: lunchEndMinutes)
    }

    /// The salary default is only a placeholder; until it's saved we ask for it instead of faking numbers.
    private var isConfigured: Bool {
        _ = salary   // re-evaluate when the salary changes
        return UserDefaults.standard.object(forKey: "salary") != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            switch page {
            case .dashboard:
                if isConfigured {
                    // ~30fps so the number visibly climbs; once a second with Reduce Motion.
                    // Fully paused while the panel is closed, so only the menu bar costs anything.
                    TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1.0 / 30, paused: !isVisible)) { context in
                        Dashboard(earnings: earnings, currency: currency, now: isVisible ? context.date : clock.now,
                                  go: go, settings: showSettings)
                    }
                    .transition(transition(from: .leading))
                } else {
                    SetupPrompt(openSettings: showSettings)
                }
            case .wishlist:
                WishlistView(earnings: earnings, currency: currency, isVisible: isVisible, done: { go(.dashboard) })
                    .transition(transition(from: .trailing))
            }
        }
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)   // the panel is exactly as tall as its content
        .background(WindowVisibilityReader(isVisible: $isVisible))
    }

    private func transition(from edge: Edge) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
    }

    private func showSettings() {
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func go(_ target: Page) {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .snappy) { page = target }
    }
}

// MARK: - First run

struct SetupPrompt: View {
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "banknote")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            VStack(spacing: 4) {
                Text("Set your salary to start").font(.headline)
                Text("WealthCounter uses your salary and working hours to count what you earn, live.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Open Settings…", action: openSettings)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(SubtleButtonStyle())
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }
}

// MARK: - Dashboard

struct Dashboard: View {
    let earnings: Earnings
    let currency: String
    let now: Date
    let go: (ContentView.Page) -> Void
    let settings: () -> Void

    @EnvironmentObject private var wishlist: Wishlist
    @EnvironmentObject private var overtime: Overtime
    @AppStorage("jobStart") private var jobStart = 0.0   // 0 = not set
    @AppStorage("overtimeMultiplier") private var multiplier = 1.5
    @AppStorage("notifyEndOfDay") private var notify = true

    var body: some View {
        let status = earnings.status(at: now)
        let today = earnings.earnedToday(at: now) + overtime.earnedToday(at: now, earnings: earnings)
        let monthStart = Calendar.current.dateInterval(of: .month, for: now)!.start
        let month = earnings.earnedThisMonth(at: now) + overtime.earned(from: monthStart, to: now, earnings: earnings)

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                StatusLine(status: status, overtime: overtime.isActive, earnings: earnings, now: now)
                Spacer()
                Text(now, format: .dateTime.weekday(.abbreviated).day().month())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 14)

            // Hero
            SectionLabel("Today")
            liveMoneyText(today, currency: currency)
                .font(.system(size: 38, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .accessibilityLabel("Earned today")
                .accessibilityValue(today.money(currency))
                .accessibilityAddTraits(.updatesFrequently)
            Text(subtitle(status: status))
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .padding(.bottom, 14)

            WorkdayBar(earnings: earnings, now: now)
                .padding(.bottom, 16)

            Divider().padding(.bottom, 12)

            VStack(spacing: 6) {
                Metric(title: "This month", value: month.money(currency))
                Metric(title: "Per hour", value: earnings.hourlyRate(on: now).money(currency))
                lifetimeMetric
            }
            .padding(.bottom, 12)

            Divider().padding(.bottom, 10)

            overtimeRow(status: status)
                .padding(.bottom, 10)

            if let next = wishlist.items.first {
                Divider()
                Button { go(.wishlist) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel("Next goal")
                        WishRow(item: next, earnings: earnings, currency: currency, now: now, compact: true)
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(SubtleButtonStyle(horizontalPadding: 0))
                .accessibilityHint("Opens your wishlist")
            }

            Divider().padding(.bottom, 8)

            HStack(spacing: 2) {
                Button { go(.wishlist) } label: { Label("Wishlist", systemImage: "gift") }
                Button(action: settings) { Label("Settings…", systemImage: "gearshape") }
                    .keyboardShortcut(",")
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .buttonStyle(SubtleButtonStyle())
            .foregroundStyle(.secondary)
            .padding(.horizontal, -8)
        }
        .padding(16)
    }

    private func subtitle(status: WorkStatus) -> String {
        let full = earnings.dailyRate(on: now).money(currency)
        let percent = Int(earnings.dayProgress(at: now) * 100)
        switch status {
        case .weekend: return "Weekends aren't counted. Enjoy it."
        case .beforeWork:
            return "Starts at \(earnings.workStart(on: now).formatted(date: .omitted, time: .shortened))"
        case .finished: return overtime.isActive ? "Workday complete · overtime running" : "Workday complete"
        case .working, .lunch: return "of \(full) · \(percent)%"
        }
    }

    @ViewBuilder
    private var lifetimeMetric: some View {
        if jobStart == 0 {
            HStack {
                Text("Lifetime").foregroundStyle(.secondary)
                Spacer()
                Button("Set Start Date…", action: settings)
                    .buttonStyle(.link)
            }
        } else {
            let start = Date(timeIntervalSinceReferenceDate: jobStart)
            let total = earnings.lifetime(since: start, at: now) + overtime.earned(from: start, to: now, earnings: earnings)
            Metric(title: "Lifetime", value: total.money(currency))
                .help("Since \(start.formatted(date: .long, time: .omitted))")
        }
    }

    private func overtimeRow(status: WorkStatus) -> some View {
        let active = overtime.isActive
        let blocked = status == .working && !active
        let caption: String = {
            if active { return "+\(overtime.earnedInCurrentSession(at: now, earnings: earnings).money(currency)) this session" }
            if blocked { return "Available outside your working hours" }
            return "Keep counting at \(multiplier.formatted())× your hourly rate"
        }()

        return HStack {
            Image(systemName: active ? "flame.fill" : "flame")
                .foregroundStyle(active ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Overtime")
                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            Toggle("Overtime", isOn: Binding(
                get: { active },
                set: { on in
                    if on {
                        overtime.start(at: .now, hourlyRate: earnings.hourlyRate(on: now) * multiplier)
                    } else {
                        let earned = overtime.stop(at: .now, earnings: earnings)
                        if notify {
                            Notifier.send(title: "Overtime done", body: "You earned an extra \(earned.money(currency)).")
                        }
                    }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(blocked)
        }
        .accessibilityElement(children: .combine)
    }
}

struct Metric: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The workday drawn to scale: paid stretches as bars, lunch as a real gap between them.
struct WorkdayBar: View {
    let earnings: Earnings
    let now: Date

    var body: some View {
        let first = Double(earnings.startMinutes)
        let span = Double(max(earnings.endMinutes - earnings.startMinutes, 1))
        let minute = now.timeIntervalSince(Calendar.current.startOfDay(for: now)) / 60
        let counting = earnings.isWorkday(now)

        VStack(spacing: 5) {
            GeometryReader { geo in
                ForEach(Array(earnings.segments.enumerated()), id: \.offset) { _, seg in
                    let length = Double(seg.end - seg.start)
                    let x = (Double(seg.start) - first) / span * geo.size.width
                    let width = length / span * geo.size.width
                    let fill = counting ? min(max((minute - Double(seg.start)) / length, 0), 1) : 0
                    Capsule()
                        .fill(.quaternary)
                        .overlay(alignment: .leading) {
                            Capsule().fill(.green).frame(width: width * fill)
                        }
                        .clipShape(Capsule())
                        .frame(width: width, height: 6)
                        .offset(x: x)
                }
            }
            .frame(height: 6)

            HStack {
                Text(time(earnings.startMinutes))
                Spacer()
                if earnings.lunchEnabled, earnings.segments.count > 1 {
                    Text("Lunch \(time(earnings.lunchStartMinutes))–\(time(earnings.lunchEndMinutes))")
                    Spacer()
                }
                Text(time(earnings.endMinutes))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Workday progress")
        .accessibilityValue("\(Int(earnings.dayProgress(at: now) * 100)) percent")
    }

    private func time(_ minutes: Int) -> String {
        Calendar.current.startOfDay(for: now).addingTimeInterval(Double(minutes) * 60)
            .formatted(date: .omitted, time: .shortened)
    }
}

struct StatusLine: View {
    let status: WorkStatus
    let overtime: Bool
    let earnings: Earnings
    let now: Date

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        if overtime && status != .working { return .orange }
        switch status {
        case .working: return .green
        case .lunch: return .yellow
        case .beforeWork, .finished, .weekend: return .secondary
        }
    }

    private var label: String {
        if overtime && status != .working { return "Overtime" }
        switch status {
        case .working:
            let left = Int(earnings.secondsLeft(at: now))
            return "Earning · \(left / 3600)h \((left % 3600) / 60)m left"
        case .lunch:
            return "Lunch · back at \(earnings.lunchEnd(on: now).formatted(date: .omitted, time: .shortened))"
        case .beforeWork: return "Not started"
        case .finished: return "Done for today"
        case .weekend: return "Weekend"
        }
    }
}
