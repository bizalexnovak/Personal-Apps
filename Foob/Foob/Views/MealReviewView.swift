import SwiftUI

/// The inline review: one card per parsed item plus the Save All bar. Nothing
/// is written until every item is confirmed or edited.
///
/// Presented by both the Siri modal (`CaptureView`) and the Log tab, so it owns
/// its own header rather than relying on a navigation bar.
struct MealReviewView: View {
    @ObservedObject var coordinator: MealCaptureCoordinator
    var onSaved: () -> Void
    /// Extra space under the save bar. The inline Log tab passes the floating
    /// orb's clearance; the modal Siri capture (no orb) passes none.
    var bottomClearance: CGFloat = 0
    /// Shown when the review is hosted somewhere with no other way out.
    var onCancel: (() -> Void)?

    private var items: [MealCaptureCoordinator.ReviewItem] { coordinator.review?.items ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let raw = coordinator.review?.rawText, !raw.isEmpty {
                        Text("You said — \u{201C}\(raw)\u{201D}")
                            .font(Lux.serifItalic(15))
                            .foregroundStyle(Lux.cream.opacity(0.55))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let notice = coordinator.notice {
                        Label(notice, systemImage: "wifi.slash")
                            .font(Lux.serifItalic(14))
                            .foregroundStyle(Lux.ember)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !items.isEmpty { dateRow }

                    ForEach(items) { item in
                        ReviewItemCard(item: item, coordinator: coordinator)
                    }

                    if items.isEmpty {
                        LuxNote("All items were removed. Cancel to start over.", size: 15)
                            .padding(.top, 30)
                    }
                }
                .padding(.horizontal, Lux.hPad)
                .padding(.top, 14)
                .padding(.bottom, 30)
            }
        }
        .luxScreen()
        .safeAreaInset(edge: .bottom, spacing: 0) { saveBar }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 0) {
            HStack {
                if let onCancel {
                    Button("CANCEL", action: onCancel)
                        .font(Lux.smallcaps(9))
                        .tracking(2)
                        .foregroundStyle(Lux.cream.opacity(0.6))
                } else {
                    Spacer().frame(width: 1)
                }
                Spacer()
                Text(items.count == 1 ? "1 ITEM" : "\(items.count) ITEMS")
                    .font(Lux.smallcaps(9))
                    .tracking(2)
                    .foregroundStyle(Lux.gold)
            }
            .padding(.bottom, 8)

            LuxTitle(text: "REVIEW")
        }
        .padding(.horizontal, Lux.hPad)
        .padding(.top, 64)
    }

    /// The date the meal will be logged against — usually today, but a meal
    /// remembered later needs moving back.
    private var dateRow: some View {
        HStack {
            Text("DATE")
                .font(Lux.smallcaps(9))
                .tracking(2.5)
                .foregroundStyle(Lux.goldLabel)
            Spacer()
            DatePicker(
                "",
                selection: $coordinator.logDate,
                in: ...Date(),
                displayedComponents: .date
            )
            .labelsHidden()
            .tint(Lux.gold)
        }
        .luxRow(vertical: 10)
    }

    // MARK: - Save bar

    private var saveBar: some View {
        VStack(spacing: 8) {
            if !coordinator.canSaveAll, !items.isEmpty {
                LuxNote("Confirm or edit every item to save.")
                    .multilineTextAlignment(.center)
            }
            Button {
                Task {
                    await coordinator.saveAll()
                    if coordinator.review == nil { onSaved() }
                }
            } label: {
                Text("SAVE ALL")
            }
            .buttonStyle(GoldCapsule(enabled: coordinator.canSaveAll))
            .disabled(!coordinator.canSaveAll)
        }
        .padding(.horizontal, Lux.hPad)
        .padding(.top, 14)
        .padding(.bottom, 16 + bottomClearance)
        // A scrim rather than a bar: content fades into the ground beneath the
        // button instead of stopping at a hard edge.
        .background(Lux.bottomScrim.ignoresSafeArea())
    }
}
