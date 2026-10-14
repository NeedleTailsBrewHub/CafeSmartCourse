//
//  DemandInference.swift
//  CafeSmartAPI
//
//  Live inference for workloadHourly / reservationsHourly — same shape as restock forecastSeries.
//

import Foundation
import Vapor

enum DemandInference {
    /// Enough history for weekday/hour priors and lag_168h features without full-collection scans.
    private static let historyLookbackDays = 90

    struct HourPoint: Sendable, Equatable {
        var hourStart: Date
        var value: Double
    }

    struct Series: Sendable, Equatable {
        var points: [HourPoint]
        var source: DemandSource

        var byHourStart: [Date: Double] {
            Dictionary(uniqueKeysWithValues: points.map { ($0.hourStart, $0.value) })
        }
    }

    private static func historyWindow(now: Date, calendar: Calendar = .current) -> (from: Date, to: Date) {
        let from = calendar.date(byAdding: .day, value: -historyLookbackDays, to: now) ?? now
        return (from, now.addingTimeInterval(1))
    }

    // MARK: - Public API

    /// Forecast cafe order volume for the next `hours` hours using workloadHourly when loaded.
    static func forecastOrders(app: Application, hours: Int, now: Date = Date()) async throws -> Series {
        let horizon = min(max(hours, 1), 24 * 60)
        let calendar = Calendar.current
        let window = historyWindow(now: now, calendar: calendar)
        let orders = try await app.mongoStore.listOrders(from: window.from, to: window.to)
            .filter { $0.status != .canceled }

        if let predictor = await app.predictors.get(.workloadHourly) {
            let points = try await forecastWorkloadWithModel(
                predictor: predictor,
                orders: orders,
                calendar: calendar,
                now: now,
                hours: horizon)
            return Series(points: points, source: .model)
        }

        let prior = historicalOrderPrior(orders: orders, calendar: calendar)
        let points = expandPrior(prior: prior, calendar: calendar, now: now, hours: horizon)
        return Series(points: points, source: .historical)
    }

    /// Forecast reservation covers for the next `hours` hours.
    static func forecastCovers(app: Application, hours: Int, now: Date = Date()) async throws -> Series {
        let horizon = min(max(hours, 1), 24 * 60)
        let calendar = Calendar.current
        let window = historyWindow(now: now, calendar: calendar)
        let reservations = try await app.mongoStore.listReservations(from: window.from, to: window.to)
            .filter { ($0.status ?? .active) != .canceled }

        if let predictor = await app.predictors.get(.reservationsHourly) {
            let points = try await forecastReservationsWithModel(
                predictor: predictor,
                reservations: reservations,
                calendar: calendar,
                now: now,
                hours: horizon)
            return Series(points: points, source: .model)
        }

        let prior = historicalCoverPrior(reservations: reservations, calendar: calendar)
        let points = expandPrior(prior: prior, calendar: calendar, now: now, hours: horizon)
        return Series(points: points, source: .historical)
    }

    /// Combined 0…1 busyness index per hour start (0.5 workload + 0.5 reservation covers).
    static func combinedBusynessIndex(
        app: Application,
        hours: Int,
        now: Date = Date()
    ) async throws -> (byHour: [Date: Double], source: DemandSource) {
        let orders = try await forecastOrders(app: app, hours: hours, now: now)
        let covers = try await forecastCovers(app: app, hours: hours, now: now)
        let maxOrders = max(orders.points.map(\.value).max() ?? 0, 1e-9)
        let maxCovers = max(covers.points.map(\.value).max() ?? 0, 1e-9)

        var out: [Date: Double] = [:]
        let keys = Set(orders.byHourStart.keys).union(covers.byHourStart.keys)
        for key in keys {
            let o = (orders.byHourStart[key] ?? 0) / maxOrders
            let c = (covers.byHourStart[key] ?? 0) / maxCovers
            out[key] = min(1, max(0, 0.5 * o + 0.5 * c))
        }
        let source: DemandSource =
            (orders.source == .model || covers.source == .model) ? .model : .historical
        return (out, source)
    }

