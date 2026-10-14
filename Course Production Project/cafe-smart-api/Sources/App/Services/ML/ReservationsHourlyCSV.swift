import Foundation

enum ReservationsHourlyCSV {
    struct HourBucket: Hashable {
        let date: Date
    }

    static let headerColumns: [String] = [
        "hour_key", "year", "month", "day", "hour", "weekday", "is_weekend",
        "covers_lag_1h", "covers_lag_24h", "covers_lag_168h", "rolling_covers_24h",
        "reservations_lag_1h", "reservations_lag_24h",
        "target_covers",
    ]

    /// Builds the reservationsHourly training CSV from store reservations.
    static func build(store: any MongoStore) async throws -> String {
        let calendar = Calendar.current
        let reservations = try await store.listReservations()
            .filter { ($0.status ?? .active) != .canceled }

        var coversByHour: [HourBucket: Double] = [:]
        var reservationsByHour: [HourBucket: Int] = [:]

        func hourStart(_ date: Date) -> Date {
            let comps = calendar.dateComponents([.year, .month, .day, .hour], from: date)
            return calendar.date(from: comps) ?? date
        }

        for r in reservations {
            let bucket = HourBucket(date: hourStart(r.startTime))
            coversByHour[bucket, default: 0] += Double(r.seatsOccupied ?? r.partySize)
            reservationsByHour[bucket, default: 0] += 1
        }

        let sortedHours = coversByHour.keys.sorted { $0.date < $1.date }

        func covers(_ b: HourBucket) -> Double { coversByHour[b] ?? 0 }
        func resCount(_ b: HourBucket) -> Int { reservationsByHour[b] ?? 0 }

        var out = headerColumns.joined(separator: ",") + "\n"

        for bucket in sortedHours {
            let d = bucket.date
            let comps = calendar.dateComponents(
                [.year, .month, .day, .hour, .weekday], from: d)
            let isWeekend = (comps.weekday == 1 || comps.weekday == 7)
            let lag1 = HourBucket(date: calendar.date(byAdding: .hour, value: -1, to: d)!)
            let lag24 = HourBucket(date: calendar.date(byAdding: .hour, value: -24, to: d)!)
            let lag168 = HourBucket(date: calendar.date(byAdding: .hour, value: -168, to: d)!)

            var sum24 = 0.0
            for k in 1...24 {
                sum24 += covers(
                    HourBucket(date: calendar.date(byAdding: .hour, value: -k, to: d)!))
            }
            let rolling = sum24 / 24.0

            let hourKey = String(
                format: "%04d-%02d-%02dT%02d",
                comps.year ?? 0, comps.month ?? 0, comps.day ?? 0, comps.hour ?? 0)

            let row: [String] = [
                hourKey,
                String(comps.year ?? 0), String(comps.month ?? 0), String(comps.day ?? 0),
                String(comps.hour ?? 0), String(comps.weekday ?? 0), isWeekend ? "true" : "false",
                String(format: "%.4f", covers(lag1)),
                String(format: "%.4f", covers(lag24)),
                String(format: "%.4f", covers(lag168)),
                String(format: "%.4f", rolling),
                String(resCount(lag1)), String(resCount(lag24)),
                String(format: "%.4f", covers(bucket)),
            ]
            out += row.joined(separator: ",") + "\n"
        }
        return out
    }

    /// Prefer real store data; fall back to a contract-valid stub when too few rows.
    static func forTraining(store: any MongoStore) async throws -> String {
        let csv = try await build(store: store)
        let rows = csv.split(whereSeparator: \.isNewline).count
        if rows < 25 {
            return minimalTrainingCSV()
        }
        return csv
    }

    static func minimalTrainingCSV() -> String {
        var rows = [headerColumns.joined(separator: ",")]
        for i in 0..<30 {
            let day = (i / 24) + 1
            let hour = i % 24
            let weekday = (i % 7) + 1
            let isWeekend = (weekday == 1 || weekday == 7) ? "true" : "false"
            let lag1 = Double(max(0, i - 1))
            let lag24 = Double(max(0, i - 24))
            let lag168 = Double(max(0, i - 168))
            let rolling = (lag1 + 1) * 0.5
            rows.append([
                String(format: "2024-01-%02dT%02d", day, hour),
                "2024", "1", String(day), String(hour), String(weekday), isWeekend,
                String(format: "%.4f", lag1),
                String(format: "%.4f", lag24),
                String(format: "%.4f", lag168),
                String(format: "%.4f", rolling),
                String(max(0, i - 1) % 5),
                String(max(0, i - 24) % 5),
                String(format: "%.4f", Double(max(1, i % 6))),
            ].joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }
}
