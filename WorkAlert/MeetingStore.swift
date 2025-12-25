import Foundation
import UserNotifications

enum DataSource {
    case mock
    case googleCalendar
}

struct DailyReminder: Identifiable, Codable, Equatable {
    var id = UUID()
    var hour: Int
    var minute: Int
    var isEnabled: Bool

    var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date)
        }
        return "\(hour):\(String(format: "%02d", minute))"
    }
}

@Observable
class MeetingStore {
    var meetings: [Meeting] = []
    var notificationPermissionGranted: Bool = false
    var alarmsSet: Bool = false
    var isLoading: Bool = false
    var errorMessage: String?
    var dataSource: DataSource = .mock
    var dailyReminders: [DailyReminder] = []

    private let notificationCenter = UNUserNotificationCenter.current()
    private var calendarService: CalendarService?

    private let alarmsSetDateKey = "alarmsSetDate"
    private let dailyRemindersKey = "dailyReminders"

    init(dataSource: DataSource = .mock) {
        self.dataSource = dataSource
        if dataSource == .mock {
            loadMockMeetings()
        }
        checkIfAlarmsSetToday()
        loadDailyReminders()
    }

    // MARK: - Persistence

    private func checkIfAlarmsSetToday() {
        if let savedDate = UserDefaults.standard.object(forKey: alarmsSetDateKey) as? Date {
            alarmsSet = Calendar.current.isDateInToday(savedDate)
        } else {
            alarmsSet = false
        }
    }

    private func saveAlarmsSetDate() {
        UserDefaults.standard.set(Date(), forKey: alarmsSetDateKey)
    }

    private func loadDailyReminders() {
        if let data = UserDefaults.standard.data(forKey: dailyRemindersKey),
           let reminders = try? JSONDecoder().decode([DailyReminder].self, from: data) {
            dailyReminders = reminders
        } else {
            // Default: one reminder at 8am
            dailyReminders = [DailyReminder(hour: 8, minute: 0, isEnabled: true)]
        }
    }

    func saveDailyReminders() {
        if let data = try? JSONEncoder().encode(dailyReminders) {
            UserDefaults.standard.set(data, forKey: dailyRemindersKey)
        }
        Task {
            await scheduleDailyReminders()
        }
    }

    func addDailyReminder() {
        dailyReminders.append(DailyReminder(hour: 9, minute: 0, isEnabled: true))
        saveDailyReminders()
    }

    func removeDailyReminder(at offsets: IndexSet) {
        dailyReminders.remove(atOffsets: offsets)
        saveDailyReminders()
    }

    func scheduleDailyReminders() async {
        // Remove existing daily reminders
        let pendingRequests = await notificationCenter.pendingNotificationRequests()
        let dailyReminderIds = pendingRequests.filter { $0.identifier.hasPrefix("daily-reminder-") }.map { $0.identifier }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: dailyReminderIds)

