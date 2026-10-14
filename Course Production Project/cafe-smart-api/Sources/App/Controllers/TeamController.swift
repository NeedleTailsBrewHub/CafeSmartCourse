//
//  TeamController.swift
//  CafeSmartAPI
//
//  On-shift staff roster + time tracking for the merchant desk.
//

@preconcurrency import BSON
import Foundation
import MongoKitten
import Vapor

struct TeamMember: Content, Sendable, Equatable, BinaryResponseEncodable {
    var id: String
    var name: String
    var role: String
    var shift: String
    /// Hourly wage in cents for labor reports (optional).
    var hourlyRateCents: Int? = nil

    func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}

struct TeamMembersWrapper: Content, Sendable, Equatable, BinaryResponseEncodable {
    var items: [TeamMember]
    func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}

struct CreateTeamMemberRequest: Content {
    var name: String
    var role: String
    var shift: String
    var hourlyRateCents: Int? = nil
}

enum TimeEntrySource: String, Content, Sendable, Equatable {
    case clock
    case manual
}

enum TimeEntryStatus: String, Content, Sendable, Equatable {
    case pending
    case approved
}

struct TimeEntry: Content, Sendable, Equatable, BinaryResponseEncodable {
    var id: String
    var teamMemberId: String
    var teamMemberName: String
    var clockIn: Date
    var clockOut: Date?
    var note: String?
    var source: TimeEntrySource
    var createdAt: Date
    var updatedAt: Date
    /// Closed punches default to pending until a manager approves.
    var status: TimeEntryStatus? = nil

    func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }

    var resolvedStatus: TimeEntryStatus {
        if clockOut == nil { return .pending }
        return status ?? .pending
    }
}

struct TimeEntriesWrapper: Content, Sendable, Equatable, BinaryResponseEncodable {
    var items: [TimeEntry]
    func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}

struct TimeMemberSummary: Content, Sendable, Equatable {
    var teamMemberId: String
    var teamMemberName: String
    var totalMinutes: Int
    var approvedMinutes: Int
    var pendingMinutes: Int
    var openMinutes: Int
    var entryCount: Int
}

struct TimePeriodSummary: Content, Sendable, Equatable, BinaryResponseEncodable {
    var period: String
    var from: Date
    var to: Date
    var totalMinutes: Int
    var approvedMinutes: Int
    var pendingMinutes: Int
    var members: [TimeMemberSummary]
    var entries: [TimeEntry]

    func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}

struct CreateTimeEntryRequest: Content {
    var teamMemberId: String
    var clockIn: Date
    var clockOut: Date
    var note: String?
}

struct UpdateTimeEntryRequest: Content {
    var clockIn: Date
    var clockOut: Date?
    var note: String?
    var status: TimeEntryStatus?
}

