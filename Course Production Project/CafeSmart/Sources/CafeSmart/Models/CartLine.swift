//
//  CartLine.swift
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

struct CartLine: Identifiable, Equatable {
    var id: String { item.id + "-" + String(sizeDeltaCents) }
    let item: MenuItem
    var quantity: Int
    let sizeDeltaCents: Int
    let sizeName: String?
    var unitCents: Int { item.priceCents + sizeDeltaCents }
    var lineCents: Int { unitCents * quantity }
}


