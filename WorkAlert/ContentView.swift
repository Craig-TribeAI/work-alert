import SwiftUI

struct ContentView: View {
    @State private var store = MeetingStore()
    @State private var authManager = GoogleAuthManager()
    @State private var showSettings = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header instruction text
                headerSection

                // Meeting list
                meetingListSection
            }
            .navigationTitle("Daily Nudge")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(store: store, authManager: authManager)
            }
            .task {
                await store.requestNotificationPermission()
                store.configureCalendarService(authManager: authManager)
                // Auto-load from Google if signed in
                if authManager.isSignedIn {
                    await store.loadFromGoogleCalendar()
                }
                await store.scheduleAlarms()
                await store.scheduleDailyReminders()
            }
            .refreshable {
                if authManager.isSignedIn {
                    await store.loadFromGoogleCalendar()
                } else {
                    await store.refreshMeetings()
                }
                await store.scheduleAlarms()
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                if newPhase == .active {
                    Task {
                        if authManager.isSignedIn {
                            await store.loadFromGoogleCalendar()
                        } else {
                            await store.refreshMeetings()
                        }
                        await store.scheduleAlarms()
                    }
                }
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Today's lineup. Let's do this.")
                    .font(.headline)
                Spacer()
                if store.dataSource == .mock {
                    Text("DEMO")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
            }
            HStack(spacing: 4) {
                if store.alarmsSet && store.futureMeetingsCount > 0 {
                    Image(systemName: "bell.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text("Alarms active for \(store.futureMeetingsCount) meeting\(store.futureMeetingsCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if !store.notificationPermissionGranted {
                    Image(systemName: "bell.slash")
                        .font(.caption)
                        .foregroundStyle(.red)
                    Text("Enable notifications in Settings")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text("Toggle off any meetings you don't need alarms for.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Meeting List Section

    private var meetingListSection: some View {
        Group {
            if store.meetings.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "calendar")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No meetings today")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    if store.dataSource == .googleCalendar {
                        Text("Pull to refresh")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach($store.meetings) { $meeting in
                        MeetingRow(meeting: $meeting)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

}

// MARK: - Meeting Row Component

struct MeetingRow: View {
    @Binding var meeting: Meeting

    private var isPast: Bool {
        meeting.startTime < Date()
    }

    var body: some View {
        HStack(spacing: 12) {
            // Time indicator
            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.startTime, style: .time)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(meeting.endTime, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 70, alignment: .leading)

            // Meeting details
            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(2)

                if let location = meeting.location {
                    HStack(spacing: 4) {
                        Image(systemName: meeting.location?.contains("http") == true ? "video.fill" : "location.fill")
                            .font(.caption2)
                        Text(location)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Alarm toggle (disabled for past meetings)
            if isPast {
                Text("Past")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Toggle("", isOn: $meeting.alarmEnabled)
                    .labelsHidden()
                    .tint(.orange)
            }
        }
        .padding(.vertical, 4)
        .opacity(isPast ? 0.4 : (meeting.alarmEnabled ? 1.0 : 0.6))
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Bindable var store: MeetingStore
    @Bindable var authManager: GoogleAuthManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Google Account Section
                Section {
                    if authManager.isSignedIn {
                        HStack {
                            Image(systemName: "person.crop.circle.fill")
                                .foregroundStyle(.green)
                            VStack(alignment: .leading) {
                                Text("Connected")
                                    .font(.subheadline)
                                if let email = authManager.userEmail {
                                    Text(email)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Sign Out") {
                                authManager.signOut()
                                store.switchToMockData()
                            }
                            .font(.caption)
                            .foregroundStyle(.red)
                        }
                    } else {
                        Button {
                            Task {
                                do {
                                    try await authManager.signIn()
                                    await store.loadFromGoogleCalendar()
                                    await store.scheduleAlarms()
                                } catch {
                                    print("Sign in error: \(error)")
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "g.circle.fill")
                                    .foregroundStyle(.blue)
                                Text("Sign in with Google")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Calendar")
                } footer: {
                    Text("Connect your Google Calendar to see your real meetings.")
                }

                // Daily Reminders Section
                Section {
                    ForEach($store.dailyReminders) { $reminder in
                        HStack {
                            DatePicker(
                                "",
                                selection: Binding(
                                    get: {
                                        var components = DateComponents()
                                        components.hour = reminder.hour
                                        components.minute = reminder.minute
                                        return Calendar.current.date(from: components) ?? Date()
                                    },
                                    set: { newDate in
                                        let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                                        reminder.hour = components.hour ?? 8
                                        reminder.minute = components.minute ?? 0
                                        store.saveDailyReminders()
                                    }
                                ),
                                displayedComponents: .hourAndMinute
                            )
                            .labelsHidden()

                            Spacer()

                            Toggle("", isOn: $reminder.isEnabled)
                                .labelsHidden()
                                .onChange(of: reminder.isEnabled) {
                                    store.saveDailyReminders()
                                }
                        }
                    }
                    .onDelete(perform: store.removeDailyReminder)

                    Button {
                        store.addDailyReminder()
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.green)
                            Text("Add Reminder")
                        }
                    }
                } header: {
                    Text("Daily Reminders")
                } footer: {
                    Text("Get notified to check your meetings at these times each day.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
