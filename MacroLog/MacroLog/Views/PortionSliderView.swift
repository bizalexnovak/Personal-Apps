import SwiftUI

/// The portion-adjust control: a slider that snaps toward ½× / 1× / 2× / 3× /
/// 4× (with tick marks), plus a text field to type an exact multiplier. Driven
/// by a `factor` binding whose setter applies the scaling — so the same control
/// works on the review card (absolute vs. a baseline) and the meal editor.
struct PortionSliderView: View {
    @Binding var factor: Double

    @State private var text = ""
    @FocusState private var editing: Bool

    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Text("Portion").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                TextField("1", text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 46)
                    .focused($editing)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                Text("×").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Image(systemName: "minus.circle").font(.caption2).foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { PortionScale.position(for: factor) },
                        set: { newPosition in
                            let snapped = PortionScale.snap(newPosition)
                            factor = PortionScale.factor(for: snapped)
                        }
                    ),
                    in: -1...1
                )
                Image(systemName: "plus.circle").font(.caption2).foregroundStyle(.secondary)
            }

            detentTicks
        }
        .onAppear { text = PortionScale.numberText(factor) }
        .onChange(of: factor) { _, newValue in
            if !editing { text = PortionScale.numberText(newValue) }
        }
        .onChange(of: text) { _, newValue in
            guard editing, let typed = Double(newValue) else { return }
            factor = PortionScale.clampFactor(typed)
        }
        .onChange(of: editing) { _, isEditing in
            if !isEditing { text = PortionScale.numberText(factor) }
        }
    }

    private var detentTicks: some View {
        GeometryReader { geo in
            ForEach(PortionScale.detents, id: \.self) { detent in
                let fraction = (PortionScale.position(for: detent) + 1) / 2
                Text(PortionScale.tickLabel(detent))
                    .font(.system(size: 9))
                    .foregroundStyle(factor == detent ? Color.accentColor : .secondary)
                    .position(x: 12 + fraction * (geo.size.width - 24), y: 6)
            }
        }
        .frame(height: 12)
    }
}
