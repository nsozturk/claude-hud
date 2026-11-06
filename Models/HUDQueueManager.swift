//
//  HUDQueueManager.swift
//  ClaudeHUD
//
//  FIFO Event Queue Manager
//  Handles arrival order of multiple questions, approvals, and task cards.
//  Provides seamless auto-advancement and live queue metrics.
//

import AppKit
import SwiftUI
import Combine

@MainActor
public class HUDQueueManager: ObservableObject {
    public static let shared = HUDQueueManager()
    
    @Published public var queue: [HUDNotificationEvent] = []
    @Published public var completedHistory: [HUDNotificationEvent] = []
    
    /// Cards put up by the settings window's test scenarios; a real arrival replaces them.
    private var scenarioIds: Set<String> = []

    public init() {}
    
    /// The currently active card at the front of the queue
    public var currentEvent: HUDNotificationEvent? {
        queue.first
    }
    
    /// Total events waiting including current
    public var totalCount: Int {
        queue.count
    }
    
    /// Additional events waiting behind the current one
    public var pendingBehindCount: Int {
        max(0, queue.count - 1)
    }
    
    /// Whether there are more events waiting in queue
    public var hasNext: Bool {
        queue.count > 1
    }
    
    // MARK: - Queue Actions
    
    public func enqueue(_ event: HUDNotificationEvent) {
        guard !queue.contains(where: { $0.sourceId == event.sourceId }) else { return }
        hudLog("📥 HUDQueueManager.enqueue: \(event.title) (Total will be: \(queue.count + 1))", category: "QUEUE")
        withAnimation(ClaudeHUDTheme.fluidSpring) {
            dropScenarios()
            queue.append(event)
        }
        HUDQuiet.playArrivalSound(for: event)
    }
    
    public func enqueueBatch(_ events: [HUDNotificationEvent]) {
        hudLog("📥 HUDQueueManager.enqueueBatch: \(events.count) events (Total will be: \(queue.count + events.count))", category: "QUEUE")
        withAnimation(ClaudeHUDTheme.fluidSpring) {
            dropScenarios()
            queue.append(contentsOf: events)
        }
    }
    
    /// Resolves the current event and automatically pops the next one to the front
    public func resolveCurrent() {
        guard !queue.isEmpty else { return }
        hudLog("✅ HUDQueueManager.resolveCurrent: popped '\(queue.first?.title ?? "")'", category: "QUEUE")
        withAnimation(ClaudeHUDTheme.fluidSpring) {
            let removed = queue.removeFirst()
            completedHistory.insert(removed, at: 0)
        }
    }
    
    /// Removes one card by its source id (the AskUserQuestion tool_use_id).
    public func remove(id: String) {
        guard queue.contains(where: { $0.sourceId == id }) else { return }
        hudLog("🧹 HUDQueueManager.remove: \(id)", category: "QUEUE")
        withAnimation(ClaudeHUDTheme.fluidSpring) {
            queue.removeAll { $0.sourceId == id }
        }
    }

    /// Test scenarios from the settings window: put the cards at the FRONT of the live queue
    /// (so they appear in the notch / top-right right away) without dropping real waiting cards.
    public func showNow(_ events: [HUDNotificationEvent]) {
        let ids = Set(events.map(\.sourceId))
        hudLog("🧪 HUDQueueManager.showNow: \(events.map(\.title))", category: "QUEUE")
        withAnimation(ClaudeHUDTheme.fluidSpring) {
            queue.removeAll { ids.contains($0.sourceId) }
            queue.insert(contentsOf: events, at: 0)
        }
        scenarioIds.formUnion(ids)
    }

    private func dropScenarios() {
        guard !scenarioIds.isEmpty else { return }
        hudLog("🧪 Real event arrived — removing test scenario cards", category: "QUEUE")
        queue.removeAll { scenarioIds.contains($0.sourceId) }
        scenarioIds.removeAll()
    }

    public func remove(ids: Set<String>) {
        withAnimation(ClaudeHUDTheme.fluidSpring) { queue.removeAll { ids.contains($0.sourceId) } }
    }

    /// Move the front card to the back, so the next one shows (swipe right / ⌃⌥→).
    public func rotate() {
        guard queue.count > 1 else { return }
        withAnimation(ClaudeHUDTheme.fluidSpring) { queue.append(queue.removeFirst()) }
    }

    /// Clears all pending events
    public func clearAll() {
        hudLog("🗑️ HUDQueueManager.clearAll: cleared \(queue.count) events", category: "QUEUE")
        withAnimation(ClaudeHUDTheme.fluidSpring) {
            queue.removeAll()
        }
    }
}
