//
//  ReportsInsightsTests.swift
//  ApiTests
//
//  Finance summary + demand / stock outlook contracts.
//

@preconcurrency import BSON
import Foundation
import Testing
import Vapor
@testable import cafe_smart_api

@Suite(.serialized)
struct ReportsInsightsTests {

    private func makePaymentsApp(adminEmail: String) async throws -> Application {
        try await APITestHelpers.makeApp(adminEmail: adminEmail) { _ in
            APITestHelpers.enableFakePaymentsEnv()
        }
    }

    private func enableMerchantPrepaid(app: Application, adminToken: String) async throws {
        let staffing = StaffingRules(
            ordersPerBaristaPerHour: 40,
            ordersPerBakerPerHour: 30,
            guestsPerHostPerHour: 50)
        let cfg = BusinessConfig(
            id: "cfg-reports",
            timezone: "America/New_York",
            hours: [BusinessHours(weekday: 2, open: "07:00", close: "19:00")],
            seatingCapacity: 40,
            staffing: staffing,
            prepaidPaymentsEnabled: true)
        let res = try await APITestHelpers.request(
            app, .PUT, "/api/auth/config", token: adminToken, body: cfg)
        #expect(res.status == .ok)
    }

    private func isoQuery(_ date: Date) -> String {
        let raw = ISO8601DateFormatter().string(from: date)
        return raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? raw
    }

    private func summaryPath(from: Date, to: Date) -> String {
        "/api/auth/reports/summary?from=\(isoQuery(from))&to=\(isoQuery(to))"
    }

    // MARK: - Schema round-trips

    @Test func inventoryCostPerUnitCentsRoundTrip() async throws {
        let adminEmail = "reports-inv-admin@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail)
        do {
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)
            let createRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/inventory",
                token: adminToken,
                body: CreateInventoryItemRequest(
                    sku: "COST-SKU-\(ObjectId().hexString.prefix(6))",
                    name: "Costed Beans",
                    quantity: 10,
                    reorderThreshold: 2,
                    unit: "kg",
                    costPerUnitCents: 250))
            #expect(createRes.status == .ok || createRes.status == .created)
            let created = try APITestHelpers.decodeBody(InventoryItem.self, from: createRes)
            #expect(created.costPerUnitCents == 250)

