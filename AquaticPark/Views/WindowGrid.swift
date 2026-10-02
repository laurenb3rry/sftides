import SwiftUI

/// Four days by the eighteen hours that can hold a window. Solid blue is a window worth walking down for, hatched
/// is passable, an outline is not, and the night hours stay empty so the eye skips them.
/// Reading across answers "when today"; reading down answers "which day".
///
/// Row height is always derived from the height the grid is handed, never fixed, so the
/// sheet cannot be made to scroll by a shorter screen.
struct WindowGrid: View {
    /// Outer index is the day offset from today, inner is the hour, values on the same
    /// 0–1 scale `swimScore` returns.
    let days: [[Double]]
    let now: Date
    /// The tapped cell, boxed in spot so the recommendations below have a visible
    /// anchor on the grid.
    var selected: Date?
    /// Fires with the hour the tap landed in.
    var onSelect: ((Date) -> Void)?

    private let gutter: CGFloat = 38
    private let gap: CGFloat = 6
    private let top: CGFloat = 14
    /// 4 AM through 9 PM. The small hours and the late evening never hold a window, so
    /// the columns that would show them are given to the hours that can.
    private let firstHour = 4
    private let hourCount = 18

    var body: some View {
        GeometryReader { geometry in
            canvas
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { value in
                    select(at: value.location, size: geometry.size)
                })
        }
    }

    private var canvas: some View {
        Canvas { context, size in
            guard !days.isEmpty else { return }
            let (column, cell, rows) = layout(size: size)

            for (offset, hours) in days.enumerated() {
                let y = top + CGFloat(offset) * (rows + gap)
                context.draw(Text(Self.label(offset: offset, from: now))
                    .font(Theme.micro(7.2)).tracking(0.9)
                    .foregroundStyle(offset == 0 ? Theme.ink : Theme.mute),
                             at: CGPoint(x: 0, y: y + rows / 2), anchor: .leading)

                for (hour, score) in hours.enumerated().dropFirst(firstHour).prefix(hourCount) {
                    let rect = CGRect(x: gutter + CGFloat(hour - firstHour) * column, y: y,
                                      width: cell, height: rows)
                    let night = hour < Conditions.firstLight || hour >= Conditions.lastLight
                    switch (night, score) {
                    case (true, _):
                        context.stroke(Path(rect), with: .color(Theme.ink.opacity(0.11)),
                                       lineWidth: 0.7)
                    case (_, Conditions.goodScore...):
                        context.fill(Path(rect), with: .color(Theme.spot))
                    case (_, Conditions.fairScore...):
                        hatch(context, in: rect)
                    default:
                        context.stroke(Path(rect), with: .color(Theme.ink.opacity(0.3)),
                                       lineWidth: 0.7)
                    }
                }
            }

            let floor = top + CGFloat(days.count) * (rows + gap) - gap
            for (hour, label) in [(6, "6A"), (12, "12P"), (18, "6P")] {
                context.draw(Text(label).font(Theme.micro(7.2)).foregroundStyle(Theme.mute),
                             at: CGPoint(x: gutter + CGFloat(hour - firstHour) * column + cell / 2,
                                         y: floor + 5), anchor: .top)
            }

            if let selected {
                let (day, hour) = Self.cell(of: selected, from: now)
                let slot = Int(hour) - firstHour
                if day >= 0, day < days.count, slot >= 0, slot < hourCount {
                    let y = top + CGFloat(day) * (rows + gap)
                    let box = CGRect(x: gutter + CGFloat(slot) * column - 2, y: y - 2,
                                     width: cell + 4, height: rows + 4)
                    context.stroke(Path(box), with: .color(Theme.spot), lineWidth: 2)
                }
            }
        }
    }

    /// Shared between the drawing closure and the tap handler so the two can never
    /// drift apart on what a cell's rect is.
    private func layout(size: CGSize) -> (column: CGFloat, cell: CGFloat, rows: CGFloat) {
        let plot = size.width - gutter
        let column = plot / CGFloat(hourCount)
        let cell = column - 1.5
        // The hour scale needs 15pt under the last row; the rest is rows and gaps.
        let rows = max((size.height - top - 15 - gap * CGFloat(days.count - 1))
                       / CGFloat(days.count), 6)
        return (column, cell, rows)
    }

    private func select(at location: CGPoint, size: CGSize) {
        guard !days.isEmpty else { return }
        let (column, _, rows) = layout(size: size)
        let hourF = (location.x - gutter) / column
        let dayF = (location.y - top) / (rows + gap)
        guard hourF >= 0, hourF < CGFloat(hourCount), dayF >= 0, Int(dayF) < days.count else { return }
        let midnight = Conditions.calendar.startOfDay(for: now)
        let time = midnight.addingTimeInterval(
            Double(Int(dayF) * 24 + firstHour + Int(hourF)) * 3600 + 1800)
        onSelect?(time)
    }

    /// The day offset and fractional hour `selected` falls on, in this grid's own
    /// coordinates — the inverse of the time the tap handler builds.
    private static func cell(of date: Date, from now: Date) -> (day: Int, hour: Double) {
        let startOfToday = Conditions.calendar.startOfDay(for: now)
        let startOfDate = Conditions.calendar.startOfDay(for: date)
        let day = Conditions.calendar.dateComponents([.day], from: startOfToday,
                                                      to: startOfDate).day ?? 0
        return (day, date.timeIntervalSince(startOfDate) / 3600)
    }

    private func hatch(_ context: GraphicsContext, in rect: CGRect) {
        context.drawLayer { layer in
            layer.clip(to: Path(rect))
            let ink = Theme.spot.opacity(0.62)
            for offset in stride(from: CGFloat(0), to: rect.width + rect.height, by: 4) {
                layer.stroke(Path {
                    $0.move(to: CGPoint(x: rect.minX + offset, y: rect.minY))
                    $0.addLine(to: CGPoint(x: rect.minX + offset - rect.height,
                                           y: rect.maxY))
                }, with: .color(ink), lineWidth: 1.5)
            }
        }
    }

    private static func label(offset: Int, from now: Date) -> String {
        guard offset > 0 else { return "TODAY" }
        let day = Conditions.calendar.date(byAdding: .day, value: offset, to: now) ?? now
        return weekday.string(from: day).uppercased()
    }

    private static func hours(of time: Date) -> CGFloat {
        let midnight = Conditions.calendar.startOfDay(for: time)
        return CGFloat(time.timeIntervalSince(midnight) / 3600)
    }

    private static let weekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = API.zone
        formatter.dateFormat = "EEE"
        return formatter
    }()
}
