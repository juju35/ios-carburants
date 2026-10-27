import Foundation

/// Texts in French, like the feed and the rest of the app.
public enum Format {
    private static let french = Locale(identifier: "fr_FR")

    /// "1,749"
    public static func priceNumber(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(3)).locale(french))
    }

    /// "1,749 €"
    public static func price(_ value: Double) -> String { "\(priceNumber(value)) €" }

    /// Driving travel time: "8 min", "1 h 12 min", "2 h".
    public static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remaining = minutes % 60
        return remaining == 0 ? "\(hours) h" : "\(hours) h \(remaining) min"
    }

    /// "850 m", "3,4 km", "12 km".
    public static func distance(_ km: Double) -> String {
        if km < 0.995 { return "\(Int((km * 100).rounded()) * 10) m" }
        if km < 10 { return "\(km.formatted(.number.precision(.fractionLength(1)).locale(french))) km" }
        return "\(Int(km.rounded())) km"
    }

    /// "12 min", "3 h", "2 j" since `date`; nil under a minute. A station clock ahead of time counts as now.
    private static func elapsed(_ date: Date, now: Date) -> String? {
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        switch minutes {
        case ..<1: return nil
        case ..<60: return "\(minutes) min"
        case ..<(48 * 60): return "\(minutes / 60) h"
        default: return "\(minutes / (24 * 60)) j"
        }
    }

    /// "il y a 12 min", "à l'instant".
    public static func ago(_ date: Date, now: Date = .now) -> String {
        elapsed(date, now: now).map { "il y a \($0)" } ?? "à l’instant"
    }

    /// "12 min", at least "1 min".
    public static func since(_ date: Date, now: Date = .now) -> String { elapsed(date, now: now) ?? "1 min" }

    /// "Gazole", "E10, SP98", "3 carburants".
    public static func fuels(_ fuels: [Fuel]) -> String {
        switch fuels.count {
        case 1: fuels[0].label
        case 2: fuels.map(\.short).joined(separator: ", ")
        default: "\(fuels.count) carburants"
        }
    }
}

/// Opening status, as carbOpening() in the Lovelace card. Stations are in France: their hours are read in
/// French time, whatever the phone's time zone.
public struct Opening: Hashable, Sendable {
    public enum State: Sendable { case open, closed, always, automate }

    public let state: State
    public let text: String

    private static let zone = TimeZone(identifier: "Europe/Paris") ?? .current
    private static let parisCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal
    }()

    public static let dayNames = ["Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi", "Dimanche"]
    private static let shortDayNames = ["lun.", "mar.", "mer.", "jeu.", "ven.", "sam.", "dim."]

    /// The time opening statuses are worked out at when none is given: now, or a fixed time (screenshots).
    nonisolated(unsafe) public static var clock: () -> Date = { .now }

    /// 9:41 today, French time: the time of screenshots, to match their status bar.
    public static var nineFortyOne: Date {
        parisCalendar.date(bySettingHour: 9, minute: 41, second: 0, of: .now) ?? .now
    }

    /// 1 = Monday … 7 = Sunday, and minutes since midnight, in French time.
    public static func now(_ date: Date = Opening.clock()) -> (day: Int, minutes: Int) {
        let parts = parisCalendar.dateComponents([.weekday, .hour, .minute], from: date)
        let day = ((parts.weekday ?? 2) + 5) % 7 + 1
        return (day, (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }

    public static func of(_ station: Station, at date: Date = Opening.clock()) -> Opening? {
        let hours = station.hours
        let (day, current) = now(date)
        if alwaysOpen(hours) { return Opening(state: .always, text: "Ouvert 24h/24") }

        let today = hours.first { $0.day == day && !$0.closed }
        if let range = today?.ranges.first(where: { contains($0, current) }) {
            return Opening(state: .open, text: "Ouvert · ferme à \(range.close)")
        }
        // After midnight, in yesterday's range that ends today (06:00–01:00).
        let yesterday = hours.first { $0.day == (day + 5) % 7 + 1 && !$0.closed }
        if let range = yesterday?.ranges.first(where: { minutes($0.close) < minutes($0.open) && current < minutes($0.close) }) {
            return Opening(state: .open, text: "Ouvert · ferme à \(range.close)")
        }
        if station.automate24 { return Opening(state: .automate, text: "Automate 24h/24") }
        if hours.isEmpty { return nil }
        return Opening(state: .closed, text: nextOpening(hours, today: today, day: day, current: current))
    }

    /// Open every day from 00:00 to 23:59 or later.
    public static func alwaysOpen(_ hours: [DayHours]) -> Bool {
        hours.count == 7 && hours.allSatisfy { day in
            !day.closed && day.ranges.contains { $0.open == "00:00" && minutes($0.close) >= 23 * 60 + 59 }
        }
    }

    /// In the range today; one ending after midnight (close before open) runs to the end of the day.
    private static func contains(_ range: TimeRange, _ current: Int) -> Bool {
        let open = minutes(range.open)
        let close = minutes(range.close)
        return close > open ? current >= open && current < close : current >= open
    }

    static func minutes(_ hhmm: String) -> Int {
        let parts = hhmm.split(separator: ":")
        let hours = parts.first.flatMap { Int($0) } ?? 0
        let mins = parts.dropFirst().first.flatMap { Int($0) } ?? 0
        return hours * 60 + mins
    }

    /// "Fermé · ouvre à 14:00" later today, else on the next open day.
    private static func nextOpening(_ hours: [DayHours], today: DayHours?, day: Int, current: Int) -> String {
        if let range = today?.ranges.first(where: { minutes($0.open) > current }) {
            return "Fermé · ouvre à \(range.open)"
        }
        for offset in 1...7 {
            let target = (day - 1 + offset) % 7 + 1
            guard let next = hours.first(where: { $0.day == target }), !next.closed, let first = next.ranges.first else { continue }
            if offset == 1 { return "Fermé · ouvre demain à \(first.open)" }
            return "Fermé · ouvre \(shortDayNames[target - 1]) à \(first.open)"
        }
        return "Fermé"
    }
}
