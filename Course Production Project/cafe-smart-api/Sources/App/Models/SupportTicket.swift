//
//  SupportTicket.swift
//  CafeSmartAPI
//

import Foundation
import Vapor

public enum SupportTicketStatus: String, Codable, Sendable, Equatable, Content {
    case open
    case inProgress
    case resolved
    case closed
}

public struct SupportTicket: Content, Sendable, Equatable, BinaryResponseEncodable {
    public var id: String
    public var creatorUserId: String
    public var creatorEmail: String
    public var message: String
    public var status: SupportTicketStatus
    public var staffNote: String?
    public var createdAt: Date
    public var updatedAt: Date
    /// Guest archived/removed from their inbox — admin desk still sees the ticket.
    public var hiddenByCreatorAt: Date? = nil
    /// Admin soft-delete — hidden from default desk; recoverable via includeDeleted.
    public var deletedAt: Date? = nil
    /// Linked café order IDs (full ObjectId strings). Display short prefix in UI.
    public var relatedOrderIds: [String]? = nil

    public init(
        id: String,
        creatorUserId: String,
        creatorEmail: String,
        message: String,
        status: SupportTicketStatus = .open,
        staffNote: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        hiddenByCreatorAt: Date? = nil,
        deletedAt: Date? = nil,
        relatedOrderIds: [String]? = nil
    ) {
        self.id = id
        self.creatorUserId = creatorUserId
        self.creatorEmail = creatorEmail
        self.message = message
        self.status = status
        self.staffNote = staffNote
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.hiddenByCreatorAt = hiddenByCreatorAt
        self.deletedAt = deletedAt
        self.relatedOrderIds = relatedOrderIds
    }

    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}

public struct CreateSupportTicketRequest: Content, Sendable, Equatable {
    public var message: String
    public var relatedOrderIds: [String]? = nil

    public init(message: String, relatedOrderIds: [String]? = nil) {
        self.message = message
        self.relatedOrderIds = relatedOrderIds
    }
}

public struct UpdateSupportTicketStatusRequest: Content, Sendable, Equatable {
    public var status: SupportTicketStatus
    public var staffNote: String?

    public init(status: SupportTicketStatus, staffNote: String? = nil) {
        self.status = status
        self.staffNote = staffNote
    }
}
