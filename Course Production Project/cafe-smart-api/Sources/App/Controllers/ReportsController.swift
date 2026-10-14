//
//  ReportsController.swift
//  CafeSmartAPI
//
//  Admin finance summary + demand / stock outlook.
//

import Vapor

actor ReportsController {
    private let team: TeamController
    private let predictor: CafePredictorController

    init(team: TeamController, predictor: CafePredictorController) {
        self.team = team
        self.predictor = predictor
    }

    func summary(req: Request) async throws -> ReportsSummary {
        let range = try ReportsInsightsService.parseSummaryRange(req: req)
        return try await ReportsInsightsService.summary(
            req: req, from: range.from, to: range.to, team: team)
    }

    func orders(req: Request) async throws -> ReportsOrdersDetail {
        let range = try ReportsInsightsService.parseSummaryRange(req: req)
        return try await ReportsInsightsService.orders(req: req, from: range.from, to: range.to)
    }

    func demand(req: Request) async throws -> DemandInsights {
        let days = ReportsInsightsService.parseDemandDays(req: req)
        return try await ReportsInsightsService.demand(
            req: req, days: days, predictor: predictor)
    }

    /// Accounting-friendly CSV. Query: `from`, `to`, `dataset` =
    /// `summary` | `byDay` | `orders` | `salesByItem` | `cogsBySku` | `labor`.
    /// Money columns are decimal currency (not cents).
    func exportCSV(req: Request) async throws -> CSVExportPayload {
        let range = try ReportsInsightsService.parseSummaryRange(req: req)
        let dataset = req.query[String.self, at: "dataset"] ?? "orders"
        return try await ReportsInsightsService.exportCSV(
            req: req,
            from: range.from,
            to: range.to,
            dataset: dataset,
            team: team)
    }
}
