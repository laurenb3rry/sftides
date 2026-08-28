import SwiftUI

struct Readout: View {
    let height: Double?
    let time: Date
    /// The marker has been scrubbed off real now, so offer the way back.
    let showsNow: Bool
    let onNow: () -> Void

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(height.map { String(format: "%.2f", $0) } ?? "—")
                    .font(.system(size: 30, design: .monospaced))
                    .tracking(-0.9)
                    .monospacedDigit()
                    .contentTransition(.opacity)
                    .foregroundStyle(Theme.ink)
                Text("FT")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.blue)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                if showsNow {
                    Text("NOW")
                        .font(.system(size: 9, design: .monospaced))
                        .tracking(0.81)
                        .foregroundStyle(Theme.blue)
                        // Widens the hit area leftward without moving the glyphs.
                        .padding(.leading, 24)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onNow)
                        .transition(.opacity)
                }
                Text(Self.stamp.string(from: time).uppercased())
                    .font(.system(size: 10.5, design: .monospaced))
                    .monospacedDigit()
                    .contentTransition(.opacity)
                    .foregroundStyle(Theme.inkMuted)
            }
        }
        .padding(.top, 16)
        .padding(.horizontal, 22)
        .padding(.bottom, 30)
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = API.zone
        formatter.dateFormat = "EEE h:mm a"
        return formatter
    }()
}
