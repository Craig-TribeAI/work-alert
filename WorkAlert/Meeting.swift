import Foundation

struct Meeting: Identifiable, Hashable {
    let id: UUID
    let title: String
    let startTime: Date
    let endTime: Date
    let location: String?
    let isRecurring: Bool
    var alarmEnabled: Bool

    init(
        id: UUID = UUID(),
        title: String,
        startTime: Date,
        endTime: Date,
        location: String? = nil,
        isRecurring: Bool = false,
        alarmEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.location = location
        self.isRecurring = isRecurring
        self.alarmEnabled = alarmEnabled
    }

    /// Returns the time 1 minute before the meeting starts
    var alarmTime: Date {
        startTime.addingTimeInterval(-60)
    }

    /// Formatted time range for display (e.g., "9:00 AM - 9:15 AM")
    var formattedTimeRange: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: startTime)) - \(formatter.string(from: endTime))"
    }
}
