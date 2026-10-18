import SwiftUI

/// The three routes, bottom of the sheet, one line each: where, how it reads in her
/// hand, and the one-word call. This is the detail layer — the headline above has
/// already answered the question, this says what the water is actually doing on each.
struct RouteRows: View {
    let routes: [RouteVerdict]

    static var height: CGFloat { 3 * rowHeight + topGap }

    private static let rowHeight: CGFloat = 24
    /// A row already sets its caps 6pt under its top; with the gap above the rows this
    /// puts COVE about 22pt under the readings' crop marks.
    private static let topGap: CGFloat = 8

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(routes.enumerated()), id: \.element.title) { index, route in
                HStack(alignment: .lastTextBaseline, spacing: 9) {
                    MicroLabel(text: route.title.uppercased(), size: 7, tracking: 1.12,
                               color: route.isFavorable ? Theme.ink : Theme.mute)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HandwritingText(text: route.condition, size: Theme.hand(8.2),
                                    tracking: 0.1)
                        .foregroundStyle(Theme.ink)
                    // GO or HOLD only — the handwritten condition beside it already
                    // carries the why, so repeating "STRONG EBB" here says nothing new.
                    // `isFavorable` is the one route the app would send you on; the cove
                    // reads CALM instead and is just as swimmable.
                    Text(route.isFavorable || route.verdict == "CALM" ? "GO" : "HOLD")
                        .font(Theme.micro(7.4).weight(route.isFavorable ? .semibold : .regular))
                        .tracking(1.04)
                        .foregroundStyle(route.isFavorable ? Theme.spot : Theme.mute)
                }
                .lineLimit(1)
                .padding(.vertical, 4)
                .frame(height: Self.rowHeight)
                // Pulls the outer rows 6pt toward the middle one (24pt pitch becomes 18).
                // An offset, so the block's height and the figure above are unchanged.
                .offset(y: CGFloat(1 - index) * 6)
            }
        }
        .padding(.top, Self.topGap)
        .padding(.horizontal, Theme.margin)
    }
}
