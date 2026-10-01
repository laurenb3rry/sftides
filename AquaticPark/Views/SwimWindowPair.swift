import SwiftUI

/// The answer the app exists to give: when the next bigger swim is good, west and east
/// side by side. The cove is deliberately absent from the headline — it is always
/// swimmable, so putting it here would bury the only line that needs a decision.
///
/// Each column is a printed label, a Didot time span, and one handwritten line carrying
/// the slack it hangs off and what the current is doing through it.
struct SwimWindowPair: View {
    let west: SwimWindow?
    let east: SwimWindow?

    static let height: CGFloat = 124

    var body: some View {
        VStack(spacing: 0) {
            MicroLabel(text: "NEXT SWIM WINDOW", size: 7.8, tracking: 1.72)
            HStack(alignment: .top, spacing: 0) {
                column("WEST → FORT MASON", west,
                       quieter: !leads(west, over: east), divided: false)
                column("EAST → WHARF", east,
                       quieter: !leads(east, over: west), divided: true)
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 24)
        .frame(height: Self.height, alignment: .top)
    }

    /// Whichever opens first reads as the live one; the other greys back. A route with
    /// no window never leads.
    private func leads(_ window: SwimWindow?, over other: SwimWindow?) -> Bool {
        guard let window else { return false }
        guard let other else { return true }
        return window.start <= other.start
    }

    private func column(_ title: String, _ window: SwimWindow?,
                        quieter: Bool, divided: Bool) -> some View {
        VStack(alignment: .center, spacing: 0) {
            MicroLabel(text: title + Self.day(of: window), tracking: 0.99,
                       color: quieter ? Theme.mute : Theme.ink)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            span(window, quieter: quieter)
                .padding(.vertical, 4)
            caption(window)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.leading, divided ? 12 : 0)
        .padding(.trailing, divided ? 0 : 12)
        .overlay(alignment: .leading) {
            if divided { Rectangle().fill(Theme.hair).frame(width: 1, height: 38) }
        }
    }

    /// One size, driven by whichever of the two spans is longer, so west and east always
    /// read at the same scale — scrubbing swaps which window leads, not the type size.
    /// A window that crosses noon spells out both meridiems and needs the smaller size;
    /// when it does, the other column drops to match rather than standing out as bigger.
    /// `minimumScaleFactor` is the escape hatch for anything longer than either was sized for.
    private var spanSize: CGFloat {
        let longest = [west, east].compactMap { $0.map { Conditions.span($0).count } }.max() ?? 0
        return longest > 13 ? 18 : 22
    }

    private func span(_ window: SwimWindow?, quieter: Bool) -> some View {
        Text(window.map(Conditions.span) ?? "—")
            .font(Theme.display(spanSize))
            .tracking(spanSize == 22 ? -0.4 : -0.3)
            .foregroundStyle(quieter ? Theme.mute : Theme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    /// Blank while the window is still today, which is the common case and wants no
    /// decoration. Once it rolls over, the day has to be said or the time is a lie.
    private static func day(of window: SwimWindow?) -> String {
        guard let window, !Conditions.calendar.isDateInToday(window.start) else { return "" }
        return " · " + weekday.string(from: window.start).uppercased()
    }

    private static let weekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = API.zone
        formatter.dateFormat = "EEE"
        return formatter
    }()

    /// `slack 11:42 am, ebb easing` — one line, in her hand.
    @ViewBuilder
    private func caption(_ window: SwimWindow?) -> some View {
        if let window {
            let slack = window.slack.map { "slack \(Conditions.handClock($0)), " } ?? ""
            HandwritingText(text: slack + window.current,
                            size: Theme.hand(7.6), tracking: 0.1)
                .foregroundStyle(Theme.ink)
                .lineSpacing(3)
                // Two lines is what the slot is built for; a long phrase shrinks into
                // it rather than pushing the ribbon below it off the screen.
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            MicroLabel(text: "NONE IN RANGE", tracking: 0.99)
        }
    }
}
