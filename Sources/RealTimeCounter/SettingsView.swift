import SwiftUI
import ServiceManagement

/// The settings window (⌘,): a fixed toolbar of panes that remembers the last one viewed.
struct SettingsView: View {
    @AppStorage("settingsPane") private var pane = "pay"

    var body: some View {
        TabView(selection: $pane) {
            PaySettings()
                .tabItem { Label("Pay", systemImage: "banknote") }
                .tag("pay")
            HoursSettings()
                .tabItem { Label("Hours", systemImage: "clock") }
                .tag("hours")
            MotivationSettings()
                .tabItem { Label("Motivation", systemImage: "sparkles") }
                .tag("motivation")
        }
        .frame(width: 460)
        .onAppear { NSApp.activate(ignoringOtherApps: true) }   // menu bar apps open settings behind other windows
    }
}

private struct PaySettings: View {
    @AppStorage("salary") private var salary = 10_000.0
    @AppStorage("period") private var period = SalaryPeriod.monthly.rawValue
    @AppStorage("currency") private var currency = "MAD"
    @AppStorage("jobStart") private var jobStart = 0.0
    @AppStorage("overtimeMultiplier") private var multiplier = 1.5

    private static let currencies = Locale.commonISOCurrencyCodes.sorted()

    var body: some View {
        Form {
            Section {
                TextField("Salary", value: $salary, format: .number, prompt: Text("e.g. 12,000"))
                Picker("Paid", selection: $period) {
                    ForEach(SalaryPeriod.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                Picker("Currency", selection: $currency) {
                    ForEach(currencyOptions, id: \.self) { code in
                        Text("\(Locale.current.localizedString(forCurrencyCode: code) ?? code) (\(code))").tag(code)
                    }
                }
            } footer: {
                if salary <= 0 {
                    ValidationMessage("Enter a salary above zero to start counting.")
                }
            }

            Section {
                DatePicker("Job started", selection: jobStartBinding, in: ...Date.now, displayedComponents: .date)
            } footer: {
                Text("Used for lifetime earnings.")
            }

            Section {
                Picker("Overtime rate", selection: $multiplier) {
                    ForEach([1.0, 1.25, 1.5, 2.0], id: \.self) { Text("\($0.formatted())× hourly rate").tag($0) }
                }
            } footer: {
                Text("Overtime only counts time outside your working hours.")
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var currencyOptions: [String] {
        Self.currencies.contains(currency) ? Self.currencies : [currency] + Self.currencies
    }

    private var jobStartBinding: Binding<Date> {
        Binding(
            get: { jobStart == 0 ? Calendar.current.startOfDay(for: .now) : Date(timeIntervalSinceReferenceDate: jobStart) },
            set: { jobStart = Calendar.current.startOfDay(for: $0).timeIntervalSinceReferenceDate }
        )
    }
}

private struct HoursSettings: View {
    @AppStorage("startMinutes") private var startMinutes = 9 * 60
    @AppStorage("endMinutes") private var endMinutes = 18 * 60
    @AppStorage("lunchEnabled") private var lunchEnabled = true
    @AppStorage("lunchStartMinutes") private var lunchStartMinutes = 13 * 60
    @AppStorage("lunchEndMinutes") private var lunchEndMinutes = 14 * 60

    var body: some View {
        Form {
            Section {
                DatePicker("Starts", selection: timeBinding($startMinutes), displayedComponents: .hourAndMinute)
                DatePicker("Ends", selection: timeBinding($endMinutes), displayedComponents: .hourAndMinute)
            } footer: {
                if endMinutes <= startMinutes {
                    ValidationMessage("Your workday has to end after it starts.")
                } else {
                    Text("Only weekdays are counted. Your salary is split evenly across each month's weekdays.")
                }
            }

            Section {
                Toggle("Lunch break", isOn: $lunchEnabled)
                if lunchEnabled {
                    DatePicker("From", selection: timeBinding($lunchStartMinutes), displayedComponents: .hourAndMinute)
                    DatePicker("Until", selection: timeBinding($lunchEndMinutes), displayedComponents: .hourAndMinute)
                }
            } footer: {
                if lunchError {
                    ValidationMessage("Lunch has to fit inside your working hours.")
                } else {
                    Text("Time on lunch isn't counted.")
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var lunchError: Bool {
        lunchEnabled && !(startMinutes <= lunchStartMinutes && lunchStartMinutes < lunchEndMinutes && lunchEndMinutes <= endMinutes)
    }
}

private struct MotivationSettings: View {
    @AppStorage("currency") private var currency = "MAD"
    @AppStorage("celebrate") private var celebrate = true
    @AppStorage("milestoneStep") private var milestoneStep = 100.0
    @AppStorage("celebrationSound") private var sound = true
    @AppStorage("notifyEndOfDay") private var notify = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                Toggle("Celebrate milestones", isOn: $celebrate)
                if celebrate {
                    TextField("Every", value: $milestoneStep, format: .currency(code: currency).precision(.fractionLength(0)))
                    Toggle("Play sound", isOn: $sound)
                    LabeledContent("Try it") {
                        Button("Preview Celebration") {
                            Celebration.show("\(milestoneStep.money(currency, decimals: 0)) today")
                        }
                    }
                }
            } footer: {
                Text("Confetti each time today's total passes another milestone, and when you earn a wishlist item.")
            }

            Section {
                Toggle("End-of-day summary", isOn: $notify)
                    .onChange(of: notify) { _, on in if on { Notifier.requestAccess() } }
            } footer: {
                Text("A notification with what you earned, sent when your workday ends. macOS asks for permission the first time.")
            }

            Section {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
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

/// Inline error placed next to the problem. The icon carries the color; the text keeps full contrast.
struct ValidationMessage: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Label {
            Text(text).foregroundStyle(.primary)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }
}
