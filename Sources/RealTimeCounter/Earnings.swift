import Foundation

enum SalaryPeriod: String, CaseIterable, Identifiable {
    case monthly = "Monthly"
    case yearly = "Yearly"
    var id: String { rawValue }
}

enum WorkStatus {
    case beforeWork, working, lunch, finished, weekend
}

/// Pure calculation of money earned, based on salary, work hours and the calendar.
struct Earnings {
    var salary: Double
    var period: SalaryPeriod
    var startMinutes: Int   // minutes after midnight, e.g. 9:00 = 540
    var endMinutes: Int     // e.g. 18:00 = 1080
    var lunchEnabled = true
    var lunchStartMinutes = 13 * 60
    var lunchEndMinutes = 14 * 60
    var calendar = Calendar.current

    /// Builds the calculator from the values saved in Settings.
    static func fromDefaults(_ d: UserDefaults = .standard) -> Earnings {
        func int(_ key: String, _ fallback: Int) -> Int { d.object(forKey: key) as? Int ?? fallback }
        return Earnings(
            salary: d.object(forKey: "salary") as? Double ?? 10_000,
            period: SalaryPeriod(rawValue: d.string(forKey: "period") ?? "") ?? .monthly,
            startMinutes: int("startMinutes", 9 * 60),
            endMinutes: int("endMinutes", 18 * 60),
            lunchEnabled: d.object(forKey: "lunchEnabled") as? Bool ?? true,
            lunchStartMinutes: int("lunchStartMinutes", 13 * 60),
            lunchEndMinutes: int("lunchEndMinutes", 14 * 60)
        )
    }

    var monthlySalary: Double { period == .monthly ? salary : salary / 12 }

    /// Paid stretches of a day in minutes after midnight: morning and afternoon around lunch.
    var segments: [(start: Int, end: Int)] {
        let end = max(endMinutes, startMinutes)
        guard lunchEnabled else { return [(startMinutes, end)] }
        let ls = min(max(lunchStartMinutes, startMinutes), end)
        let le = min(max(lunchEndMinutes, ls), end)
        return [(startMinutes, ls), (le, end)].filter { $0.end > $0.start }
    }

    var workMinutes: Int { max(segments.reduce(0) { $0 + $1.end - $1.start }, 1) }
    var workSeconds: Double { Double(workMinutes) * 60 }

    /// Paid seconds between two moments within a single day.
    func workedSeconds(on day: Date, from: Date, to: Date) -> Double {
        let midnight = calendar.startOfDay(for: day)
        return segments.reduce(0) { total, seg in
            let s = max(midnight.addingTimeInterval(Double(seg.start) * 60), from)
            let e = min(midnight.addingTimeInterval(Double(seg.end) * 60), to)
            return total + max(e.timeIntervalSince(s), 0)
        }
    }

    func lunchEnd(on date: Date) -> Date {
        calendar.startOfDay(for: date).addingTimeInterval(Double(lunchEndMinutes) * 60)
    }

    /// Paid seconds still left today.
    func secondsLeft(at now: Date) -> Double {
        workedSeconds(on: now, from: now, to: workEnd(on: now))
    }

    func isWorkday(_ date: Date) -> Bool { !calendar.isDateInWeekend(date) }

