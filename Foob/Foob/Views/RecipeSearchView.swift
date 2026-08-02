import SwiftUI
import SwiftData

/// Search the web for recipes and import them into the library. Queries every
/// configured provider (Spoonacular, Edamam, and the always-on TheMealDB) and
/// lets the user tap a result to save it as a recipe.
struct RecipeSearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appBackground) private var appBackground

    @State private var query = ""
    @State private var results: [RecipeSearchResult] = []
    @State private var providerErrors: [String] = []
    @State private var isSearching = false
    @State private var searched = false
    @State private var importingID: String?
    @State private var importedIDs: Set<String> = []

    private let aggregator = RecipeSearchAggregator.configured
    private let lookup: NutritionLookup = USDANutritionLookupService()

    var body: some View {
        NavigationStack {
            List {
                if !searched {
                    providerStatusSection
                }

                if isSearching {
                    HStack { ProgressView(); Text("Searching…").foregroundStyle(.secondary) }
                } else if searched && results.isEmpty {
                    ContentUnavailableView(
                        "No recipes found",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different search, or add a provider key in Settings \u{2192} API keys for a bigger library.")
                    )
                } else {
                    ForEach(results) { result in
                        resultRow(result)
                    }
                }

                if !providerErrors.isEmpty {
                    Section("Some sources didn\u{2019}t respond") {
                        ForEach(providerErrors, id: \.self) { message in
                            Text(message).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .appBackground(appBackground)
            .navigationTitle("Find a recipe")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search recipes (e.g. \u{201C}chicken burrito\u{201D})")
            .onSubmit(of: .search) { runSearch() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var providerStatusSection: some View {
        Section {
            ForEach(Array(aggregator.providers.enumerated()), id: \.offset) { _, provider in
                HStack {
                    Image(systemName: provider.isConfigured ? "checkmark.circle.fill" : "minus.circle")
                        .foregroundStyle(provider.isConfigured ? Color.green : .secondary)
                    Text(provider.displayName)
                    Spacer()
                    Text(provider.isConfigured ? "On" : "Add key in Settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Sources")
        } footer: {
            Text("TheMealDB is always on (no key). Add Spoonacular or Edamam keys in Settings \u{2192} API keys for a much larger library with nutrition included.")
        }
    }

    private func resultRow(_ result: RecipeSearchResult) -> some View {
        HStack(spacing: 12) {
            thumbnail(result.imageURL)
            VStack(alignment: .leading, spacing: 3) {
                Text(result.title).font(.subheadline.weight(.medium))
                Text("\(result.sourceName) · \(result.slot.label)")
                    .font(.caption2).foregroundStyle(.secondary)
                if let preview = result.previewPerServing {
                    Text("~\(Int(preview.calories.rounded())) kcal · P \(Int(preview.protein.rounded()))g · C \(Int(preview.carbs.rounded()))g · F \(Int(preview.fat.rounded()))g / serving")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("Macros filled from USDA on import")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            importControl(result)
        }
    }

    @ViewBuilder
    private func importControl(_ result: RecipeSearchResult) -> some View {
        if importedIDs.contains(result.id) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else if importingID == result.id {
            ProgressView()
        } else {
            Button {
                importResult(result)
            } label: {
                Image(systemName: "plus.circle.fill").font(.title3)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Add \(result.title) to recipes")
        }
    }

    @ViewBuilder
    private func thumbnail(_ url: URL?) -> some View {
        AsyncImage(url: url) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Image(systemName: "fork.knife").foregroundStyle(.secondary)
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.4)))
    }

    private func runSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        searched = true
        Task {
            let (found, errors) = await aggregator.search(trimmed)
            results = found
            providerErrors = errors
            isSearching = false
        }
    }

    private func importResult(_ result: RecipeSearchResult) {
        importingID = result.id
        Task {
            _ = await RecipeImporter.makeRecipe(from: result, lookup: lookup, into: modelContext)
            importingID = nil
            importedIDs.insert(result.id)
        }
    }
}
