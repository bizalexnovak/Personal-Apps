import SwiftUI

/// The optional second step of a check-in, in the spirit of How We Feel's
/// two-step pattern: tap a mood (done, saved, five-second promise kept),
/// then — only if you want to — say more about it.
///
/// CRITICAL: this view must be skippable in *zero* taps. It never gates
/// saving the check-in — by the time this appears, the entry it describes
/// is already in the store. Callers must present it as a dismissible sheet
/// over an already-saved entry (swipe down, or tap "Done" with nothing
/// selected); there is no "Cancel" because there is nothing to cancel.
struct MoodDetailStep: View {
    let mood: Int
    @Binding var emotionWords: [String]
    @Binding var contextTags: [String]
    var onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    section(title: "What's the shape of it?") {
                        chipFlow(EmotionVocabulary.words(for: mood), selection: $emotionWords)
                    }
                    ForEach(ContextTagCatalog.groups, id: \.title) { group in
                        section(title: group.title) {
                            chipFlow(group.tags, selection: $contextTags)
                        }
                    }
                    Button("Done", action: onDone)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
                .padding()
            }
            .navigationTitle("Anything else?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Not really a cancel — the check-in is already saved.
                    // This just closes the sheet without touching either list.
                    Button("Skip", action: onDone)
                }
            }
        }
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            content()
        }
    }

    /// A simple wrapping row of chips. SwiftUI has no built-in flow layout
    /// pre-iOS 16 `Layout`, but iOS 17 is the floor here, so a real `Layout`
    /// keeps chips wrapping naturally instead of scrolling horizontally.
    private func chipFlow(_ words: [String], selection: Binding<[String]>) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(words, id: \.self) { word in
                SelectableChip(
                    label: word,
                    isOn: selection.wrappedValue.contains(word)
                ) {
                    toggle(word, in: selection)
                }
            }
        }
    }

    private func toggle(_ word: String, in selection: Binding<[String]>) {
        if let index = selection.wrappedValue.firstIndex(of: word) {
            selection.wrappedValue.remove(at: index)
        } else {
            selection.wrappedValue.append(word)
        }
    }
}

/// One toggleable word or tag, matching Components.swift's thin-material
/// capsule language: dim outline when off, accent tint when on.
struct SelectableChip: View {
    var label: String
    var isOn: Bool
    var onTap: () -> Void

    @Environment(\.appAccent) private var accent

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(isOn ? accent.opacity(0.2) : .clear)
                )
                .background(.thinMaterial, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(isOn ? accent : .quaternary, lineWidth: isOn ? 1.5 : 0.5)
                )
                .foregroundStyle(isOn ? accent : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Minimal wrapping layout for chip rows — lays views out left to right,
/// wrapping to a new line when a row runs out of width.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth.isFinite ? maxWidth : rowWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
