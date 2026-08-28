import SwiftUI

/// The three swims, read at the marker (§5.7). Verdicts come from `Conditions`;
/// this only styles them.
struct RouteRead: View {
    let routes: [RouteVerdict]
    let gate: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("ROUTE READ").foregroundStyle(Theme.inkMuted)
                Spacer()
                Text(gate).foregroundStyle(Theme.inkFaint)
            }
            .font(.system(size: 10.5, design: .monospaced))
            .monospacedDigit()
            .padding(.bottom, 14)

            ForEach(Array(routes.enumerated()), id: \.element.title) { index, route in
                if index > 0 {
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                }
                row(route)
            }
        }
        .padding(.top, 18)
        .padding(.horizontal, 22)
        .padding(.bottom, 22)
    }

    private func row(_ route: RouteVerdict) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(route.title)
                    .font(.system(size: 14))
                    .foregroundStyle(route.isFavorable ? Theme.ink : Theme.inkSecond)
                Text(route.sublabel)
                    .font(.system(size: 10, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Theme.inkFaint)
            }
            Spacer(minLength: 0)
            pill(route)
        }
        .padding(.vertical, 12)
    }

    private func pill(_ route: RouteVerdict) -> some View {
        Text(route.verdict)
            .font(.system(size: 10, design: .monospaced))
            .tracking(0.7)
            .monospacedDigit()
            .foregroundStyle(route.isFavorable ? Theme.blue : Theme.inkMuted)
            .padding(.vertical, 4)
            .padding(.horizontal, 9)
            .overlay(
                Rectangle().stroke(route.isFavorable ? Theme.blue : Theme.pillOff, lineWidth: 1)
            )
    }
}
