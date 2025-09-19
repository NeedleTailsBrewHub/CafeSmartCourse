//
//  AppNotificationBanner.swift
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

struct AppNotificationBanner: View {
    @Environment(AppNotificationCenter.self) var center
    
    var body: some View {
        ZStack {
            if center.isPresented {
                #if os(macOS)
                HStack {
                    Spacer()
                    banner
                        .frame(width: 320)
                        .transition(.opacity)
                        .zIndex(1000)
                }
                #else
                banner
                    .transition(.opacity)
                    .zIndex(1000)
                #endif
            }
        }
        .animation(.easeInOut(duration: 0.2), value: center.isPresented)
#if os(macOS)
        .padding(.top, 8)
#elseif os(iOS)
        .padding(.top, 60)
#else
        .padding(.top, 30)
#endif
        .ignoresSafeArea(.container, edges: .top)
    }
    
    private var banner: some View {
        Text(center.message)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 12)
    }
}


