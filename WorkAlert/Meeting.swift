import Foundation

struct Meeting: Identifiable, Hashable {
    let id: UUID
    let calendarEventId: String?  // Google Calendar event ID for matching across refreshes
    let title: String
    let startTime: Date
    let endTime: Date
    let location: String?
    let isRecurring: Bool
    var alarmEnabled: Bool

    init(
        id: UUID = UUID(),
        calendarEventId: String? = nil,
        title: String,
        startTime: Date,
        endTime: Date,
        location: String? = nil,
        isRecurring: Bool = false,
        alarmEnabled: Bool = true
    ) {
        self.id = id
        self.calendarEventId = calendarEventId
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

    /// Stable identifier for matching meetings across refreshes
    /// Uses calendar event ID if available, falls back to title+time hash
    var stableId: String {
        if let eventId = calendarEventId {
            return eventId
        }
        // For mock data, use title + start time as a stable identifier
        let dateFormatter = ISO8601DateFormatter()
        return "\(title)-\(dateFormatter.string(from: startTime))"
    }

    /// Check if this meeting has meaningfully changed from another (same stableId)
    func hasChanged(from other: Meeting) -> Bool {
        return title != other.title ||
               abs(startTime.timeIntervalSince(other.startTime)) > 60 ||
               abs(endTime.timeIntervalSince(other.endTime)) > 60 ||
               location != other.location
    }
}
