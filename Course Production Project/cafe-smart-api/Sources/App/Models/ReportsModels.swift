//
//  ReportsModels.swift
//  CafeSmartAPI
//

import Foundation
import Vapor

public struct ReportsLaborMember: Content, Sendable, Equatable {
    public var teamMemberId: String
    public var teamMemberName: String
    public var approvedMinutes: Int
    public var laborCents: Int
    public var missingRate: Bool

    public init(
        teamMemberId: String,
        teamMemberName: String,
        approvedMinutes: Int,
        laborCents: Int,
        missingRate: Bool
    ) {
        self.teamMemberId = teamMemberId
        self.teamMemberName = teamMemberName
        self.approvedMinutes = approvedMinutes
        self.laborCents = laborCents
        self.missingRate = missingRate
    }
}

/// Per-day finance rollup for charting / drill-down.
public struct ReportsDayBucket: Content, Sendable, Equatable {
    public var day: Date
    public var orderCount: Int
    public var grossCents: Int
    public var netSalesCents: Int
    public var taxCents: Int
    public var loyaltyDiscountCents: Int
    public var collectedCents: Int
    public var cogsCents: Int

    public init(
        day: Date,
        orderCount: Int,
        grossCents: Int,
        netSalesCents: Int,
        taxCents: Int,
        loyaltyDiscountCents: Int,
        collectedCents: Int,
        cogsCents: Int
    ) {
        self.day = day
        self.orderCount = orderCount
        self.grossCents = grossCents
        self.netSalesCents = netSalesCents
        self.taxCents = taxCents
        self.loyaltyDiscountCents = loyaltyDiscountCents
        self.collectedCents = collectedCents
        self.cogsCents = cogsCents
    }
}

/// Menu-item mix for the selected range.
public struct ReportsSalesItem: Content, Sendable, Equatable {
    public var menuItemId: String
    public var name: String
    public var quantity: Int
    public var revenueCents: Int

    public init(menuItemId: String, name: String, quantity: Int, revenueCents: Int) {
        self.menuItemId = menuItemId
        self.name = name
        self.quantity = quantity
        self.revenueCents = revenueCents
    }
}

/// Ingredient COGS by SKU for the selected range.
public struct ReportsCogsSku: Content, Sendable, Equatable {
    public var sku: String
    public var name: String
    public var units: Double
    public var cogsCents: Int
    public var missingCost: Bool

    public init(sku: String, name: String, units: Double, cogsCents: Int, missingCost: Bool) {
        self.sku = sku
        self.name = name
        self.units = units
        self.cogsCents = cogsCents
        self.missingCost = missingCost
    }
}

/// Compact order row for finance drill-down.
public struct ReportsOrderRow: Content, Sendable, Equatable {
    public var id: String
    public var createdAt: Date
    public var customerName: String?
    public var status: OrderStatus
    public var paymentStatus: OrderPaymentStatus?
    public var channel: Order.OrderChannel?
    public var subtotalCents: Int
    public var loyaltyDiscountCents: Int
    public var taxCents: Int
    public var netSalesCents: Int
    public var totalCents: Int
    public var itemCount: Int

    public init(
        id: String,
        createdAt: Date,
        customerName: String?,
        status: OrderStatus,
        paymentStatus: OrderPaymentStatus?,
        channel: Order.OrderChannel?,
        subtotalCents: Int,
        loyaltyDiscountCents: Int,
        taxCents: Int,
        netSalesCents: Int,
        totalCents: Int,
        itemCount: Int
    ) {
        self.id = id
        self.createdAt = createdAt
        self.customerName = customerName
        self.status = status
        self.paymentStatus = paymentStatus
        self.channel = channel
        self.subtotalCents = subtotalCents
        self.loyaltyDiscountCents = loyaltyDiscountCents
        self.taxCents = taxCents
        self.netSalesCents = netSalesCents
        self.totalCents = totalCents
        self.itemCount = itemCount
    }
}

public struct ReportsOrdersDetail: Content, Sendable, Equatable, BinaryResponseEncodable {
    public var from: Date
    public var to: Date
    public var items: [ReportsOrderRow]

