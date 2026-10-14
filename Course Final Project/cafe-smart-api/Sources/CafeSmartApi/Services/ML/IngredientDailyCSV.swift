import Foundation

enum IngredientDailyCSV {
    struct DayBucket: Hashable {
        let date: Date
    }

    /// Builds the ingredientDaily training/export CSV from store data.
    static func build(store: any MongoStore, sku: String? = nil) async throws -> String {
        var dayToIngredientQty: [String: [DayBucket: Double]] = [:]
        var dayToItemsTotal: [DayBucket: Double] = [:]
        var dayToOrdersTotal: [DayBucket: Int] = [:]

        let calendar = Calendar.current
        let df = ISO8601DateFormatter()

        var recipeMap: [String: [RecipeComponent]] = [:]
        for r in try await store.listRecipes() {
            recipeMap[r.menuItemId] = r.components
        }

        func startOfDay(_ date: Date) -> Date {
            calendar.startOfDay(for: date)
        }

        let orders = try await store.listOrders()
        for o in orders {
            let createdDay = DayBucket(date: startOfDay(o.createdAt))
            dayToOrdersTotal[createdDay, default: 0] += 1

            for it in o.items {
                let db = DayBucket(date: startOfDay(o.createdAt))
                dayToItemsTotal[db, default: 0.0] += Double(it.quantity)
                if let comps = recipeMap[it.menuItemId] {
                    for c in comps {
                        let factor = c.unitsPerItem * (1.0 + (c.wastageRate ?? 0.0))
                        let used = Double(it.quantity) * factor
                        var m = dayToIngredientQty[c.sku] ?? [:]
                        m[db, default: 0.0] += used
                        dayToIngredientQty[c.sku] = m
                    }
                }
            }
        }

        var allDays: Set<DayBucket> = []
        for m in dayToIngredientQty.values {
            for k in m.keys { allDays.insert(k) }
        }
        let sortedDays = allDays.sorted { $0.date < $1.date }

        func usage(_ sku: String, _ d: DayBucket) -> Double {
            dayToIngredientQty[sku]?[d] ?? 0.0
        }
        func orderCount(_ d: DayBucket) -> Int {
            dayToOrdersTotal[d] ?? 0
        }
        func items(_ d: DayBucket) -> Double {
            dayToItemsTotal[d] ?? 0.0
        }

        var out = [
            "sku", "date", "year", "month", "day", "weekday", "is_weekend",
            "orders_total_lag_1d", "items_total_lag_1d",
            "usage_lag_1d", "usage_lag_7d", "rolling_usage_last_7d",
            "usage_same_weekday_lag_28d",
            "target_usage",
        ].joined(separator: ",") + "\n"

        func emitRows(for sku: String) {
            for db in sortedDays {
                let d = db.date
                let comps = calendar.dateComponents([.year, .month, .day, .weekday], from: d)
                let isWeekend = (comps.weekday == 1 || comps.weekday == 7)
                let dLag1 = DayBucket(date: calendar.date(byAdding: .day, value: -1, to: d)!)
                let dLag7 = DayBucket(date: calendar.date(byAdding: .day, value: -7, to: d)!)
                let dLag28 = DayBucket(date: calendar.date(byAdding: .day, value: -28, to: d)!)

                var sum: Double = 0
                for k in 1...7 {
                    sum += usage(sku, DayBucket(date: calendar.date(byAdding: .day, value: -k, to: d)!))
                }
                let avg7 = sum / 7.0

                let row: [String] = [
                    sku,
                    df.string(from: d),
                    String(comps.year ?? 0), String(comps.month ?? 0), String(comps.day ?? 0),
                    String(comps.weekday ?? 0), isWeekend ? "true" : "false",
                    String(orderCount(dLag1)), String(format: "%.4f", items(dLag1)),
                    String(format: "%.4f", usage(sku, dLag1)), String(format: "%.4f", usage(sku, dLag7)),
                    String(format: "%.4f", avg7), String(format: "%.4f", usage(sku, dLag28)),
                    String(format: "%.4f", usage(sku, db)),
                ]
                out += row.joined(separator: ",") + "\n"
            }
        }

        if let sku, !sku.isEmpty {
            emitRows(for: sku)
        } else {
            for sku in dayToIngredientQty.keys.sorted() {
                emitRows(for: sku)
            }
        }
        return out
    }

    /// Prefer real store data; fall back to a contract-valid stub when too few rows.
    /// Used by server train and by CSV export for local Create ML training.
    static func forTraining(store: any MongoStore, sku: String? = nil) async throws -> String {
        let csv = try await build(store: store, sku: sku)
        let rows = csv.split(whereSeparator: \.isNewline).count
        // header + at least 5 data rows (Create ML / trainer requirement)
        if rows < 6 {
            return CafePredictorController.minimalTrainingCSV()
        }
        return csv
    }
}
