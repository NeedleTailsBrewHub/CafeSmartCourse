//
//  IconChip.swift
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

struct IconChip: View {
    var name: String
    var body: some View {
        Group {
            #if os(Android)
            Image(name, bundle: .module)
                .resizable()
                .scaledToFit()
            #else
            Image(systemName: name)
                .resizable()
                .scaledToFit()
            #endif
        }
        .frame(width: 18, height: 18)
        .padding(5)
        .frame(width: 28, height: 28)
        .background(Color.gray.opacity(0.15))
        .cornerRadius(14)
    }
}


