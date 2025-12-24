import Foundation

class CalendarService {
    private let authManager: GoogleAuthManager
    private let baseURL = "https://www.googleapis.com/calendar/v3"

    init(authManager: GoogleAuthManager) {
        self.authManager = authManager
    }

    // MARK: - Fetch Today's Events

    func fetchTodaysMeetings() async throws -> [Meeting] {
        let accessToken = try await authManager.getAccessToken()

        // Calculate start and end of today
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        // Format dates for API (RFC3339)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timeMin = formatter.string(from: startOfDay)
        let timeMax = formatter.string(from: endOfDay)

        // Build URL with query parameters
        var components = URLComponents(string: "\(baseURL)/calendars/primary/events")!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: timeMin),
            URLQueryItem(name: "timeMax", value: timeMax),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "50")
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CalendarServiceError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw CalendarServiceError.apiError(statusCode: httpResponse.statusCode)
        }

        let calendarResponse = try JSONDecoder().decode(GoogleCalendarResponse.self, from: data)

        // Convert Google Calendar events to our Meeting model
        return calendarResponse.items.compactMap { event -> Meeting? in
            // Skip all-day events (they don't have dateTime)
            guard let startDateTime = event.start.dateTime,
                  let endDateTime = event.end.dateTime else {
                return nil
            }

            let startDate = parseGoogleDate(startDateTime)
            let endDate = parseGoogleDate(endDateTime)

            guard let start = startDate, let end = endDate else {
                return nil
            }

            return Meeting(
                id: UUID(), // Generate new UUID since Google IDs are strings
                title: event.summary ?? "Untitled Meeting",
                startTime: start,
                endTime: end,
                location: event.location ?? event.hangoutLink,
                isRecurring: event.recurringEventId != nil,
                alarmEnabled: true
            )
        }
    }

    // MARK: - Date Parsing

    private func parseGoogleDate(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = formatter.date(from: dateString) {
            return date
        }

        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: dateString)
    }
}

// MARK: - Google Calendar API Response Models

struct GoogleCalendarResponse: Codable {
    let items: [GoogleCalendarEvent]
}

struct GoogleCalendarEvent: Codable {
    let id: String
    let summary: String?
    let location: String?
    let hangoutLink: String?
    let start: GoogleCalendarDateTime
    let end: GoogleCalendarDateTime
    let recurringEventId: String?
}

struct GoogleCalendarDateTime: Codable {
    let dateTime: String?  // For timed events
    let date: String?      // For all-day events
    let timeZone: String?
}

// MARK: - Errors

enum CalendarServiceError: LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Google Calendar API"
        case .apiError(let statusCode):
            return "Google Calendar API error (status: \(statusCode))"
        }
    }
}
