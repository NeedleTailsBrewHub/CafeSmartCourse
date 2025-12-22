//
//  ReservationViewModel.swift
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

import Observation
import SkipFuseUI
import BSON
import SkipKeychain
import JWTKit
#if SKIP
import SkipFoundation
#else
import Foundation
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor
@Observable
final class ReservationViewModel {
    // MARK: - State
    var reservations: [Reservation] = []
    var isLoading: Bool = false
    var errorMessage: String?
    
    // MARK: - API
    func fetchReservations() async throws {
        isLoading = true
        defer { isLoading = false }
        let response: Response<ReservationsWrapper> = try await URLSession.shared.request(
            method: .get,
            httpHost: Constants.httpHost,
            url: "api/auth/reservations",
            token: nil,
            body: nil
        )
        let http = response.urlResponse as! HTTPURLResponse
        guard (200...299).contains(http.statusCode), let data = response.data else {
            throw Errors.failedRequest(http.statusCode)
        }
        reservations = data.items
    }
    
    func createReservation(_ requestModel: CreateReservationRequest) async throws -> Reservation {
        let body = try BSONEncoder().encode(requestModel).makeData()
        let response: Response<Reservation> = try await URLSession.shared.request(
            method: .post,
            httpHost: Constants.httpHost,
            url: "api/auth/reservations",
            token: nil,
            body: body
        )
        let http = response.urlResponse as! HTTPURLResponse
        guard (200...299).contains(http.statusCode), let reservation = response.data else {
            throw Errors.failedRequest(http.statusCode)
        }
        reservations.append(reservation)
        return reservation
    }
    
    func fetchReservation(id: String) async throws -> Reservation {
        let response: Response<Reservation> = try await URLSession.shared.request(
            method: .get,
            httpHost: Constants.httpHost,
            url: "api/auth/reservations/\(id)",
            token: nil,
            body: nil
        )
        let http = response.urlResponse as! HTTPURLResponse
        guard (200...299).contains(http.statusCode), let reservation = response.data else {
            throw Errors.failedRequest(http.statusCode)
        }
        return reservation
    }
    
    func deleteReservation(id: String) async throws {
        let response: Response<Data> = try await URLSession.shared.request(
            method: .delete,
            httpHost: Constants.httpHost,
            url: "api/auth/reservations/\(id)",
            token: nil,
            body: Data()
        )
        let http = response.urlResponse as! HTTPURLResponse
        guard (200...299).contains(http.statusCode) else {
            throw Errors.failedRequest(http.statusCode)
        }
        reservations.removeAll { $0.id == id }
    }
}

// moved to Models/CollectionModels.swift
