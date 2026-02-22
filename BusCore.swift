import Foundation

// MARK: - Models shared by App / Widget

struct BusSchedule: Codable {
    let routeName: String
    let stopName: String
    let weekday: DaySchedule
    let saturday: DaySchedule
    let sundayHoliday: DaySchedule
}

struct DaySchedule: Codable {
    let outbound: [BusTrip]
}

struct BusTrip: Codable, Hashable {
    let depart: String
    let arrive: String
}

enum ServiceType: String {
    case weekday = "平日"
    case saturday = "土曜"
    case sundayHoliday = "日曜祝日"
}

struct BusCandidate: Identifiable, Hashable {
    let id = UUID()
    let trip: BusTrip
    let departureDate: Date
    let arrivalDate: Date
    let now: Date

    var departString: String { trip.depart }
    var arriveString: String { trip.arrive }

    /// 分単位（切り上げではなく floor ベース）
    var minutesUntil: Int {
        max(0, Int(departureDate.timeIntervalSince(now) / 60))
    }

    var isDeparted: Bool {
        departureDate <= now
    }
}

// MARK: - Local JSON Loader

enum LocalJSONLoader {
    static func loadSchedule(filename: String = "times", bundle: Bundle = .main) throws -> BusSchedule {
        let url = try fileURL(filename: filename, ext: "json", bundle: bundle)
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(BusSchedule.self, from: data)
    }

    /// holidays.json は 1行に1件の `yyyy/M/d` 形式を想定
    static func loadHolidayStrings(filename: String = "holidays", bundle: Bundle = .main) throws -> [String] {
        let url = try fileURL(filename: filename, ext: "json", bundle: bundle)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func fileURL(filename: String, ext: String, bundle: Bundle) throws -> URL {
        if let url = bundle.url(forResource: filename, withExtension: ext) {
            return url
        }

        // Widget などで bundle が異なるときの保険（all bundles を探索）
        let bundles = [bundle] + Bundle.allBundles + Bundle.allFrameworks
        for b in bundles {
            if let url = b.url(forResource: filename, withExtension: ext) {
                return url
            }
        }

        throw NSError(
            domain: "LocalJSONLoader",
            code: 404,
            userInfo: [NSLocalizedDescriptionKey: "\(filename).\(ext) が見つかりません"]
        )
    }
}

// MARK: - Holiday Calendar

struct HolidayCalendar {
    private let holidayKeys: Set<String>
    private let calendar: Calendar

    init(holidayStrings: [String], calendar: Calendar = TimetableCalculator.jstCalendar) {
        self.calendar = calendar
        self.holidayKeys = Set(holidayStrings.compactMap { Self.normalizeDateKey($0) })
    }

    func serviceType(for date: Date) -> ServiceType {
        let weekday = calendar.component(.weekday, from: date)
        let key = Self.key(from: date, calendar: calendar)
        let isHoliday = holidayKeys.contains(key)

        // Gregorian weekday: 1=Sun, 7=Sat
        if isHoliday || weekday == 1 {
            return .sundayHoliday
        }
        if weekday == 7 {
            return .saturday
        }
        return .weekday
    }

    static func key(from date: Date, calendar: Calendar = TimetableCalculator.jstCalendar) -> String {
        let y = calendar.component(.year, from: date)
        let m = calendar.component(.month, from: date)
        let d = calendar.component(.day, from: date)
        return "\(y)/\(m)/\(d)"
    }

    private static func normalizeDateKey(_ raw: String) -> String? {
        let parts = raw.split(separator: "/").map(String.init)
        guard parts.count == 3,
              let y = Int(parts[0]),
              let m = Int(parts[1]),
              let d = Int(parts[2]) else {
            return nil
        }
        return "\(y)/\(m)/\(d)"
    }
}

// MARK: - Timetable Calculation

enum TimetableCalculator {
    static let jstTimeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
    static var jstCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = jstTimeZone
        cal.locale = Locale(identifier: "ja_JP")
        return cal
    }

    static func trips(for serviceType: ServiceType, in schedule: BusSchedule) -> [BusTrip] {
        switch serviceType {
        case .weekday:
            return schedule.weekday.outbound
        case .saturday:
            return schedule.saturday.outbound
        case .sundayHoliday:
            return schedule.sundayHoliday.outbound
        }
    }

    static func nextBuses(
        now: Date,
        schedule: BusSchedule,
        holidayCalendar: HolidayCalendar,
        limit: Int = 3
    ) -> [BusCandidate] {
        let type = holidayCalendar.serviceType(for: now)
        let dayTrips = trips(for: type, in: schedule)
        let cal = jstCalendar

        let candidates = dayTrips.compactMap { trip -> BusCandidate? in
            guard let depart = date(for: trip.depart, on: now, calendar: cal),
                  let arrive = date(for: trip.arrive, on: now, calendar: cal) else {
                return nil
            }
            return BusCandidate(trip: trip, departureDate: depart, arrivalDate: arrive, now: now)
        }
        .filter { $0.departureDate >= now }
        .sorted { $0.departureDate < $1.departureDate }

        return Array(candidates.prefix(limit))
    }

    static func allCandidatesForToday(
        baseDate: Date,
        schedule: BusSchedule,
        holidayCalendar: HolidayCalendar
    ) -> [BusCandidate] {
        let type = holidayCalendar.serviceType(for: baseDate)
        let tripsToday = trips(for: type, in: schedule)
        let cal = jstCalendar

        return tripsToday.compactMap { trip in
            guard let depart = date(for: trip.depart, on: baseDate, calendar: cal),
                  let arrive = date(for: trip.arrive, on: baseDate, calendar: cal) else {
                return nil
            }
            return BusCandidate(trip: trip, departureDate: depart, arrivalDate: arrive, now: baseDate)
        }
    }

    static func findBus(
        departHHmm: String,
        baseDate: Date,
        schedule: BusSchedule,
        holidayCalendar: HolidayCalendar
    ) -> BusCandidate? {
        allCandidatesForToday(baseDate: baseDate, schedule: schedule, holidayCalendar: holidayCalendar)
            .first(where: { $0.trip.depart == departHHmm })
    }

    static func serviceTypeText(
        on date: Date,
        holidayCalendar: HolidayCalendar
    ) -> String {
        holidayCalendar.serviceType(for: date).rawValue
    }

    static func date(for hhmm: String, on baseDate: Date, calendar: Calendar = jstCalendar) -> Date? {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return nil
        }

        let comps = calendar.dateComponents([.year, .month, .day], from: baseDate)
        var merged = DateComponents()
        merged.calendar = calendar
        merged.timeZone = calendar.timeZone
        merged.year = comps.year
        merged.month = comps.month
        merged.day = comps.day
        merged.hour = hour
        merged.minute = minute
        merged.second = 0
        return calendar.date(from: merged)
    }
}