    /// Scale factor for restock: predicted avg orders over lead window ÷ historical baseline.
    /// Clamped to [0.75, 1.75] so cold starts don't explode reorder qty.
    static func busynessScale(app: Application, leadTimeDays: Int, now: Date = Date()) async throws
        -> Double
    {
        let hours = max(1, leadTimeDays) * 24
        let series = try await forecastOrders(app: app, hours: hours, now: now)
        let predictedAvg =
            series.points.isEmpty
            ? 0 : series.points.map(\.value).reduce(0, +) / Double(series.points.count)

        let calendar = Calendar.current
        let window = historyWindow(now: now, calendar: calendar)
        let orders = try await app.mongoStore.listOrders(from: window.from, to: window.to)
            .filter { $0.status != .canceled }
        let prior = historicalOrderPrior(orders: orders, calendar: calendar)
        let baselineValues = prior.values.flatMap(\.values)
        let baselineAvg =
            baselineValues.isEmpty
            ? predictedAvg : baselineValues.reduce(0, +) / Double(baselineValues.count)

        guard baselineAvg > 0.05 else { return 1.0 }
        let raw = predictedAvg / baselineAvg
        return min(1.75, max(0.75, raw))
    }

    // MARK: - Model inference

    private static func forecastWorkloadWithModel(
        predictor: any PredictorServing,
        orders: [Order],
        calendar: Calendar,
        now: Date,
        hours: Int
    ) async throws -> [HourPoint] {
        let (_, outName) = try await predictor.ioNames()
        var orderCounts = hourlyOrderCounts(orders: orders, calendar: calendar)
        var coverCounts = hourlyGuestCounts(orders: orders, calendar: calendar)

        var lag1 = value(orderCounts, at: now, hoursAgo: 1, calendar: calendar)
        var lag24 = value(orderCounts, at: now, hoursAgo: 24, calendar: calendar)
        var lag168 = value(orderCounts, at: now, hoursAgo: 168, calendar: calendar)
        var rolling = rollingAverage(orderCounts, at: now, window: 24, calendar: calendar)
        var coversLag1 = value(coverCounts, at: now, hoursAgo: 1, calendar: calendar)
        var coversLag24 = value(coverCounts, at: now, hoursAgo: 24, calendar: calendar)

        var points: [HourPoint] = []
        let start = hourStart(now, calendar: calendar)

        for offset in 0..<hours {
            guard let target = calendar.date(byAdding: .hour, value: offset, to: start) else {
                continue
            }
            let comps = calendar.dateComponents(
                [.year, .month, .day, .hour, .weekday], from: target)
            let inputs: [String: PredictorFeature] = [
                "orders_lag_1h": .double(lag1),
                "orders_lag_24h": .double(lag24),
                "orders_lag_168h": .double(lag168),
                "rolling_orders_24h": .double(rolling),
                "covers_lag_1h": .double(coversLag1),
                "covers_lag_24h": .double(coversLag24),
                "year": .int(comps.year ?? 0),
                "month": .int(comps.month ?? 0),
                "day": .int(comps.day ?? 0),
                "hour": .int(comps.hour ?? 0),
                "weekday": .int(comps.weekday ?? 0),
            ]
            let out = try await predictor.predictMultiple(inputs: inputs, outputName: outName)
            let pred = max(0, Double(out.first ?? 0))
            points.append(HourPoint(hourStart: target, value: pred))

            // Roll features for next step (recursive one-step, same idea as restock).
            lag168 = lag24
            lag24 = lag1
            lag1 = pred
            rolling = (rolling * 23 + pred) / 24
            coversLag24 = coversLag1
            coversLag1 = pred  // approximate covers ~ orders when guest count unknown
            orderCounts[target] = pred
        }
        return points
    }

