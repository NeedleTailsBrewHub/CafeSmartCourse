//
//  AIModels.swift
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

import Foundation
import BSON

public struct ModelUploadResponse: Codable, Sendable, Equatable {
    public let id: String
    public let filename: String
    public let runtime: String
    public let bytes: Int
    public let storedAt: String
    public let kind: String
    public let active: Bool
}

public struct MLModelArtifact: Codable, Sendable, Equatable {
    // Some endpoints may return `id` as String while others return `_id` as ObjectId
    public var id: String?
    public var _id: ObjectId?
    public var filename: String?
    public var runtime: PredictRuntime?
    public var kind: PredictorKind
    public var storedAt: String?
    public var bytes: Int?
    public var active: Bool
    public var uploadedAt: Date?
}

public struct ModelsList: Codable, Sendable, Equatable {
    public let items: [MLModelArtifact]
}

public enum PredictorKind: String, Codable, Sendable, CaseIterable, Equatable {
    case workloadHourly
    case reservationsHourly
    case restockDaily
    case reservationDuration
}

public enum PredictRuntime: String, Codable, Sendable, Equatable {
    case onnx
    case coreml
}

public struct RestockDecisionRequest: Codable, Sendable, Equatable {
    public let sku: String
    public let daysAhead: Int?
}

public struct RestockDecisionResponse: Codable, Sendable, Equatable {
    public let sku: String
    public let needRestock: Bool
    public let reorderQty: Int
    public let reorderPoint: Int
    public let leadTimeDays: Int
    public let onHand: Int
    public let forecastSumNextLeadTime: Int
}


