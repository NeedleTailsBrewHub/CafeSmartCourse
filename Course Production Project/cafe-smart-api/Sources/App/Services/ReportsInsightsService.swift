//
//  ReportsInsightsService.swift
//  CafeSmartAPI
//
//  Server-authoritative finance summary + demand / stock outlook.
//

import Foundation
import Vapor

enum ReportsInsightsService {
    private static let maxSummaryDays = 366
    private static let maxDemandDays = 60
    private static let historicalLookbackDays = 90
    private static let maxSalesItems = 40
    private static let maxCogsSkus = 40
    private static let maxOrderRows = 200

    // MARK: - Summary

    static func summary(
        req: Request,
        from: Date,
        to: Date,
        team: TeamController,
        salesItemLimit: Int? = maxSalesItems,
        cogsSkuLimit: Int? = maxCogsSkus
    ) async throws -> ReportsSummary {
        try validateSummaryWindow(from: from, to: to)
        let calendar = Calendar.current

        let orders = try await req.store.listOrders(from: from, to: to).filter { order in
            order.status != .canceled
        }

        // Pipeline payment mix (all open + completed non-canceled tickets).
        var paidCount = 0
        var unpaidCount = 0
        var waivedCount = 0
        var collectedCents = 0
        for order in orders {
            switch order.paymentStatus {
            case .paid:
                paidCount += 1
                let subtotal = order.subtotalCents ?? 0
                let loyalty = order.loyaltyDiscountCents ?? 0
                let tax = order.taxCents ?? 0
                collectedCents += order.totalCents ?? max(0, subtotal - loyalty + tax)
            case .waived:
                waivedCount += 1
            case .unpaid, .none:
                unpaidCount += 1
            }
        }

        // Recognized P&L: completed + paid. COGS attaches to completed (ingredients used).
        let revenueOrders = orders.filter(Self.isRecognizedRevenue)
        let cogsOrders = orders.filter { $0.status == .completed }

        var grossCents = 0
        var loyaltyDiscountCents = 0
        var taxCents = 0
        for order in revenueOrders {
            let subtotal = order.subtotalCents ?? 0
            let loyalty = order.loyaltyDiscountCents ?? 0
            let tax = order.taxCents ?? 0
            grossCents += subtotal
            loyaltyDiscountCents += loyalty
            taxCents += tax
        }

        let netCents = max(0, grossCents - loyaltyDiscountCents)
        let orderCount = revenueOrders.count
        let averageOrderCents = orderCount > 0 ? netCents / orderCount : 0

        let recipes = try await req.store.listRecipes()
        var recipesByMenuId: [String: Recipe] = [:]
        for recipe in recipes {
            if recipesByMenuId[recipe.menuItemId] == nil {
                recipesByMenuId[recipe.menuItemId] = recipe
            }
        }

        let inventory = try await req.store.listInventory()
        var costBySku: [String: Int?] = [:]
        var nameBySku: [String: String] = [:]
        for item in inventory where item.deletedAt == nil {
            costBySku[item.sku] = item.costPerUnitCents
            nameBySku[item.sku] = item.name
        }

        var cogsCents = 0
        var missingCostSkus = Set<String>()
        var unitsBySku: [String: Double] = [:]
        var cogsBySkuMap: [String: Int] = [:]

        for order in cogsOrders {
            let needed = OrderInventoryService.requiredUnitsExact(
                items: order.items, recipesByMenuId: recipesByMenuId)
            for (sku, units) in needed {
                unitsBySku[sku, default: 0] += units
                guard let costOpt = costBySku[sku], let cost = costOpt else {
                    missingCostSkus.insert(sku)
                    continue
                }
                let line = Int((units * Double(cost)).rounded())
                cogsCents += line
                cogsBySkuMap[sku, default: 0] += line
            }
        }

        let menu = try await req.store.listMenu()
        let menuById = Dictionary(uniqueKeysWithValues: menu.map { ($0.id, $0) })
        var qtyByItem: [String: Int] = [:]
        var revenueByItem: [String: Int] = [:]
        for order in revenueOrders {
            for item in order.items {
                qtyByItem[item.menuItemId, default: 0] += item.quantity
                let unit = item.unitPriceCents
                    ?? menuById[item.menuItemId]?.priceCents
                    ?? 0
                revenueByItem[item.menuItemId, default: 0] += unit * item.quantity
            }
        }
        let salesSorted = qtyByItem.keys.map { id in
            ReportsSalesItem(
                menuItemId: id,
                name: menuById[id]?.name ?? id,
                quantity: qtyByItem[id] ?? 0,
                revenueCents: revenueByItem[id] ?? 0)
        }
        .sorted {
            if $0.revenueCents != $1.revenueCents { return $0.revenueCents > $1.revenueCents }
            return $0.quantity > $1.quantity
        }
        let salesByItem: [ReportsSalesItem] = {
            guard let salesItemLimit else { return salesSorted }
            return Array(salesSorted.prefix(salesItemLimit))
        }()

        let cogsSorted = Set(unitsBySku.keys).union(missingCostSkus).map { sku -> ReportsCogsSku in
            let missing = missingCostSkus.contains(sku)
            return ReportsCogsSku(
                sku: sku,
                name: nameBySku[sku] ?? sku,
                units: unitsBySku[sku] ?? 0,
                cogsCents: cogsBySkuMap[sku] ?? 0,
                missingCost: missing)
        }
        .sorted {
            if $0.missingCost != $1.missingCost { return $0.missingCost && !$1.missingCost }
            if $0.cogsCents != $1.cogsCents { return $0.cogsCents > $1.cogsCents }
            return $0.sku.localizedCaseInsensitiveCompare($1.sku) == .orderedAscending
        }
        let cogsBySku: [ReportsCogsSku] = {
            guard let cogsSkuLimit else { return cogsSorted }
            return Array(cogsSorted.prefix(cogsSkuLimit))
        }()

        // Day buckets — revenue / COGS only for recognized / completed tickets.
        var dayAgg: [Date: (
            count: Int, gross: Int, loyalty: Int, tax: Int, collected: Int, cogs: Int
        )] = [:]
        for order in orders {
            let day = calendar.startOfDay(for: order.createdAt)
            var row = dayAgg[day] ?? (0, 0, 0, 0, 0, 0)
            let subtotal = order.subtotalCents ?? 0
            let loyalty = order.loyaltyDiscountCents ?? 0
            let tax = order.taxCents ?? 0
            if Self.isRecognizedRevenue(order) {
                row.count += 1
                row.gross += subtotal
                row.loyalty += loyalty
                row.tax += tax
            }
            if order.paymentStatus == .paid {
                row.collected += order.totalCents ?? max(0, subtotal - loyalty + tax)
            }
            if order.status == .completed {
                let needed = OrderInventoryService.requiredUnits(
                    items: order.items, recipesByMenuId: recipesByMenuId)
                for (sku, units) in needed {
                    if let costOpt = costBySku[sku], let cost = costOpt {
                        row.cogs += units * cost
                    }
                }
            }
            dayAgg[day] = row
        }
        // Drop empty days (pipeline-only activity with no finance).
        let byDay = dayAgg.keys.sorted().compactMap { day -> ReportsDayBucket? in
            let row = dayAgg[day]!
            guard row.count > 0 || row.collected > 0 || row.cogs > 0 else { return nil }
            return ReportsDayBucket(
                day: day,
                orderCount: row.count,
                grossCents: row.gross,
                netSalesCents: max(0, row.gross - row.loyalty),
                taxCents: row.tax,
                loyaltyDiscountCents: row.loyalty,
                collectedCents: row.collected,
                cogsCents: row.cogs)
        }

        let (members, entries) = try await team.rosterAndTimeEntries(req: req)
        let membersById = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0) })
        var laborById: [String: (name: String, minutes: Int, labor: Int, missing: Bool)] = [:]

        for entry in entries {
            guard entry.resolvedStatus == .approved, let clockOut = entry.clockOut else { continue }
            let start = max(entry.clockIn, from)
            let end = min(clockOut, to)
            guard end > start else { continue }
            let minutes = max(0, Int(end.timeIntervalSince(start) / 60))
            guard minutes > 0 else { continue }

            let rate = membersById[entry.teamMemberId]?.hourlyRateCents
            let missing = rate == nil
            let laborCentsForEntry: Int
            if let rate {
                laborCentsForEntry = minutes * max(0, rate) / 60
            } else {
                laborCentsForEntry = 0
            }
            var row = laborById[entry.teamMemberId]
                ?? (entry.teamMemberName, 0, 0, false)
            row.name = entry.teamMemberName
            row.minutes += minutes
            row.labor += laborCentsForEntry
            row.missing = row.missing || missing
            laborById[entry.teamMemberId] = row
        }

        let laborByMember = laborById.map { id, row in
            ReportsLaborMember(
                teamMemberId: id,
                teamMemberName: row.name,
                approvedMinutes: row.minutes,
                laborCents: row.labor,
                missingRate: row.missing)
        }
        .sorted { $0.teamMemberName.localizedCaseInsensitiveCompare($1.teamMemberName) == .orderedAscending }

        let laborCents = laborByMember.reduce(0) { $0 + $1.laborCents }
        let missingRateMemberCount = laborByMember.filter(\.missingRate).count
        let contributionCents = netCents - cogsCents - laborCents

        return ReportsSummary(
            from: from,
            to: to,
            orderCount: orderCount,
            grossCents: grossCents,
            netCents: netCents,
            taxCents: taxCents,
            loyaltyDiscountCents: loyaltyDiscountCents,
            averageOrderCents: averageOrderCents,
            paidCount: paidCount,
            unpaidCount: unpaidCount,
            waivedCount: waivedCount,
            cogsCents: cogsCents,
            missingCostSkuCount: missingCostSkus.count,
            laborCents: laborCents,
            missingRateMemberCount: missingRateMemberCount,
            contributionCents: contributionCents,
            laborByMember: laborByMember,
            collectedCents: collectedCents,
            byDay: byDay,
            salesByItem: salesByItem,
            cogsBySku: cogsBySku)
    }

    // MARK: - Order detail

    static func orders(
        req: Request,
        from: Date,
        to: Date,
        rowLimit: Int? = maxOrderRows
    ) async throws -> ReportsOrdersDetail {
        try validateSummaryWindow(from: from, to: to)
        // Indexed page — do not full-scan the orders collection.
        let limit = rowLimit ?? 50_000
        let page = try await req.store.pageOrders(
            filter: OrderListFilter(
                limit: limit,
                statuses: [.pending, .preparing, .ready, .completed],
                from: from,
                to: to.addingTimeInterval(-0.001)))
        let orders = page.items.filter { $0.createdAt >= from && $0.createdAt < to }

        let items = orders.map { order -> ReportsOrderRow in
            let subtotal = order.subtotalCents ?? 0
            let loyalty = order.loyaltyDiscountCents ?? 0
            let tax = order.taxCents ?? 0
            return ReportsOrderRow(
                id: order.id,
                createdAt: order.createdAt,
                customerName: order.customerName,
                status: order.status,
                paymentStatus: order.paymentStatus,
                channel: order.channel,
                subtotalCents: subtotal,
                loyaltyDiscountCents: loyalty,
                taxCents: tax,
                netSalesCents: max(0, subtotal - loyalty),
                totalCents: order.totalCents ?? max(0, subtotal - loyalty + tax),
                itemCount: order.items.reduce(0) { $0 + $1.quantity })
        }
        return ReportsOrdersDetail(from: from, to: to, items: items)
    }

    // MARK: - CSV export (accounting)

    /// Money columns are decimal currency (cents ÷ 100), not integer cents.
    static func exportCSV(
        req: Request,
        from: Date,
        to: Date,
        dataset: String,
        team: TeamController
    ) async throws -> CSVExportPayload {
        try validateSummaryWindow(from: from, to: to)
        let key = dataset.lowercased()
        let csv: String
        switch key {
        case "summary":
            let s = try await summary(
                req: req, from: from, to: to, team: team,
                salesItemLimit: nil, cogsSkuLimit: nil)
            csv = csvSummary(s)
        case "byday", "by_day", "daily":
            let s = try await summary(
                req: req, from: from, to: to, team: team,
                salesItemLimit: 0, cogsSkuLimit: 0)
            csv = csvByDay(s.byDay)
        case "orders", "transactions":
            let detail = try await orders(req: req, from: from, to: to, rowLimit: nil)
            csv = csvOrders(detail.items)
        case "salesbyitem", "sales_by_item", "sales":
            let s = try await summary(
                req: req, from: from, to: to, team: team,
                salesItemLimit: nil, cogsSkuLimit: 0)
            csv = csvSalesByItem(s.salesByItem)
        case "cogsbysku", "cogs_by_sku", "cogs":
            let s = try await summary(
                req: req, from: from, to: to, team: team,
                salesItemLimit: 0, cogsSkuLimit: nil)
            csv = csvCogsBySku(s.cogsBySku)
        case "labor":
            let s = try await summary(
                req: req, from: from, to: to, team: team,
                salesItemLimit: 0, cogsSkuLimit: 0)
            csv = csvLabor(s.laborByMember)
        default:
            throw Abort(
                .badRequest,
                reason: "dataset must be one of: summary, byDay, orders, salesByItem, cogsBySku, labor")
        }
        return CSVExportPayload(csv: csv)
    }

    private static func csvSummary(_ s: ReportsSummary) -> String {
        var lines = [
            "from,to,orderCount,gross,netSales,tax,loyalty,collected,cogs,labor,contribution,averageOrder,paidCount,unpaidCount,waivedCount,missingCostSkuCount,missingRateMemberCount"
        ]
        lines.append(
            [
                isoDay(s.from),
                isoDay(s.to),
                "\(s.orderCount)",
                money(s.grossCents),
                money(s.netCents),
                money(s.taxCents),
                money(s.loyaltyDiscountCents),
                money(s.collectedCents),
                money(s.cogsCents),
                money(s.laborCents),
                money(s.contributionCents),
                money(s.averageOrderCents),
                "\(s.paidCount)",
                "\(s.unpaidCount)",
                "\(s.waivedCount)",
                "\(s.missingCostSkuCount)",
                "\(s.missingRateMemberCount)",
            ].joined(separator: ","))
        return lines.joined(separator: "\n")
    }

    private static func csvByDay(_ days: [ReportsDayBucket]) -> String {
        var lines = ["day,orderCount,gross,netSales,tax,loyalty,collected,cogs"]
        for d in days {
            lines.append(
                [
                    isoDay(d.day),
                    "\(d.orderCount)",
                    money(d.grossCents),
                    money(d.netSalesCents),
                    money(d.taxCents),
                    money(d.loyaltyDiscountCents),
                    money(d.collectedCents),
                    money(d.cogsCents),
                ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private static func csvOrders(_ rows: [ReportsOrderRow]) -> String {
        var lines = [
            "id,createdAt,customerName,status,paymentStatus,channel,itemCount,subtotal,loyalty,tax,netSales,total"
        ]
        for r in rows {
            lines.append(
                [
                    csvField(r.id),
                    isoDateTime(r.createdAt),
                    csvField(r.customerName ?? ""),
                    csvField(r.status.rawValue),
                    csvField(r.paymentStatus?.rawValue ?? ""),
                    csvField(r.channel?.rawValue ?? ""),
                    "\(r.itemCount)",
                    money(r.subtotalCents),
                    money(r.loyaltyDiscountCents),
                    money(r.taxCents),
                    money(r.netSalesCents),
                    money(r.totalCents),
                ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private static func csvSalesByItem(_ rows: [ReportsSalesItem]) -> String {
        var lines = ["menuItemId,name,quantity,revenue"]
        for r in rows {
            lines.append(
                [
                    csvField(r.menuItemId),
                    csvField(r.name),
                    "\(r.quantity)",
                    money(r.revenueCents),
                ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private static func csvCogsBySku(_ rows: [ReportsCogsSku]) -> String {
        var lines = ["sku,name,units,cogs,missingCost"]
        for r in rows {
            lines.append(
                [
                    csvField(r.sku),
                    csvField(r.name),
                    String(format: "%.4f", r.units),
                    money(r.cogsCents),
                    r.missingCost ? "true" : "false",
                ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private static func csvLabor(_ rows: [ReportsLaborMember]) -> String {
        var lines = ["teamMemberId,teamMemberName,approvedMinutes,labor,missingRate"]
        for r in rows {
            lines.append(
                [
                    csvField(r.teamMemberId),
                    csvField(r.teamMemberName),
                    "\(r.approvedMinutes)",
                    money(r.laborCents),
                    r.missingRate ? "true" : "false",
                ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private static func money(_ cents: Int) -> String {
        String(format: "%.2f", Double(cents) / 100.0)
    }

    private static func isoDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private static func isoDateTime(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    private static func csvField(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n")
            || value.contains("\r")
        {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    // MARK: - Demand

    static func demand(
        req: Request,
        days: Int,
        predictor: CafePredictorController
    ) async throws -> DemandInsights {
        let clampedDays = min(maxDemandDays, max(1, days))
        let calendar = Calendar.current
        let now = Date()
        let horizonHours = clampedDays * 24

        let series = try await DemandInference.forecastOrders(
            app: req.application, hours: horizonHours, now: now)
        let source = series.source
        let coveredDays = Set(series.points.map { calendar.startOfDay(for: $0.hourStart) }).count
        let effectiveDays = max(1, min(clampedDays, coveredDays))

        let lookbackStart =
            calendar.date(byAdding: .day, value: -historicalLookbackDays, to: now) ?? now
        let historyOrders = try await req.store.listOrders(from: lookbackStart, to: now.addingTimeInterval(1))
            .filter { $0.status != .canceled }
        let guestTotal = historyOrders.reduce(0.0) { sum, order in
            sum + Double(order.guests ?? 1)
        }
        let guestsPerOrder =
            historyOrders.isEmpty ? 1.0 : guestTotal / Double(historyOrders.count)

        var sumByBucket: [Int: [Int: Double]] = [:]
        var nByBucket: [Int: [Int: Double]] = [:]
        for weekday in 1...7 {
            sumByBucket[weekday] = Dictionary(uniqueKeysWithValues: (0..<24).map { ($0, 0.0) })
            nByBucket[weekday] = Dictionary(uniqueKeysWithValues: (0..<24).map { ($0, 0.0) })
        }
        for point in series.points {
            let weekday = calendar.component(.weekday, from: point.hourStart)
            let hour = calendar.component(.hour, from: point.hourStart)
            sumByBucket[weekday]?[hour, default: 0] += point.value
            nByBucket[weekday]?[hour, default: 0] += 1
        }
        var counts: [Int: [Int: Double]] = [:]
        for weekday in 1...7 {
            counts[weekday] = [:]
            for hour in 0..<24 {
                let n = nByBucket[weekday]?[hour] ?? 0
                counts[weekday]?[hour] =
                    n > 0 ? (sumByBucket[weekday]?[hour] ?? 0) / n : 0
            }
        }

        let maxCount = counts.values.flatMap(\.values).max() ?? 0
        var heatmap: [DemandHourCell] = []
        for weekday in 1...7 {
            for hour in 0..<24 {
                let raw = counts[weekday]?[hour] ?? 0
                let index = maxCount > 0 ? raw / maxCount : 0
                heatmap.append(DemandHourCell(weekday: weekday, hour: hour, index: index))
            }
        }

        let staffingRules = try await req.store.getBusinessConfig()?.staffing
            ?? StaffingRules(
                ordersPerBaristaPerHour: 40,
                ordersPerBakerPerHour: 25,
                guestsPerHostPerHour: 60)
        let businessHours = try await req.store.getBusinessConfig()?.hours ?? []

        var peaks: [DemandPeakWindow] = []
        var staffingByHour: [Int: (orders: Double, guests: Double)] = [:]
        var ordersByDayHour: [Date: [Int: Double]] = [:]

        for point in series.points {
            let day = calendar.startOfDay(for: point.hourStart)
            let hour = calendar.component(.hour, from: point.hourStart)
            let predicted = point.value
            let guests = predicted * guestsPerOrder
            let index = maxCount > 0 ? predicted / maxCount : 0
            if predicted > 0 {
                peaks.append(
                    DemandPeakWindow(
                        day: day, hour: hour, predictedOrders: predicted, busynessIndex: index))
            }
            var agg = staffingByHour[hour] ?? (0, 0)
            agg.orders += predicted
            agg.guests += guests
            staffingByHour[hour] = agg
            if predicted > 0 {
                ordersByDayHour[day, default: [:]][hour, default: 0] += predicted
            }
        }

        peaks.sort {
            if $0.predictedOrders != $1.predictedOrders {
                return $0.predictedOrders > $1.predictedOrders
            }
            if $0.day != $1.day { return $0.day < $1.day }
            return $0.hour < $1.hour
        }
        let peakLimit = min(peaks.count, max(8, effectiveDays * 2))
        peaks = Array(peaks.prefix(peakLimit))

        let dayDivisor = Double(effectiveDays)
        var staffing: [DemandStaffSuggestion] = []
        for hour in 0..<24 {
            let avgOrders = (staffingByHour[hour]?.orders ?? 0) / dayDivisor
            let avgGuests = (staffingByHour[hour]?.guests ?? 0) / dayDivisor
            guard avgOrders > 0 else { continue }
            staffing.append(
                Self.staffSuggestion(
                    hour: hour,
                    orders: avgOrders,
                    guests: avgGuests,
                    rules: staffingRules))
        }
        staffing.sort { $0.hour < $1.hour }

        var staffingByDay: [DemandDayStaffPlan] = []
        for day in ordersByDayHour.keys.sorted() {
            let weekday = calendar.component(.weekday, from: day)
            let hourMap = ordersByDayHour[day] ?? [:]
            var hours: [DemandStaffSuggestion] = []
            var maxBaristas = 0
            var maxBakers = 0
            var maxHosts = 0
            var personHoursBaristas = 0.0
            var personHoursBakers = 0.0
            var personHoursHosts = 0.0
            var peakHour = 0
            var peakOrders = -1.0

            for hour in 0..<24 {
                guard let orders = hourMap[hour], orders > 0 else { continue }
                guard Self.isOpenHour(weekday: weekday, hour: hour, hours: businessHours)
                else { continue }
                let row = Self.staffSuggestion(
                    hour: hour,
                    orders: orders,
                    guests: orders * guestsPerOrder,
                    rules: staffingRules)
                hours.append(row)
                maxBaristas = max(maxBaristas, row.baristas)
                maxBakers = max(maxBakers, row.bakers)
                maxHosts = max(maxHosts, row.hosts)
                personHoursBaristas += Double(row.baristas)
                personHoursBakers += Double(row.bakers)
                personHoursHosts += Double(row.hosts)
                if orders > peakOrders {
                    peakOrders = orders
                    peakHour = hour
                }
            }
            guard !hours.isEmpty else { continue }
            staffingByDay.append(
                DemandDayStaffPlan(
                    day: day,
                    weekday: weekday,
                    peakHour: peakHour,
                    maxBaristas: maxBaristas,
                    maxBakers: maxBakers,
                    maxHosts: maxHosts,
                    personHoursBaristas: personHoursBaristas,
                    personHoursBakers: personHoursBakers,
                    personHoursHosts: personHoursHosts,
                    totalPersonHours: personHoursBaristas + personHoursBakers + personHoursHosts,
                    hours: hours))
        }

        let (stockOutlook, predictedStockSpendCents, stockSource) = try await buildStockOutlook(
            req: req, predictor: predictor)

        return DemandInsights(
            days: effectiveDays,
            source: source,
            heatmap: heatmap,
            peaks: peaks,
            staffing: staffing,
            stockOutlook: stockOutlook,
            predictedStockSpendCents: predictedStockSpendCents,
            stockSource: stockSource,
            staffingByDay: staffingByDay)
    }

    private static func staffSuggestion(
        hour: Int,
        orders: Double,
        guests: Double,
        rules: StaffingRules
    ) -> DemandStaffSuggestion {
        let baristas = Int(ceil(orders / Double(max(1, rules.ordersPerBaristaPerHour))))
        let bakers = Int(ceil(orders / Double(max(1, rules.ordersPerBakerPerHour))))
        let hosts = Int(ceil(guests / Double(max(1, rules.guestsPerHostPerHour))))
        return DemandStaffSuggestion(
            hour: hour,
            predictedOrders: orders,
            baristas: max(0, baristas),
            bakers: max(0, bakers),
            hosts: max(0, hosts))
    }

    /// When business hours are configured, only staff open clock hours.
    private static func isOpenHour(weekday: Int, hour: Int, hours: [BusinessHours]) -> Bool {
        guard !hours.isEmpty else { return true }
        guard let bh = hours.first(where: { $0.weekday == weekday }) else { return false }
        guard let openH = parseClockHour(bh.open), let closeH = parseClockHour(bh.close)
        else { return true }
        if closeH > openH {
            return hour >= openH && hour < closeH
        }
        // Overnight window (e.g. 22:00–02:00).
        return hour >= openH || hour < closeH
    }

    private static func parseClockHour(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":")
        guard let first = parts.first, let hour = Int(first), (0..<24).contains(hour)
        else { return nil }
        return hour
    }

    // MARK: - Stock outlook (ML restock when available)

    private static func buildStockOutlook(
        req: Request,
        predictor: CafePredictorController
    ) async throws -> ([StockOutlookRow], Int, StockOutlookSource) {
        let hasRestockModel = await req.application.predictors.get(.restockDaily) != nil
        let useTestStore = (Environment.get("USE_TEST_STORE") ?? "").lowercased() == "true"
        let isTesting = req.application.environment == .testing || useTestStore

        if hasRestockModel || isTesting {
            let results = await predictor.computeRestockDecisions(app: req.application)
            if !results.isEmpty {
                var spend = 0
                var rows: [StockOutlookRow] = []
                for result in results where result.decision.needRestock {
                    let d = result.decision
                    if let s = d.predictedSpendCents { spend += s }
                    rows.append(
                        StockOutlookRow(
                            sku: d.sku,
                            name: result.item.name,
                            needRestock: true,
                            reorderQty: d.reorderQty,
                            unitCostCents: d.unitCostCents,
                            predictedSpendCents: d.predictedSpendCents,
                            busynessScale: d.busynessScale ?? 1))
                }
                rows.sort { $0.sku.localizedCaseInsensitiveCompare($1.sku) == .orderedAscending }
                return (rows, spend, .model)
            }
        }

        // Threshold fallback when no restock model / all SKUs failed.
        let busynessScale = try await DemandInference.busynessScale(
            app: req.application, leadTimeDays: 3, now: Date())
        let inventory = try await req.store.listInventory().filter { $0.deletedAt == nil }
        var stockOutlook: [StockOutlookRow] = []
        var predictedStockSpendCents = 0

        for item in inventory {
            let needRestock = item.quantity <= item.reorderThreshold
            guard needRestock else { continue }
            let fromPar = max(0, (item.parLevel ?? 0) - item.quantity)
            let reorderQty = item.reorderQuantity ?? fromPar
            let unitCost = item.costPerUnitCents
            let spend: Int? = unitCost.map { Int((Double($0 * reorderQty) * busynessScale).rounded()) }
            if let spend { predictedStockSpendCents += spend }
            stockOutlook.append(
                StockOutlookRow(
                    sku: item.sku,
                    name: item.name,
                    needRestock: true,
                    reorderQty: reorderQty,
                    unitCostCents: unitCost,
                    predictedSpendCents: spend,
                    busynessScale: busynessScale))
        }
        stockOutlook.sort { $0.sku.localizedCaseInsensitiveCompare($1.sku) == .orderedAscending }
        return (stockOutlook, predictedStockSpendCents, .threshold)
    }

    // MARK: - Validation

    /// Revenue is recognized when the ticket is handed off and paid (or prepaid).
    private static func isRecognizedRevenue(_ order: Order) -> Bool {
        order.status == .completed && order.paymentStatus == .paid
    }

    static func parseSummaryRange(req: Request) throws -> (from: Date, to: Date) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()

        func parse(_ raw: String?) -> Date? {
            guard let raw else { return nil }
            return formatter.date(from: raw) ?? fallback.date(from: raw)
        }

        guard let from = parse(req.query[String.self, at: "from"]),
              let to = parse(req.query[String.self, at: "to"])
        else {
            throw Abort(.badRequest, reason: "from and to ISO8601 query params are required")
        }
        try validateSummaryWindow(from: from, to: to)
        return (from, to)
    }

    static func parseDemandDays(req: Request) -> Int {
        let raw = req.query[Int.self, at: "days"] ?? 14
        return min(maxDemandDays, max(1, raw))
    }

    private static func validateSummaryWindow(from: Date, to: Date) throws {
        guard from <= to else {
            throw Abort(.badRequest, reason: "from must be less than or equal to to")
        }
        let seconds = to.timeIntervalSince(from)
        let maxSeconds = TimeInterval(maxSummaryDays) * 24 * 60 * 60
        guard seconds <= maxSeconds else {
            throw Abort(.badRequest, reason: "Date range must be at most \(maxSummaryDays) days")
        }
    }
}
