import SwiftUI
import Foundation
import Combine

// MARK: - ViewModel

@MainActor
final class BusTimeViewModel: ObservableObject {
    @Published var schedule: BusSchedule?
    @Published var holidayStrings: [String] = []
    @Published var errorMessage: String?
    @Published var now: Date = Date()

    private var timer: Timer?

    func load() {
        do {
            schedule = try LocalJSONLoader.loadSchedule(bundle: .main)
            holidayStrings = try LocalJSONLoader.loadHolidayStrings(bundle: .main)
            errorMessage = nil
            startTimer()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startTimer() {
        timer?.invalidate()

        // まず現在時刻を反映
        now = Date()

        // 次の「分の切り替わり」直後に1回だけ発火させる
        let current = Date()
        let cal = TimetableCalculator.jstCalendar
        let nextMinute = cal.date(byAdding: .minute, value: 1, to: current).flatMap {
            cal.dateInterval(of: .minute, for: $0)?.start
        } ?? current.addingTimeInterval(60)

        let initialDelay = max(0.05, nextMinute.timeIntervalSince(current) + 0.05)

        timer = Timer.scheduledTimer(withTimeInterval: initialDelay, repeats: false) { [weak self] _ in
            guard let self else { return }

            DispatchQueue.main.async {
                self.now = Date()

                // 以降は分単位でぴったり更新
                self.timer?.invalidate()
                self.timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                    DispatchQueue.main.async {
                        self?.now = Date()
                    }
                }
            }
        }
    }

    deinit {
        timer?.invalidate()
    }

    var serviceType: ServiceType {
        HolidayCalendar(holidayStrings: holidayStrings).serviceType(for: now)
    }

    var todayTimetable: [BusTrip] {
        guard let schedule else { return [] }
        return TimetableCalculator.trips(for: serviceType, in: schedule)
    }

    var nextBuses: [BusCandidate] {
        guard let schedule else { return [] }
        let holidayCalendar = HolidayCalendar(holidayStrings: holidayStrings)
        return TimetableCalculator.nextBuses(
            now: now,
            schedule: schedule,
            holidayCalendar: holidayCalendar,
            limit: 3
        )
    }

    var lastBus: String? {
        todayTimetable.last?.depart
    }

    var nowText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = TimetableCalculator.jstTimeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: now)
    }
}

// MARK: - View

struct ContentView: View {
    @StateObject private var vm = BusTimeViewModel()
    @State private var selectedDeparture: String = ""
    @State private var scheduledNotificationIDs: Set<String> = []
    private let nowDepartureOptionTag = "__NOW__"

    private func countdownColor(for minutesUntil: Int) -> Color {
        if minutesUntil <= 0 { return .red }
        if minutesUntil <= 5 { return .orange }
        return .primary
    }
    private func notificationID(for bus: BusCandidate) -> String {
        "bus_notify_\(bus.departString)_\(bus.arriveString)"
    }

    private func refreshScheduledNotifications() {
        Task {
            let requests = await NotificationManager.pendingRequests()
            let ids = Set(requests.map { $0.identifier })
            await MainActor.run {
                scheduledNotificationIDs = ids
            }
        }
    }

