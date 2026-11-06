//
//  FileDiffApprovalView.swift
//  ClaudeHUD
//
//  File Modification & Diff Approval Card
//  Displays line-by-line syntax diff (additions & deletions) with 1-click Apply.
//

import SwiftUI

public struct FileDiffApprovalView: View {
    public let diff: FileDiffData
    public let displayPosition: HUDDisplayPosition
    public var onApply: () -> Void
    public var onReject: () -> Void
    
    @State private var isApplyHovered: Bool = false
    @State private var isRejectHovered: Bool = false
    
    public init(
        diff: FileDiffData,
        displayPosition: HUDDisplayPosition = .notch,
        onApply: @escaping () -> Void,
        onReject: @escaping () -> Void
    ) {
        self.diff = diff
        self.displayPosition = displayPosition
        self.onApply = onApply
        self.onReject = onReject
    }
    
    private var fullDiffString: String {
        diff.lines.map { line in
            let prefix = line.type == .addition ? "+ " : (line.type == .deletion ? "- " : "  ")
            return prefix + line.text
        }.joined(separator: "\n")
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: - Header: File Path & Diff Stats
            HStack(spacing: 8) {
                // File Type Badge
                HStack(spacing: 4) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 9))
                    Text(diff.filePath)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .lineLimit(1)
                }
                .foregroundColor(ClaudeHUDTheme.creamText)
                
                // Additions / Deletions Stats
                HStack(spacing: 4) {
                    Text("+\(diff.additionsCount)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(ClaudeHUDTheme.emerald)
                    
                    Text("-\(diff.deletionsCount)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(ClaudeHUDTheme.ruby)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.06)))
                
                Spacer()
                
                CopyButton(fullDiffString, label: "Copy Diff")
            }
            .padding(.horizontal, 2)
            
            // MARK: - Subheader
            Text("Allow Claude to edit this file?")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(ClaudeHUDTheme.creamText)
                .padding(.horizontal, 2)
            
            // MARK: - Scrollable Line-by-Line Diff View
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(diff.lines) { line in
                        DiffLineRow(line: line)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .frame(maxHeight: 220)
            .background(Color.black.opacity(0.75))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
            )
            
            // MARK: - Action Buttons
            HStack(spacing: 10) {
                Spacer()
                
                // Reject Button
                Button(action: onReject) {
                    Text("Reject")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isRejectHovered ? ClaudeHUDTheme.ruby : ClaudeHUDTheme.secondaryText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isRejectHovered ? ClaudeHUDTheme.ruby.opacity(0.15) : Color.white.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(isRejectHovered ? ClaudeHUDTheme.ruby.opacity(0.35) : Color.white.opacity(0.10), lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)
                .onHover { isRejectHovered = $0 }
                
                // Apply Diff Button
                Button(action: onApply) {
                    HStack(spacing: 5) {
                        Text("Apply Diff")
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
                                    colors: [ClaudeHUDTheme.emerald, Color(red: 0.12, green: 0.60, blue: 0.40)],
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
                        color: ClaudeHUDTheme.emerald.opacity(isApplyHovered ? 0.45 : 0.20),
                        radius: 8,
                        y: 3
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .onHover { isApplyHovered = $0 }
                .scaleEffect(isApplyHovered ? 1.02 : 1.0)
                .animation(ClaudeHUDTheme.snappySpring, value: isApplyHovered)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .liquidGlass(cornerRadius: displayPosition == .notch ? 22 : 18, isHovered: false)
    }
}

// MARK: - Diff Line Row

private struct DiffLineRow: View {
    let line: DiffLine
    
    var body: some View {
        HStack(spacing: 6) {
            // Diff Indicator (+ / - / space)
            Text(prefixSymbol)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(symbolColor)
                .frame(width: 12, alignment: .center)
            
            // Text Content
            Text(line.text)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(textColor)
                .lineLimit(1)
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(rowBackground)
        .cornerRadius(3)
    }
    
    private var prefixSymbol: String {
        switch line.type {
        case .addition: return "+"
        case .deletion: return "-"
        case .context: return " "
        }
    }
    
    private var symbolColor: Color {
        switch line.type {
        case .addition: return ClaudeHUDTheme.emerald
        case .deletion: return ClaudeHUDTheme.ruby
        case .context: return ClaudeHUDTheme.subtleText
        }
    }
    
    private var textColor: Color {
        switch line.type {
        case .addition: return Color(red: 0.65, green: 0.95, blue: 0.75)
        case .deletion: return Color(red: 0.98, green: 0.65, blue: 0.65)
        case .context: return ClaudeHUDTheme.secondaryText
        }
    }
    
    private var rowBackground: Color {
        switch line.type {
        case .addition: return ClaudeHUDTheme.emerald.opacity(0.12)
        case .deletion: return ClaudeHUDTheme.ruby.opacity(0.15)
        case .context: return Color.clear
        }
    }
}
