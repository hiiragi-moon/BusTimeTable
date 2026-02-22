import WidgetKit
import SwiftUI

struct BusWidgetEntry: TimelineEntry {
    let date: Date
    let routeName: String
    let stopName: String
    let serviceTypeText: String
    let nowText: String
    let nextBuses: [BusCandidate]
    let errorMessage: String?
}

struct BusWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> BusWidgetEntry {
        BusWidgetEntry(
            date: Date(),
            routeName: "浜11",
            stopName: "三ツ沢池",
            serviceTypeText: "平日",
            nowText: "12:00",
            nextBuses: [],
            errorMessage: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (BusWidgetEntry) -> Void) {
        completion(makeEntry(now: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BusWidgetEntry>) -> Void) {
        let now = Date()
        let entry = makeEntry(now: now)

        // 次の分の切り替わり直後に更新（+1秒）
        let cal = TimetableCalculator.jstCalendar
        let nextMinute = cal.date(byAdding: .minute, value: 1, to: now).flatMap {
            cal.dateInterval(of: .minute, for: $0)?.start
        } ?? now.addingTimeInterval(60)

        let refreshDate = nextMinute.addingTimeInterval(1)

        let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
        completion(timeline)
    }

    private func makeEntry(now: Date) -> BusWidgetEntry {
        do {
            let schedule = try LocalJSONLoader.loadSchedule(bundle: .main)
            let holidayStrings = try LocalJSONLoader.loadHolidayStrings(bundle: .main)
            let holidayCalendar = HolidayCalendar(holidayStrings: holidayStrings)

            let serviceType = holidayCalendar.serviceType(for: now)
            let nextBuses = TimetableCalculator.nextBuses(
                now: now,
                schedule: schedule,
                holidayCalendar: holidayCalendar,
                limit: 3
            )

            return BusWidgetEntry(
                date: now,
                routeName: schedule.routeName,
                stopName: schedule.stopName,
                serviceTypeText: serviceType.rawValue,
                nowText: hmString(now),
                nextBuses: nextBuses,
                errorMessage: nil
            )
        } catch {
            return BusWidgetEntry(
                date: now,
                routeName: "浜11",
                stopName: "三ツ沢池",
                serviceTypeText: "-",
                nowText: hmString(now),
                nextBuses: [],
                errorMessage: error.localizedDescription
            )
        }
    }

    private func hmString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = TimetableCalculator.jstTimeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

struct BusWidgetEntryView: View {
    var entry: BusWidgetProvider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.routeName)
                        .font(.headline)
                    Text("\(entry.stopName) → 横浜駅")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(entry.serviceTypeText)
                        .font(.caption2)
                        .foregroundStyle(.blue)
                    Text(entry.nowText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if let error = entry.errorMessage {
                Text("読込エラー")
                    .font(.caption)
                    .foregroundStyle(.red)
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if entry.nextBuses.isEmpty {
                Text("本日の運行は終了しました")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(entry.nextBuses.prefix(3).enumerated()), id: \.element.id) { index, bus in
                    HStack {
                        Text("\(bus.departString)発")
                            .font(.subheadline.monospacedDigit())
                            .fontWeight(.semibold)

                        Spacer()

                        Text("到着 \(bus.arriveString)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)

                        Text("あと\(bus.minutesUntil)分")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(bus.minutesUntil <= 5 ? .orange : .primary)
                    }

                    if index < min(entry.nextBuses.count, 3) - 1 {
                        Divider()
                    }
                }
            }
        }
        .padding(12)
        .containerBackground(.background, for: .widget)
    }
}

struct BusTimeTableWidget: Widget {
    let kind: String = "BusTimeTableWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BusWidgetProvider()) { entry in
            BusWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("次のバス")
        .description("次のバス3便を表示します。")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

#Preview(as: .systemMedium) {
    BusTimeTableWidget()
} timeline: {
    BusWidgetEntry(
        date: Date(),
        routeName: "浜11",
        stopName: "三ツ沢池",
        serviceTypeText: "平日",
        nowText: "12:00",
        nextBuses: [],
        errorMessage: nil
    )
}
