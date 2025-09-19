//
//  SupportView.swift
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

struct SupportView: View {
    
    @State var message: String = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                SectionHeader(
                    title: "Help & support",
                    subtitle: "We’re here to help")
                CardContainer(
                    padding: AppSpacing.lg,
                    cornerRadius: 16,
                    backgroundColor: .surfaceColor,
                    borderColor: .gray.opacity(0.15),
                    borderWidth: 1, shadowEnabled: true,
                    shadowColor: .black.opacity(0.05),
                    shadowRadius: 10,
                    shadowX: 0,
                    shadowY: 6) {
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        Text("Send us a message")
                            .font(AppFont.headline())
                        TextField("Describe your issue", text: $message)
                            .font(AppFont.body())
                            .lineLimit(5, reservesSpace: true)
                        PrimaryButton(title: "Submit", fillWidth: true) {}
                    }
                }
                CardContainer(
                    padding: AppSpacing.lg,
                    cornerRadius: 16,
                    backgroundColor: .surfaceColor,
                    borderColor: .gray.opacity(0.15),
                    borderWidth: 1,
                    shadowEnabled: true,
                    shadowColor: .black.opacity(0.05),
                    shadowRadius: 10,
                    shadowX: 0,
                    shadowY: 6) {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("FAQ")
                            .font(AppFont.headline())
                        Text("• How do I change my order?\n• How do I reset my password?\n• How do I contact the café?")
                            .font(AppFont.body())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Help & support")
    }
}


