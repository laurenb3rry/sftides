import SwiftUI

struct Readout: View {
    let height: Double?
    let time: Date

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            HStack(alignment: .lastTextBaseline, spacing: 9) {
                Text(height.map { String(format: "%.2f", $0) } ?? "—")
                    .font(.system(size: 32))
                    .tracking(-0.8)
                    .monospacedDigit()
                    .contentTransition(.opacity)
                    .foregroundStyle(Theme.ink)
                Text("FT")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.blue)
            }
            Spacer()
            Text(Self.stamp.string(from: time).uppercased())
                .font(.system(size: 11, design: .monospaced))
                .monospacedDigit()
                .contentTransition(.opacity)
                .foregroundStyle(Theme.inkMuted)
        }
        .padding(.top, 12)
        .padding(.horizontal, 22)
        .padding(.bottom, 16)
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = API.zone
        formatter.dateFormat = "EEE HH:mm"
        return formatter
    }()
}
