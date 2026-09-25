import Foundation

struct OvertimeSession: Codable {
    var start: Date
    var end: Date?          // nil while running
    var hourlyRate: Double  // regular hourly rate × multiplier, fixed when started
}

/// Extra time worked outside regular hours, saved so it counts toward today, the month and lifetime.
final class Overtime: ObservableObject {
    @Published private(set) var sessions: [OvertimeSession] { didSet { save() } }
    private let key = "overtimeSessions"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([OvertimeSession].self, from: data) {
            sessions = saved
        } else {
            sessions = []
        }
    }

    var isActive: Bool { sessions.last.map { $0.end == nil } ?? false }

    func start(at now: Date, hourlyRate: Double) {
        guard !isActive else { return }
        sessions.append(OvertimeSession(start: now, hourlyRate: hourlyRate))
    }

    /// Stops the running session and returns what it earned.
    @discardableResult
    func stop(at now: Date, earnings: Earnings) -> Double {
        guard isActive else { return 0 }
        let earned = earnedInCurrentSession(at: now, earnings: earnings)
        sessions[sessions.count - 1].end = now
        return earned
    }

    func earnedInCurrentSession(at now: Date, earnings: Earnings) -> Double {
        guard isActive, let s = sessions.last else { return 0 }
        return value(of: s, from: s.start, to: now, earnings: earnings)
    }

    /// Overtime money earned between two moments. Regular paid hours are skipped.
    func earned(from start: Date, to end: Date, earnings: Earnings) -> Double {
        sessions.reduce(0) { total, s in
            total + value(of: s, from: max(s.start, start), to: min(s.end ?? end, end), earnings: earnings)
        }
    }

    func earnedToday(at now: Date, earnings: Earnings) -> Double {
        earned(from: Calendar.current.startOfDay(for: now), to: now, earnings: earnings)
    }

    private func value(of s: OvertimeSession, from: Date, to: Date, earnings: Earnings) -> Double {
        guard to > from else { return 0 }
        let extra = to.timeIntervalSince(from) - earnings.paidSeconds(from: from, to: to)
        return max(extra, 0) / 3600 * s.hourlyRate
    }

    private func save() {
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
