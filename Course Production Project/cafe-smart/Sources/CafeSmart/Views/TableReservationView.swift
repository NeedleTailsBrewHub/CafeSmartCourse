//
//  TableReservationView.swift
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

struct TableReservationView: View {
    @Environment(AuthenticationViewModel.self) var authenticationViewModel
    @Environment(ReservationViewModel.self) var reservationViewModel
    @Environment(AppNotificationCenter.self) var appNotificationCenter

    @State var name: String = ""
    @State var partySize: String = "2"
    @State var selectedDay: Date = Date()
    @State var selectedSlot: Date? = nil
    @State var selectedTableOption: ReservationTableOption? = nil
    @State var phone: String = ""
    @State var notes: String = ""
    @State var isSubmitting = false
    @State var localError: String?
    @State var cancelingId: String?

#if os(Android)
    private let personIcon = "android_group"
    private let numberIcon = "android_tag"
    private let calendarIcon = "android_calendar"
#else
    private let personIcon = "person.fill"
    private let numberIcon = "number"
    private let calendarIcon = "calendar"
#endif

    private var myReservations: [Reservation] {
        let userId = authenticationViewModel.user?.id
        return reservationViewModel.reservations.filter { reservation in
            guard let userId else { return false }
            // Defense-in-depth: never show another customer's booking in the guest UI.
            return reservation.customerUserId == userId
        }
    }

    private var upcoming: [Reservation] {
        myReservations
            .filter { ($0.status ?? .active) == .active }
            .sorted { $0.startTime < $1.startTime }
    }

    private var past: [Reservation] {
        myReservations
            .filter { ($0.status ?? .active) != .active }
            .sorted { $0.startTime > $1.startTime }
    }

