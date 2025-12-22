//
//  AppNotificationCenter.swift
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
import Observation
import SkipFuse

@MainActor
@Observable
final class AppNotificationCenter {
    var isPresented: Bool = false
    var message: String = ""
    var iconSystemName: String? = nil
    var duration: TimeInterval = 3.0
    
    private var dismissTask: Task<Void, Never>? = nil
    private let maxQueueSize: Int = 8
    private struct Banner: Sendable {
        let message: String
        let iconSystemName: String?
        let duration: TimeInterval
    }
    private var queue: [Banner] = []
    
    func show(_ message: String, iconSystemName: String? = nil, duration: TimeInterval = 3.0) {
        let normalized = AppNotificationCenter.compact(message)
        let banner = Banner(message: normalized, iconSystemName: iconSystemName, duration: duration)
        if isPresented {
            if queue.count < maxQueueSize {
                queue.append(banner)
            }
            return
        }
        present(banner)
    }
    
    func hide() {
        self.isPresented = false
        self.message = ""
        self.iconSystemName = nil
        dismissTask?.cancel()
        dismissTask = nil
        // Present next queued banner after the fade-out transition completes
        // Matches the 0.2s animation duration used by the banner view
        let nextBanner: Banner? = queue.first
        if nextBanner != nil {
            queue.removeFirst()
            let delayNanoseconds: UInt64 = 220_000_000 // 0.22s to ensure animation completes
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: delayNanoseconds)
                await MainActor.run {
                    guard let self else { return }
                    if let bannerToPresent = nextBanner, self.isPresented == false {
                        self.present(bannerToPresent)
                    }
                }
            }
        }
    }
    
    private func scheduleAutoDismiss() {
        dismissTask?.cancel()
        let seconds = duration
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.hide()
            }
        }
    }
    
    private func present(_ banner: Banner) {
        self.message = banner.message
        self.iconSystemName = banner.iconSystemName
        self.duration = banner.duration
        self.isPresented = true
        scheduleAutoDismiss()
    }

    func reset() {
        dismissTask?.cancel()
        dismissTask = nil
        queue.removeAll()
        isPresented = false
        message = ""
        iconSystemName = nil
    }

    private static func compact(_ message: String) -> String {
        // Collapse whitespace/newlines and hard-cap length to reduce CA commit size
        let singleLine = message.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let trimmed = singleLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(160))
    }
}