        // Schedule enabled reminders
        for reminder in dailyReminders where reminder.isEnabled {
            let content = UNMutableNotificationContent()
            content.title = "Check your meetings"
            content.body = "Open Daily Nudge to see today's schedule"
            content.sound = UNNotificationSound.default

            var dateComponents = DateComponents()
            dateComponents.hour = reminder.hour
            dateComponents.minute = reminder.minute

            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            let request = UNNotificationRequest(
                identifier: "daily-reminder-\(reminder.id.uuidString)",
                content: content,
                trigger: trigger
            )

            do {
                try await notificationCenter.add(request)
            } catch {
                print("Failed to schedule daily reminder: \(error)")
            }
        }
    }

    // MARK: - Configure Calendar Service

    func configureCalendarService(authManager: GoogleAuthManager) {
        self.calendarService = CalendarService(authManager: authManager)
    }

    // MARK: - Load Meetings from Google Calendar

    func loadFromGoogleCalendar() async {
        guard let service = calendarService else {
            errorMessage = "Calendar service not configured"
            return
        }

        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            let fetchedMeetings = try await service.fetchTodaysMeetings()
            await MainActor.run {
                self.meetings = fetchedMeetings
                self.dataSource = .googleCalendar
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    // MARK: - Refresh Meetings

    func refreshMeetings() async {
        switch dataSource {
        case .mock:
            loadMockMeetings()
        case .googleCalendar:
            await loadFromGoogleCalendar()
        }
    }

    // MARK: - Switch to Mock Data

    func switchToMockData() {
        dataSource = .mock
        loadMockMeetings()
    }

    // MARK: - Mock Data Loading

    func loadMockMeetings() {
        let calendar = Calendar.current
        let today = Date()

        // Helper to create a date for today at specific hour/minute
        func todayAt(hour: Int, minute: Int) -> Date {
            var components = calendar.dateComponents([.year, .month, .day], from: today)
            components.hour = hour
            components.minute = minute
            return calendar.date(from: components) ?? today
        }

        meetings = [
            Meeting(
                title: "FD sync [bi-weekly]",
                startTime: todayAt(hour: 9, minute: 0),
                endTime: todayAt(hour: 9, minute: 30),
                location: "Zoom - Team Room",
                isRecurring: true
            ),
            Meeting(
                title: "Leadership Weekly",
                startTime: todayAt(hour: 10, minute: 0),
                endTime: todayAt(hour: 10, minute: 30),
                location: "Conference Room A",
                isRecurring: true
            ),
            Meeting(
                title: "Foundry Pipeline Review [weekly]",
                startTime: todayAt(hour: 11, minute: 0),
                endTime: todayAt(hour: 12, minute: 0),
                location: "Zoom - Planning Room",
                isRecurring: true
            ),
            Meeting(
                title: "Lunch Break",
                startTime: todayAt(hour: 12, minute: 0),
                endTime: todayAt(hour: 13, minute: 0),
                alarmEnabled: false // No alarm for lunch by default
            ),
            Meeting(
                title: "Client Call - Acme Corp",
                startTime: todayAt(hour: 14, minute: 0),
                endTime: todayAt(hour: 14, minute: 45),
                location: "Teams Meeting"
            ),
            Meeting(
                title: "1:1 with Manager",
                startTime: todayAt(hour: 15, minute: 30),
                endTime: todayAt(hour: 16, minute: 0),
                location: "Slack Huddle"
            ),
            Meeting(
                title: "Team Retrospective",
                startTime: todayAt(hour: 16, minute: 30),
                endTime: todayAt(hour: 17, minute: 30),
                location: "Conference Room B",
                isRecurring: true
            )
        ]
        dataSource = .mock
    }

    // MARK: - Notification Permission

    func requestNotificationPermission() async {
        do {
            let granted = try await notificationCenter.requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            await MainActor.run {
                self.notificationPermissionGranted = granted
            }
        } catch {
            print("Notification permission error: \(error)")
        }
    }

    // MARK: - Toggle Meeting Alarm

    func toggleAlarm(for meeting: Meeting) {
        if let index = meetings.firstIndex(where: { $0.id == meeting.id }) {
            meetings[index].alarmEnabled.toggle()
        }
    }

    // MARK: - Schedule Notifications

    func scheduleAlarms() async {
        // Remove any previously scheduled notifications
        notificationCenter.removeAllPendingNotificationRequests()

        let enabledMeetings = meetings.filter { $0.alarmEnabled }

        for meeting in enabledMeetings {
            // Only schedule if the alarm time is in the future
            guard meeting.alarmTime > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Meeting in 1 minute"
            content.body = meeting.title
            if let location = meeting.location {
                content.subtitle = location
            }
            content.sound = UNNotificationSound(named: UNNotificationSoundName("retro-game.wav"))
            content.categoryIdentifier = "MEETING_ALARM"

            let triggerDate = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: meeting.alarmTime
            )
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: triggerDate,
                repeats: false
            )

            let request = UNNotificationRequest(
                identifier: meeting.id.uuidString,
                content: content,
                trigger: trigger
            )

            do {
                try await notificationCenter.add(request)
            } catch {
                print("Failed to schedule notification for \(meeting.title): \(error)")
            }
        }

        await MainActor.run {
            self.alarmsSet = true
            self.saveAlarmsSetDate()
        }
    }

    // MARK: - Cancel All Alarms

    func cancelAllAlarms() {
        notificationCenter.removeAllPendingNotificationRequests()
        alarmsSet = false
    }

    // MARK: - Helpers

    var enabledMeetingsCount: Int {
        meetings.filter { $0.alarmEnabled }.count
    }

    var futureMeetingsCount: Int {
        meetings.filter { $0.alarmEnabled && $0.alarmTime > Date() }.count
    }
}
