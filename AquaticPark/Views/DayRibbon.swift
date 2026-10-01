import SwiftUI

/// Today in one 24-hour bar. Each hour is inked in proportion to how good a big swim
/// would be in it, the next window is boxed, and a caret marks now. It is the only
/// element that answers "is it worth going out at all today" without being read.
struct DayRibbon: View {
    /// 24 scores, one per hour of today, on the 0–1 scale `swimScore` returns.
    let hours: [Double]
    let highlight: SwimWindow?
    let now: Date

    static let height: CGFloat = 36

    private let bar: CGFloat = 11
    private let top: CGFloat = 7

    var body: some View {
        Canvas { context, size in
            let column = size.width / 24

            context.fill(Path(CGRect(x: 0, y: top, width: size.width, height: bar)),
                         with: .color(Theme.ink.opacity(0.07)))

            for (hour, score) in hours.enumerated() where score > Conditions.fairScore {
                let rect = CGRect(x: CGFloat(hour) * column, y: top, width: column, height: bar)
                context.fill(Path(rect), with: .color(
                    Theme.spot.opacity(score > Conditions.goodScore ? 1 : 0.32)))
            }

            if let highlight, Conditions.calendar.isDateInToday(highlight.start) {
                let from = Self.hours(of: highlight.start)
                let to = Self.hours(of: highlight.end)
                let box = CGRect(x: from * column, y: top - 3,
                                 width: max((to - from) * column, 3), height: bar + 6)
                context.stroke(Path(box), with: .color(Theme.ink), lineWidth: 1.3)
            }

            // A caret rather than a line: the line would read as a window edge.
            let x = Self.hours(of: now) * column
            var caret = Path()
            caret.move(to: CGPoint(x: x - 3.5, y: top - 6))
            caret.addLine(to: CGPoint(x: x + 3.5, y: top - 6))
            caret.addLine(to: CGPoint(x: x, y: top - 1))
            context.fill(caret, with: .color(Theme.ink))

            for (hour, label) in [(0, "12A"), (6, "6A"), (12, "12P"), (18, "6P"), (24, "12A")] {
                let x = min(max(CGFloat(hour) * column, 9), size.width - 9)
                context.draw(Text(label).font(Theme.micro(6.8)).foregroundStyle(Theme.mute),
                             at: CGPoint(x: x, y: top + bar + 8), anchor: .center)
            }
        }
        .frame(height: Self.height)
        .padding(.horizontal, Theme.margin)
        .padding(.top, 11)
    }

    /// Hours since local midnight, fractional — the ribbon's only coordinate.
    private static func hours(of time: Date) -> CGFloat {
        let midnight = Conditions.calendar.startOfDay(for: time)
        return CGFloat(time.timeIntervalSince(midnight) / 3600)
    }
}