    func workdaysInMonth(of date: Date) -> Int {
        guard let range = calendar.range(of: .day, in: .month, for: date),
              let first = calendar.date(from: calendar.dateComponents([.year, .month], from: date))
        else { return 22 }
        return range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: first) }
            .filter(isWorkday).count
    }

    func dailyRate(on date: Date) -> Double {
        monthlySalary / Double(max(workdaysInMonth(of: date), 1))
    }

    func hourlyRate(on date: Date) -> Double { dailyRate(on: date) / (workSeconds / 3600) }

    func workStart(on date: Date) -> Date {
        calendar.startOfDay(for: date).addingTimeInterval(Double(startMinutes) * 60)
    }

    func workEnd(on date: Date) -> Date {
        calendar.startOfDay(for: date).addingTimeInterval(Double(endMinutes) * 60)
    }

    /// Fraction of today's workday completed, 0...1 (0 on weekends).
    func dayProgress(at now: Date) -> Double {
        guard isWorkday(now) else { return 0 }
        let worked = workedSeconds(on: now, from: calendar.startOfDay(for: now), to: now)
        return min(worked / workSeconds, 1)
    }

    func status(at now: Date) -> WorkStatus {
        guard isWorkday(now) else { return .weekend }
        if now < workStart(on: now) { return .beforeWork }
        if now >= workEnd(on: now) { return .finished }
        let minute = Int(now.timeIntervalSince(calendar.startOfDay(for: now)) / 60)
        return segments.contains { minute >= $0.start && minute < $0.end } ? .working : .lunch
    }

    func earnedToday(at now: Date) -> Double {
        dailyRate(on: now) * dayProgress(at: now)
    }

    /// Money earned during work hours between two moments.
    func earned(from start: Date, to end: Date) -> Double {
        guard end > start else { return 0 }
        var rates = MonthRates(earnings: self)
        var total = 0.0
        var day = calendar.startOfDay(for: start)
        while day <= end {
            if isWorkday(day) {
                total += rates.daily(on: day) * workedSeconds(on: day, from: start, to: end) / workSeconds
            }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return total
    }

    /// Regular paid seconds between two moments (used so overtime never double-counts work hours).
    func paidSeconds(from start: Date, to end: Date) -> Double {
        guard end > start else { return 0 }
        var total = 0.0
        var day = calendar.startOfDay(for: start)
        while day <= end {
            if isWorkday(day) { total += workedSeconds(on: day, from: start, to: end) }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return total
    }

    /// Everything earned since the job started. Days before today are cached so the
    /// 30fps dashboard doesn't re-walk years of calendar on every frame.
    func lifetime(since jobStart: Date, at now: Date) -> Double {
        let midnight = calendar.startOfDay(for: now)
        let key = "\(salary)|\(period)|\(segments.map { "\($0.start)-\($0.end)" })|\(jobStart)|\(midnight)"
        let base: Double
        if let cached = LifetimeCache.value, LifetimeCache.key == key {
            base = cached
        } else {
            base = earned(from: jobStart, to: midnight)
            LifetimeCache.key = key
            LifetimeCache.value = base
        }
        return base + earned(from: max(jobStart, midnight), to: now)
    }

    /// The moment the money earned since `start` reaches `amount` (nil if more than ~50 years away).
    func date(whenEarned amount: Double, since start: Date) -> Date? {
        guard monthlySalary > 0 else { return nil }
        var rates = MonthRates(earnings: self)
        var remaining = amount
        var day = calendar.startOfDay(for: start)
        for _ in 0..<(365 * 50) {
            if isWorkday(day) {
                let rate = rates.daily(on: day) / workSeconds
                for seg in segments {
                    let from = max(day.addingTimeInterval(Double(seg.start) * 60), start)
                    let to = day.addingTimeInterval(Double(seg.end) * 60)
                    guard to > from else { continue }
                    let available = rate * to.timeIntervalSince(from)
                    if available >= remaining { return from.addingTimeInterval(remaining / rate) }
                    remaining -= available
                }
            }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return nil
    }

    /// Work time needed to earn `amount` at the current hourly rate, e.g. "3 workdays 4h".
    func workTime(for amount: Double, at now: Date) -> String {
        let rate = hourlyRate(on: now)
        guard rate > 0 else { return "—" }
        let totalMinutes = Int((amount / rate * 60).rounded(.up))
        let dayMinutes = workMinutes
        let d = totalMinutes / dayMinutes
        let h = (totalMinutes % dayMinutes) / 60
        let m = totalMinutes % 60
        let days = "\(d) workday\(d == 1 ? "" : "s")"
        if d > 0 { return d >= 10 || h == 0 ? days : "\(days) \(h)h" }
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        return "\(max(m, 1))m"
    }

    func earnedThisMonth(at now: Date) -> Double {
        guard let first = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else { return 0 }
        let today = calendar.startOfDay(for: now)
        var day = first
        var fullDays = 0
        while day < today {
            if isWorkday(day) { fullDays += 1 }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return Double(fullDays) * dailyRate(on: now) + earnedToday(at: now)
    }
}

private enum LifetimeCache {
    static var key = ""
    static var value: Double?
}

/// Caches the daily rate per month so long date walks stay cheap.
private struct MonthRates {
    let earnings: Earnings
    var cache: [Int: Double] = [:]

    mutating func daily(on day: Date) -> Double {
        let c = earnings.calendar.dateComponents([.year, .month], from: day)
        let key = (c.year ?? 0) * 12 + (c.month ?? 0)
        if let rate = cache[key] { return rate }
        let rate = earnings.dailyRate(on: day)
        cache[key] = rate
        return rate
    }
}

private enum MoneyFormatters {
    static var cache: [String: NumberFormatter] = [:]
}

extension Double {
    /// Currency string, truncated (never rounded up) so a live counter only ever moves forward.
    func money(_ currency: String, decimals: Int = 2) -> String {
        let code = currency.isEmpty ? "USD" : currency
        let key = "\(code)|\(decimals)"
        let f = MoneyFormatters.cache[key] ?? {
            let f = NumberFormatter()
            f.numberStyle = .currency
            f.currencyCode = code
            f.minimumFractionDigits = decimals
            f.maximumFractionDigits = decimals
            f.roundingMode = .down
            MoneyFormatters.cache[key] = f
            return f
        }()
        return f.string(from: NSNumber(value: self)) ?? String(format: "%.\(decimals)f", self)
    }
}
