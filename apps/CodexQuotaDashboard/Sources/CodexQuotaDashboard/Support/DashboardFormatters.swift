import Foundation

enum DashboardFormat {
    static func tokens(_ value: Double?) -> String {
        let value = value ?? 0
        if value >= 1_000_000 {
            return String(format: "%.1f млн", value / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1f тыс.", value / 1_000)
        }
        return String(Int(value))
    }

    static func duration(_ value: Double?) -> String {
        let seconds = Int(value ?? 0)
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        if hours > 0 {
            return "\(hours) ч \(minutes) мин"
        }
        return "\(max(1, minutes)) мин"
    }

    static func reset(_ timestamp: TimeInterval?) -> String {
        guard let timestamp else { return "Нет данных" }
        let date = Date(timeIntervalSince1970: timestamp)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM, HH:mm"
        return formatter.string(from: date)
    }

    static func remaining(_ timestamp: TimeInterval?) -> String {
        guard let timestamp else { return "" }
        let seconds = max(0, Int(timestamp - Date().timeIntervalSince1970))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        return "через \(days) д. \(hours) ч."
    }

    static func updated(_ timestamp: TimeInterval?) -> String {
        guard let timestamp else { return "нет данных" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }
}
