//
//  ReservationAvailability.swift
//  CafeSmartAPI
//
//  Slot grid + capacity from admin booking settings, hours, tables, and caps.
//

import Foundation
import Vapor

/// Pickable seating option for a time slot (guest table-type choice).
public struct ReservationTableOption: Content, Sendable, Equatable {
    public var tableId: String
    public var areaId: String
    public var label: String
    public var capacity: Int
    public var outside: Bool
    public var highTop: Bool
    public var accessible: Bool

    public init(
        tableId: String,
        areaId: String,
        label: String,
        capacity: Int,
        outside: Bool,
        highTop: Bool,
        accessible: Bool
    ) {
        self.tableId = tableId
        self.areaId = areaId
        self.label = label
        self.capacity = capacity
        self.outside = outside
        self.highTop = highTop
        self.accessible = accessible
    }
}

public struct ReservationSlot: Content, Sendable, Equatable {
    public var startTime: Date
    public var endTime: Date
    public var availableTableCount: Int
    public var bestTableId: String?
    public var bestAreaId: String?
    public var seatsRemaining: Int
    /// Historical busyness for this weekday+hour (0…1), from orders when available.
    public var busynessIndex: Double? = nil
    /// Up to 3 quieter available slots are marked recommended.
    public var recommended: Bool? = nil
    /// Free tables the guest can request for this slot (append-only for BinaryCodable).
    public var tableOptions: [ReservationTableOption] = []
}

public struct ReservationAvailabilityResponse: Content, Sendable, Equatable, BinaryResponseEncodable {
    public var date: String
    public var partySize: Int
    public var slotMinutes: Int
    public var turnMinutes: Int
    public var timezone: String
    public var open: String?
    public var close: String?
    public var slots: [ReservationSlot]

    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}

enum ReservationAvailability {
    static let defaultOpen = "08:00"
    static let defaultClose = "21:00"

