import SwiftUI

/// Settings → Community suggestions: propose app improvements, see everyone
/// else's ideas ranked by votes, upvote (tap again to remove your vote), and
/// discuss in comments. Submitting something very close to an existing
/// suggestion nudges toward voting/commenting on that one instead — with a
/// "post anyway" override, so similar-but-different ideas are never blocked.
struct SuggestionsView: View {

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

    @Environment(\.dismiss) private var dismiss
    /// Suggestion tapped → its thread. Held by ID so the row stays a plain
    /// button rather than a NavigationLink with a system chevron.
    @State private var openSuggestion: SuggestionsService.Suggestion?

    var body: some View {
        Group {
            if ClaudeEndpoint.proxyConfig == nil {
                VStack(spacing: 14) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(Lux.goldLabel)
                    Text("NEEDS AN INVITE CODE")
                        .font(Lux.smallcaps(9))
                        .tracking(2.5)
                        .foregroundStyle(Lux.goldLabel)
                    LuxNote("The suggestions board lives on the shared server. Add your invite code under Settings → API keys.", size: 15)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, Lux.hPad)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                board
            }
        }
        .luxScreen()
        .safeAreaInset(edge: .top, spacing: 0) {
            LuxHeader(title: "SUGGESTIONS", subtitle: "What should Foob do next?") {
                LuxBackButton { dismiss() }
            } trailing: {
                if ClaudeEndpoint.proxyConfig != nil {
                    Button { draft = ""; showCompose = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Lux.cream)
                    }
                    .accessibilityLabel("New suggestion")
                }
            }
            .padding(.bottom, 8)
            .background(Lux.ground)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var board: some View {
        List {
            Group {
                if let errorMessage {
                    HStack(spacing: 7) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 11))
                        Text(errorMessage)
                            .font(Lux.serifItalic(14))
                    }
                    .foregroundStyle(Lux.ember)
                    .padding(.top, 12)
                }

                if loading && suggestions.isEmpty {
                    LuxNote("Loading…").padding(.top, 20)
                } else if suggestions.isEmpty {
                    LuxNote("No suggestions yet — start the board with the + button.", size: 15)
                        .padding(.top, 20)
                }
            }
            .luxRowChrome()

            ForEach(suggestions) { suggestion in
                row(suggestion)
                    .luxRowChrome()
            }

            Group {
                LuxNote("Ranked by votes. Vote for what you want built next; tap one to discuss.")
                    .padding(.top, 14)
                    .padding(.bottom, 40)
            }
            .luxRowChrome()
        }
        .luxList()
        .refreshable { await load() }
        .navigationDestination(item: $openSuggestion) { suggestion in
            SuggestionDetailView(
                suggestion: suggestion,
                voted: votedIDs.contains(suggestion.id),
                onChanged: { Task { await load() } }
            )
        }
        .sheet(isPresented: $showCompose) { composeSheet.luxSheetChrome() }
        .sheet(isPresented: $showSimilar) { similarSheet.luxSheetChrome() }
        .task { await load() }
    }

    private func row(_ suggestion: SuggestionsService.Suggestion) -> some View {
        let voted = votedIDs.contains(suggestion.id)
        return HStack(alignment: .top, spacing: 12) {
            Button {
                toggleVote(suggestion)
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: voted ? "arrowtriangle.up.fill" : "arrowtriangle.up")
                        .font(.system(size: 12))
                    Text("\(suggestion.votes)")
                        .font(Lux.serif(19))
                        .monospacedDigit()
                }
                .foregroundStyle(voted ? Lux.gold : Lux.cream.opacity(0.6))
                .frame(minWidth: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(voted ? "Remove your vote" : "Vote for this suggestion")

            Button {
                openSuggestion = suggestion
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(suggestion.text)
                        .font(Lux.serif(17))
                        .foregroundStyle(Lux.cream)
                        .multilineTextAlignment(.leading)
                    Text("\(suggestion.author.uppercased()) · \(suggestion.createdDate.formatted(date: .abbreviated, time: .omitted).uppercased()) · \(suggestion.comments) COMMENT\(suggestion.comments == 1 ? "" : "S")")
                        .font(Lux.smallcaps(8))
                        .tracking(1.5)
                        .foregroundStyle(Lux.cream.opacity(0.45))
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .luxRow(vertical: 12)
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
        .luxSheetChrome()
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
