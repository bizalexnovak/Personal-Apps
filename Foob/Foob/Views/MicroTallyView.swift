import SwiftUI

extension MicronutrientField: Identifiable {
    var id: String { label }
}

/// The Micros side of the Today tab's Macros/Micros switch: every tracked
/// vitamin, mineral, and supplement with the day's total against its adult
/// Daily Value, plus a tap-through to what it's good for and what
/// overconsuming does. Emits rows (not a List) so it slots into HomeView's
/// existing List section.
struct MicroTallySection: View {
    /// The day's summed micronutrient record.
    let micros: Micronutrients
    /// Row tapped — the parent presents the info sheet (a sheet modifier on
    /// the ForEach itself would attach one per row, which SwiftUI mishandles).
    var onSelect: (MicronutrientField) -> Void

    var body: some View {
        ForEach(Micronutrients.fields) { field in
            let value = micros[keyPath: field.keyPath] ?? 0
            let info = MicronutrientGuide.info(for: field.label)
            Button {
                onSelect(field)
            } label: {
                row(field: field, value: value, info: info)
            }
            .buttonStyle(.plain)
            .luxRow(vertical: 10)
        }
    }

    private func row(field: MicronutrientField, value: Double, info: MicronutrientInfo?) -> some View {
        let target = info?.dailyValue
        let overLimit = info?.upperLimit.map { value > $0 } ?? false
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(field.label)
                    .font(Lux.serif(17))
                    .foregroundStyle(Lux.cream)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if overLimit {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Lux.ember)
                        .accessibilityLabel("Above the daily upper limit")
                }
                Text(amountText(value, target: target, unit: field.unit))
                    .font(Lux.serif(15))
                    .monospacedDigit()
                    .foregroundStyle(overLimit ? Lux.ember : Lux.gold)
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(Lux.cream.opacity(0.35))
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            }
            // Only nutrients with a Daily Value get a gauge — trans fat, total
            // sugars and caffeine have no reference to measure against, so a
            // bar there would imply a target that doesn't exist.
            if let target, target > 0 {
                LuxBar(progress: min(value / target, 1), height: 2)
            }
        }
        .contentShape(Rectangle())
    }

    private func amountText(_ value: Double, target: Double?, unit: String) -> String {
        let v = trimmed(value)
        guard let target else { return "\(v) \(unit)" }
        return "\(v) / \(trimmed(target)) \(unit)"
    }

    private func trimmed(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 10_000
            ? "\(Int(value))"
            : String(format: "%.1f", value)
    }
}

/// What one micronutrient does and what chronically overdoing it causes, with
/// today's amount against the Daily Value and upper limit.
struct MicronutrientInfoSheet: View {
    let field: MicronutrientField
    let todayAmount: Double
    @Environment(\.dismiss) private var dismiss

    private var info: MicronutrientInfo? { MicronutrientGuide.info(for: field.label) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Today") {
                        Text("\(format(todayAmount)) \(field.unit)").monospacedDigit()
                    }
                    if let dv = info?.dailyValue {
                        LabeledContent("Daily Value") {
                            Text("\(format(dv)) \(field.unit)").monospacedDigit()
                        }
                    }
                    if let limit = info?.upperLimit {
                        LabeledContent("Upper limit") {
                            Text(limit == 0 ? "As low as possible" : "\(format(limit)) \(field.unit)")
                                .monospacedDigit()
                        }
                    }
                }

                if let info {
                    Section("What it's good for") {
                        Text(info.goodFor).font(.subheadline)
                    }
                    Section("Too much") {
                        Text(info.excess).font(.subheadline)
                    }
                }

                Section {
                } footer: {
                    Text("General adult reference values (FDA Daily Values / NIH upper limits) — individual needs vary. Informational only, not medical advice.")
                }
            }
            .navigationTitle(field.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func format(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }
}
