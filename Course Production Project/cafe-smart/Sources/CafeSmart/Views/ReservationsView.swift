//
//  ReservationsView.swift
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

struct ReservationsView: View {
    @Environment(ReservationViewModel.self) var reservationViewModel
    @State var name: String = ""
    @State var partySize: String = "2"
    @State var time: String = "2:00 PM"
    
    #if os(Android)
    let numberIcon = "android_tag"
    let clockIcon = "android_clock"
    #else
    let numberIcon = "number"
    let clockIcon = "clock.fill"
    #endif

    @State var availableWidth: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                if let err = reservationViewModel.errorMessage, !err.isEmpty {
                    Text(err)
                        .font(AppFont.footnote())
                        .foregroundStyle(.red)
                        .padding(10)
                        .frame(minWidth: 0, maxWidth: availableWidth > 0 ? availableWidth : .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                SectionHeader(title: "Reservations", subtitle: "Check, book, and manage tables")

                LazyVStack(spacing: AppSpacing.md) {
                    if reservationViewModel.isLoading {
                        ProgressView()
                            .frame(minWidth: 0, maxWidth: availableWidth > 0 ? availableWidth : .infinity)
                    }
                    if reservationViewModel.reservations.isEmpty && !reservationViewModel.isLoading {
                        Text("No reservations yet.")
                            .font(AppFont.subheadline())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 0, maxWidth: availableWidth > 0 ? availableWidth : .infinity, alignment: .center)
                    }
                    ForEach(reservationViewModel.reservations) { r in
                        CardContainer(
                            padding: AppSpacing.md,
                            cornerRadius: 16,
                            backgroundColor: .surfaceColor,
                            borderColor: .separatorColor.opacity(0.35),
                            borderWidth: 1,
                            shadowEnabled: true,
                            shadowColor: .black.opacity(0.05),
                            shadowRadius: 10,
                            shadowX: 0,
                            shadowY: 6) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(r.name)
                                        .font(AppFont.headline())
                                    Text("Party of \(r.partySize) • \(r.startTime.formatted(date: .omitted, time: .shortened))")
                                        .font(AppFont.subheadline())
                                        .foregroundStyle(.secondary)
                                    if let notes = r.notes, !notes.isEmpty {
                                        Text(notes)
                                            .font(AppFont.footnote())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text((r.status?.rawValue.capitalized) ?? "")
                                    .font(AppFont.footnote())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.appColor.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }
                        .frame(minWidth: 0, maxWidth: availableWidth > 0 ? availableWidth : .infinity, alignment: .leading)
                    }
                }

                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    SectionHeader(title: "New reservation", subtitle: "Quick add")
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "person.fill")
                        AppTextField(placeholder: "Name", text: $name)
                    }
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: numberIcon)
                        AppTextField(placeholder: "Party size", text: $partySize)
//                            .keyboardType(.numberPad)
                    }
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: clockIcon)
                        AppTextField(placeholder: "Time (e.g., 2:00 PM)", text: $time)
                    }
                    PrimaryButton(title: "Book table", fillWidth: true) {
                        Task {
                            await book()
                        }
                    }
                }
            }
            .padding()
        }
        .captureWidth(in: $availableWidth)
        .navigationTitle("Reservations")
        .task {
            if reservationViewModel.reservations.isEmpty {
                do {
                    try await reservationViewModel.fetchReservations()
                } catch {
                    reservationViewModel.errorMessage = "Failed to load reservations."
                }
            }
        }
        .refreshable {
            do {
                try await reservationViewModel.fetchReservations()
            } catch {
                reservationViewModel.errorMessage = "Failed to refresh reservations."
            }
        }
    }
}


extension ReservationsView {
    @MainActor private func book() async {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty, let size = Int(partySize) else { return }
        // Convert UI time string to Date by appending to today (simple heuristic)
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let now = Date()
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        if let t = formatter.date(from: time) {
            let timeComps = cal.dateComponents([.hour, .minute], from: t)
            comps.hour = timeComps.hour; comps.minute = timeComps.minute
        }
        let startTime = cal.date(from: comps) ?? now
        let req = CreateReservationRequest(name: name, partySize: size, startTime: startTime)
        do { _ = try await reservationViewModel.createReservation(req) } catch { logger.error("Failed to create reservation: \(String(describing: error))") }
        name = ""
        partySize = "2"
        time = "2:00 PM"
    }
}

