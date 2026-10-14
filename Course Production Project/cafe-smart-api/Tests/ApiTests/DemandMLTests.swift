import Testing
import Vapor
import Foundation
import BSON
@testable import cafe_smart_api

@Suite(.serialized)
actor DemandMLTests {
    private var app: Application!

    func setUp() async throws {
        app = try await APITestHelpers.makeApp(adminEmail: "demand-ml-test@example.com")
    }

    func tearDown() async throws {
        try await APITestHelpers.shutdownApp(app)
    }

    private func withApp(_ body: () async throws -> Void) async throws {
        try await setUp()
        do {
            try await body()
        } catch {
            try await tearDown()
            throw error
        }
        try await tearDown()
    }

    @Test
    func testStartTrainReservationDurationReturns400() async throws {
        try await withApp {
            let controller = CafePredictorController()
            let req = Request(application: app, on: app.eventLoopGroup.next())
            req.headers.contentType = .json
            try req.content.encode(CafePredictorController.TrainRequest(kind: "reservationDuration"))

            do {
                _ = try await controller.startTrain(req: req)
                Issue.record("Expected reservationDuration training to be rejected")
            } catch let abort as any AbortError {
                #expect(abort.status == .badRequest)
                #expect(abort.reason.contains("reservationDuration"))
            }
        }
    }

    @Test
    func testOrdersHourlyCSVHeaderContainsTargetOrders() async throws {
        try await withApp {
            let csv = try await OrdersHourlyCSV.forTraining(store: app.mongoStore)
            let header = csv.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            #expect(header.contains("target_orders"))
            for col in OrdersHourlyCSV.headerColumns {
                #expect(header.contains(col), "Missing column \(col)")
            }
            #expect(header.split(separator: ",").map(String.init) == OrdersHourlyCSV.headerColumns)
        }
    }

    @Test
    func testReservationsHourlyCSVHeaderContainsTargetCovers() async throws {
        try await withApp {
            let csv = try await ReservationsHourlyCSV.forTraining(store: app.mongoStore)
            let header = csv.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            #expect(header.contains("target_covers"))
            #expect(header.split(separator: ",").map(String.init) == ReservationsHourlyCSV.headerColumns)
        }
    }

    @Test
    func testAvailabilityRecommendsQuieterSlot() async throws {
        try await withApp {
            let calendar = Calendar.current
            guard let day = calendar.date(byAdding: .day, value: 3, to: calendar.startOfDay(for: Date()))
            else {
                Issue.record("Could not build future day")
                return
            }
            let dateRaw = ReservationAvailability.formatDay(day, calendar: calendar)

            // Seed same-weekday history: busy at 12:00, quiet at 09:00.
            let store = app.mongoStore as! TestableMongoStore
            for weeksAgo in 1...8 {
                guard let pastDay = calendar.date(byAdding: .day, value: -7 * weeksAgo, to: day),
                      let busyAt = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: pastDay)
                else { continue }
                _ = try await store.create(order: Order(
                    id: ObjectId().hexString,
                    status: .completed,
                    customerName: "Busy \(weeksAgo)",
                    items: [OrderItem(menuItemId: "espresso", quantity: 1)],
                    createdAt: busyAt
                ))
            }
            for weeksAgo in 1...2 {
                guard let pastDay = calendar.date(byAdding: .day, value: -7 * weeksAgo, to: day),
                      let quietAt = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: pastDay)
                else { continue }
                _ = try await store.create(order: Order(
                    id: ObjectId().hexString,
                    status: .completed,
                    customerName: "Quiet \(weeksAgo)",
                    items: [OrderItem(menuItemId: "tea", quantity: 1)],
                    createdAt: quietAt
                ))
            }

            let orders = try await store.listOrders()
            var config = BusinessConfig(
                id: "cfg",
                timezone: TimeZone.current.identifier,
                hours: (1...7).map { BusinessHours(weekday: $0, open: "08:00", close: "21:00") },
                seatingCapacity: 40,
                staffing: StaffingRules(
                    ordersPerBaristaPerHour: 40,
                    ordersPerBakerPerHour: 25,
                    guestsPerHostPerHour: 60)
            )
            config.reservationBooking = ReservationBookingSettings(
                enabled: true,
                tablesAvailable: 8,
                defaultPartyCapacity: 4,
                slotIntervalMinutes: 60,
                turnMinutes: 60,
                slotStarts: ["09:00", "12:00"]
            )

            let response = ReservationAvailability.slots(
                dateRaw: dateRaw,
                partySize: 2,
                config: config,
                tables: [],
                areas: [],
                reservations: [],
                orders: orders,
                now: Date.distantPast
            )

            #expect(response.slots.count == 2)
            let noon = response.slots.first {
                calendar.component(.hour, from: $0.startTime) == 12
            }
            let morning = response.slots.first {
                calendar.component(.hour, from: $0.startTime) == 9
            }
            #expect(noon != nil)
            #expect(morning != nil)
            #expect((morning?.busynessIndex ?? 1) < (noon?.busynessIndex ?? 0))
            // Quieter available slot is recommended (up to 3 picks).
            #expect(morning?.recommended == true)
            #expect(response.slots.contains { $0.recommended == true })
        }
    }

    @Test
    func testRollFeaturesUpdatesLags() {
        let rolled = CafePredictorController.rollFeatures(
            lag1: 2, lag7: 5, rolling: 3, prediction: 10)
        #expect(rolled.lag1 == 10)
        #expect(rolled.lag7 == 2)
        #expect(abs(rolled.rolling - ((3.0 * 6 + 10) / 7)) < 0.0001)
    }

    @Test
    func testExportOrdersHourlyDataset() async throws {
        try await withApp {
            let controller = CafePredictorController()
            let r = Request(application: app, on: app.eventLoopGroup.next())
            try r.query.encode(["dataset": "ordersHourly"])
            let resp = try await controller.exportCSV(req: r)
            #expect(resp.status == .ok)
            let body = String(data: APITestHelpers.responseData(resp), encoding: .utf8) ?? ""
            #expect(body.contains("target_orders"))
        }
    }

    @Test
    func testWorkloadPredictorDrivesBusynessScaleAndAvailability() async throws {
        try await withApp {
            let store = app.mongoStore as! TestableMongoStore
            let calendar = Calendar.current
            let now = Date()

            // Quiet historical baseline so scripted high predictions lift scale.
            for weekday in 1...7 {
                for hour in [9, 12] {
                    var comps = calendar.dateComponents([.year, .month, .day], from: now)
                    comps.weekday = weekday
                    comps.hour = hour
                    // Place on a past week matching weekday.
                    guard let pastDay = calendar.date(
                        byAdding: .day, value: -7 - (weekday % 3), to: now)
                    else { continue }
                    var pastComps = calendar.dateComponents(
                        [.year, .month, .day], from: pastDay)
                    pastComps.hour = hour
                    guard let at = calendar.date(from: pastComps) else { continue }
                    _ = try await store.create(order: Order(
                        id: ObjectId().hexString,
                        status: .completed,
                        customerName: "Base \(weekday)-\(hour)",
                        items: [OrderItem(menuItemId: "tea", quantity: 1)],
                        createdAt: at
                    ))
                }
            }

            await app.predictors.set(
                kind: .workloadHourly,
                runtime: .onnx,
                path: "test://workload",
                predictor: ScriptedHourPredictor(outputName: "target_orders", base: 20))
            await app.predictors.set(
                kind: .reservationsHourly,
                runtime: .onnx,
                path: "test://reservations",
                predictor: ScriptedHourPredictor(outputName: "target_covers", base: 8))

            let scale = try await DemandInference.busynessScale(
                app: app, leadTimeDays: 3, now: now)
            #expect(scale > 1.0)
            #expect(scale <= 1.75)

            let series = try await DemandInference.forecastOrders(
                app: app, hours: 6, now: now)
            #expect(series.source == .model)
            #expect(series.points.count == 6)
            let firstHour = calendar.component(.hour, from: series.points[0].hourStart)
            #expect(series.points[0].value == Double(20 + firstHour))

            var inv = InventoryItem(
                id: ObjectId().hexString,
                sku: "BUSY-SCALE-SKU",
                name: "Scale Beans",
                quantity: 10,
                reorderThreshold: 5,
                unit: "bag",
                supplier: nil)
            inv.leadTimeDays = 3
            _ = try await store.create(inventoryItem: inv)

            let controller = CafePredictorController()
            struct DecideBody: Content { let sku: String; let daysAhead: Int }
            let req = Request(application: app, on: app.eventLoopGroup.next())
            req.headers.contentType = .json
            try req.content.encode(DecideBody(sku: "BUSY-SCALE-SKU", daysAhead: 7))
            let decision = try await controller.decideRestock(req: req)
            #expect(decision.busynessScale == scale)
            // Scaled demand lifts ROP vs unscaled testing ramp (1+2+3=6 → ROP 11).
            #expect(decision.reorderPoint > 11)

            let (intensity, intensitySource) = try await DemandInference.combinedBusynessIndex(
                app: app, hours: 48, now: now)
            #expect(intensitySource == .model)
            #expect(!intensity.isEmpty)

            var config = BusinessConfig(
                id: "cfg",
                timezone: TimeZone.current.identifier,
                hours: (1...7).map { BusinessHours(weekday: $0, open: "08:00", close: "21:00") },
                seatingCapacity: 40,
                staffing: StaffingRules(
                    ordersPerBaristaPerHour: 40,
                    ordersPerBakerPerHour: 25,
                    guestsPerHostPerHour: 60)
            )
            config.reservationBooking = ReservationBookingSettings(
                enabled: true,
                tablesAvailable: 8,
                defaultPartyCapacity: 4,
                slotIntervalMinutes: 60,
                turnMinutes: 60,
                slotStarts: ["09:00", "12:00"]
            )
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.dateFormat = "yyyy-MM-dd"
            let dateRaw = formatter.string(from: now)

            // Force noon intensity higher than morning so recommendation prefers 09:00.
            let dayStart = calendar.startOfDay(for: now)
            var forced: [Date: Double] = [:]
            if let nine = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dayStart),
               let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: dayStart)
            {
                forced[nine] = 0.2
                forced[noon] = 1.0
            }

            let response = ReservationAvailability.slots(
                dateRaw: dateRaw,
                partySize: 2,
                config: config,
                tables: [],
                areas: [],
                reservations: [],
                orders: [],
                now: Date.distantPast,
                intensityByHourStart: forced)
            let noon = response.slots.first {
                calendar.component(.hour, from: $0.startTime) == 12
            }
            let morning = response.slots.first {
                calendar.component(.hour, from: $0.startTime) == 9
            }
            #expect((morning?.busynessIndex ?? 1) < (noon?.busynessIndex ?? 0))
            #expect(morning?.recommended == true)
        }
    }
}