    var body: some View {
        ScreenCanvas {
            PageHeader(
                title: "Reserve a table",
                subtitle: "Book seating and manage your bookings",
                systemImage: calendarIcon)

            if let err = reservationViewModel.errorMessage, !err.isEmpty {
                ErrorBanner(message: err)
            }
            if let localError, !localError.isEmpty {
                ErrorBanner(message: localError)
            }

            PanelSection(title: "Book a table", subtitle: "Pick an open time for your party") {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    HStack(spacing: AppSpacing.sm) {
                        AppImage(name: personIcon)
                        AppTextField(placeholder: "Name", text: $name)
                    }
                    HStack(spacing: AppSpacing.sm) {
                        AppImage(name: numberIcon)
                        AppTextField(placeholder: "Party size", text: $partySize)
                    }
                    HStack(alignment: .top, spacing: AppSpacing.sm) {
                        AppImage(name: calendarIcon)
                            .padding(.top, 6)
                        ReservationSlotPicker(
                            selectedDay: $selectedDay,
                            selectedSlot: $selectedSlot,
                            partySizeText: $partySize,
                            selectedTableOption: $selectedTableOption)
                    }
                    AppTextField(placeholder: "Phone (optional)", text: $phone)
                    AppTextField(placeholder: "Notes (optional)", text: $notes)
                    PrimaryButton(
                        title: isSubmitting ? "Booking…" : "Confirm reservation",
                        fillWidth: true
                    ) {
                        Task { await confirm() }
                    }
                    .disabled(isSubmitting || selectedSlot == nil)
                }
            }

            if reservationViewModel.isLoading && reservationViewModel.reservations.isEmpty {
                LoadingBlock()
            } else if !upcoming.isEmpty {
                PanelSection(title: "Upcoming", subtitle: "\(upcoming.count) active") {
                    VStack(spacing: AppSpacing.md) {
                        ForEach(upcoming) { r in
                            reservationCard(r, canCancel: true)
                        }
                    }
                }
            } else {
                EmptyState(
                    title: "No upcoming reservations",
                    subtitle: "Book above to reserve a table.",
                    systemImage: personIcon
                )
            }

            if !past.isEmpty {
                PanelSection(title: "Past", subtitle: "Completed and canceled") {
                    VStack(spacing: AppSpacing.md) {
                        ForEach(past) { r in
                            reservationCard(r, canCancel: false)
                        }
                    }
                }
            }
        }
        .navigationTitle("Reservations")
        .onAppear {
            if name.isEmpty {
                name = authenticationViewModel.user?.name
                    ?? authenticationViewModel.user?.email
                    ?? ""
            }
        }
        .task {
            await reload()
        }
        .refreshable {
            await reload()
        }
    }

    @ViewBuilder
    private func reservationCard(_ r: Reservation, canCancel: Bool) -> some View {
        SurfacePanel {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                AdaptiveDetailRow {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(r.name)
                            .font(AppFont.headline())
                        Text(
                            "Party of \(r.partySize) · \(r.startTime.formatted(date: .abbreviated, time: .shortened))"
                        )
                        .font(AppFont.subheadline())
                        .foregroundStyle(.secondary)
                        if let phone = r.phone, !phone.isEmpty {
                            Text(phone)
                                .font(AppFont.footnote())
                                .foregroundStyle(.secondary)
                        }
                        if let notes = r.notes, !notes.isEmpty {
                            Text(notes)
                                .font(AppFont.footnote())
                                .foregroundStyle(.secondary)
                        }
                    }
                } actions: {
                    StatusChip(
                        text: (r.status ?? .active).rawValue.capitalized,
                        tone: chipTone(for: r.status ?? .active))
                }

                if canCancel {
                    DestructiveButton(
                        title: cancelingId == r.id ? "Canceling…" : "Cancel reservation",
                        fillWidth: true
                    ) {
                        Task { await cancel(r) }
                    }
                    .disabled(cancelingId != nil)
                }
            }
        }
    }

    private func chipTone(for status: ReservationStatus) -> StatusChipTone {
        switch status {
        case .active: return .accent
        case .completed: return .success
        case .canceled: return .danger
        }
    }

    @MainActor
    private func reload() async {
        do {
            try await reservationViewModel.fetchReservations(reset: true, scope: .mine)
            reservationViewModel.errorMessage = nil
        } catch {
            reservationViewModel.errorMessage = "Failed to load reservations."
        }
    }

    @MainActor
    private func confirm() async {
        guard !isSubmitting else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            localError = "Please enter a name."
            return
        }
        guard let size = Int(partySize.trimmingCharacters(in: .whitespacesAndNewlines)), size > 0 else {
            localError = "Party size must be a positive number."
            return
        }
        guard let startTime = selectedSlot else {
            localError = "Pick an available time slot."
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        let req = CreateReservationRequest(
            name: trimmed,
            partySize: size,
            startTime: startTime,
            phone: phone.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            areaId: selectedTableOption?.areaId,
            tableId: selectedTableOption?.tableId,
            status: .active)
        do {
            _ = try await reservationViewModel.createReservation(req)
            localError = nil
            appNotificationCenter.show(
                "Reservation confirmed",
                iconSystemName: "checkmark.circle.fill",
                duration: 3)
            partySize = "2"
            notes = ""
            selectedSlot = nil
            selectedTableOption = nil
            await reservationViewModel.fetchAvailability(date: selectedDay, partySize: 2, force: true)
            try? await reservationViewModel.fetchReservations(reset: true, scope: .mine)
        } catch {
            if case Errors.failedRequest(let code) = error, code == 409 {
                localError = "That table or time was just taken. Pick another option."
                await reservationViewModel.fetchAvailability(date: selectedDay, partySize: size, force: true)
                selectedTableOption = nil
            } else {
                localError = "Could not book reservation. Try again."
            }
            logger.error("Reservation failed: \(String(describing: error))")
        }
    }

    @MainActor
    private func cancel(_ reservation: Reservation) async {
        cancelingId = reservation.id
        defer { cancelingId = nil }
        do {
            _ = try await reservationViewModel.cancelReservation(id: reservation.id)
            reservationViewModel.errorMessage = nil
            appNotificationCenter.show(
                "Reservation canceled",
                iconSystemName: "checkmark.circle.fill",
                duration: 2.5)
        } catch {
            if case Errors.failedRequest(let code) = error {
                reservationViewModel.errorMessage = "Could not cancel reservation (\(code))."
            } else {
                reservationViewModel.errorMessage = "Could not cancel reservation."
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