    public init(from: Date, to: Date, items: [ReportsOrderRow]) {
        self.from = from
        self.to = to
        self.items = items
    }

    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}

public struct ReportsSummary: Content, Sendable, Equatable, BinaryResponseEncodable {
    public var from: Date
    public var to: Date
    public var orderCount: Int
    /// Merchandise subtotal of completed+paid tickets (before loyalty / tax).
    public var grossCents: Int
    /// After loyalty / discounts (tax excluded). Merchant “Net” KPI uses contributionCents.
    public var netCents: Int
    public var taxCents: Int
    public var loyaltyDiscountCents: Int
    public var averageOrderCents: Int
    public var paidCount: Int
    public var unpaidCount: Int
    public var waivedCount: Int
    /// Recipe ingredient cost for completed tickets.
    public var cogsCents: Int
    public var missingCostSkuCount: Int
    public var laborCents: Int
    public var missingRateMemberCount: Int
    /// Net after overhead: after-loyalty sales − recipe COGS − approved labor.
    public var contributionCents: Int
    public var laborByMember: [ReportsLaborMember]
    /// Cash / card collected (paid orders’ totals, includes tax).
    public var collectedCents: Int
    public var byDay: [ReportsDayBucket]
    public var salesByItem: [ReportsSalesItem]
    public var cogsBySku: [ReportsCogsSku]

    public init(
        from: Date,
        to: Date,
        orderCount: Int,
        grossCents: Int,
        netCents: Int,
        taxCents: Int,
        loyaltyDiscountCents: Int,
        averageOrderCents: Int,
        paidCount: Int,
        unpaidCount: Int,
        waivedCount: Int,
        cogsCents: Int,
        missingCostSkuCount: Int,
        laborCents: Int,
        missingRateMemberCount: Int,
        contributionCents: Int,
        laborByMember: [ReportsLaborMember],
        collectedCents: Int = 0,
        byDay: [ReportsDayBucket] = [],
        salesByItem: [ReportsSalesItem] = [],
        cogsBySku: [ReportsCogsSku] = []
    ) {
        self.from = from
        self.to = to
        self.orderCount = orderCount
        self.grossCents = grossCents
        self.netCents = netCents
        self.taxCents = taxCents
        self.loyaltyDiscountCents = loyaltyDiscountCents
        self.averageOrderCents = averageOrderCents
        self.paidCount = paidCount
        self.unpaidCount = unpaidCount
        self.waivedCount = waivedCount
        self.cogsCents = cogsCents
        self.missingCostSkuCount = missingCostSkuCount
        self.laborCents = laborCents
        self.missingRateMemberCount = missingRateMemberCount
        self.contributionCents = contributionCents
        self.laborByMember = laborByMember
        self.collectedCents = collectedCents
        self.byDay = byDay
        self.salesByItem = salesByItem
        self.cogsBySku = cogsBySku
    }

    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}

public enum DemandSource: String, Content, Sendable, Equatable {
    case model
    case historical
}

/// How stock outlook rows were produced.
public enum StockOutlookSource: String, Content, Sendable, Equatable {
    /// RestockDaily ML + ROP (same path as predictor/restock/decide).
    case model
    /// Quantity ≤ reorderThreshold fallback.
    case threshold
}

public struct DemandHourCell: Content, Sendable, Equatable {
    /// 1=Sun … 7=Sat (Calendar weekday).
    public var weekday: Int
    public var hour: Int
    /// Relative intensity 0…1.
    public var index: Double

    public init(weekday: Int, hour: Int, index: Double) {
        self.weekday = weekday
        self.hour = hour
        self.index = index
    }
}

public struct DemandPeakWindow: Content, Sendable, Equatable {
    public var day: Date
    public var hour: Int
    public var predictedOrders: Double
    public var busynessIndex: Double

    public init(day: Date, hour: Int, predictedOrders: Double, busynessIndex: Double) {
        self.day = day
        self.hour = hour
        self.predictedOrders = predictedOrders
        self.busynessIndex = busynessIndex
    }
}