    private static func forecastReservationsWithModel(
        predictor: any PredictorServing,
        reservations: [Reservation],
        calendar: Calendar,
        now: Date,
        hours: Int
    ) async throws -> [HourPoint] {
        let (_, outName) = try await predictor.ioNames()
        var covers = hourlyReservationCovers(reservations: reservations, calendar: calendar)
        var counts = hourlyReservationCounts(reservations: reservations, calendar: calendar)

        var coversLag1 = value(covers, at: now, hoursAgo: 1, calendar: calendar)
        var coversLag24 = value(covers, at: now, hoursAgo: 24, calendar: calendar)
        var coversLag168 = value(covers, at: now, hoursAgo: 168, calendar: calendar)
        var rolling = rollingAverage(covers, at: now, window: 24, calendar: calendar)
        var resLag1 = value(counts, at: now, hoursAgo: 1, calendar: calendar)
        var resLag24 = value(counts, at: now, hoursAgo: 24, calendar: calendar)

        var points: [HourPoint] = []
        let start = hourStart(now, calendar: calendar)

        for offset in 0..<hours {
            guard let target = calendar.date(byAdding: .hour, value: offset, to: start) else {
                continue
            }
            let comps = calendar.dateComponents(
                [.year, .month, .day, .hour, .weekday], from: target)
            let inputs: [String: PredictorFeature] = [
                "covers_lag_1h": .double(coversLag1),
                "covers_lag_24h": .double(coversLag24),
                "covers_lag_168h": .double(coversLag168),
                "rolling_covers_24h": .double(rolling),
                "reservations_lag_1h": .double(resLag1),
                "reservations_lag_24h": .double(resLag24),
                "year": .int(comps.year ?? 0),
                "month": .int(comps.month ?? 0),
                "day": .int(comps.day ?? 0),
                "hour": .int(comps.hour ?? 0),
                "weekday": .int(comps.weekday ?? 0),
            ]
            let out = try await predictor.predictMultiple(inputs: inputs, outputName: outName)
            let pred = max(0, Double(out.first ?? 0))
            points.append(HourPoint(hourStart: target, value: pred))

            coversLag168 = coversLag24
            coversLag24 = coversLag1
            coversLag1 = pred
            rolling = (rolling * 23 + pred) / 24
            resLag24 = resLag1
            resLag1 = max(1, pred / 2)
            covers[target] = pred
        }
        return points
    }

    // MARK: - Historical priors

