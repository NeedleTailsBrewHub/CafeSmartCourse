//
//  TeamMember.swift
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

#if SKIP
import SkipFoundation
#else
import Foundation
#endif

public struct TeamMember: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var name: String
    public var role: String
    public var shift: String

    public init(id: String, name: String, role: String, shift: String) {
        self.id = id
        self.name = name
        self.role = role
        self.shift = shift
    }
}


