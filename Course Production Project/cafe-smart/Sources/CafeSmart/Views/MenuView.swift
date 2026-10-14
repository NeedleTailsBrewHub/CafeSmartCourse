//
//  MenuView.swift
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

import SwiftUI
import VenueSmartKit

/// Single ordering surface — browse and cart live together in `OrderFlowView`.
/// Kept as a thin alias so older navigation routes still resolve cleanly.
struct MenuView: View {
    var body: some View {
        OrderFlowView()
    }
}
