import SwiftUI

/// Settings → Community suggestions: propose app improvements, see everyone
/// else's ideas ranked by votes, upvote (tap again to remove your vote), and
/// discuss in comments. Submitting something very close to an existing
/// suggestion nudges toward voting/commenting on that one instead — with a
/// "post anyway" override, so similar-but-different ideas are never blocked.
struct SuggestionsView: View {
    @Environment(\.appBackground) private var appBackground

    @State private var suggestions: [SuggestionsService.Suggestion] = []
    @State private var votedIDs: Set<Int> = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var showCompose = false
    @State private var draft = ""
    @State private var submitting = false
    /// Set when the server flags the draft as a near-duplicate.
    @State private var similar: [SuggestionsService.Suggestion] = []
    @State private var showSimilar = false

    private let service = SuggestionsService()

    var body: some View {
        Group {
            if ClaudeEndpoint.proxyConfig == nil {
                ContentUnavailableView(
                    "Needs an invite code",
                    systemImage: "lightbulb",
                    description: Text("The suggestions board lives on the shared server. Add your invite code under Settings \u{2192} API keys.")
                )
            } else {
                board
            }
        }
        .appBackground(appBackground)
        .navigationTitle("Suggestions")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var board: some View {
        List {
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }
            Section {
                if loading && suggestions.isEmpty {
                    HStack { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
                } else if suggestions.isEmpty {
                    Text("No suggestions yet — start the board with the + button.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(suggestions) { suggestion in
                        row(suggestion)
                    }
                }
            } footer: {
                Text("Ranked by votes. Vote for what you want built next; tap a suggestion to discuss.")
            }
        }
        .refreshable { await load() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { draft = ""; showCompose = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New suggestion")
            }
        }
        .sheet(isPresented: $showCompose) { composeSheet }
        .sheet(isPresented: $showSimilar) { similarSheet }
        .task { await load() }
    }

    private func row(_ suggestion: SuggestionsService.Suggestion) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                toggleVote(suggestion)
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: votedIDs.contains(suggestion.id)
                        ? "arrowtriangle.up.fill" : "arrowtriangle.up")
                    Text("\(suggestion.votes)")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                }
                .foregroundStyle(votedIDs.contains(suggestion.id) ? Color.accentColor : .secondary)
                .frame(minWidth: 34)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Vote for this suggestion")

            NavigationLink {
                SuggestionDetailView(
                    suggestion: suggestion,
                    voted: votedIDs.contains(suggestion.id),
                    onChanged: { Task { await load() } }
                )
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(suggestion.text)
                    Text("\(suggestion.author) · \(suggestion.createdDate.formatted(date: .abbreviated, time: .omitted)) · \(suggestion.comments) comment\(suggestion.comments == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var composeSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What should Foob do better?", text: $draft, axis: .vertical)
                        .lineLimit(3...8)
                } footer: {
                    Text("Everyone using the app can see and vote on suggestions.")
                }
            }
            .keyboardDismissBar()
            .navigationTitle("New suggestion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showCompose = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if submitting {
                        ProgressView()
                    } else {
                        Button("Post") { submit(force: false) }
                            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).count < 5)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    /// Shown when the server found near-duplicates: vote for the existing one
    /// (and discuss there), or insist the idea is different and post anyway.
    private var similarSheet: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(similar) { existing in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(existing.text)
                            Text("\(existing.votes) vote\(existing.votes == 1 ? "" : "s") · \(existing.author)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button {
                                voteForExisting(existing)
                            } label: {
                                Label(
                                    votedIDs.contains(existing.id) ? "Voted" : "Vote for this one",
                                    systemImage: votedIDs.contains(existing.id)
                                        ? "checkmark.circle.fill" : "arrowtriangle.up.circle"
                                )
                                .font(.subheadline)
                            }
                            .buttonStyle(.borderless)
                            .disabled(votedIDs.contains(existing.id))
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Similar suggestion\(similar.count == 1 ? "" : "s") already posted")
                } footer: {
                    Text("If yours is the same idea, vote for the existing one and add a comment from its page. If it's genuinely different, post anyway.")
                }

                Section {
                    Button("Mine is different — post anyway") {
                        showSimilar = false
                        submit(force: true)
                    }
                }
            }
            .navigationTitle("Hold on")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showSimilar = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Actions

    @MainActor
    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let (items, voted) = try await service.list()
            suggestions = items
            votedIDs = voted
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submit(force: Bool) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        submitting = true
        Task {
            defer { submitting = false }
            do {
                switch try await service.submit(text, force: force) {
                case .created:
                    draft = ""
                    showCompose = false
                    await load()
                case .similar(let found):
                    similar = found
                    showCompose = false
                    showSimilar = true
                }
            } catch {
                errorMessage = error.localizedDescription
                showCompose = false
            }
        }
    }

    private func toggleVote(_ suggestion: SuggestionsService.Suggestion) {
        Task {
            if let result = try? await service.vote(suggestion.id) {
                if result.voted { votedIDs.insert(suggestion.id) } else { votedIDs.remove(suggestion.id) }
                await load() // refresh counts + ranking
            }
        }
    }

    private func voteForExisting(_ suggestion: SuggestionsService.Suggestion) {
        Task {
            if let result = try? await service.vote(suggestion.id), result.voted {
                votedIDs.insert(suggestion.id)
            }
        }
    }
}

