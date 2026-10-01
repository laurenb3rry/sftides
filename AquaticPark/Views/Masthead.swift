import SwiftUI

/// Small caps label used all over the sheet: the masthead, the figure captions, the
/// column heads. Monospaced so the tracking stays even at these sizes.
struct MicroLabel: View {
    let text: String
    var size: CGFloat = 7.6
    var tracking: CGFloat = Theme.labelTracking
    var color: Color = Theme.mute

    var body: some View {
        Text(text)
            .font(Theme.micro(size))
            .tracking(tracking)
            .foregroundStyle(color)
    }
}

struct Masthead: View {
    let now: Date

    static let height: CGFloat = 24

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            MicroLabel(text: "AQUATIC PARK", size: 8.6, tracking: 2.24, color: Theme.ink)
            Spacer()
            MicroLabel(text: Self.stamp.string(from: now).uppercased(),
                       size: 8.6, tracking: 1.72)
        }
        .padding(.horizontal, Theme.margin)
        .padding(.bottom, 7)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.ink).frame(height: 2)
        }
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = API.zone
        formatter.dateFormat = "EEE d MMM · h:mm a"
        return formatter
    }()
}

/// The rule-and-label pair that heads each figure. Carries its own top margin so the
/// figure block below can be sized as one piece.
struct FigureCaption: View {
    let left: String
    let right: String

    static let height: CGFloat = 31

    var body: some View {
        HStack {
            MicroLabel(text: left, tracking: 1.29)
            Spacer()
            MicroLabel(text: right, tracking: 1.29)
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 6)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.ink).frame(height: 1)
        }
        .padding(.top, 16)
        .frame(height: Self.height, alignment: .bottom)
    }
}