public struct DemandStaffSuggestion: Content, Sendable, Equatable {
    public var hour: Int
    public var predictedOrders: Double
    public var baristas: Int
    public var bakers: Int
    public var hosts: Int

    public init(hour: Int, predictedOrders: Double, baristas: Int, bakers: Int, hosts: Int) {
        self.hour = hour
        self.predictedOrders = predictedOrders
        self.baristas = baristas
        self.bakers = bakers
        self.hosts = hosts
    }

    /// Concurrent people needed this hour.
    public var headcount: Int { baristas + bakers + hosts }
}

/// Per-calendar-day staffing plan from the demand forecast.
public struct DemandDayStaffPlan: Content, Sendable, Equatable {
    public var day: Date
    /// 1=Sun … 7=Sat (Calendar weekday).
    public var weekday: Int
    public var peakHour: Int
    public var maxBaristas: Int
    public var maxBakers: Int
    public var maxHosts: Int
    /// Sum of hourly barista headcounts (= barista-hours to schedule).
    public var personHoursBaristas: Double
    public var personHoursBakers: Double
    public var personHoursHosts: Double
    public var totalPersonHours: Double
    public var hours: [DemandStaffSuggestion]

    public init(
        day: Date,
        weekday: Int,
        peakHour: Int,
        maxBaristas: Int,
        maxBakers: Int,
        maxHosts: Int,
        personHoursBaristas: Double,
        personHoursBakers: Double,
        personHoursHosts: Double,
        totalPersonHours: Double,
        hours: [DemandStaffSuggestion]
    ) {
        self.day = day
        self.weekday = weekday
        self.peakHour = peakHour
        self.maxBaristas = maxBaristas
        self.maxBakers = maxBakers
        self.maxHosts = maxHosts
        self.personHoursBaristas = personHoursBaristas
        self.personHoursBakers = personHoursBakers
        self.personHoursHosts = personHoursHosts
        self.totalPersonHours = totalPersonHours
        self.hours = hours
    }

    public var maxHeadcount: Int { maxBaristas + maxBakers + maxHosts }
}

public struct StockOutlookRow: Content, Sendable, Equatable {
    public var sku: String
    public var name: String
    public var needRestock: Bool
    public var reorderQty: Int
    public var unitCostCents: Int?
    public var predictedSpendCents: Int?
    public var busynessScale: Double

    public init(
        sku: String,
        name: String,
        needRestock: Bool,
        reorderQty: Int,
        unitCostCents: Int?,
        predictedSpendCents: Int?,
        busynessScale: Double
    ) {
        self.sku = sku
        self.name = name
        self.needRestock = needRestock
        self.reorderQty = reorderQty
        self.unitCostCents = unitCostCents
        self.predictedSpendCents = predictedSpendCents
        self.busynessScale = busynessScale
    }
}

public struct DemandInsights: Content, Sendable, Equatable, BinaryResponseEncodable {
    public var days: Int
    public var source: DemandSource
    public var heatmap: [DemandHourCell]
    public var peaks: [DemandPeakWindow]
    public var staffing: [DemandStaffSuggestion]
    public var stockOutlook: [StockOutlookRow]
    public var predictedStockSpendCents: Int
    public var stockSource: StockOutlookSource
    /// Per-day headcount and person-hours across the forecast horizon.
    public var staffingByDay: [DemandDayStaffPlan]

    public init(
        days: Int,
        source: DemandSource,
        heatmap: [DemandHourCell],
        peaks: [DemandPeakWindow],
        staffing: [DemandStaffSuggestion],
        stockOutlook: [StockOutlookRow],
        predictedStockSpendCents: Int,
        stockSource: StockOutlookSource = .threshold,
        staffingByDay: [DemandDayStaffPlan] = []
    ) {
        self.days = days
        self.source = source
        self.heatmap = heatmap
        self.peaks = peaks
        self.staffing = staffing
        self.stockOutlook = stockOutlook
        self.predictedStockSpendCents = predictedStockSpendCents
        self.stockSource = stockSource
        self.staffingByDay = staffingByDay
    }

    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}
