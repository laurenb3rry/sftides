import SwiftUI

/// The three routes, bottom of the sheet, one line each: where, how it reads in her
/// hand, and the one-word call. This is the detail layer — the headline above has
/// already answered the question, this says what the water is actually doing on each.
struct RouteRows: View {
    let routes: [RouteVerdict]

    static var height: CGFloat { 3 * rowHeight }

    private static let rowHeight: CGFloat = 24

    var body: some View {
        VStack(spacing: 0) {
            ForEach(routes, id: \.title) { route in
                HStack(alignment: .lastTextBaseline, spacing: 9) {
                    MicroLabel(text: route.title.uppercased(), tracking: 1.29,
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
                        .font(Theme.micro(8.2).weight(route.isFavorable ? .semibold : .regular))
                        .tracking(1.15)
                        .foregroundStyle(route.isFavorable ? Theme.spot : Theme.mute)
                }
                .lineLimit(1)
                .padding(.vertical, 4)
                .frame(height: Self.rowHeight)
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(Theme.hair).frame(height: 1) }
        .padding(.horizontal, Theme.margin)
    }
}
