//
//  TrainScheduleService.swift
//  CafeSmartAPI
//
//  Monthly auto-training for restock / workload / reservations predictors.
//

@preconcurrency import BSON
import Foundation
import MongoKitten
import NIOCore
import Vapor

struct AutoTrainStatus: Content, Sendable, Equatable {
    var enabled: Bool
    var dayOfMonth: Int
    var hourUTC: Int
    var lastRunAt: Date?
    var lastRunYearMonth: String?
}

struct AutoTrainScheduleDoc: Codable, Sendable {
    var id: String
    var lastRunAt: Date?
    var lastRunYearMonth: String?
}

enum TrainScheduleService {
    private static let collectionName = "ml_schedule"
    private static let docId = "auto-train"
    private static let kinds: [PredictorKind] = [
        .restockDaily, .workloadHourly, .reservationsHourly,
    ]

    private struct MemoryKey: StorageKey {
        typealias Value = AutoTrainScheduleDoc
    }

    private struct TaskKey: StorageKey {
        typealias Value = RepeatedTask
    }

    static func isEnabled() -> Bool {
        let raw = (Environment.get("AUTO_TRAIN_ENABLED") ?? "").lowercased()
        return raw == "1" || raw == "true" || raw == "yes"
    }

    static func dayOfMonth() -> Int {
        max(1, min(28, Int(Environment.get("AUTO_TRAIN_DAY") ?? "1") ?? 1))
    }

    static func hourUTC() -> Int {
        max(0, min(23, Int(Environment.get("AUTO_TRAIN_HOUR_UTC") ?? "10") ?? 10))
    }

    static func status(app: Application) async -> AutoTrainStatus {
        let doc = await load(app: app)
        return AutoTrainStatus(
            enabled: isEnabled(),
            dayOfMonth: dayOfMonth(),
            hourUTC: hourUTC(),
            lastRunAt: doc.lastRunAt,
            lastRunYearMonth: doc.lastRunYearMonth)
    }

    /// Start periodic checks (every 30 minutes). No-op when disabled or testing.
    static func start(app: Application) {
        guard app.environment != .testing else { return }
        guard isEnabled() else {
            app.logger.info("AUTO_TRAIN_ENABLED is off; monthly train scheduler idle")
            return
        }
        if app.storage[TaskKey.self] != nil { return }

        let interval: TimeAmount = .minutes(30)
        let task = app.eventLoopGroup.next().scheduleRepeatedTask(
            initialDelay: .seconds(20), delay: interval
        ) { _ in
            // Hop onto app event loop / async context
            Task {
                await tick(app: app, now: Date())
            }
        }
        app.storage[TaskKey.self] = task
        app.logger.info(
            "Monthly auto-train scheduler started (day=\(dayOfMonth()) hourUTC=\(hourUTC()))")
    }

    /// Testable tick — returns true when a run was started this call.
    @discardableResult
    static func tick(app: Application, now: Date = Date()) async -> Bool {
        guard isEnabled() else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.component(.day, from: now)
        let hour = calendar.component(.hour, from: now)
        guard day == dayOfMonth(), hour >= hourUTC() else { return false }

        let ym = yearMonth(now, calendar: calendar)
        var doc = await load(app: app)
        if doc.lastRunYearMonth == ym { return false }

        app.logger.info("Auto-train starting for \(ym)")
        await enqueueAll(app: app)

        doc.lastRunAt = now
        doc.lastRunYearMonth = ym
        await save(app: app, doc: doc)
        return true
    }

    /// Force-mark / clear for tests.
    static func resetForTests(app: Application) {
        app.storage[MemoryKey.self] = AutoTrainScheduleDoc(id: docId, lastRunAt: nil, lastRunYearMonth: nil)
    }

    private static func yearMonth(_ date: Date, calendar: Calendar) -> String {
        let y = calendar.component(.year, from: date)
        let m = calendar.component(.month, from: date)
        return String(format: "%04d-%02d", y, m)
    }

    private static func enqueueAll(app: Application) async {
        let runner = app.processRunner
        let workingDirectory = TrainJobService.normalizedDirectory(app.directory.workingDirectory)
        for kind in kinds {
            let scriptPath = TrainJobService.scriptPath(for: kind, workingDirectory: workingDirectory)
            let csvBuilder: @Sendable () async throws -> String
            switch kind {
            case .restockDaily:
                csvBuilder = { try await IngredientDailyCSV.forTraining(store: app.mongoStore) }
            case .workloadHourly:
                csvBuilder = { try await OrdersHourlyCSV.forTraining(store: app.mongoStore) }
            case .reservationsHourly:
                csvBuilder = { try await ReservationsHourlyCSV.forTraining(store: app.mongoStore) }
            case .reservationDuration:
                continue
            }
            do {
                _ = try await app.trainJobs.start(
                    app: app,
                    kind: kind,
                    runner: runner,
                    csvBuilder: csvBuilder,
                    scriptPath: scriptPath)
                app.logger.info("Auto-train queued \(kind.rawValue)")
            } catch {
                app.logger.warning(
                    "Auto-train skip \(kind.rawValue): \(error)")
            }
        }
    }

    private static func load(app: Application) async -> AutoTrainScheduleDoc {
        if app.environment == .testing {
            return app.storage[MemoryKey.self]
                ?? AutoTrainScheduleDoc(id: docId, lastRunAt: nil, lastRunYearMonth: nil)
        }
        do {
            if let doc = try await app.mongoDB[collectionName].findOne("id" == docId) {
                return try BSONDecoder().decode(AutoTrainScheduleDoc.self, from: doc)
            }
        } catch {
            app.logger.warning("Auto-train schedule load failed: \(error)")
        }
        return AutoTrainScheduleDoc(id: docId, lastRunAt: nil, lastRunYearMonth: nil)
    }

    private static func save(app: Application, doc: AutoTrainScheduleDoc) async {
        if app.environment == .testing {
            app.storage[MemoryKey.self] = doc
            return
        }
        do {
            let encoded = try BSONEncoder().encode(doc)
            let coll = app.mongoDB[collectionName]
            if try await coll.findOne("id" == docId) != nil {
                _ = try await coll.updateOne(where: "id" == docId, to: encoded)
            } else {
                try await coll.insert(encoded)
            }
        } catch {
            app.logger.warning("Auto-train schedule save failed: \(error)")
        }
    }
}
