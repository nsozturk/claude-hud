//
//  PermissionApprovalView.swift
//  ClaudeHUD
//
//  Command Execution Approval View
//  Direct implementation of Claude Desktop's Permission Dialog:
//  - "Needs your input" pulsating amber indicator
//  - "Allow Claude to run this command?" heading
//  - Classifier risk reason ("Contains brace with quote character...")
//  - Scrollable dark syntax-colored code block with custom scrollbar
//  - "Deny" & "Allow once ⌘↵" action buttons
//

import SwiftUI

public struct PermissionApprovalView: View {
    public let permission: ToolPermission
    public let displayPosition: HUDDisplayPosition
    public var onAllow: () -> Void
    public var onAlwaysAllow: () -> Void
    public var onDeny: () -> Void
    
    @State private var isAllowHovered: Bool = false
    @State private var isDenyHovered: Bool = false
    @State private var isCopied: Bool = false
    
    public init(
        permission: ToolPermission,
        displayPosition: HUDDisplayPosition = .notch,
        onAllow: @escaping () -> Void,
        onAlwaysAllow: @escaping () -> Void,
        onDeny: @escaping () -> Void
    ) {
        self.permission = permission
        self.displayPosition = displayPosition
        self.onAllow = onAllow
        self.onAlwaysAllow = onAlwaysAllow
        self.onDeny = onDeny
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: - Top Status Indicator: "Needs your input"
            HStack(spacing: 6) {
                // Amber Bullseye/Pulsing Dot
                ZStack {
                    Circle()
                        .stroke(ClaudeHUDTheme.amber.opacity(0.6), lineWidth: 1.5)
                        .frame(width: 13, height: 13)
                    
                    Circle()
                        .fill(ClaudeHUDTheme.amber)
                        .frame(width: 6, height: 6)
                }
                
                Text("Needs your input")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(ClaudeHUDTheme.amber)
                
                Spacer()
                
                // Working Directory Pill + Copy
                HStack(spacing: 5) {
                    Image(systemName: "folder")
                        .font(.system(size: 8))
                    Text(permission.workingDir)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                    CopyButton(permission.workingDir)
                }
                .foregroundColor(ClaudeHUDTheme.subtleText)
                .lineLimit(1)
            }
            .padding(.horizontal, 2)
            
            // MARK: - Heading & Classifier Warning Reason
            VStack(alignment: .leading, spacing: 4) {
                Text("Allow Claude to run this command?")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(ClaudeHUDTheme.creamText)
                    .textSelection(.enabled)
                
                if let reason = permission.reason, !reason.isEmpty {
                    Text(reason)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(ClaudeHUDTheme.secondaryText)
                        .lineLimit(2)
                        .textSelection(.enabled)
                } else if permission.isDestructive {
                    Text("Destructive command detected (requires explicit authorization)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(ClaudeHUDTheme.ruby)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 2)
            
            // MARK: - Scrollable Monospace Code Block
            VStack(spacing: 0) {
                // Code Box Header with 1-Click Copy Button
                HStack(spacing: 6) {
                    Text("COMMAND / SCRIPT")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(ClaudeHUDTheme.subtleText)
                    
                    Spacer()
                    
                    CopyButton(permission.command, label: "Copy Script")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.85))
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10))
                
                ScrollView(.vertical, showsIndicators: true) {
                    SyntaxHighlightedBashView(command: permission.command)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 220)
                .background(Color.black.opacity(0.70))
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                )
            }
            
            // MARK: - Action Buttons (Deny & Allow once ⌘↵)
            HStack(spacing: 10) {
                Spacer()
                
                // Deny Button
                Button(action: onDeny) {
                    Text("Deny")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isDenyHovered ? ClaudeHUDTheme.ruby : ClaudeHUDTheme.secondaryText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isDenyHovered ? ClaudeHUDTheme.ruby.opacity(0.15) : Color.white.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(isDenyHovered ? ClaudeHUDTheme.ruby.opacity(0.35) : Color.white.opacity(0.10), lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)
                .onHover { isDenyHovered = $0 }

                // Adds Claude's own "always allow" rule for this call (only when Claude offered one).
                if permission.canAlwaysAllow {
                    Button("Always allow", action: onAlwaysAllow)
                        .buttonStyle(HUDSecondaryButtonStyle())
                        .help("Allow and add Claude's suggested permission rule")
                }

                // Allow Once (⌘↵) Primary Button
                Button(action: onAllow) {
                    HStack(spacing: 5) {
                        Text("Allow once")
                            .font(.system(size: 12, weight: .bold))
                        
                        // ⌘↵ Keyboard Badge
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
                            .stroke(Color.white.opacity(0.40), lineWidth: 0.8)
                    )
                    .shadow(
                        color: ClaudeHUDTheme.terracotta.opacity(isAllowHovered ? 0.50 : 0.25),
                        radius: 8,
                        y: 3
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .onHover { isAllowHovered = $0 }
                .scaleEffect(isAllowHovered ? 1.02 : 1.0)
                .animation(ClaudeHUDTheme.snappySpring, value: isAllowHovered)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .liquidGlass(cornerRadius: displayPosition == .notch ? 22 : 18, isHovered: false)
    }
}

// MARK: - Syntax Highlighted Monospace Bash Block

private struct SyntaxHighlightedBashView: View {
    let command: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(command.components(separatedBy: "\n").enumerated()), id: \.offset) { index, line in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if index == 0 && !line.trimmingCharacters(in: .whitespaces).hasPrefix("$") {
                        Text("$")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(ClaudeHUDTheme.terracottaGlow)
                    }
                    
                    highlightedLine(line)
                }
            }
        }
    }
    
    @ViewBuilder
    private func highlightedLine(_ line: String) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        if trimmed.hasPrefix("#") {
            // Comment
            Text(line)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundColor(ClaudeHUDTheme.subtleText)
        } else if trimmed.hasPrefix("python3") || trimmed.hasPrefix("curl") || trimmed.hasPrefix("while") || trimmed.hasPrefix("done") {
            // Keyword/CLI start
            Text(line)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(Color(red: 0.40, green: 0.75, blue: 0.98)) // Cyan/Blue
        } else if line.contains("=") && !line.contains("==") {
            // Variable assignment
            Text(line)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(Color(red: 0.50, green: 0.88, blue: 0.65)) // Soft Green
        } else {
            // Default code line
            Text(line)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(ClaudeHUDTheme.creamText)
        }
    }
}