    private func isNotificationScheduled(for bus: BusCandidate) -> Bool {
        scheduledNotificationIDs.contains(notificationID(for: bus))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let errorMessage = vm.errorMessage {
                    errorView(message: errorMessage)
                } else if let schedule = vm.schedule {
                    mainView(schedule: schedule)
                } else {
                    ProgressView("読み込み中...")
                        .onAppear {
                            vm.load()
                            refreshScheduledNotifications()
                        }
                }
            }
        }
    }

    private func mainView(schedule: BusSchedule) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard(schedule: schedule)
                statusCard
                nextBusCard
                departureSearchCard

                if vm.nextBuses.isEmpty {
                    endOfServiceCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .onAppear {
            refreshScheduledNotifications()
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            Text("読み込みエラー")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("再読み込み") {
                vm.load()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
    }

    private func headerCard(schedule: BusSchedule) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text(schedule.routeName)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(schedule.stopName + " → 横浜駅")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Text("現在時刻")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(vm.nowText)
                    .font(.title3.weight(.bold))
                    .fontWeight(.bold)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("今日のダイヤ", systemImage: "calendar")
                Spacer()
                Text(vm.serviceType.rawValue)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

private var nextBusCard: some View {
    VStack(alignment: .leading, spacing: 14) {
        Text("次のバス")
            .font(.headline)

        if vm.nextBuses.isEmpty {
            Text("本日の運行は終了しました")
                .foregroundStyle(.secondary)
        } else {
            ForEach(Array(vm.nextBuses.enumerated()), id: \.element.id) { index, bus in
                VStack(alignment: .leading, spacing: 10) {
                    // 1行目: 出発時刻（左） / あとn分（右）
                    HStack(alignment: .lastTextBaseline, spacing: 10) {
                        HStack(alignment: .lastTextBaseline, spacing: 2) {
                            Text(bus.departString)
                                .font(.title3.monospacedDigit())
                                .fontWeight(.semibold)
                            Text("発")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 12)

                        HStack(alignment: .lastTextBaseline, spacing: 2) {
                            Text("あと")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text("\(bus.minutesUntil)分")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(countdownColor(for: bus.minutesUntil))
                        }
                    }

                    // 2行目: 到着予定（左） / 通知ボタン（右）
                    HStack(alignment: .center, spacing: 12) {
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text("到着予定")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(bus.arriveString)
                                .font(.subheadline.monospacedDigit())
                                .fontWeight(.semibold)
                        }

                        Spacer(minLength: 16)

                        if bus.minutesUntil < 5 {
                            HStack(spacing: 6) {
                                Image(systemName: "figure.run")
                                    .font(.footnote.weight(.semibold))
                                Text("急いでください")
                                    .font(.footnote.weight(.semibold))
                            }
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.orange.opacity(0.12), in: Capsule())
                        } else {
                            Button {
                                Task {
                                    let id = notificationID(for: bus)

                                    if isNotificationScheduled(for: bus) {
                                        NotificationManager.cancelNotification(identifier: id)
                                        refreshScheduledNotifications()
                                        return
                                    }

                                    let granted = await NotificationManager.requestPermission()
                                    guard granted, let schedule = vm.schedule else { return }

                                    do {
                                        try await NotificationManager.scheduleBusNotification(
                                            routeName: schedule.routeName,
                                            stopName: schedule.stopName,
                                            depart: bus.departureDate,
                                            minutesBefore: 5,
                                            identifier: id
                                        )
                                        refreshScheduledNotifications()
                                    } catch {
                                        print("通知予約エラー:", error)
                                    }
                                }
                            } label: {
                                if isNotificationScheduled(for: bus) {
                                    Label("通知を解除", systemImage: "bell.slash")
                                        .font(.footnote.weight(.semibold))
                                } else {
                                    Label("5分前に通知", systemImage: "bell.badge")
                                        .font(.footnote.weight(.semibold))
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .tint(isNotificationScheduled(for: bus) ? .red : .blue)
                        }
                    }
                }
                if index < vm.nextBuses.count - 1 {
                    Divider()
                }
            }
        }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
}

    private var selectedDepartureEntry: BusTrip? {
        guard !selectedDeparture.isEmpty else { return nil }

        if selectedDeparture == nowDepartureOptionTag {
            guard let next = vm.nextBuses.first else { return nil }
            return BusTrip(depart: next.departString, arrive: next.arriveString)
        }

        return vm.todayTimetable.first { $0.depart == selectedDeparture }
    }

    private var availableDepartureOptions: [BusTrip] {
        vm.todayTimetable
    }

    private var isNowDepartureSelected: Bool {
        selectedDeparture == nowDepartureOptionTag
    }

    private var departureSearchCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("出発時刻を調べる")
                .font(.headline)

            Menu {
                Button("選択をクリア") {
                    selectedDeparture = ""
                }

                Divider()

                Picker("出発時刻", selection: $selectedDeparture) {
                    Text("現在時刻（今から探す）")
                        .tag(nowDepartureOptionTag)
                    ForEach(availableDepartureOptions, id: \.depart) { item in
                        Text("\(item.depart) 発（到着 \(item.arrive)）")
                            .tag(item.depart)
                    }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("出発時刻")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let selected = selectedDepartureEntry {
                            if isNowDepartureSelected {
                                Text("現在時刻から検索（次便 \(selected.depart) 発）")
                                    .font(.body.monospacedDigit())
                                    .fontWeight(.semibold)
                            } else {
                                Text("\(selected.depart) 発")
                                    .font(.body.monospacedDigit())
                                    .fontWeight(.semibold)
                            }
                        } else {
                            Text("プルダウンで選択")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }

            if let selected = selectedDepartureEntry {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        if isNowDepartureSelected {
                            Text("次便")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        Text(selected.depart)
                            .font(.title3.monospacedDigit())
                            .fontWeight(.semibold)
                        Text("発")
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("到着予定 \(selected.arrive)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var endOfServiceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("メモ")
                .font(.headline)

            Text("次の改善として、終車後に「明日の始発」を表示する機能を追加できます。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    ContentView()
}
