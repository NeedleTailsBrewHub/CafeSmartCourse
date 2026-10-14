//
//  SupportView.swift
//  CafeSmart
//

import SwiftUI
import VenueSmartKit

struct SupportView: View {
    @Environment(SupportViewModel.self) var supportViewModel
    @Environment(OrderViewModel.self) var orderViewModel
    @State var message: String = ""
    @State var submittedToast = false
    @State var ticketPendingArchive: SupportTicket?
    @State var ticketPendingRemove: SupportTicket?
    @State var selectedOrderIds: [String] = []
    @State var peekOrderId: String?

#if os(Android)
    private let supportIcon = "android_note"
#else
    private let supportIcon = "questionmark.circle.fill"
#endif

    private let maxLinkedOrders = 5

    private var canSubmit: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !supportViewModel.isSubmitting
    }

    private var trimmedLength: Int {
        message.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    private var recentOrders: [Order] {
        Array(
            orderViewModel.orders
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(12))
    }

    var body: some View {
        ScreenCanvas {
            PageHeader(
                title: "Help & support",
                subtitle: "Ask about orders, pickup, or your account — our café team replies here.",
                systemImage: supportIcon)

            if submittedToast {
                SurfacePanel(tone: .accent) {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        StatusChip(text: "Message sent", tone: .success)
                        Text("Thanks — you’ll see updates on this ticket below. The café team can also find it on Support desk.")
                            .font(AppFont.body())
                            .foregroundStyle(.secondary)
                        SecondaryButton(title: "Dismiss", fillWidth: false) {
                            submittedToast = false
                        }
                    }
                }
            }

            if let err = supportViewModel.errorMessage, !err.isEmpty {
                ErrorBanner(message: err)
            }

            PanelSection(title: "Write to us", subtitle: "A short note is enough — we read every message") {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    TextField("What’s going on?", text: $message, axis: .vertical)
                        .font(AppFont.body())
                        .lineLimit(4...14)
                        .padding(AppSpacing.md)
                        .background(Color.elevatedSurfaceColor)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                                .strokeBorder(
                                    canSubmit ? Color.appColor.opacity(0.35) : Color.separatorColor.opacity(0.45),
                                    lineWidth: 1)
                        )
                        .accessibilityLabel("Support message")

                    orderAttachSection

                    HStack {
                        Text(trimmedLength == 0 ? "Tip: link an order if this is about pickup." : "\(trimmedLength) characters")
                            .font(AppFont.caption())
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }

                    PrimaryButton(
                        title: supportViewModel.isSubmitting ? "Sending…" : "Send message",
                        systemImageName: supportIcon,
                        fillWidth: true
                    ) {
                        Task { await submit() }
                    }
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1 : 0.55)
                }
            }

            PanelSection(title: "My tickets", subtitle: "Archive clears your list — the café keeps a copy") {
                if supportViewModel.isLoading && supportViewModel.tickets.isEmpty {
                    LoadingBlock()
                } else if supportViewModel.tickets.isEmpty {
                    EmptyState(
                        title: "No open tickets",
                        subtitle: "When you send a message, it shows up here with status updates.",
                        systemImage: supportIcon)
                } else {
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        ForEach(supportViewModel.tickets) { ticket in
                            guestTicketCard(ticket)
                        }
                    }
                }
            }

            PanelSection(title: "Quick answers", subtitle: "Common café questions") {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    faqRow(
                        question: "How do I change my order?",
                        answer: "Cancel while it’s pending, then place a new order from the Menu tab.")
                    Divider()
                    faqRow(
                        question: "How do I reset my password?",
                        answer: "Open Settings → Security and enter your current password, then a new one.")
                    Divider()
                    faqRow(
                        question: "Will archive delete my message for staff?",
                        answer: "No. Archive only removes it from your list. Support desk still sees it.")
                }
            }
        }
        .navigationTitle("Support")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .task {
            await reloadMine()
            try? await orderViewModel.fetchOrders(reset: true, scope: .mine)
        }
        .refreshable {
            await reloadMine()
            try? await orderViewModel.fetchOrders(reset: true, scope: .mine)
        }
        .sheet(isPresented: Binding(
            get: { peekOrderId != nil },
            set: { if !$0 { peekOrderId = nil } }
        )) {
            if let peekOrderId {
                SupportOrderPeekSheet(orderId: peekOrderId)
            }
        }
        .confirmationDialog(
            "Archive this ticket?",
            isPresented: Binding(
                get: { ticketPendingArchive != nil },
                set: { if !$0 { ticketPendingArchive = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Archive from my list") {
                if let ticket = ticketPendingArchive {
                    Task { await archive(ticket) }
                }
            }
            Button("Cancel", role: .cancel) { ticketPendingArchive = nil }
        } message: {
            Text("Staff can still see the original message. This only clears it from your inbox.")
        }
        .confirmationDialog(
            "Remove this ticket?",
            isPresented: Binding(
                get: { ticketPendingRemove != nil },
                set: { if !$0 { ticketPendingRemove = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove from my list", role: .destructive) {
                if let ticket = ticketPendingRemove {
                    Task { await remove(ticket) }
                }
            }
            Button("Cancel", role: .cancel) { ticketPendingRemove = nil }
        } message: {
            Text("Same as archive — your café team keeps the ticket for follow-up.")
        }
    }

    @ViewBuilder
    private var orderAttachSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Related orders")
                .font(AppFont.headline())
            Text(selectedOrderIds.isEmpty
                 ? "Optional — tap an order to attach it (max \(maxLinkedOrders))."
                 : "\(selectedOrderIds.count) attached — tap again to remove.")
                .font(AppFont.caption())
                .foregroundStyle(.secondary)

            if recentOrders.isEmpty {
                Text("No recent orders to attach.")
                    .font(AppFont.footnote())
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.sm) {
                        ForEach(recentOrders) { order in
                            let selected = selectedOrderIds.contains(order.id)
                            Button {
                                toggleOrder(order.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(SupportTicketLogic.orderLabel(order.id))
                                        .font(AppFont.headline())
                                        .foregroundStyle(selected ? Color.white : Color.appColor)
                                    Text(order.createdAt, style: .date)
                                        .font(AppFont.caption())
                                        .foregroundStyle(selected ? Color.white.opacity(0.9) : .secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(selected ? Color.appColor : Color.appColor.opacity(0.10))
                                .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                                        .strokeBorder(Color.appColor.opacity(selected ? 0 : 0.20), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                "\(selected ? "Remove" : "Attach") order \(SupportTicketLogic.orderLabel(order.id))")
                        }
                    }
                }
            }
        }
    }

    private func guestTicketCard(_ ticket: SupportTicket) -> some View {
        AdaptiveDetailRow {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack(spacing: AppSpacing.sm) {
                    StatusChip(
                        text: SupportTicketLogic.statusLabel(ticket.status),
                        tone: SupportTicketLogic.statusTone(ticket.status))
                    Spacer(minLength: 0)
                    Text(ticket.createdAt, style: .relative)
                        .font(AppFont.caption())
                        .foregroundStyle(.secondary)
                }
                Text(ticket.message)
                    .font(AppFont.body())
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                SupportOrderChips(orderIds: ticket.linkedOrderIds) { id in
                    peekOrderId = id
                }
                if let note = ticket.staffNote, !note.isEmpty {
                    Text(note)
                        .font(AppFont.footnote())
                        .foregroundStyle(.secondary)
                        .padding(AppSpacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.appColor.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                        .accessibilityLabel("Staff reply: \(note)")
                }
            }
        } actions: {
            HStack(spacing: AppSpacing.sm) {
                SecondaryButton(title: "Archive", fillWidth: false) {
                    ticketPendingArchive = ticket
                }
                DestructiveButton(title: "Remove", fillWidth: false) {
                    ticketPendingRemove = ticket
                }
            }
        }
        .padding(AppSpacing.md)
        .background(Color.elevatedSurfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                .strokeBorder(Color.separatorColor.opacity(0.35), lineWidth: 1)
        )
    }

    private func faqRow(question: String, answer: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(question)
                .font(AppFont.headline())
            Text(answer)
                .font(AppFont.footnote())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func toggleOrder(_ id: String) {
        if let idx = selectedOrderIds.firstIndex(of: id) {
            selectedOrderIds.remove(at: idx)
        } else if selectedOrderIds.count < maxLinkedOrders {
            selectedOrderIds.append(id)
        }
    }

    @MainActor
    private func reloadMine() async {
        do {
            try await supportViewModel.fetchTickets(scopeMine: true)
        } catch {
            supportViewModel.errorMessage = "Could not load your tickets."
        }
    }

    private func submit() async {
        do {
            _ = try await supportViewModel.submit(
                message: message, relatedOrderIds: selectedOrderIds)
            message = ""
            selectedOrderIds = []
            submittedToast = true
        } catch SupportViewModel.Errors.emptyMessage {
            supportViewModel.errorMessage = "Please enter a message."
        } catch {
            supportViewModel.errorMessage = "Could not send message. Try again."
        }
    }

    private func archive(_ ticket: SupportTicket) async {
        do {
            try await supportViewModel.archiveTicket(id: ticket.id)
            ticketPendingArchive = nil
        } catch {
            supportViewModel.errorMessage = "Could not archive ticket."
            ticketPendingArchive = nil
        }
    }

    private func remove(_ ticket: SupportTicket) async {
        do {
            try await supportViewModel.deleteTicket(id: ticket.id, hard: false)
            ticketPendingRemove = nil
        } catch {
            supportViewModel.errorMessage = "Could not remove ticket."
            ticketPendingRemove = nil
        }
    }
}
