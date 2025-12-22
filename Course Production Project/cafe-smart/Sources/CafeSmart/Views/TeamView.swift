//
//  TeamView.swift
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

struct TeamView: View {
    @Environment(TeamViewModel.self) var teamViewModel
    @State var editMember: TeamMember? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                SectionHeader(title: "Team", subtitle: "Who's on shift today")
                VStack(spacing: AppSpacing.md) {
                    if teamViewModel.members.isEmpty && !teamViewModel.isLoading {
                        Text("No team members yet.")
                            .font(AppFont.subheadline()).foregroundStyle(.secondary)
                    }
                    ForEach(teamViewModel.members) { member in
                        CardContainer(
                            padding: AppSpacing.md,
                            cornerRadius: 16,
                            backgroundColor: .surfaceColor,
                            borderColor: .gray.opacity(0.15),
                            borderWidth: 1,
                            shadowEnabled: true,
                            shadowColor: .black.opacity(0.05),
                            shadowRadius: 10,
                            shadowX: 0,
                            shadowY: 6) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(member.name).font(AppFont.headline())
                                    Text(member.role).font(AppFont.subheadline()).foregroundStyle(.secondary)
                                }
                                Spacer()
                                HStack(spacing: AppSpacing.sm) {
                                    Text(member.shift).font(AppFont.footnote())
                                        .padding(.horizontal, 10).padding(.vertical, 6)
                                        .background(Color.appColor.opacity(0.12))
                                        .clipShape(Capsule())
                                    PrimaryButton(title: "Edit", fillWidth: true) { editMember = member }
                                        .frame(minWidth: 0, maxWidth: 160)
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Team")
        .task {
            if teamViewModel.members.isEmpty {
                try? await teamViewModel.fetchTeam()
            }
        }
        .refreshable {
            try? await teamViewModel.fetchTeam()
        }
        .sheet(item: $editMember) { member in
            TeamMemberEditSheet(member: member) { updated in
                Task {
                    try? await teamViewModel.updateMember(updated)
                }
            }
        }
    }
}


struct TeamMemberEditSheet: View {
    @Environment(\.dismiss) var dismiss
    @State var member: TeamMember
    var onSave: (TeamMember) -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $member.name)
                    TextField("Role", text: $member.role)
                    TextField("Shift", text: $member.shift)
                }
            }
            .navigationTitle("Edit member")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { onSave(member); dismiss() } }
            }
        }
    }
}


