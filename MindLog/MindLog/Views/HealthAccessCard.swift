import SwiftUI

/// A soft ask for Health access: explains what MindLog would read and why,
/// and is equally happy left declined forever. Hides itself on devices
/// without Health (e.g. iPad) rather than showing a dead end.
struct HealthAccessCard: View {
    @Environment(\.appAccent) private var accent
    @AppStorage(HealthKitReader.optInKey) private var optedIn = false
    @ObservedObject private var reader = HealthKitReader.shared

    var body: some View {
        if !HealthKitReader.isAvailable {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Label("Sleep & steps", systemImage: "heart.text.square")
                    .font(.headline)
                    .foregroundStyle(accent)

                if optedIn {
                    connectedContent
                } else {
                    disconnectedContent
                }
            }
            .card()
            .task(id: optedIn) {
                if optedIn { await reader.snapshot(for: .now) }
            }
        }
    }

    private var disconnectedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("If you'd like, MindLog can read your sleep and steps from Health so a day's mood sits next to how you slept and moved. Read-only, stays on this phone, and everything works fine if you'd rather not.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                Task {
                    let granted = await reader.requestAccess()
                    if granted {
                        optedIn = true
                        await reader.snapshot(for: .now)
                    }
                }
            } label: {
                Text("Connect Health")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
        }
    }

    private var connectedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(reader.latest?.summary ?? "No sleep or step data yet for today.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button(role: .destructive) {
                optedIn = false
                HealthSnapshotStore.clear()
            } label: {
                Text("Disconnect")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Text("This stops MindLog from reading new data. To revoke access itself, use the Health app under Sharing.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
