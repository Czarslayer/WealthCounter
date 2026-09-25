import SwiftUI
import ServiceManagement

struct ContentView: View {
    @AppStorage("salary") private var salary = 10_000.0
    @AppStorage("period") private var period = SalaryPeriod.monthly.rawValue
    @AppStorage("currency") private var currency = "MAD"
    @AppStorage("startMinutes") private var startMinutes = 9 * 60
    @AppStorage("endMinutes") private var endMinutes = 18 * 60
    @AppStorage("lunchEnabled") private var lunchEnabled = true
    @AppStorage("lunchStartMinutes") private var lunchStartMinutes = 13 * 60
    @AppStorage("lunchEndMinutes") private var lunchEndMinutes = 14 * 60
    @State private var page = Page.dashboard

    enum Page { case dashboard, wishlist, settings }

    private var earnings: Earnings {
        Earnings(salary: salary, period: SalaryPeriod(rawValue: period) ?? .monthly,
                 startMinutes: startMinutes, endMinutes: endMinutes,
                 lunchEnabled: lunchEnabled, lunchStartMinutes: lunchStartMinutes, lunchEndMinutes: lunchEndMinutes)
    }

    var body: some View {
        VStack(spacing: 0) {
            switch page {
            case .dashboard:
                // Redraws ~30x per second so the number visibly climbs.
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    Dashboard(earnings: earnings, currency: currency, now: context.date, go: go)
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            case .wishlist:
                WishlistView(earnings: earnings, currency: currency, done: { go(.dashboard) })
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .settings:
                SettingsView(done: { go(.dashboard) })
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(width: 320)
    }

    private func go(_ target: Page) {
        withAnimation(.snappy) { page = target }
    }
}

// MARK: - Dashboard

struct Dashboard: View {
    let earnings: Earnings
    let currency: String
    let now: Date
    let go: (ContentView.Page) -> Void

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
        let live = status == .working || overtime.isActive

        VStack(alignment: .leading, spacing: 18) {
            HStack {
                StatusPill(status: status, overtime: overtime.isActive, earnings: earnings, now: now)
                Spacer()
                Text(now, format: .dateTime.weekday(.wide).day().month())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Earned today")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(today.money(currency, decimals: 4))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(live ? AnyShapeStyle((overtime.isActive ? Color.orange : .green).gradient) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }

            VStack(spacing: 6) {
                ProgressView(value: earnings.dayProgress(at: now))
                    .tint(.green)
                HStack {
                    Text(earnings.workStart(on: now), format: .dateTime.hour().minute())
                    Spacer()
                    Text("\(Int(earnings.dayProgress(at: now) * 100))%")
                    Spacer()
                    Text(earnings.workEnd(on: now), format: .dateTime.hour().minute())
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }

            overtimeControl(status: status)

            HStack(spacing: 10) {
                StatTile(title: "This month", value: month.money(currency))
                StatTile(title: "Per hour", value: earnings.hourlyRate(on: now).money(currency))
            }

            lifetimeCard

            if let next = wishlist.items.first {
                Button { go(.wishlist) } label: {
                    WishRow(item: next, earnings: earnings, currency: currency, now: now, compact: true)
                }
                .buttonStyle(.plain)
            }

            Divider()

            HStack(spacing: 16) {
                Button { go(.wishlist) } label: {
                    Label("Wishlist", systemImage: "gift")
                }
                Button { go(.settings) } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(18)
    }

    @ViewBuilder
    private func overtimeControl(status: WorkStatus) -> some View {
        if overtime.isActive {
            HStack {
                Label {
                    Text("Overtime +\(overtime.earnedInCurrentSession(at: now, earnings: earnings).money(currency))")
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "flame.fill")
                }
                .font(.callout.weight(.medium))
                .foregroundStyle(.orange)
                Spacer()
                Button("Stop") {
                    let earned = overtime.stop(at: now, earnings: earnings)
                    if notify {
                        Notifier.send(title: "Overtime done 🔥", body: "You earned an extra \(earned.money(currency)).")
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding(10)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else if status != .working {
            Button {
                overtime.start(at: now, hourlyRate: earnings.hourlyRate(on: now) * multiplier)
            } label: {
                Label("Start overtime · ×\(multiplier.formatted())", systemImage: "flame")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.orange)
        }
    }

    private var lifetimeCard: some View {
        Button { if jobStart == 0 { go(.settings) } } label: {
            VStack(alignment: .leading, spacing: 3) {
                if jobStart == 0 {
                    Text("Lifetime earnings").font(.caption).foregroundStyle(.secondary)
                    Text("Set your job start date in Settings →")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    let start = Date(timeIntervalSinceReferenceDate: jobStart)
                    let total = earnings.lifetime(since: start, at: now)
                        + overtime.earned(from: start, to: now, earnings: earnings)
                    Text("Lifetime earnings · since \(start.formatted(.dateTime.month(.abbreviated).year()))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(total.money(currency))
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.yellow.gradient)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct StatusPill: View {
    let status: WorkStatus
    let overtime: Bool
    let earnings: Earnings
    let now: Date

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.caption.weight(.medium))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(color.opacity(0.15), in: Capsule())
    }

    private var color: Color {
        if overtime && status != .working { return .red }
        switch status {
        case .working: return .green
        case .lunch: return .yellow
        case .beforeWork: return .orange
        case .finished: return .blue
        case .weekend: return .purple
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
        case .beforeWork: return "Not started yet"
        case .finished: return "Done for today"
        case .weekend: return "Weekend"
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Settings

struct SettingsView: View {
    let done: () -> Void

    @AppStorage("salary") private var salary = 10_000.0
    @AppStorage("period") private var period = SalaryPeriod.monthly.rawValue
    @AppStorage("currency") private var currency = "MAD"
    @AppStorage("startMinutes") private var startMinutes = 9 * 60
    @AppStorage("endMinutes") private var endMinutes = 18 * 60
    @AppStorage("lunchEnabled") private var lunchEnabled = true
    @AppStorage("lunchStartMinutes") private var lunchStartMinutes = 13 * 60
    @AppStorage("lunchEndMinutes") private var lunchEndMinutes = 14 * 60
    @AppStorage("jobStart") private var jobStart = 0.0
    @AppStorage("overtimeMultiplier") private var multiplier = 1.5
    @AppStorage("celebrate") private var celebrate = true
    @AppStorage("milestoneStep") private var milestoneStep = 100.0
    @AppStorage("celebrationSound") private var sound = true
    @AppStorage("notifyEndOfDay") private var notify = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(action: done) { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                Text("Settings").font(.headline)
                Spacer()
                Button("Done", action: done)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .top], 18)

            Form {
                Section("Pay") {
                    TextField("Salary", value: $salary, format: .number)
                    Picker("Period", selection: $period) {
                        ForEach(SalaryPeriod.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    TextField("Currency", text: $currency)
                    DatePicker("Job started", selection: jobStartBinding, in: ...Date.now, displayedComponents: .date)
                }

                Section {
                    DatePicker("Starts", selection: timeBinding($startMinutes), displayedComponents: .hourAndMinute)
                    DatePicker("Ends", selection: timeBinding($endMinutes), displayedComponents: .hourAndMinute)
                    Toggle("Lunch break", isOn: $lunchEnabled)
                    if lunchEnabled {
                        DatePicker("Lunch from", selection: timeBinding($lunchStartMinutes), displayedComponents: .hourAndMinute)
                        DatePicker("Lunch until", selection: timeBinding($lunchEndMinutes), displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("Hours")
                } footer: {
                    Text("Weekends and lunch aren't counted. Your salary is split evenly across each month's weekdays.")
                }

                Section("Overtime") {
                    Picker("Overtime rate", selection: $multiplier) {
                        ForEach([1.0, 1.25, 1.5, 2.0], id: \.self) { Text("×\($0.formatted())").tag($0) }
                    }
                }

                Section("Fun") {
                    Toggle("Celebrate milestones", isOn: $celebrate)
                    if celebrate {
                        TextField("Every", value: $milestoneStep, format: .number)
                        Toggle("Sound", isOn: $sound)
                        Button("Preview celebration") {
                            Celebration.show("💰 \(milestoneStep.money(currency, decimals: 0)) today!")
                        }
                    }
                    Toggle("End-of-day notification", isOn: $notify)
                        .onChange(of: notify) { _, on in if on { Notifier.requestAccess() } }
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, on in
                            try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                        }
                }
            }
            .formStyle(.grouped)
            .frame(height: 440)
        }
    }

    private var jobStartBinding: Binding<Date> {
        Binding(
            get: { jobStart == 0 ? Calendar.current.startOfDay(for: .now) : Date(timeIntervalSinceReferenceDate: jobStart) },
            set: { jobStart = Calendar.current.startOfDay(for: $0).timeIntervalSinceReferenceDate }
        )
    }

    /// Bridges "minutes after midnight" storage to a DatePicker.
    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { Calendar.current.startOfDay(for: .now).addingTimeInterval(Double(minutes.wrappedValue) * 60) },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }
}
