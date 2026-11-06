//
//  CopyButton.swift
//  ClaudeHUD
//
//  Universal 1-Click Copy Button with Visual Feedback
//  Copies any text, command, path, or question directly to macOS NSPasteboard.
//

import SwiftUI
import AppKit

public enum ClipboardHelper {
    public static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

public struct CopyButton: View {
    public let textToCopy: String
    public var label: String?
    
    @State private var isCopied: Bool = false
    @State private var isHovered: Bool = false
    
    public init(_ textToCopy: String, label: String? = nil) {
        self.textToCopy = textToCopy
        self.label = label
    }
    
    public var body: some View {
        Button(action: {
            ClipboardHelper.copy(textToCopy)
            withAnimation(ClaudeHUDTheme.snappySpring) {
                isCopied = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                withAnimation(ClaudeHUDTheme.fluidSpring) {
                    isCopied = false
                }
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 9, weight: .bold))
                
                if isCopied {
                    Text("Copied!")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                } else if let label = label {
                    Text(label)
                        .font(.system(size: 10, weight: .medium))
                }
            }
            .foregroundColor(isCopied ? ClaudeHUDTheme.emerald : (isHovered ? ClaudeHUDTheme.creamText : ClaudeHUDTheme.secondaryText))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(
                        isCopied
                        ? ClaudeHUDTheme.emerald.opacity(0.20)
                        : (isHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.05))
                    )
            )
            .overlay(
                Capsule()
                    .stroke(
                        isCopied
                        ? ClaudeHUDTheme.emerald.opacity(0.50)
                        : Color.white.opacity(isHovered ? 0.20 : 0.08),
                        lineWidth: 0.8
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Click to copy to clipboard")
    }
}
