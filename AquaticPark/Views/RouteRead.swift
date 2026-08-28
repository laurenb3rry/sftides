import SwiftUI

/// State C — three routes, no separators.
struct RouteRead: View {
    let routes: [RouteVerdict]
    let gate: String

    var body: some View {
        VStack(spacing: 0) {
            header
            ForEach(routes, id: \.title) { row($0) }
        }
        .padding(.bottom, 18)
    }

    private var header: some View {
        HStack {
            Text("ROUTE")
                .tracking(0.81)
            Spacer()
            Text(gate)
                .tracking(0.54)
                .monospacedDigit()
        }
        .font(.system(size: 9, design: .monospaced))
        .foregroundStyle(Theme.inkFaint)
        .padding(.top, 14)
        .padding(.horizontal, 22)
        .padding(.bottom, 4)
    }

    private func row(_ route: RouteVerdict) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(route.title)
                    .font(.system(size: 13))
                    .foregroundStyle(route.isFavorable ? Theme.ink : Theme.inkSecond)
                Text(route.sublabel)
                    .font(.system(size: 9, design: .monospaced))
                    .tracking(0.54)
                    .monospacedDigit()
                    .foregroundStyle(Theme.inkFaint)
            }
            Spacer(minLength: 0)
            pill(route)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 22)
    }

    private func pill(_ route: RouteVerdict) -> some View {
        Text(route.verdict)
            .font(.system(size: 9, design: .monospaced))
            .tracking(0.63)
            .monospacedDigit()
            .foregroundStyle(route.isFavorable ? Theme.blue : Theme.inkMuted)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .overlay(
                Rectangle().stroke(route.isFavorable ? Theme.blue : Theme.pillOff, lineWidth: 1)
            )
    }
}
