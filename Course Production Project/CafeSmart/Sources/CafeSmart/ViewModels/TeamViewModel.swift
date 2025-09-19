//
//  TeamViewModel.swift
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
final class TeamViewModel {
    var members: [TeamMember] = []
    var isLoading: Bool = false
    var errorMessage: String?

    func fetchTeam() async throws {
        isLoading = true
        defer { isLoading = false }
        let response: Response<[TeamMember]> = try await URLSession.shared.request(
            method: .get,
            httpHost: Constants.httpHost,
            url: "api/auth/team",
            token: nil,
            body: nil
        )
        let http = response.urlResponse as! HTTPURLResponse
        guard (200...299).contains(http.statusCode), let data = response.data else { throw Errors.failedRequest(http.statusCode) }
        members = data
    }

    func updateMember(_ member: TeamMember) async throws -> TeamMember {
        let body = try BSONEncoder().encode(member).makeData()
        let response: Response<TeamMember> = try await URLSession.shared.request(
            method: .put,
            httpHost: Constants.httpHost,
            url: "api/auth/team/\(member.id)",
            token: nil,
            body: body
        )
        let http = response.urlResponse as! HTTPURLResponse
        guard (200...299).contains(http.statusCode), let updated = response.data else { throw Errors.failedRequest(http.statusCode) }
        if let idx = members.firstIndex(where: { $0.id == member.id }) { members[idx] = updated }
        return updated
    }
}


