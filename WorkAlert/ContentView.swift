import SwiftUI

struct ContentView: View {
    @State private var store = MeetingStore()
    @State private var authManager = GoogleAuthManager()
    @State private var showingConfirmation = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Data source selector
                dataSourceSection

                // Header instruction text
                headerSection

                // Meeting list
                meetingListSection

                // Set Alarms button
                bottomButtonSection
            }
            .navigationTitle("Work Alert")
            .task {
                await store.requestNotificationPermission()
                store.configureCalendarService(authManager: authManager)
            }
            .alert("Alarms Set!", isPresented: $showingConfirmation) {
                Button("OK", role: .cancel) { }
            } message: {
                let count = store.futureMeetingsCount
                if count > 0 {
                    Text("You'll be alerted 1 minute before \(count) meeting\(count == 1 ? "" : "s").")
                } else {
                    Text("No upcoming meetings to set alarms for.")
                }
            }
            .refreshable {
                await store.refreshMeetings()
            }
        }
    }

    // MARK: - Data Source Section

    private var dataSourceSection: some View {
        VStack(spacing: 12) {
            if authManager.isSignedIn {
                // Signed in - show account info and data source toggle
                HStack {
                    Image(systemName: "person.crop.circle.fill")
                        .foregroundStyle(.green)
                    Text(authManager.userEmail ?? "Connected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Sign Out") {
                        authManager.signOut()
                        store.switchToMockData()
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }

                // Toggle between mock and real data
                HStack {
                    Button {
                        store.switchToMockData()
                    } label: {
                        Text("Mock Data")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(store.dataSource == .mock ? Color.orange : Color.gray.opacity(0.3))
                            .foregroundStyle(store.dataSource == .mock ? .white : .primary)
                            .clipShape(Capsule())
                    }

                    Button {
                        Task {
                            await store.loadFromGoogleCalendar()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if store.isLoading {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                            Text("Google Calendar")
                        }
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(store.dataSource == .googleCalendar ? Color.orange : Color.gray.opacity(0.3))
                        .foregroundStyle(store.dataSource == .googleCalendar ? .white : .primary)
                        .clipShape(Capsule())
                    }
                    .disabled(store.isLoading)

                    Spacer()
                }
            } else {
                // Not signed in - show connect button
                HStack {
                    Image(systemName: "calendar.badge.plus")
                        .foregroundStyle(.orange)
                    Text("Connect your calendar to load real meetings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                Button {
                    Task {
                        do {
                            try await authManager.signIn()
                            await store.loadFromGoogleCalendar()
                        } catch {
                            print("Sign in error: \(error)")
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "g.circle.fill")
                        Text("Sign in with Google")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            // Error message
            if let error = store.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Here are your meetings today.")
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
            Text("Toggle off any you don't need alarms for. Tap Set Alarms and you're done.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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

    // MARK: - Bottom Button Section

    private var bottomButtonSection: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    await store.scheduleAlarms()
                    showingConfirmation = true
                }
            } label: {
                HStack {
                    Image(systemName: "bell.fill")
                    Text("Set Alarms")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(store.notificationPermissionGranted ? Color.orange : Color.gray)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!store.notificationPermissionGranted || store.meetings.isEmpty)

            if !store.notificationPermissionGranted {
                Text("Please enable notifications in Settings to use alarms.")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }
}

// MARK: - Meeting Row Component

struct MeetingRow: View {
    @Binding var meeting: Meeting

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

            // Alarm toggle
            Toggle("", isOn: $meeting.alarmEnabled)
                .labelsHidden()
                .tint(.orange)
        }
        .padding(.vertical, 4)
        .opacity(meeting.alarmEnabled ? 1.0 : 0.6)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
