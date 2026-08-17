import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Settings → Food database: browse/search everything the app can match
/// without USDA, import nutrition sheets (CSV), and see sync status. Rows
/// come from label scans (automatic), CSV imports, the bundled starter set,
/// and — for invite-code installs — the shared community database.
struct FoodDatabaseView: View {
    @Environment(\.modelContext) private var modelContext
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

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Group {
                // The search field is part of the page rather than a system
                // searchable bar, which would arrive with its own chrome and
                // its own idea of what a text field looks like.
                LuxUnderlinedField(
                    placeholder: "Search your database",
                    text: $query,
                    size: 18,
                    autocapitalization: .sentences
                )
                .padding(.top, 16)

                HStack(spacing: 8) {
                    Button("IMPORT CSV") { showImporter = true }
                        .buttonStyle(GhostCapsule(gold: true))
                    if ClaudeEndpoint.proxyConfig != nil {
                        Button(syncing ? "SYNCING…" : "SYNC COMMUNITY") { syncNow() }
                            .buttonStyle(GhostCapsule())
                            .disabled(syncing)
                    }
                    Spacer()
                }
                .padding(.top, 18)

                if let importMessage {
                    LuxNote(importMessage, size: 14)
                        .padding(.top, 10)
                }

                LuxSectionHeader(text: "FOODS")
                    .padding(.top, 24)
                    .padding(.bottom, 2)
            }
            .luxRowChrome()

            if filtered.isEmpty {
                LuxNote(query.isEmpty
                        ? "Nothing here yet — scan a label or import a sheet."
                        : "No matches.", size: 15)
                    .padding(.top, 8)
                    .luxRowChrome()
            } else {
                ForEach(filtered) { food in
                    foodRow(food)
                        .luxRowChrome()
                }
                .onDelete(perform: deleteFoods)
            }

            Group {
                LuxNote("Scanned labels are added automatically, without duplicates. A CSV needs a header row of name, brand, serving, calories, protein, carbs, fat — plus optional micronutrient columns like caffeine or sodium. Values are per serving.")
                    .padding(.top, 16)
                    .padding(.bottom, 40)
            }
            .luxRowChrome()
        }
        .luxList()
        .safeAreaInset(edge: .top, spacing: 0) {
            LuxHeader(title: "FOOD DATABASE", subtitle: subtitle) {
                LuxBackButton { dismiss() }
            } trailing: {
                EmptyView()
            }
            .padding(.bottom, 8)
            .background(Lux.ground)
        }
        .toolbar(.hidden, for: .navigationBar)
        .keyboardDismissBar()
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            importFile(result)
        }
    }

    /// "220 foods on file, searched before USDA." — what's here and why it
    /// matters, which the old section header said in passing.
    private var subtitle: String {
        let n = foods.count
        guard n > 0 else { return "Nothing on file yet." }
        return "\(n) food\(n == 1 ? "" : "s") on file, searched before USDA."
    }

    private func foodRow(_ food: CustomFood) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(food.displayName)
                .font(Lux.serif(17))
                .foregroundStyle(Lux.cream)
            Text("\(food.serving.uppercased()) · \(Int(food.calories.rounded())) KCAL · P \(Int(food.protein.rounded())) · C \(Int(food.carbs.rounded())) · F \(Int(food.fat.rounded()))")
                .font(Lux.smallcaps(8))
                .tracking(1.5)
                .foregroundStyle(Lux.cream.opacity(0.45))
            Text(sourceLabel(food.source).uppercased())
                .font(Lux.smallcaps(7))
                .tracking(2)
                .foregroundStyle(Lux.goldLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .luxRow(vertical: 11)
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