    /// weekday -> hour -> average count per distinct ISO week in the sample.
    static func historicalOrderPrior(orders: [Order], calendar: Calendar) -> [Int: [Int: Double]] {
        var totals: [Int: [Int: Double]] = [:]
        var weekKeys = Set<String>()
        for order in orders {
            let weekday = calendar.component(.weekday, from: order.createdAt)
            let hour = calendar.component(.hour, from: order.createdAt)
            totals[weekday, default: [:]][hour, default: 0] += 1
            let week = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: order.createdAt)
            weekKeys.insert("\(week.yearForWeekOfYear ?? 0)-\(week.weekOfYear ?? 0)")
        }
        let weeks = max(1.0, Double(weekKeys.count))
        var out: [Int: [Int: Double]] = [:]
        for weekday in 1...7 {
            out[weekday] = [:]
            for hour in 0..<24 {
                out[weekday]?[hour] = (totals[weekday]?[hour] ?? 0) / weeks
            }
        }
        return out
    }

    static func historicalCoverPrior(reservations: [Reservation], calendar: Calendar) -> [Int: [Int:
        Double]]
    {
        var totals: [Int: [Int: Double]] = [:]
        var weekKeys = Set<String>()
        for r in reservations {
            let weekday = calendar.component(.weekday, from: r.startTime)
            let hour = calendar.component(.hour, from: r.startTime)
            totals[weekday, default: [:]][hour, default: 0] += Double(r.seatsOccupied ?? r.partySize)
            let week = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: r.startTime)
            weekKeys.insert("\(week.yearForWeekOfYear ?? 0)-\(week.weekOfYear ?? 0)")
        }
        let weeks = max(1.0, Double(weekKeys.count))
        var out: [Int: [Int: Double]] = [:]
        for weekday in 1...7 {
            out[weekday] = [:]
            for hour in 0..<24 {
                out[weekday]?[hour] = (totals[weekday]?[hour] ?? 0) / weeks
            }
        }
        return out
    }

    private static func expandPrior(
        prior: [Int: [Int: Double]],
        calendar: Calendar,
        now: Date,
        hours: Int
    ) -> [HourPoint] {
        let start = hourStart(now, calendar: calendar)
        var points: [HourPoint] = []
        for offset in 0..<hours {
            guard let target = calendar.date(byAdding: .hour, value: offset, to: start) else {
                continue
            }
            let weekday = calendar.component(.weekday, from: target)
            let hour = calendar.component(.hour, from: target)
            let value = prior[weekday]?[hour] ?? 0
            points.append(HourPoint(hourStart: target, value: value))
        }
        return points
    }

    // MARK: - Bucketing helpers

    static func hourStart(_ date: Date, calendar: Calendar) -> Date {
        let comps = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        return calendar.date(from: comps) ?? date
    }

    private static func hourlyOrderCounts(orders: [Order], calendar: Calendar) -> [Date: Double] {
        var map: [Date: Double] = [:]
        for o in orders {
            let h = hourStart(o.createdAt, calendar: calendar)
            map[h, default: 0] += 1
        }
        return map
    }

    private static func hourlyGuestCounts(orders: [Order], calendar: Calendar) -> [Date: Double] {
        var map: [Date: Double] = [:]
        for o in orders {
            let h = hourStart(o.createdAt, calendar: calendar)
            map[h, default: 0] += Double(o.guests ?? 1)
        }
        return map
    }

    private static func hourlyReservationCovers(reservations: [Reservation], calendar: Calendar)
        -> [Date: Double]
    {
        var map: [Date: Double] = [:]
        for r in reservations {
            let h = hourStart(r.startTime, calendar: calendar)
            map[h, default: 0] += Double(r.seatsOccupied ?? r.partySize)
        }
        return map
    }

    private static func hourlyReservationCounts(reservations: [Reservation], calendar: Calendar)
        -> [Date: Double]
    {
        var map: [Date: Double] = [:]
        for r in reservations {
            let h = hourStart(r.startTime, calendar: calendar)
            map[h, default: 0] += 1
        }
        return map
    }

    private static func value(
        _ map: [Date: Double], at now: Date, hoursAgo: Int, calendar: Calendar
    ) -> Double {
        let start = hourStart(now, calendar: calendar)
        guard let t = calendar.date(byAdding: .hour, value: -hoursAgo, to: start) else { return 0 }
        return map[t] ?? 0
    }

    private static func rollingAverage(
        _ map: [Date: Double], at now: Date, window: Int, calendar: Calendar
    ) -> Double {
        let start = hourStart(now, calendar: calendar)
        var sum = 0.0
        for k in 1...window {
            guard let t = calendar.date(byAdding: .hour, value: -k, to: start) else { continue }
            sum += map[t] ?? 0
        }
        return sum / Double(window)
    }
}

/// Deterministic predictor for tests — returns `base + hour` (or covers variant).
actor ScriptedHourPredictor: PredictorServing {
    let outputName: String
    let base: Float

    init(outputName: String = "target_orders", base: Float = 2) {
        self.outputName = outputName
        self.base = base
    }

    func ioNames() async throws -> (input: String, output: String) {
        ("features", outputName)
    }

    func predictMultiple(inputs: [String: PredictorFeature], outputName: String) async throws
        -> [Float]
    {
        _ = outputName
        let hour: Int = {
            if case .int(let h) = inputs["hour"] { return h }
            return 0
        }()
        return [base + Float(hour)]
    }
}
