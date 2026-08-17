
extension View {
    /// Emerald chrome for the utility sheets the handoff didn't redraw
    /// (macro override, food swap, micronutrient editors). They keep their
    /// Form layout — restyling them was out of scope — but stop arriving as
    /// bright system panels in the middle of a dark app.
    func luxSheetChrome() -> some View {
        self
            .tint(Lux.gold)
            .scrollContentBackground(.hidden)
            .background(Lux.sheet.ignoresSafeArea())
            .presentationBackground(Lux.sheet)
            .preferredColorScheme(.dark)
    }
}
