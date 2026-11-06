//
//  QueueIndicatorBadge.swift
//  ClaudeHUD
//
//  Notch Queue Indicator Badge & Stacked Card Depth Effect
//  Appears on the notch when multiple questions/approvals are lined up in queue.
//

import SwiftUI

public struct QueueIndicatorBadge: View {
    @ObservedObject var queueManager = HUDQueueManager.shared
    
    public init() {}
    
    public var body: some View {
        if queueManager.hasNext {
            HStack(spacing: 6) {
                // Stack Icon
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(ClaudeHUDTheme.terracottaGlow)
                
                // Position text
                Text("1 of \(queueManager.totalCount)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(ClaudeHUDTheme.creamText)
                
                Text("•")
                    .font(.system(size: 8))
                    .foregroundColor(ClaudeHUDTheme.subtleText)
                
                // Pending count pill
                Text("+\(queueManager.pendingBehindCount) in line")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(ClaudeHUDTheme.amber)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(ClaudeHUDTheme.amber.opacity(0.18)))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.75))
                    .overlay(
                        Capsule()
                            .stroke(ClaudeHUDTheme.terracotta.opacity(0.40), lineWidth: 0.8)
                    )
            )
            .shadow(color: ClaudeHUDTheme.terracotta.opacity(0.35), radius: 6, y: 2)
            .transition(.scale.combined(with: .opacity))
        }
    }
}

// MARK: - Stacked Card Depth Background (Cards peeking behind the active card)

public struct StackedCardDepthView: View {
    @ObservedObject var queueManager = HUDQueueManager.shared
    @ObservedObject var settings = HUDSettingsStore.shared
    
    public init() {}
    
    /// One layer per waiting card (up to 4), sharing `stackDepth` points below the card,
    /// so the stack shows how much is queued without growing down the screen.
    public var body: some View {
        let behind = queueManager.pendingBehindCount
        if settings.showQueueStackedDepth && behind > 0 {
            let layers = min(behind, 4)
            let step = settings.stackDepth / Double(layers)
            let radius: CGFloat = settings.displayPosition == .notch ? 23 : 19
            ZStack {
                ForEach((1...layers).reversed(), id: \.self) { i in
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(ClaudeHUDTheme.darkCharcoal.opacity(1 - Double(i - 1) * 0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .stroke(i == 1 ? ClaudeHUDTheme.terracotta.opacity(0.25) : Color.white.opacity(0.08), lineWidth: 0.8)
                        )
                        // Width only: a uniform scale would pull the bottom edge back up under the card.
                        .scaleEffect(x: 1 - 0.045 * CGFloat(i), y: 1)
                        .offset(y: CGFloat(step) * CGFloat(i))
                }
            }
            .animation(ClaudeHUDTheme.fluidSpring, value: layers)
        }
    }
}