            let getRes = try await APITestHelpers.request(
                app, .GET, "/api/auth/inventory/\(created.id)", token: adminToken)
            #expect(getRes.status == .ok)
            let fetched = try APITestHelpers.decodeBody(InventoryItem.self, from: getRes)
            #expect(fetched.costPerUnitCents == 250)
        }
        try await APITestHelpers.shutdownApp(app)
    }

    @Test func teamHourlyRateRoundTrip() async throws {
        let adminEmail = "reports-team-admin@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail)
        do {
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)
            let createRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/team",
                token: adminToken,
                body: CreateTeamMemberRequest(
                    name: "Rate Tester",
                    role: "Barista",
                    shift: "Morning",
                    hourlyRateCents: 1500))
            #expect(createRes.status == .ok || createRes.status == .created)
            var created = try APITestHelpers.decodeBody(TeamMember.self, from: createRes)
            #expect(created.hourlyRateCents == 1500)

            let listRes = try await APITestHelpers.request(
                app, .GET, "/api/auth/team", token: adminToken)
            #expect(listRes.status == .ok)
            let listed = try APITestHelpers.decodeBody(TeamMembersWrapper.self, from: listRes)
            #expect(listed.items.contains(where: {
                $0.id == created.id && $0.hourlyRateCents == 1500
            }))

            created.hourlyRateCents = 1850
            let updateRes = try await APITestHelpers.request(
                app, .PUT, "/api/auth/team/\(created.id)",
                token: adminToken,
                body: created)
            #expect(updateRes.status == .ok)
            let updated = try APITestHelpers.decodeBody(TeamMember.self, from: updateRes)
            #expect(updated.hourlyRateCents == 1850)
        }
        try await APITestHelpers.shutdownApp(app)
    }

    @Test func prepaidOrderPersistsTaxCents() async throws {
        let adminEmail = "reports-tax-admin@example.com"
        let app = try await makePaymentsApp(adminEmail: adminEmail)
        do {
            await app.fakeStripe?.setTaxPercent(10)
            let (_, userToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "reports-tax-guest@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)
            try await enableMerchantPrepaid(app: app, adminToken: adminToken)

            let menuRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/menu",
                token: adminToken,
                body: CreateMenuItemRequest(
                    name: "Tax Latte", priceCents: 1000, isAvailable: true))
            let menu = try APITestHelpers.decodeBody(MenuItem.self, from: menuRes)

            let prepRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/checkout/prepare",
                token: userToken,
                body: CreateCheckoutSessionRequest(
                    customerName: "Tax Guest",
                    items: [OrderItem(menuItemId: menu.id, quantity: 1)],
                    channel: .pickup))
            #expect(prepRes.status == .ok)
            let session = try APITestHelpers.decodeBody(CheckoutSessionResponse.self, from: prepRes)
            #expect(session.quote.taxCents == 100)
            let piId = try #require(session.paymentIntentId)
            await app.fakeStripe?.markSucceeded(piId)

            let confirmRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/checkout/confirm",
                token: userToken,
                body: ConfirmCheckoutRequest(sessionId: session.sessionId))
            #expect(confirmRes.status == .ok)
            let order = try APITestHelpers.decodeBody(Order.self, from: confirmRes)
            #expect(order.taxCents == 100)
        }
        try await APITestHelpers.shutdownApp(app)
    }

    // MARK: - Summary

    @Test func summaryRevenueAndCogsAndLabor() async throws {
        let adminEmail = "reports-summary-admin@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail)
        do {
            let (_, userToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "reports-summary-guest@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)

            let invRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/inventory",
                token: adminToken,
                body: CreateInventoryItemRequest(
                    sku: "RPT-MILK-\(ObjectId().hexString.prefix(6))",
                    name: "Report Milk",
                    quantity: 50,
                    reorderThreshold: 5,
                    unit: "L",
                    costPerUnitCents: 250))
            let inv = try APITestHelpers.decodeBody(InventoryItem.self, from: invRes)

            let menuRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/menu",
                token: adminToken,
                body: CreateMenuItemRequest(
                    name: "Report Latte", priceCents: 500, isAvailable: true))
            let menu = try APITestHelpers.decodeBody(MenuItem.self, from: menuRes)

            let recipeRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/recipes",
                token: adminToken,
                body: CreateRecipeRequest(
                    menuItemId: menu.id,
                    components: [.init(sku: inv.sku, unitsPerItem: 1.0)]))
            #expect(recipeRes.status == .ok || recipeRes.status == .created)

            let orderRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/orders",
                token: userToken,
                body: CreateOrderRequest(
                    customerName: "Guest",
                    items: [OrderItem(menuItemId: menu.id, quantity: 2)],
                    channel: .pickup))
            #expect(orderRes.status == .ok || orderRes.status == .created)
            var order = try APITestHelpers.decodeBody(Order.self, from: orderRes)
            #expect(order.subtotalCents == 1000)
            #expect(order.totalCents == 1000)
            #expect(order.paymentStatus == .unpaid)

            // Open unpaid ticket must not count toward net sales / COGS yet.
            let openFrom = order.createdAt.addingTimeInterval(-24 * 60 * 60)
            let openTo = order.createdAt.addingTimeInterval(24 * 60 * 60)
            let openSummaryRes = try await APITestHelpers.request(
                app, .GET, summaryPath(from: openFrom, to: openTo), token: adminToken)
            #expect(openSummaryRes.status == .ok)
            let openSummary = try APITestHelpers.decodeBody(ReportsSummary.self, from: openSummaryRes)
            #expect(openSummary.orderCount == 0)
            #expect(openSummary.netCents == 0)
            #expect(openSummary.cogsCents == 0)
            #expect(openSummary.unpaidCount == 1)

            for stage: OrderStatus in [.preparing, .ready, .completed] {
                let statusRes = try await APITestHelpers.request(
                    app, .PUT, "/api/auth/orders/\(order.id)/status",
                    token: adminToken,
                    body: UpdateOrderStatusRequest(status: stage))
                #expect(statusRes.status == .ok)
                order = try APITestHelpers.decodeBody(Order.self, from: statusRes)
            }
            #expect(order.status == .completed)
            #expect(order.paymentStatus == .paid)

            let teamRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/team",
                token: adminToken,
                body: CreateTeamMemberRequest(
                    name: "Labor Lead",
                    role: "Barista",
                    shift: "Morning",
                    hourlyRateCents: 1500))
            let member = try APITestHelpers.decodeBody(TeamMember.self, from: teamRes)

            let clockIn = order.createdAt.addingTimeInterval(-30 * 60)
            let clockOut = clockIn.addingTimeInterval(60 * 60)
            let entryRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/team/time-entries",
                token: adminToken,
                body: CreateTimeEntryRequest(
                    teamMemberId: member.id,
                    clockIn: clockIn,
                    clockOut: clockOut,
                    note: "shift"))
            #expect(entryRes.status == .ok || entryRes.status == .created)
            let entry = try APITestHelpers.decodeBody(TimeEntry.self, from: entryRes)

            let approveRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/team/time-entries/\(entry.id)/approve",
                token: adminToken)
            #expect(approveRes.status == .ok)

            let from = order.createdAt.addingTimeInterval(-24 * 60 * 60)
            let to = order.createdAt.addingTimeInterval(24 * 60 * 60)
            let summaryRes = try await APITestHelpers.request(
                app, .GET, summaryPath(from: from, to: to), token: adminToken)
            #expect(summaryRes.status == .ok)
            let summary = try APITestHelpers.decodeBody(ReportsSummary.self, from: summaryRes)

            #expect(summary.orderCount == 1)
            #expect(summary.grossCents == 1000)
            #expect(summary.netCents == 1000)  // completed+paid − loyalty
            #expect(summary.collectedCents == 1000)
            #expect(summary.cogsCents == 500)  // 2 units × 250
            #expect(summary.laborCents == 1500)  // 60 min × 1500 / 60
            #expect(summary.contributionCents == 1000 - 500 - 1500)
            #expect(summary.paidCount == 1)
            #expect(summary.unpaidCount == 0)
            #expect(summary.laborByMember.count == 1)
            #expect(summary.laborByMember[0].approvedMinutes == 60)
            #expect(summary.byDay.count == 1)
            #expect(summary.salesByItem.contains { $0.menuItemId == menu.id && $0.quantity == 2 })
            #expect(summary.cogsBySku.contains { $0.sku == inv.sku && $0.cogsCents == 500 })
        }
        try await APITestHelpers.shutdownApp(app)
    }

    @Test func summaryUsesFractionalCogsNotCeilPack() async throws {
        let adminEmail = "reports-frac-cogs-admin@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail)
        do {
            let (_, userToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "reports-frac-cogs-guest@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)

            // $25.00 / kg; espresso uses 18 g = 0.018 kg → $0.45 COGS (not $25 ceil).
            let invRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/inventory",
                token: adminToken,
                body: CreateInventoryItemRequest(
                    sku: "RPT-BEANS-\(ObjectId().hexString.prefix(6))",
                    name: "Espresso Beans",
                    quantity: 10,
                    reorderThreshold: 1,
                    unit: "kg",
                    costPerUnitCents: 2500))
            let inv = try APITestHelpers.decodeBody(InventoryItem.self, from: invRes)

            let menuRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/menu",
                token: adminToken,
                body: CreateMenuItemRequest(
                    name: "Frac Espresso", priceCents: 300, isAvailable: true))
            let menu = try APITestHelpers.decodeBody(MenuItem.self, from: menuRes)

            let recipeRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/recipes",
                token: adminToken,
                body: CreateRecipeRequest(
                    menuItemId: menu.id,
                    components: [.init(sku: inv.sku, unitsPerItem: 0.018)]))
            #expect(recipeRes.status == .ok || recipeRes.status == .created)

            let orderRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/orders",
                token: userToken,
                body: CreateOrderRequest(
                    customerName: "Guest",
                    items: [OrderItem(menuItemId: menu.id, quantity: 1)],
                    channel: .pickup))
            #expect(orderRes.status == .ok || orderRes.status == .created)
            var order = try APITestHelpers.decodeBody(Order.self, from: orderRes)

            // Stock deduct still ceils 0.018 → 1 kg.
            let stockRes = try await APITestHelpers.request(
                app, .GET, "/api/auth/inventory/\(inv.id)", token: adminToken)
            let stock = try APITestHelpers.decodeBody(InventoryItem.self, from: stockRes)
            #expect(stock.quantity == 9)

            for stage: OrderStatus in [.preparing, .ready, .completed] {
                let statusRes = try await APITestHelpers.request(
                    app, .PUT, "/api/auth/orders/\(order.id)/status",
                    token: adminToken,
                    body: UpdateOrderStatusRequest(status: stage))
                #expect(statusRes.status == .ok)
                order = try APITestHelpers.decodeBody(Order.self, from: statusRes)
            }

            let from = order.createdAt.addingTimeInterval(-3600)
            let to = order.createdAt.addingTimeInterval(3600)
            let summaryRes = try await APITestHelpers.request(
                app, .GET, summaryPath(from: from, to: to), token: adminToken)
            #expect(summaryRes.status == .ok)
            let summary = try APITestHelpers.decodeBody(ReportsSummary.self, from: summaryRes)
            #expect(summary.cogsCents == 45)
            #expect(summary.cogsCents < 2500)
            #expect(summary.cogsBySku.contains { $0.sku == inv.sku && $0.cogsCents == 45 })
        }
        try await APITestHelpers.shutdownApp(app)
    }

    @Test func summaryRejectsGuest403() async throws {
        let adminEmail = "reports-guest-admin@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail)
        do {
            let (_, userToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "reports-guest@example.com")
            _ = try await APITestHelpers.registerAndLogin(app: app, email: adminEmail)

            let from = Date().addingTimeInterval(-86400)
            let to = Date().addingTimeInterval(86400)
            let res = try await APITestHelpers.request(
                app, .GET, summaryPath(from: from, to: to), token: userToken)
            #expect(
                res.status == .forbidden
                    || res.status == .unauthorized
                    || res.status.code == 995)
        }
        try await APITestHelpers.shutdownApp(app)
    }

    @Test func summaryRejectsBadDateRange400() async throws {
        let adminEmail = "reports-range-admin@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail)
        do {
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)
            let from = Date()
            let to = from.addingTimeInterval(-3600)
            let res = try await APITestHelpers.request(
                app, .GET, summaryPath(from: from, to: to), token: adminToken)
            #expect(res.status == .badRequest)
        }
        try await APITestHelpers.shutdownApp(app)
    }

    // MARK: - CSV export

    @Test func exportOrdersAndSummaryCSV() async throws {
        let adminEmail = "reports-csv-admin@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail)
        do {
            let (_, userToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "reports-csv-guest@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)

            let menuRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/menu",
                token: adminToken,
                body: CreateMenuItemRequest(
                    name: "CSV Latte", priceCents: 750, isAvailable: true))
            let menu = try APITestHelpers.decodeBody(MenuItem.self, from: menuRes)

            let orderRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/orders",
                token: userToken,
                body: CreateOrderRequest(
                    customerName: "CSV Guest",
                    items: [OrderItem(menuItemId: menu.id, quantity: 1)],
                    channel: .pickup))
            #expect(orderRes.status == .ok || orderRes.status == .created)
            var order = try APITestHelpers.decodeBody(Order.self, from: orderRes)

            for stage: OrderStatus in [.preparing, .ready, .completed] {
                let statusRes = try await APITestHelpers.request(
                    app, .PUT, "/api/auth/orders/\(order.id)/status",
                    token: adminToken,
                    body: UpdateOrderStatusRequest(status: stage))
                #expect(statusRes.status == .ok)
                order = try APITestHelpers.decodeBody(Order.self, from: statusRes)
            }
            #expect(order.paymentStatus == .paid)

            let from = order.createdAt.addingTimeInterval(-24 * 60 * 60)
            let to = order.createdAt.addingTimeInterval(24 * 60 * 60)
            let base =
                "/api/auth/reports/export?from=\(isoQuery(from))&to=\(isoQuery(to))"

            let ordersRes = try await APITestHelpers.request(
                app, .GET, "\(base)&dataset=orders", token: adminToken)
            #expect(ordersRes.status == .ok)
            let ordersPayload = try APITestHelpers.decodeBody(CSVExportPayload.self, from: ordersRes)
            #expect(ordersPayload.csv.contains("id,createdAt,customerName"))
            #expect(ordersPayload.csv.contains(order.id))
            #expect(ordersPayload.csv.contains("7.50"))

            let summaryRes = try await APITestHelpers.request(
                app, .GET, "\(base)&dataset=summary", token: adminToken)
            #expect(summaryRes.status == .ok)
            let summaryPayload = try APITestHelpers.decodeBody(
                CSVExportPayload.self, from: summaryRes)
            #expect(summaryPayload.csv.contains("orderCount,gross,netSales"))
            #expect(summaryPayload.csv.contains("7.50"))

            let badRes = try await APITestHelpers.request(
                app, .GET, "\(base)&dataset=notAThing", token: adminToken)
            #expect(badRes.status == .badRequest)
        }
        try await APITestHelpers.shutdownApp(app)
    }

    // MARK: - Demand

    @Test func demandReturnsHeatmapAndStock() async throws {
        let adminEmail = "reports-demand-admin@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail)
        do {
            let (_, userToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "reports-demand-guest@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)

            let invRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/inventory",
                token: adminToken,
                body: CreateInventoryItemRequest(
                    sku: "LOW-SKU-\(ObjectId().hexString.prefix(6))",
                    name: "Low Stock Syrup",
                    quantity: 1,
                    reorderThreshold: 5,
                    unit: "bottle",
                    parLevel: 10,
                    reorderQuantity: 8,
                    costPerUnitCents: 400))
            let inv = try APITestHelpers.decodeBody(InventoryItem.self, from: invRes)

            let menuRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/menu",
                token: adminToken,
                body: CreateMenuItemRequest(
                    name: "Demand Latte", priceCents: 400, isAvailable: true))
            let menu = try APITestHelpers.decodeBody(MenuItem.self, from: menuRes)

            _ = try await APITestHelpers.request(
                app, .POST, "/api/auth/orders",
                token: userToken,
                body: CreateOrderRequest(
                    customerName: "Guest",
                    items: [OrderItem(menuItemId: menu.id, quantity: 1)],
                    channel: .pickup))

            let res = try await APITestHelpers.request(
                app, .GET, "/api/auth/reports/demand?days=7", token: adminToken)
            #expect(res.status == .ok)
            let insights = try APITestHelpers.decodeBody(DemandInsights.self, from: res)
            #expect(insights.days == 7)
            #expect(insights.source == .historical)
            #expect(insights.heatmap.count == 7 * 24)
            #expect(!insights.staffingByDay.isEmpty)
            #expect(insights.staffingByDay.allSatisfy { !$0.hours.isEmpty })
            #expect(insights.staffingByDay.contains { $0.totalPersonHours > 0 })
            // In testing, stock outlook uses the same ROP path as restock/decide
            // (synthetic forecast series), not threshold-only qty.
            #expect(insights.stockSource == .model)
            let stockRow = insights.stockOutlook.first { $0.sku == inv.sku }
            #expect(stockRow != nil)
            #expect(stockRow?.needRestock == true)
            #expect((stockRow?.reorderQty ?? 0) >= 8)
            #expect((stockRow?.predictedSpendCents ?? 0) >= 3200)
            #expect(insights.predictedStockSpendCents >= 3200)
        }
        try await APITestHelpers.shutdownApp(app)
    }

    @Test func demandUsesWorkloadModelInference() async throws {
        let adminEmail = "reports-demand-model@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail)
        do {
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)

            await app.predictors.set(
                kind: .workloadHourly,
                runtime: .onnx,
                path: "test://workload-reports",
                predictor: ScriptedHourPredictor(outputName: "target_orders", base: 5))

            let res = try await APITestHelpers.request(
                app, .GET, "/api/auth/reports/demand?days=2", token: adminToken)
            #expect(res.status == .ok)
            let insights = try APITestHelpers.decodeBody(DemandInsights.self, from: res)
            #expect(insights.source == .model)
            #expect(insights.heatmap.count == 7 * 24)
            #expect(!insights.peaks.isEmpty)
            #expect(insights.staffingByDay.count >= 1)
            #expect(insights.staffingByDay.contains { $0.maxHeadcount >= 1 && !$0.hours.isEmpty })
            // Scripted predictor returns base+hour (>0 for every hour in horizon).
            #expect(insights.peaks.contains { $0.predictedOrders >= 5 })
            #expect(insights.stockOutlook.allSatisfy { $0.busynessScale > 0 })
        }
        try await APITestHelpers.shutdownApp(app)
    }
}
