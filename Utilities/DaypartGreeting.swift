import Foundation

enum DaypartGreeting {
    static func title(at date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5...7: return "Early morning"
        case 8...11: return "Morning"
        case 12...14: return "Early afternoon"
        case 15...17: return "Late afternoon"
        case 18...19: return "Early evening"
        case 20...22: return "Evening"
        default: return "Night"
        }
    }
}
