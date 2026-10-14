import Foundation

enum OrdersHourlyCSV {
    struct HourBucket: Hashable {
        let date: Date
    }

    static let headerColumns: [String] = [
        "hour_key", "year", "month", "day", "hour", "weekday", "is_weekend",
        "orders_lag_1h", "orders_lag_24h", "orders_lag_168h", "rolling_orders_24h",
        "covers_lag_1h", "covers_lag_24h",
        "target_orders",
    ]

    /// Builds the ordersHourly / workloadHourly training CSV from store orders.
    static func build(store: any MongoStore) async throws -> String {
        let calendar = Calendar.current
        let orders = try await store.listOrders().filter { $0.status != .canceled }

        var ordersByHour: [HourBucket: Int] = [:]
        var coversByHour: [HourBucket: Double] = [:]

        func hourStart(_ date: Date) -> Date {
            let comps = calendar.dateComponents([.year, .month, .day, .hour], from: date)
            return calendar.date(from: comps) ?? date
        }

        for o in orders {
            let bucket = HourBucket(date: hourStart(o.createdAt))
            ordersByHour[bucket, default: 0] += 1
            coversByHour[bucket, default: 0] += Double(o.guests ?? 1)
        }

        let sortedHours = ordersByHour.keys.sorted { $0.date < $1.date }

        func orderCount(_ b: HourBucket) -> Int { ordersByHour[b] ?? 0 }
        func covers(_ b: HourBucket) -> Double { coversByHour[b] ?? 0 }

        var out = headerColumns.joined(separator: ",") + "\n"

        for bucket in sortedHours {
            let d = bucket.date
            let comps = calendar.dateComponents(
                [.year, .month, .day, .hour, .weekday], from: d)
            let isWeekend = (comps.weekday == 1 || comps.weekday == 7)
            let lag1 = HourBucket(date: calendar.date(byAdding: .hour, value: -1, to: d)!)
            let lag24 = HourBucket(date: calendar.date(byAdding: .hour, value: -24, to: d)!)
            let lag168 = HourBucket(date: calendar.date(byAdding: .hour, value: -168, to: d)!)

            var sum24 = 0
            for k in 1...24 {
                sum24 += orderCount(
                    HourBucket(date: calendar.date(byAdding: .hour, value: -k, to: d)!))
            }
            let rolling = Double(sum24) / 24.0

            let hourKey = String(
                format: "%04d-%02d-%02dT%02d",
                comps.year ?? 0, comps.month ?? 0, comps.day ?? 0, comps.hour ?? 0)

            let row: [String] = [
                hourKey,
                String(comps.year ?? 0), String(comps.month ?? 0), String(comps.day ?? 0),
                String(comps.hour ?? 0), String(comps.weekday ?? 0), isWeekend ? "true" : "false",
                String(orderCount(lag1)), String(orderCount(lag24)), String(orderCount(lag168)),
                String(format: "%.4f", rolling),
                String(format: "%.4f", covers(lag1)), String(format: "%.4f", covers(lag24)),
                String(orderCount(bucket)),
            ]
            out += row.joined(separator: ",") + "\n"
        }
        return out
    }

    /// Prefer real store data; fall back to a contract-valid stub when too few rows.
    static func forTraining(store: any MongoStore) async throws -> String {
        let csv = try await build(store: store)
        let rows = csv.split(whereSeparator: \.isNewline).count
        // header + at least 24 data rows
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
            let lag1 = max(0, i - 1)
            let lag24 = max(0, i - 24)
            let lag168 = max(0, i - 168)
            let rolling = Double(lag1 + 1) * 0.4
            rows.append([
                String(format: "2024-01-%02dT%02d", day, hour),
                "2024", "1", String(day), String(hour), String(weekday), isWeekend,
                String(lag1), String(lag24), String(lag168), String(format: "%.4f", rolling),
                String(format: "%.4f", Double(lag1) * 1.2),
                String(format: "%.4f", Double(lag24) * 1.2),
                String(max(1, i % 8)),
            ].joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }
}
