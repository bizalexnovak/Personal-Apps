import SwiftUI

/// The portion-adjust control: a slider that snaps toward ½× / 1× / 2× / 5× /
/// 10× (with tick labels), plus a text field to type an exact multiplier. Driven
/// by a `factor` binding whose setter applies the scaling — so the same control
/// works on the review card (absolute vs. a baseline) and the meal editor.
///
/// The track is drawn rather than using `Slider`, because the system control
/// brings its own thumb, track weight, and tint, none of which survive contact
/// with this palette.
struct PortionSliderView: View {
    @Binding var factor: Double

    @State private var text = ""
    @FocusState private var editing: Bool

    private let thumbSize: CGFloat = 22

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                LuxFieldLabel(text: "PORTION")
                Spacer()
                TextField("1", text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 46)
                    .focused($editing)
                    .font(Lux.serif(19))
                    .monospacedDigit()
                    .foregroundStyle(Lux.cream)
                    .tint(Lux.gold)
                Text("×")
                    .font(Lux.serif(19))
                    .foregroundStyle(Lux.cream.opacity(0.5))
            }

            track

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

    /// Position of the current factor along the track, 0…1.
    private var fraction: Double {
        (PortionScale.position(for: factor) + 1) / 2
    }

    private var track: some View {
        GeometryReader { geo in
            let usable = max(0, geo.size.width - thumbSize)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Lux.cream.opacity(0.10))
                    .frame(height: 2)
                Capsule()
                    .fill(Lux.goldFillH)
                    .frame(width: thumbSize / 2 + usable * fraction, height: 2)
                Circle()
                    .fill(Lux.goldFill)
                    .overlay(Circle().stroke(Lux.cream.opacity(0.5), lineWidth: 1))
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: usable * fraction)
            }
            .frame(height: thumbSize)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard usable > 0 else { return }
                        let raw = (value.location.x - thumbSize / 2) / usable
                        let position = min(max(raw, 0), 1) * 2 - 1 // back to -1…1
                        factor = PortionScale.factor(for: PortionScale.snap(position))
                    }
            )
        }
        .frame(height: thumbSize)
        .accessibilityElement()
        .accessibilityLabel("Portion")
        .accessibilityValue("\(PortionScale.numberText(factor)) times")
        .accessibilityAdjustableAction { direction in
            let step = 0.08
            let current = PortionScale.position(for: factor)
            let moved = direction == .increment ? current + step : current - step
            factor = PortionScale.factor(for: PortionScale.snap(min(max(moved, -1), 1)))
        }
    }

    private var detentTicks: some View {
        GeometryReader { geo in
            let usable = max(0, geo.size.width - thumbSize)
            ForEach(PortionScale.detents, id: \.self) { detent in
                let position = (PortionScale.position(for: detent) + 1) / 2
                Text(PortionScale.tickLabel(detent))
                    .font(Lux.serifItalic(10))
                    .foregroundStyle(factor == detent ? Lux.gold : Lux.cream.opacity(0.35))
                    .position(x: thumbSize / 2 + position * usable, y: 6)
            }
        }
        .frame(height: 14)
    }
}
