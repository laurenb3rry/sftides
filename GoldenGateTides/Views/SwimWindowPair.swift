import SwiftUI

/// The answer the app exists to give: when the next bigger swim is good, west and east
/// side by side. The cove is deliberately absent from the headline — it is always
/// swimmable, so putting it here would bury the only line that needs a decision.
///
/// Each column is a printed label, a Didot time span, and one handwritten line saying
/// which leg is slack and what runs on the other.
///
/// While the time being read is inside a pair of windows round one slack, that route
/// takes the whole row: its ride-out window pushes in from the left, the other route is
/// shoved off its edge through a blur, the divider goes and the header glides to centre.
/// Leaving the pair plays it backwards.
struct SwimWindowPair: View {
    let west: SwimWindow?
    let east: SwimWindow?
    let pair: WindowPair?
    /// What the sheet is reading — the scrub marker, else now. Inside a pair, it picks
    /// which of the two is inked.
    let time: Date

    static let height: CGFloat = 100

    /// One spring for the push, the glide and the digits rolling over.
    private static let spring = Animation.spring(duration: 0.6, bounce: 0.18)

    private static let westTitle = "WEST ← FORT MASON"
    private static let eastTitle = "EAST → WHARF"

    /// A column in the row. The id carries it across layouts: a route's slack-out window
    /// keeps the route's id, so the column already showing slides into place rather than
    /// being swapped out, and only the ride-out window is new.
    private struct Column: Identifiable, Equatable {
        let id: String
        let window: SwimWindow?
        let quieter: Bool
    }

    private struct Header: Identifiable, Equatable {
        let id: String
        let text: String
        let quieter: Bool
    }

    private var columns: [Column] {
        guard let pair else {
            return [Column(id: "west", window: west, quieter: !leads(west, over: east)),
                    Column(id: "east", window: east, quieter: !leads(east, over: west))]
        }
        let id = pair.route == .west ? "west" : "east"
        // Inked: the window the time is in, or the next to open.
        let riding = time <= pair.ride.end
        return [Column(id: id + "-ride", window: pair.ride, quieter: !riding),
                Column(id: id, window: pair.slack, quieter: riding)]
    }

    private var headers: [Header] {
        guard let pair else {
            return [Header(id: "west", text: Self.westTitle + Self.day(of: west),
                           quieter: !leads(west, over: east)),
                    Header(id: "east", text: Self.eastTitle + Self.day(of: east),
                           quieter: !leads(east, over: west))]
        }
        let west = pair.route == .west
        return [Header(id: west ? "west" : "east",
                       text: (west ? Self.westTitle : Self.eastTitle) + Self.day(of: pair.slack),
                       quieter: false)]
    }

    var body: some View {
        VStack(spacing: 0) {
            MicroLabel(text: "NEXT SWIM WINDOW", size: 7.8, tracking: 1.72)
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(Array(headers.enumerated()), id: \.element.id) { index, header in
                        MicroLabel(text: header.text, tracking: 0.99,
                                   color: header.quieter ? Theme.mute : Theme.ink)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity)
                            .padding(index == 0 ? .trailing : .leading, headers.count > 1 ? 12 : 0)
                            .transition(Self.push(header.id))
                    }
                }
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                        VStack(spacing: 0) {
                            span(column.window, quieter: column.quieter)
                                .padding(.vertical, 4)
                            caption(column.window)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(index == 0 ? .trailing : .leading, 12)
                        .transition(Self.push(column.id))
                    }
                }
            }
            .overlay {
                Rectangle().fill(Theme.hair).frame(width: 1, height: 38)
                    .opacity(pair == nil ? 1 : 0)
            }
            .contentTransition(.numericText())
            .animation(Self.spring, value: columns)
            .animation(Self.spring, value: headers)
            .padding(.top, 12)
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 24)
        .frame(height: Self.height, alignment: .top)
    }

    /// East leaves and arrives over the right edge; west and both ride-out windows over
    /// the left, so the row reads as one sideways push.
    private static func push(_ id: String) -> some Transition {
        MoveTransition(edge: id == "east" ? .trailing : .leading)
            .combined(with: BlurReplaceTransition(configuration: .downUp))
    }

    /// Whichever opens first reads as the live one; the other greys back. A route with
    /// no window never leads.
    private func leads(_ window: SwimWindow?, over other: SwimWindow?) -> Bool {
        guard let window else { return false }
        guard let other else { return true }
        return window.start <= other.start
    }

    /// One size, driven by whichever of the two spans is longer, so west and east always
    /// read at the same scale — scrubbing swaps which window leads, not the type size.
    /// A window that crosses noon spells out both meridiems and needs the smaller size;
    /// when it does, the other column drops to match rather than standing out as bigger.
    /// `minimumScaleFactor` is the escape hatch for anything longer than either was sized for.
    private var spanSize: CGFloat {
        let longest = columns.compactMap { $0.window.map { Conditions.span($0).count } }.max() ?? 0
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

    /// `slack out, 0.6kt flood back` — one line, in her hand.
    @ViewBuilder
    private func caption(_ window: SwimWindow?) -> some View {
        if let window {
            HandwritingText(text: window.caption,
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