/// One suggestion: full text, vote toggle, and the comment thread.
struct SuggestionDetailView: View {
    let suggestion: SuggestionsService.Suggestion
    @State var voted: Bool
    /// Tells the board to refresh after a vote/comment here.
    var onChanged: () -> Void

    @Environment(\.appBackground) private var appBackground
    @State private var votes: Int
    @State private var comments: [SuggestionsService.Comment] = []
    @State private var newComment = ""
    @State private var posting = false

    private let service = SuggestionsService()

    init(suggestion: SuggestionsService.Suggestion, voted: Bool, onChanged: @escaping () -> Void) {
        self.suggestion = suggestion
        self._voted = State(initialValue: voted)
        self.onChanged = onChanged
        self._votes = State(initialValue: suggestion.votes)
    }

    var body: some View {
        List {
            Section {
                Text(suggestion.text)
                Text("\(suggestion.author) · \(suggestion.createdDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    toggleVote()
                } label: {
                    Label(
                        voted ? "Voted (\(votes)) — tap to remove" : "Vote (\(votes))",
                        systemImage: voted ? "arrowtriangle.up.fill" : "arrowtriangle.up"
                    )
                }
            }

            Section("Comments") {
                if comments.isEmpty {
                    Text("No comments yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(comments) { comment in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(comment.text).font(.subheadline)
                            Text("\(comment.author) · \(comment.createdDate.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                HStack {
                    TextField("Add a comment…", text: $newComment, axis: .vertical)
                        .lineLimit(1...4)
                    Button {
                        postComment()
                    } label: {
                        if posting { ProgressView() } else { Image(systemName: "arrow.up.circle.fill") }
                    }
                    .disabled(posting || newComment.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .keyboardDismissBar()
        .appBackground(appBackground)
        .navigationTitle("Suggestion")
        .navigationBarTitleDisplayMode(.inline)
        .task { comments = (try? await service.comments(for: suggestion.id)) ?? [] }
    }

    private func toggleVote() {
        Task {
            if let result = try? await service.vote(suggestion.id) {
                voted = result.voted
                votes = result.votes
                onChanged()
            }
        }
    }

    private func postComment() {
        let text = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        posting = true
        Task {
            defer { posting = false }
            if (try? await service.addComment(text, to: suggestion.id)) != nil {
                newComment = ""
                comments = (try? await service.comments(for: suggestion.id)) ?? comments
                onChanged()
            }
        }
    }
}
