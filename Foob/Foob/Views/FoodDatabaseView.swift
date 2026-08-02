import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Settings → Food database: browse/search everything the app can match
/// without USDA, import nutrition sheets (CSV), and see sync status. Rows
/// come from label scans (automatic), CSV imports, the bundled starter set,
/// and — for invite-code installs — the shared community database.
struct FoodDatabaseView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appBackground) private var appBackground
    @Query(sort: \CustomFood.name) private var foods: [CustomFood]

    @State private var query = ""
    @State private var showImporter = false
    @State private var importMessage: String?
    @State private var syncing = false

    private var filtered: [CustomFood] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return foods }
        return foods.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.brand.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Foods stored") { Text("\(foods.count)").monospacedDigit() }
                Button {
                    showImporter = true
                } label: {
                    Label("Import nutrition sheet (CSV)", systemImage: "square.and.arrow.down")
                }
                if ClaudeEndpoint.proxyConfig != nil {
                    Button {
                        syncNow()
                    } label: {
                        if syncing {
                            HStack { ProgressView(); Text("Syncing…") }
                        } else {
                            Label("Sync with community now", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(syncing)
                }
                if let importMessage {
                    Text(importMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Scanned labels are added automatically (no duplicates). CSV format: a header row of name, brand, serving, calories, protein, carbs, fat — plus optional micronutrient columns like caffeine or sodium. Values are per serving.")
            }

            Section("Foods (searched before USDA)") {
                if filtered.isEmpty {
                    Text(query.isEmpty ? "Nothing here yet — scan a label or import a sheet." : "No matches.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filtered) { food in
                        foodRow(food)
                    }
                    .onDelete(perform: deleteFoods)
                }
            }
        }
        .searchable(text: $query, prompt: "Search your database")
        .keyboardDismissBar()
        .appBackground(appBackground)
        .navigationTitle("Food database")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            importFile(result)
        }
    }

    private func foodRow(_ food: CustomFood) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(food.displayName)
            Text("\(food.serving) · \(Int(food.calories.rounded())) kcal · P \(Int(food.protein.rounded()))g · C \(Int(food.carbs.rounded()))g · F \(Int(food.fat.rounded()))g")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(sourceLabel(food.source))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func sourceLabel(_ source: String) -> String {
        switch source {
        case "scan": return "From a label scan"
        case "import": return "Imported sheet"
        case "community": return "Community"
        case "seed": return "Starter set"
        default: return source
        }
    }

    private func deleteFoods(_ offsets: IndexSet) {
        let targets = offsets.map { filtered[$0] }
        for food in targets {
            modelContext.delete(food)
        }
        try? modelContext.save()
    }

    private func importFile(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        // Security-scoped: files picked from outside the sandbox need this.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let (added, skipped) = try CustomFoodStore.importCSV(text, in: modelContext)
            importMessage = "Imported \(added) food\(added == 1 ? "" : "s")"
                + (skipped > 0 ? " (\(skipped) already in the database)" : "")
        } catch {
            importMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func syncNow() {
        syncing = true
        Task {
            await CommunitySync.syncNow(context: modelContext)
            syncing = false
            importMessage = "Synced."
        }
    }
}
