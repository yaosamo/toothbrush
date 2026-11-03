import Foundation

struct BrushSession: Codable {
    let date: Date
    let seconds: Int
}

struct Achievement: Identifiable {
    let id: String
    let title: String
    let detail: String
    let emoji: String
    let isEarned: ([BrushSession]) -> Bool
}

enum Achievements {
    static let all: [Achievement] = [
        Achievement(id: "first", title: "First Brush", detail: "Finish your first brushing", emoji: "🪥") { $0.count >= 1 },
        Achievement(id: "twoMin", title: "Two-Minute Hero", detail: "Brush for 2 whole minutes", emoji: "⏱️") {
            $0.contains { $0.seconds >= 120 }
        },
        Achievement(id: "sunMoon", title: "Sun & Moon", detail: "Brush morning and evening on the same day", emoji: "🌗") {
            hasMorningAndEvening($0)
        },
        Achievement(id: "streak3", title: "Bamboo Sprout", detail: "Brush 3 days in a row", emoji: "🎋") { streak($0) >= 3 },
        Achievement(id: "streak7", title: "Bamboo Forest", detail: "Brush 7 days in a row", emoji: "🌳") { streak($0) >= 7 },
        Achievement(id: "ten", title: "Temple Guardian", detail: "Brush 10 times", emoji: "🏮") { $0.count >= 10 },
        Achievement(id: "thirty", title: "Golden Panda", detail: "Brush 30 times", emoji: "🥇") { $0.count >= 30 },
    ]

    /// Longest run of consecutive calendar days with at least one session.
    static func streak(_ sessions: [BrushSession]) -> Int {
        let cal = Calendar.current
        let days = Set(sessions.map { cal.startOfDay(for: $0.date) }).sorted()
        var best = 0, run = 0
        var prev: Date?
        for d in days {
            if let p = prev, cal.dateComponents([.day], from: p, to: d).day == 1 { run += 1 } else { run = 1 }
            best = max(best, run)
            prev = d
        }
        return best
    }

    static func hasMorningAndEvening(_ sessions: [BrushSession]) -> Bool {
        let cal = Calendar.current
        let byDay = Dictionary(grouping: sessions) { cal.startOfDay(for: $0.date) }
        return byDay.values.contains { day in
            let hours = day.map { cal.component(.hour, from: $0.date) }
            return hours.contains { $0 < 12 } && hours.contains { $0 >= 17 }
        }
    }
}

final class AchievementStore: ObservableObject {
    @Published private(set) var sessions: [BrushSession] = []
    @Published private(set) var unlocked: [String: Date] = [:]
    /// Set when a new achievement is earned; the UI shows it and clears it.
    @Published var justUnlocked: Achievement?

    /// Sessions shorter than this are treated as accidental button presses.
    let minimumSeconds = 10

    private let key = "brushwatch.store.v1"

    private struct Saved: Codable {
        var sessions: [BrushSession]
        var unlocked: [String: Date]
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            sessions = saved.sessions
            unlocked = saved.unlocked
        }
    }

    var totalSessions: Int { sessions.count }

    /// Records a finished session. Returns true if it counted.
    @discardableResult
    func record(seconds: Int, at date: Date = Date()) -> Bool {
        guard seconds >= minimumSeconds else { return false }
        sessions.append(BrushSession(date: date, seconds: seconds))
        for a in Achievements.all where unlocked[a.id] == nil && a.isEarned(sessions) {
            unlocked[a.id] = date
            justUnlocked = a   // if several unlock at once, the last one is shown
        }
        save()
        return true
    }

    func reset() {
        sessions = []; unlocked = [:]; justUnlocked = nil
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(Saved(sessions: sessions, unlocked: unlocked)) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