    static func calendar(for timezone: String) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: timezone) ?? .current
        return cal
    }

    static func parseDay(_ raw: String, calendar: Calendar) -> Date? {
        let parts = raw.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var comps = DateComponents()
        comps.year = parts[0]
        comps.month = parts[1]
        comps.day = parts[2]
        return calendar.date(from: comps)
    }

    static func formatDay(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func parseHHMM(_ raw: String, on day: Date, calendar: Calendar) -> Date? {
        let parts = raw.split(separator: ":")
        guard parts.count >= 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return calendar.date(bySettingHour: h, minute: m, second: 0, of: day)
    }

    static func formatHHMM(_ date: Date, calendar: Calendar) -> String {
        let h = calendar.component(.hour, from: date)
        let m = calendar.component(.minute, from: date)
        return String(format: "%02d:%02d", h, m)
    }

    static func hours(for day: Date, config: BusinessConfig?, calendar: Calendar) -> (open: String, close: String)? {
        let weekday = calendar.component(.weekday, from: day) // 1=Sun … 7=Sat
        if let match = config?.hours.first(where: { $0.weekday == weekday }) {
            return (match.open, match.close)
        }
        if let config, !config.hours.isEmpty {
            return nil
        }
        return (defaultOpen, defaultClose)
    }

    static func reservationEnd(_ reservation: Reservation, turn: Int) -> Date {
        let minutes = reservation.durationMinutes ?? turn
        return reservation.startTime.addingTimeInterval(TimeInterval(max(15, minutes) * 60))
    }

    static func overlaps(_ aStart: Date, _ aEnd: Date, _ bStart: Date, _ bEnd: Date) -> Bool {
        aStart < bEnd && bStart < aEnd
    }

    static func activeReservations(_ items: [Reservation]) -> [Reservation] {
        items.filter { ($0.status ?? .active) == .active }
    }

    /// Candidate start times for a day from admin settings + open hours.
    static func candidateStarts(
        day: Date,
        openAt: Date,
        closeAt: Date,
        booking: ReservationBookingSettings,
        calendar: Calendar
    ) -> [Date] {
        let turn = booking.turnMinutes
        let lastStart = closeAt.addingTimeInterval(-TimeInterval(turn * 60))
        guard lastStart >= openAt else { return [] }

        let explicit = booking.slotStarts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !explicit.isEmpty {
            return explicit.compactMap { parseHHMM($0, on: day, calendar: calendar) }
                .filter { $0 >= openAt && $0 <= lastStart }
                .sorted()
        }

        let interval = TimeInterval(booking.slotIntervalMinutes * 60)
        var starts: [Date] = []
        var cursor = openAt
        while cursor <= lastStart {
            starts.append(cursor)
            cursor = cursor.addingTimeInterval(interval)
        }
        return starts
    }

    /// Annotate slots with busyness and recommend up to 3 quieter available ones.
    /// Prefer `intensityByHourStart` (model or combined forecast); else historical order counts.
    static func annotateBusyness(
        slots: [ReservationSlot],
        orders: [Order],
        calendar: Calendar,
        intensityByHourStart: [Date: Double]? = nil
    ) -> [ReservationSlot] {
        let maxIntensity: Double
        if let intensityByHourStart, !intensityByHourStart.isEmpty {
            maxIntensity = max(1e-9, intensityByHourStart.values.max() ?? 0)
        } else {
            maxIntensity = 0
        }

        var counts: [Int: [Int: Int]] = [:]
        if maxIntensity <= 0 {
            for order in orders where order.status != .canceled {
                let weekday = calendar.component(.weekday, from: order.createdAt)
                let hour = calendar.component(.hour, from: order.createdAt)
                counts[weekday, default: [:]][hour, default: 0] += 1
            }
        }
        let maxCount = max(1, counts.values.flatMap(\.values).max() ?? 0)

        var annotated = slots.map { slot -> ReservationSlot in
            var copy = slot
            let hourKey = calendar.date(
                from: calendar.dateComponents(
                    [.year, .month, .day, .hour], from: slot.startTime))
                ?? slot.startTime
            if let intensityByHourStart, maxIntensity > 0 {
                let raw = intensityByHourStart[hourKey] ?? 0
                copy.busynessIndex = min(1, max(0, raw / maxIntensity))
            } else {
                let weekday = calendar.component(.weekday, from: slot.startTime)
                let hour = calendar.component(.hour, from: slot.startTime)
                let raw = Double(counts[weekday]?[hour] ?? 0)
                copy.busynessIndex = raw / Double(maxCount)
            }
            copy.recommended = false
            return copy
        }

        let quietest = annotated.enumerated()
            .filter { $0.element.availableTableCount > 0 }
            .sorted {
                let lhs = $0.element.busynessIndex ?? 1
                let rhs = $1.element.busynessIndex ?? 1
                if lhs != rhs { return lhs < rhs }
                return $0.element.startTime < $1.element.startTime
            }
            .prefix(3)
        for entry in quietest {
            annotated[entry.offset].recommended = true
        }
        return annotated
    }

    /// Build available slots for a calendar day and party size.
    static func slots(
        dateRaw: String,
        partySize: Int,
        config: BusinessConfig?,
        tables: [Table],
        areas: [SeatingArea],
        reservations: [Reservation],
        orders: [Order] = [],
        now: Date = Date(),
        intensityByHourStart: [Date: Double]? = nil
    ) -> ReservationAvailabilityResponse {
        let timezone = config?.timezone ?? TimeZone.current.identifier
        let calendar = calendar(for: timezone)
        let booking = config?.bookingSettings ?? .default
        let turn = booking.turnMinutes
        let slotMinutes = booking.slotIntervalMinutes

        guard booking.enabled, booking.tablesAvailable > 0, partySize > 0,
              let day = parseDay(dateRaw, calendar: calendar),
              let window = hours(for: day, config: config, calendar: calendar),
              let openAt = parseHHMM(window.open, on: day, calendar: calendar),
              let closeAt = parseHHMM(window.close, on: day, calendar: calendar),
              closeAt > openAt
        else {
            return ReservationAvailabilityResponse(
                date: dateRaw,
                partySize: partySize,
                slotMinutes: slotMinutes,
                turnMinutes: turn,
                timezone: timezone,
                open: nil,
                close: nil,
                slots: [])
        }

        let active = activeReservations(reservations)
        let activeTables = tables.filter(\.active).sorted {
            if $0.capacity != $1.capacity { return $0.capacity < $1.capacity }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        // Admin table inventory caps how many physical tables are offered.
        let inventoryTables = Array(activeTables.prefix(booking.tablesAvailable))
        let useVirtual = inventoryTables.isEmpty
        if useVirtual, partySize > booking.defaultPartyCapacity {
            return ReservationAvailabilityResponse(
                date: dateRaw,
                partySize: partySize,
                slotMinutes: slotMinutes,
                turnMinutes: turn,
                timezone: timezone,
                open: window.open,
                close: window.close,
                slots: [])
        }
        let eligibleTables = inventoryTables.filter { $0.capacity >= partySize }
        let seatingCap: Int = {
            if !inventoryTables.isEmpty {
                return inventoryTables.reduce(0) { $0 + max(0, $1.capacity) }
            }
            return booking.tablesAvailable * booking.defaultPartyCapacity
        }()

        let starts = candidateStarts(
            day: day,
            openAt: openAt,
            closeAt: closeAt,
            booking: booking,
            calendar: calendar)

        var result: [ReservationSlot] = []
        for start in starts where start >= now.addingTimeInterval(-60) {
            let end = start.addingTimeInterval(TimeInterval(turn * 60))
            if let slot = evaluateSlot(
                start: start,
                end: end,
                partySize: partySize,
                seatingCap: seatingCap,
                tablesAvailable: booking.tablesAvailable,
                eligibleTables: eligibleTables,
                useVirtualTables: inventoryTables.isEmpty,
                areas: areas,
                active: active,
                turn: turn)
            {
                result.append(slot)
            }
        }

        result = annotateBusyness(
            slots: result,
            orders: orders,
            calendar: calendar,
            intensityByHourStart: intensityByHourStart)

        return ReservationAvailabilityResponse(
            date: dateRaw,
            partySize: partySize,
            slotMinutes: slotMinutes,
            turnMinutes: turn,
            timezone: timezone,
            open: window.open,
            close: window.close,
            slots: result)
    }

    /// Returns assignment details when the requested start is bookable.
    static func assignment(
        startTime: Date,
        partySize: Int,
        config: BusinessConfig?,
        tables: [Table],
        areas: [SeatingArea],
        reservations: [Reservation],
        preferredTableId: String? = nil,
        preferredAreaId: String? = nil
    ) -> (tableId: String?, areaId: String?, turnMinutes: Int, seatsOccupied: Int)? {
        let timezone = config?.timezone ?? TimeZone.current.identifier
        let calendar = calendar(for: timezone)
        let dateRaw = formatDay(startTime, calendar: calendar)
        let response = slots(
            dateRaw: dateRaw,
            partySize: partySize,
            config: config,
            tables: tables,
            areas: areas,
            reservations: reservations,
            now: Date.distantPast)
        guard let match = response.slots.first(where: {
            abs($0.startTime.timeIntervalSince(startTime)) < 1
        }), match.availableTableCount > 0
        else { return nil }

        let booking = config?.bookingSettings ?? .default
        if !match.tableOptions.isEmpty {
            if let preferredTableId,
               let chosen = match.tableOptions.first(where: { $0.tableId == preferredTableId })
            {
                return (chosen.tableId, chosen.areaId, response.turnMinutes, partySize)
            }
            if let preferredAreaId,
               let chosen = match.tableOptions.first(where: { $0.areaId == preferredAreaId })
            {
                return (chosen.tableId, chosen.areaId, response.turnMinutes, partySize)
            }
            if let bestId = match.bestTableId,
               let chosen = match.tableOptions.first(where: { $0.tableId == bestId })
            {
                return (chosen.tableId, chosen.areaId, response.turnMinutes, partySize)
            }
            if let chosen = match.tableOptions.first {
                return (chosen.tableId, chosen.areaId, response.turnMinutes, partySize)
            }
        }
        if match.bestTableId != nil {
            return (match.bestTableId, match.bestAreaId, response.turnMinutes, partySize)
        }
        // Virtual inventory — no physical table id.
        guard partySize <= booking.defaultPartyCapacity else { return nil }
        return (nil, nil, response.turnMinutes, partySize)
    }

    static func optionLabel(table: Table, areaName: String) -> String {
        var parts: [String] = [areaName]
        if table.outside == true { parts.append("Outdoor") }
        if table.highTop == true { parts.append("High-top") }
        if table.accessible { parts.append("Accessible") }
        parts.append("\(table.capacity)-top")
        return "\(parts.joined(separator: " · ")) · \(table.name)"
    }

    private static func evaluateSlot(
        start: Date,
        end: Date,
        partySize: Int,
        seatingCap: Int,
        tablesAvailable: Int,
        eligibleTables: [Table],
        useVirtualTables: Bool,
        areas: [SeatingArea],
        active: [Reservation],
        turn: Int
    ) -> ReservationSlot? {
        let overlapping = active.filter {
            overlaps(start, end, $0.startTime, reservationEnd($0, turn: turn))
        }
        let seatsUsed = overlapping.reduce(0) { $0 + ($1.seatsOccupied ?? $1.partySize) }
        let seatsRemaining = max(0, seatingCap - seatsUsed)
        guard seatsRemaining >= partySize else { return nil }

        // Concurrent reservation count vs admin table inventory.
        let tablesInUse = overlapping.count
        let tablesFree = max(0, tablesAvailable - tablesInUse)
        guard tablesFree > 0 else { return nil }

        if useVirtualTables {
            return ReservationSlot(
                startTime: start,
                endTime: end,
                availableTableCount: tablesFree,
                bestTableId: nil,
                bestAreaId: nil,
                seatsRemaining: seatsRemaining,
                tableOptions: [])
        }

        let busyTableIds = Set(overlapping.compactMap(\.tableId))
        let areaById = Dictionary(uniqueKeysWithValues: areas.map { ($0.id, $0) })
        let free = eligibleTables.filter { table in
            guard !busyTableIds.contains(table.id) else { return false }
            return areaById[table.areaId]?.active ?? true
        }
        // Respect both free physical tables and admin inventory remaining.
        let availableCount = min(free.count, tablesFree)
        guard availableCount > 0 else { return nil }
        let offered = Array(free.prefix(availableCount))
        guard let best = offered.first else { return nil }

        let options = offered.map { table in
            ReservationTableOption(
                tableId: table.id,
                areaId: table.areaId,
                label: optionLabel(table: table, areaName: areaById[table.areaId]?.name ?? "Seating"),
                capacity: table.capacity,
                outside: table.outside == true,
                highTop: table.highTop == true,
                accessible: table.accessible)
        }

        return ReservationSlot(
            startTime: start,
            endTime: end,
            availableTableCount: availableCount,
            bestTableId: best.id,
            bestAreaId: best.areaId,
            seatsRemaining: seatsRemaining,
            tableOptions: options)
    }
}
