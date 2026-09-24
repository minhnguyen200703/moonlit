import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: MomentStore
    @AppStorage("reminderInterval") private var interval = 2
    @AppStorage("reminderStartHour") private var startHour = 8
    @AppStorage("reminderEndHour") private var endHour = 22
    @State private var status = ""
    @AppStorage("remindersEnabled") private var remindersEnabled = false

    var body: some View {
        Form {
            Section("Gentle reminders") {
                Picker("Every", selection: $interval) {
                    ForEach([1, 2, 3, 4, 6], id: \.self) { Text("\($0) hour\($0 == 1 ? "" : "s")").tag($0) }
                }
                Picker("Start", selection: $startHour) {
                    ForEach(0..<24, id: \.self) { Text(hourLabel($0)).tag($0) }
                }
                Picker("End", selection: $endHour) {
                    ForEach(0..<24, id: \.self) { Text(hourLabel($0)).tag($0) }
                }

                Button(remindersEnabled ? "Save reminder schedule" : "Enable reminders") {
                    Task { await enableReminders() }
                }
                if !status.isEmpty { Text(status).font(.caption).foregroundStyle(MoonlitTheme.wine) }
            }

            Section("Connection") {
                Label(store.couple?.isActive == true ? "Paired privately" : "Waiting for your person", systemImage: "person.2.fill")
                Label("Photos use a private Supabase bucket", systemImage: "lock.fill")
                Label(
                    store.isSyncing ? "Synchronizing" :
                        (store.lastRefreshSucceeded ? "Shared sky is up to date" : "Refresh needed"),
                    systemImage: "arrow.triangle.2.circlepath"
                )
            }

            if store.legacyImportCount > 0 {
                Section("Earlier moments") {
                    Text("Moonlit found \(store.legacyImportCount) moment\(store.legacyImportCount == 1 ? "" : "s") from v0.1. They remain only on this iPhone until you choose to share them.")
                    Button("Share earlier moments") {
                        Task { await store.shareLegacyMoments() }
                    }
                }
            }

            Section("Moonlit") {
                Text("Version 0.2 Phase 2")
                Text("Under the same moon, always ♡")
                    .foregroundStyle(MoonlitTheme.wine)
            }
        }
        .navigationTitle("Settings")
    }

    private func enableReminders() async {
        do {
            let granted = try await ReminderService.shared.requestPermission()
            guard granted else { status = "Notifications are not allowed in iOS Settings."; return }
            try await ReminderService.shared.schedule(.init(
                intervalHours: interval,
                startHour: startHour,
                endHour: endHour
            ))
            status = "Reminders are scheduled ♡"
            remindersEnabled = true
        } catch {
            status = error.localizedDescription
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        return Calendar.current.date(from: components)?.formatted(date: .omitted, time: .shortened) ?? "\(hour):00"
    }
}
