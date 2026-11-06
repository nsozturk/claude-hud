//
//  PlanChecklistView.swift
//  ClaudeHUD
//
//  Turn Plan & Milestone Checklist Card
//  Displays real-time step checklist for Claude's update_plan tool call.
//

import SwiftUI

public struct PlanChecklistView: View {
    public let plan: PlanChecklistData
    public let displayPosition: HUDDisplayPosition
    public var onApprove: () -> Void
    public var onModify: () -> Void
    
    @State private var isApproveHovered: Bool = false
    @State private var isModifyHovered: Bool = false
    
    public init(
        plan: PlanChecklistData,
        displayPosition: HUDDisplayPosition = .notch,
        onApprove: @escaping () -> Void,
        onModify: @escaping () -> Void
    ) {
        self.plan = plan
        self.displayPosition = displayPosition
        self.onApprove = onApprove
        self.onModify = onModify
    }
    
    private var fullPlanText: String {
        plan.steps.map { "\($0.index). [\($0.status.rawValue)] \($0.title)" }.joined(separator: "\n")
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: - Header
            HStack(spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "list.clipboard.fill")
                        .font(.system(size: 10))
                        .foregroundColor(ClaudeHUDTheme.terracottaGlow)
                    
                    Text("PLAN UPDATE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(ClaudeHUDTheme.terracottaGlow)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(ClaudeHUDTheme.terracotta.opacity(0.18)))
                
                Spacer()
                
                CopyButton(fullPlanText, label: "Copy Plan")
            }
            
            // MARK: - Plan Title
            Text(plan.planTitle)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(ClaudeHUDTheme.creamText)
                .textSelection(.enabled)
                .padding(.horizontal, 2)
            
            // MARK: - Steps Checklist
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(plan.steps) { step in
                        PlanStepRow(step: step)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .frame(maxHeight: 220)
            .background(Color.black.opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
            )
            
            // MARK: - Action Buttons
            HStack(spacing: 10) {
                Spacer()
                
                // Modify Button
                Button(action: onModify) {
                    Text("Request Changes")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isModifyHovered ? ClaudeHUDTheme.creamText : ClaudeHUDTheme.secondaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isModifyHovered ? Color.white.opacity(0.10) : Color.white.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)
                .onHover { isModifyHovered = $0 }
                
                // Approve Plan Button
                Button(action: onApprove) {
                    HStack(spacing: 5) {
                        Text("Approve Plan")
                            .font(.system(size: 12, weight: .bold))
                        
                        HStack(spacing: 2) {
                            Text("⌘")
                                .font(.system(size: 10, weight: .bold))
                            Image(systemName: "return")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundColor(ClaudeHUDTheme.creamText.opacity(0.8))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.white.opacity(0.18))
                        )
                    }
                    .foregroundColor(ClaudeHUDTheme.creamText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [ClaudeHUDTheme.terracottaGlow, ClaudeHUDTheme.terracotta],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.40), lineWidth: 0.8)
                    )
                    .shadow(
                        color: ClaudeHUDTheme.terracotta.opacity(isApproveHovered ? 0.45 : 0.20),
                        radius: 8,
                        y: 3
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .onHover { isApproveHovered = $0 }
                .scaleEffect(isApproveHovered ? 1.02 : 1.0)
                .animation(ClaudeHUDTheme.snappySpring, value: isApproveHovered)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .liquidGlass(cornerRadius: displayPosition == .notch ? 22 : 18, isHovered: false)
    }
}

// MARK: - Step Row

private struct PlanStepRow: View {
    let step: PlanStepItem
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Status Icon
            ZStack {
                switch step.status {
                case .completed:
                    Circle()
                        .fill(ClaudeHUDTheme.emerald.opacity(0.25))
                        .frame(width: 18, height: 18)
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(ClaudeHUDTheme.emerald)
                    
                case .active:
                    Circle()
                        .fill(ClaudeHUDTheme.terracotta.opacity(0.25))
                        .frame(width: 18, height: 18)
                    Image(systemName: "play.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(ClaudeHUDTheme.terracottaGlow)
                    
                case .pending:
                    Circle()
                        .stroke(Color.white.opacity(0.25), lineWidth: 1.2)
                        .frame(width: 18, height: 18)
                    Text("\(step.index)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(ClaudeHUDTheme.subtleText)
                }
            }
            .padding(.top, 1)
            
            // Step Title
            Text(step.title)
                .font(.system(size: 11, weight: step.status == .active ? .bold : .medium))
                .foregroundColor(step.status == .completed ? ClaudeHUDTheme.secondaryText : ClaudeHUDTheme.creamText)
                .strikethrough(step.status == .completed, color: ClaudeHUDTheme.subtleText)
                .lineLimit(2)
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            step.status == .active
            ? ClaudeHUDTheme.terracotta.opacity(0.10)
            : Color.clear
        )
        .cornerRadius(6)
    }
}
