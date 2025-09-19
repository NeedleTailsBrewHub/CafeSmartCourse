//
//  ReportsView.swift
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

struct ReportsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                SectionHeader(
                    title: "Reports",
                    subtitle: "Sales and performance overview")
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
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        Text("Today")
                            .font(AppFont.headline())
                        Text("Sales: $1,240 • Orders: 86")
                            .font(AppFont.body())
                        Text("Peak hour: 12–1 PM")
                            .font(AppFont.body())
                            .foregroundStyle(.secondary)
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
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        Text("Week to date")
                            .font(AppFont.headline())
                        Text("Sales: $7,985 • Orders: 504")
                            .font(AppFont.body())
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Reports")
    }
}


