//
//  PredicationViewModel.swift
//  CafeSmart
//
//  Created by NeedleTails on 8/19/25
//
//  Copyright (c) 2025 NeedleTails Organization.
//
//  This project is proprietary and confidential.
//
//  MIT License
//
//  This file is part of the CafeSmart Project
//

#if canImport(CoreML)
import Observation
import Foundation

@MainActor
@Observable
final class PredictionViewModel {
    func decideRestockItems(sku: String, daysAhead: Int? = 7) async throws -> RestockDecisionResponse {
        try await AIService.shared.prepareRestockPredictor()
        return try await AIService.shared.decideRestock(sku: sku, daysAhead: daysAhead)
    }
}
#endif