actor TeamController {
    private let collection = "team_members"
    private let timeCollection = "time_entries"

    private struct TeamMemoryKey: StorageKey {
        typealias Value = [TeamMember]
    }

    private struct TimeMemoryKey: StorageKey {
        typealias Value = [TimeEntry]
    }

    private func actorVenueRole(_ req: Request) -> VenueRole {
        (try? RoleGate.venueRole(req: req)) ?? .guest
    }

    private func linkedTeamMemberId(_ req: Request) -> String? {
        req.storage.get(UserKey.self)?.teamMemberId
    }

    /// Staff may only touch their linked roster id.
    private func requireSelfClockTarget(req: Request, memberId: String) throws {
        let role = actorVenueRole(req)
        guard role == .staff else { return }
        guard let linked = linkedTeamMemberId(req), linked == memberId else {
            throw Abort(.forbidden, reason: "Staff can only clock their linked roster profile")
        }
    }

    private func redactRate(_ member: TeamMember) -> TeamMember {
        var copy = member
        copy.hourlyRateCents = nil
        return copy
    }

    private func loadMemory(_ app: Application) -> [TeamMember] {
        if let existing = app.storage[TeamMemoryKey.self] { return existing }
        let seeded = Self.shouldSeedDemoRoster() ? Self.seedMembers() : []
        app.storage[TeamMemoryKey.self] = seeded
        return seeded
    }

    /// Demo roster only when `DemoModePolicy` is enabled (DEBUG + SEED_TEST_DATA).
    private static func shouldSeedDemoRoster() -> Bool {
        DemoModePolicy.isEnabled
    }

    /// Test seam for seed gating.
    static func shouldSeedDemoRosterForTests() -> Bool {
        DemoModePolicy.isEnabled
    }

    private func saveMemory(_ app: Application, _ members: [TeamMember]) {
        app.storage[TeamMemoryKey.self] = members
    }

    private func loadTimeMemory(_ app: Application) -> [TimeEntry] {
        app.storage[TimeMemoryKey.self] ?? []
    }

    private func saveTimeMemory(_ app: Application, _ entries: [TimeEntry]) {
        app.storage[TimeMemoryKey.self] = entries
    }

    private static func seedMembers() -> [TeamMember] {
        [
            .init(
                id: ObjectId().hexString, name: "Alex Rivera", role: "Barista", shift: "Morning",
                hourlyRateCents: 1850),
            .init(
                id: ObjectId().hexString, name: "Sam Chen", role: "Shift lead", shift: "Mid",
                hourlyRateCents: 2200),
            .init(
                id: ObjectId().hexString, name: "Jordan Lee", role: "Baker", shift: "Morning",
                hourlyRateCents: 2000),
            .init(
                id: ObjectId().hexString, name: "Riley Park", role: "Barista", shift: "Evening",
                hourlyRateCents: 1800),
            .init(
                id: ObjectId().hexString, name: "Casey Nguyen", role: "Host", shift: "Mid",
                hourlyRateCents: 1750),
        ]
    }

    // MARK: Roster

    func list(req: Request) async throws -> TeamMembersWrapper {
        let role = actorVenueRole(req)
        var items: [TeamMember]
        if req.application.environment == .testing {
            items = loadMemory(req.application)
        } else {
            let coll = req.mongoDB[collection]
            items = []
            for try await doc in coll.find() {
                items.append(try BSONDecoder().decode(TeamMember.self, from: doc))
            }
            if items.isEmpty, Self.shouldSeedDemoRoster() {
                let seeded = Self.seedMembers()
                for member in seeded {
                    try await coll.insert(BSONEncoder().encode(member))
                }
                items = seeded
            }
        }
        if role == .staff {
            if let linked = linkedTeamMemberId(req) {
                items = items.filter { $0.id == linked }.map(redactRate)
            } else {
                items = []
            }
        }
        items.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return TeamMembersWrapper(items: items)
    }

    func create(req: Request) async throws -> TeamMember {
        let body = try req.content.decode(CreateTeamMemberRequest.self)
        let name = body.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let role = body.role.trimmingCharacters(in: .whitespacesAndNewlines)
        let shift = body.shift.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !role.isEmpty, !shift.isEmpty else {
            throw Abort(.badRequest, reason: "Name, role, and shift are required")
        }
        let member = TeamMember(
            id: ObjectId().hexString,
            name: name,
            role: role,
            shift: shift,
            hourlyRateCents: body.hourlyRateCents.map { max(0, $0) }
        )
        if req.application.environment == .testing {
            var members = loadMemory(req.application)
            members.append(member)
            saveMemory(req.application, members)
            return member
        }
        try await req.mongoDB[collection].insert(BSONEncoder().encode(member))
        return member
    }

    func update(req: Request) async throws -> TeamMember {
        guard let id = req.parameters.get("id"), !id.isEmpty else { throw Abort(.badRequest) }
        let body = try req.content.decode(TeamMember.self)
        let updated = TeamMember(
            id: id,
            name: body.name.trimmingCharacters(in: .whitespacesAndNewlines),
            role: body.role.trimmingCharacters(in: .whitespacesAndNewlines),
            shift: body.shift.trimmingCharacters(in: .whitespacesAndNewlines),
            hourlyRateCents: body.hourlyRateCents.map { max(0, $0) }
        )
        guard !updated.name.isEmpty, !updated.role.isEmpty, !updated.shift.isEmpty else {
            throw Abort(.badRequest, reason: "Name, role, and shift are required")
        }
        if req.application.environment == .testing {
            var members = loadMemory(req.application)
            guard let idx = members.firstIndex(where: { $0.id == id }) else { throw Abort(.notFound) }
            members[idx] = updated
            saveMemory(req.application, members)
            return updated
        }
        let coll = req.mongoDB[collection]
        let result = try await coll.updateOne(where: "id" == id, to: BSONEncoder().encode(updated))
        guard result.updatedCount > 0 else { throw Abort(.notFound) }
        return updated
    }

    func delete(req: Request) async throws -> HTTPStatus {
        guard let id = req.parameters.get("id"), !id.isEmpty else { throw Abort(.badRequest) }
        if req.application.environment == .testing {
            var members = loadMemory(req.application)
            let before = members.count
            members.removeAll { $0.id == id }
            guard members.count < before else { throw Abort(.notFound) }
            saveMemory(req.application, members)
            var entries = loadTimeMemory(req.application)
            entries.removeAll { $0.teamMemberId == id }
            saveTimeMemory(req.application, entries)
            return .noContent
        }
        let deleted = try await req.mongoDB[collection].deleteOne(where: "id" == id)
        guard deleted.deletes > 0 else { throw Abort(.notFound) }
        _ = try await req.mongoDB[timeCollection].deleteAll(where: "teamMemberId" == id)
        return .noContent
    }

    // MARK: Time entries

    func listTimeEntries(req: Request) async throws -> TimeEntriesWrapper {
        let role = actorVenueRole(req)
        var memberId = req.query[String.self, at: "teamMemberId"]
        if role == .staff {
            guard let linked = linkedTeamMemberId(req) else {
                return TimeEntriesWrapper(items: [])
            }
            memberId = linked
        }
        let limit = min(500, max(1, req.query[Int.self, at: "limit"] ?? 100))
        let (fromDate, toDate) = Self.parseRange(req)
        var filtered = try await loadEntries(req: req).filter { entry in
            if let memberId, entry.teamMemberId != memberId { return false }
            if let fromDate, entry.clockIn < fromDate { return false }
            if let toDate, entry.clockIn > toDate { return false }
            return true
        }
        filtered.sort { $0.clockIn > $1.clockIn }
        return TimeEntriesWrapper(items: Array(filtered.prefix(limit)))
    }

    /// Aggregated hours for week / month / year (manager timesheet).
    func timeSummary(req: Request) async throws -> TimePeriodSummary {
        let period = (req.query[String.self, at: "period"] ?? "week").lowercased()
        let calendar = Calendar.current
        let anchor: Date = {
            if let raw = req.query[String.self, at: "anchor"],
               let d = ISO8601DateFormatter().date(from: raw) { return d }
            return Date()
        }()
        let range = try Self.periodRange(period: period, anchor: anchor, calendar: calendar)
        let role = actorVenueRole(req)
        var memberId = req.query[String.self, at: "teamMemberId"]
        if role == .staff {
            guard let linked = linkedTeamMemberId(req) else {
                return TimePeriodSummary(
                    period: period, from: range.from, to: range.to,
                    totalMinutes: 0, approvedMinutes: 0, pendingMinutes: 0,
                    members: [], entries: [])
            }
            memberId = linked
        }
        let now = Date()
        let allEntries = try await loadEntries(req: req)
        let inRange = allEntries.filter { entry in
            if let memberId, entry.teamMemberId != memberId { return false }
            // Closed punches overlapping the window, or open punches started in-range.
            if entry.clockIn > range.to { return false }
            let end = entry.clockOut ?? now
            return end >= range.from && entry.clockIn <= range.to
        }
        // Always surface currently-open punches so roster clock state cannot drift
        // when the manager is viewing another week / filtered member list.
        let openPunches = allEntries.filter { entry in
            guard entry.clockOut == nil else { return false }
            if let memberId { return entry.teamMemberId == memberId }
            return true
        }
        var byId = Dictionary(uniqueKeysWithValues: inRange.map { ($0.id, $0) })
        for open in openPunches {
            byId[open.id] = open
        }
        let entries = byId.values.sorted { $0.clockIn > $1.clockIn }

        var byMember: [String: (name: String, total: Int, approved: Int, pending: Int, open: Int, count: Int)] = [:]
        for entry in entries {
            let minutes = Self.minutes(for: entry, now: now, clampFrom: range.from, clampTo: range.to)
            var row = byMember[entry.teamMemberId]
                ?? (entry.teamMemberName, 0, 0, 0, 0, 0)
            row.name = entry.teamMemberName
            row.total += minutes
            row.count += 1
            if entry.clockOut == nil {
                row.open += minutes
            } else if entry.resolvedStatus == .approved {
                row.approved += minutes
            } else {
                row.pending += minutes
            }
            byMember[entry.teamMemberId] = row
        }

        let members = byMember.map { id, row in
            TimeMemberSummary(
                teamMemberId: id,
                teamMemberName: row.name,
                totalMinutes: row.total,
                approvedMinutes: row.approved,
                pendingMinutes: row.pending,
                openMinutes: row.open,
                entryCount: row.count)
        }
        .sorted { $0.teamMemberName.localizedCaseInsensitiveCompare($1.teamMemberName) == .orderedAscending }

        return TimePeriodSummary(
            period: period,
            from: range.from,
            to: range.to,
            totalMinutes: members.reduce(0) { $0 + $1.totalMinutes },
            approvedMinutes: members.reduce(0) { $0 + $1.approvedMinutes },
            pendingMinutes: members.reduce(0) { $0 + $1.pendingMinutes },
            members: members,
            entries: Array(entries.prefix(500)))
    }

    func createTimeEntry(req: Request) async throws -> TimeEntry {
        let body = try req.content.decode(CreateTimeEntryRequest.self)
        let member = try await requireMember(req: req, id: body.teamMemberId)
        guard body.clockOut > body.clockIn else {
            throw Abort(.badRequest, reason: "clockOut must be after clockIn")
        }
        let now = Date()
        let note = body.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = TimeEntry(
            id: ObjectId().hexString,
            teamMemberId: member.id,
            teamMemberName: member.name,
            clockIn: body.clockIn,
            clockOut: body.clockOut,
            note: (note?.isEmpty == false) ? note : nil,
            source: .manual,
            createdAt: now,
            updatedAt: now,
            status: .pending
        )
        try await persist(entry: entry, req: req)
        return entry
    }

    func updateTimeEntry(req: Request) async throws -> TimeEntry {
        guard let entryId = req.parameters.get("entryId"), !entryId.isEmpty else {
            throw Abort(.badRequest)
        }
        let body = try req.content.decode(UpdateTimeEntryRequest.self)
        if let out = body.clockOut, out <= body.clockIn {
            throw Abort(.badRequest, reason: "clockOut must be after clockIn")
        }
        var entry = try await requireEntry(req: req, id: entryId)
        entry.clockIn = body.clockIn
        entry.clockOut = body.clockOut
        let note = body.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.note = (note?.isEmpty == false) ? note : nil
        if let status = body.status {
            guard entry.clockOut != nil else {
                throw Abort(.badRequest, reason: "Cannot approve an open punch")
            }
            entry.status = status
        } else if entry.clockOut != nil, entry.status == nil {
            entry.status = .pending
        }
        entry.updatedAt = Date()
        try await replace(entry: entry, req: req)
        return entry
    }

    func approveTimeEntry(req: Request) async throws -> TimeEntry {
        guard let entryId = req.parameters.get("entryId"), !entryId.isEmpty else {
            throw Abort(.badRequest)
        }
        var entry = try await requireEntry(req: req, id: entryId)
        guard entry.clockOut != nil else {
            throw Abort(.badRequest, reason: "Cannot approve an open punch")
        }
        entry.status = .approved
        entry.updatedAt = Date()
        try await replace(entry: entry, req: req)
        return entry
    }

    func deleteTimeEntry(req: Request) async throws -> HTTPStatus {
        guard let entryId = req.parameters.get("entryId"), !entryId.isEmpty else {
            throw Abort(.badRequest)
        }
        if req.application.environment == .testing {
            var entries = loadTimeMemory(req.application)
            let before = entries.count
            entries.removeAll { $0.id == entryId }
            guard entries.count < before else { throw Abort(.notFound) }
            saveTimeMemory(req.application, entries)
            return .noContent
        }
        let deleted = try await req.mongoDB[timeCollection].deleteOne(where: "id" == entryId)
        guard deleted.deletes > 0 else { throw Abort(.notFound) }
        return .noContent
    }

    func clockIn(req: Request) async throws -> TimeEntry {
        guard let id = req.parameters.get("id"), !id.isEmpty else { throw Abort(.badRequest) }
        try requireSelfClockTarget(req: req, memberId: id)
        let member = try await requireMember(req: req, id: id)
        if let open = try await openEntry(req: req, teamMemberId: id) {
            throw Abort(
                .conflict,
                reason: "Already clocked in since \(ISO8601DateFormatter().string(from: open.clockIn))")
        }
        let now = Date()
        let entry = TimeEntry(
            id: ObjectId().hexString,
            teamMemberId: member.id,
            teamMemberName: member.name,
            clockIn: now,
            clockOut: nil,
            note: nil,
            source: .clock,
            createdAt: now,
            updatedAt: now,
            status: .pending
        )
        try await persist(entry: entry, req: req)
        return entry
    }

    func clockOut(req: Request) async throws -> TimeEntry {
        guard let id = req.parameters.get("id"), !id.isEmpty else { throw Abort(.badRequest) }
        try requireSelfClockTarget(req: req, memberId: id)
        _ = try await requireMember(req: req, id: id)
        guard var open = try await openEntry(req: req, teamMemberId: id) else {
            throw Abort(.conflict, reason: "Not currently clocked in")
        }
        let now = Date()
        guard now > open.clockIn else {
            throw Abort(.badRequest, reason: "clockOut must be after clockIn")
        }
        open.clockOut = now
        open.status = .pending
        open.updatedAt = now
        try await replace(entry: open, req: req)
        return open
    }

    // MARK: Helpers

    /// Full roster + punches for finance reports (no list limit / clockIn filter).
    /// Bypasses staff privacy — callers must already be admin/report-scoped.
    func rosterAndTimeEntries(req: Request) async throws -> (members: [TeamMember], entries: [TimeEntry]) {
        let members: [TeamMember]
        if req.application.environment == .testing {
            members = loadMemory(req.application)
        } else {
            var loaded: [TeamMember] = []
            for try await doc in req.mongoDB[collection].find() {
                loaded.append(try BSONDecoder().decode(TeamMember.self, from: doc))
            }
            members = loaded
        }
        let entries = try await loadEntries(req: req)
        return (members, entries)
    }

    private func loadEntries(req: Request) async throws -> [TimeEntry] {
        if req.application.environment == .testing {
            return loadTimeMemory(req.application)
        }
        var loaded: [TimeEntry] = []
        for try await doc in req.mongoDB[timeCollection].find() {
            loaded.append(try BSONDecoder().decode(TimeEntry.self, from: doc))
        }
        return loaded
    }

    private static func parseRange(_ req: Request) -> (Date?, Date?) {
        var fromDate: Date?
        var toDate: Date?
        if let raw = req.query[String.self, at: "from"], let d = ISO8601DateFormatter().date(from: raw) {
            fromDate = d
        }
        if let raw = req.query[String.self, at: "to"], let d = ISO8601DateFormatter().date(from: raw) {
            toDate = d
        }
        return (fromDate, toDate)
    }

    private static func periodRange(
        period: String,
        anchor: Date,
        calendar: Calendar
    ) throws -> (from: Date, to: Date) {
        switch period {
        case "month":
            let from = calendar.date(from: calendar.dateComponents([.year, .month], from: anchor))
                ?? calendar.startOfDay(for: anchor)
            guard let next = calendar.date(byAdding: .month, value: 1, to: from) else {
                throw Abort(.badRequest, reason: "Invalid period")
            }
            return (from, next.addingTimeInterval(-1))
        case "year":
            let from = calendar.date(from: calendar.dateComponents([.year], from: anchor))
                ?? calendar.startOfDay(for: anchor)
            guard let next = calendar.date(byAdding: .year, value: 1, to: from) else {
                throw Abort(.badRequest, reason: "Invalid period")
            }
            return (from, next.addingTimeInterval(-1))
        default: // week
            let from = calendar.dateInterval(of: .weekOfYear, for: anchor)?.start
                ?? calendar.startOfDay(for: anchor)
            guard let next = calendar.date(byAdding: .day, value: 7, to: from) else {
                throw Abort(.badRequest, reason: "Invalid period")
            }
            return (from, next.addingTimeInterval(-1))
        }
    }

    private static func minutes(
        for entry: TimeEntry,
        now: Date,
        clampFrom: Date,
        clampTo: Date
    ) -> Int {
        let start = max(entry.clockIn, clampFrom)
        let end = min(entry.clockOut ?? now, clampTo)
        guard end > start else { return 0 }
        return max(0, Int(end.timeIntervalSince(start) / 60))
    }

    private func requireMember(req: Request, id: String) async throws -> TeamMember {
        if req.application.environment == .testing {
            guard let member = loadMemory(req.application).first(where: { $0.id == id }) else {
                throw Abort(.notFound, reason: "Team member not found")
            }
            return member
        }
        guard let doc = try await req.mongoDB[collection].findOne("id" == id) else {
            throw Abort(.notFound, reason: "Team member not found")
        }
        return try BSONDecoder().decode(TeamMember.self, from: doc)
    }

    private func requireEntry(req: Request, id: String) async throws -> TimeEntry {
        if req.application.environment == .testing {
            guard let entry = loadTimeMemory(req.application).first(where: { $0.id == id }) else {
                throw Abort(.notFound, reason: "Time entry not found")
            }
            return entry
        }
        guard let doc = try await req.mongoDB[timeCollection].findOne("id" == id) else {
            throw Abort(.notFound, reason: "Time entry not found")
        }
        return try BSONDecoder().decode(TimeEntry.self, from: doc)
    }

    private func openEntry(req: Request, teamMemberId: String) async throws -> TimeEntry? {
        let entries: [TimeEntry]
        if req.application.environment == .testing {
            entries = loadTimeMemory(req.application)
        } else {
            var loaded: [TimeEntry] = []
            for try await doc in req.mongoDB[timeCollection].find("teamMemberId" == teamMemberId) {
                loaded.append(try BSONDecoder().decode(TimeEntry.self, from: doc))
            }
            entries = loaded
        }
        return entries.first { $0.teamMemberId == teamMemberId && $0.clockOut == nil }
    }

    private func persist(entry: TimeEntry, req: Request) async throws {
        if req.application.environment == .testing {
            var entries = loadTimeMemory(req.application)
            entries.append(entry)
            saveTimeMemory(req.application, entries)
            return
        }
        try await req.mongoDB[timeCollection].insert(BSONEncoder().encode(entry))
    }

    private func replace(entry: TimeEntry, req: Request) async throws {
        if req.application.environment == .testing {
            var entries = loadTimeMemory(req.application)
            guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else {
                throw Abort(.notFound)
            }
            entries[idx] = entry
            saveTimeMemory(req.application, entries)
            return
        }
        let result = try await req.mongoDB[timeCollection].updateOne(
            where: "id" == entry.id,
            to: BSONEncoder().encode(entry))
        guard result.updatedCount > 0 else { throw Abort(.notFound) }
    }
}
