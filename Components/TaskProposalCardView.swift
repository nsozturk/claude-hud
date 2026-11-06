//
//  TaskProposalCardView.swift
//  ClaudeHUD
//
//  Task Suggestion Card View
//  Replicates and elevates Claude Desktop's interactive card:
//  - "New session" badge
//  - Title & TLDR Brief
//  - "Do it here" (current turn) vs "Start" (spawn child session) buttons
//  - "Received message from <Session>" footnote badge
//

import SwiftUI

public struct TaskProposalCardView: View {
    public let task: TaskProposal
    public let displayPosition: HUDDisplayPosition
    public var onDoItHere: () -> Void
    public var onStartNewSession: () -> Void
    public var onOptions: () -> Void
    public var onDismiss: () -> Void
    
    @State private var isDoItHereHovered: Bool = false
    @State private var isStartHovered: Bool = false
    @State private var isDismissHovered: Bool = false
    
    public init(
        task: TaskProposal,
        displayPosition: HUDDisplayPosition = .notch,
        onDoItHere: @escaping () -> Void,
        onStartNewSession: @escaping () -> Void,
        onOptions: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.task = task
        self.displayPosition = displayPosition
        self.onDoItHere = onDoItHere
        self.onStartNewSession = onStartNewSession
        self.onOptions = onOptions
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // MARK: - Header: "New session" & Close Button
            HStack(spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(ClaudeHUDTheme.terracottaGlow)
                    
                    Text("New session")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(ClaudeHUDTheme.secondaryText)
                }
                
                Spacer()
                
                // Dismiss 'X'
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(isDismissHovered ? ClaudeHUDTheme.creamText : ClaudeHUDTheme.subtleText)
                        .padding(4)
                        .background(
                            Circle()
                                .fill(isDismissHovered ? Color.white.opacity(0.12) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .onHover { isDismissHovered = $0 }
            }
            
            // MARK: - Title
            Text(task.title)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(ClaudeHUDTheme.creamText)
                .lineLimit(1)
                .textSelection(.enabled)
            
            // MARK: - TLDR Body
            Text(task.tldr)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(ClaudeHUDTheme.secondaryText)
                .lineLimit(3)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            
            // MARK: - Action Buttons
            HStack(spacing: 8) {
                // Left: Options & Copy
                Button(action: onOptions) {
                    Text("Options")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(ClaudeHUDTheme.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)
                
                CopyButton(task.prompt.isEmpty ? task.tldr : task.prompt, label: "Copy Prompt")
                
                Spacer()
                
                // "Do it here" Button (Inject into current session)
                Button(action: onDoItHere) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 9, weight: .bold))
                        Text("Do it here")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(isDoItHereHovered ? ClaudeHUDTheme.creamText : ClaudeHUDTheme.creamText.opacity(0.9))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                isDoItHereHovered
                                ? ClaudeHUDTheme.terracotta.opacity(0.25)
                                : Color.white.opacity(0.08)
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(
                                isDoItHereHovered
                                ? ClaudeHUDTheme.terracotta.opacity(0.6)
                                : Color.white.opacity(0.12),
                                lineWidth: 0.8
                            )
                    )
                }
                .buttonStyle(.plain)
                .onHover { isDoItHereHovered = $0 }
                .scaleEffect(isDoItHereHovered ? 1.02 : 1.0)
                .animation(ClaudeHUDTheme.snappySpring, value: isDoItHereHovered)
                
                // "Start" Button (Spawn new session worktree)
                Button(action: onStartNewSession) {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 8, weight: .bold))
                        Text("Start")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(ClaudeHUDTheme.creamText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        ClaudeHUDTheme.terracottaGlow,
                                        ClaudeHUDTheme.terracotta
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.35), lineWidth: 0.8)
                    )
                    .shadow(
                        color: ClaudeHUDTheme.terracotta.opacity(isStartHovered ? 0.45 : 0.20),
                        radius: 8,
                        y: 3
                    )
                }
                .buttonStyle(.plain)
                .onHover { isStartHovered = $0 }
                .scaleEffect(isStartHovered ? 1.03 : 1.0)
                .animation(ClaudeHUDTheme.snappySpring, value: isStartHovered)
            }
            .padding(.top, 2)
            
            // MARK: - Footnote: "Received message from <Session>"
            HStack(spacing: 4) {
                Text("Received message from")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(ClaudeHUDTheme.subtleText)
                
                HStack(spacing: 3) {
                    Text(task.parentSessionName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(ClaudeHUDTheme.creamText.opacity(0.85))
                        .underline()
                    
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(ClaudeHUDTheme.terracottaGlow)
                }
            }
            .padding(.top, 4)
        }
        .padding(14)
        .liquidGlass(cornerRadius: displayPosition == .notch ? 22 : 18, isHovered: false)
    }
}
