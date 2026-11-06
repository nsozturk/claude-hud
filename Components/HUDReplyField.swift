//
//  HUDReplyField.swift
//  ClaudeHUD
//
//  The free-text answer box used by "Other" on question cards and by session cards:
//  type, or press the mic to start macOS Dictation (its own floating mic window appears when
//  Dictation is on in System Settings → Keyboard). ↵ sends.
//

import AppKit
import SwiftUI

struct HUDReplyField: View {
    var placeholder: String = "Reply…"
    @Binding var text: String
    var showsSend: Bool = true
    var autoFocus: Bool = false
    var onSubmit: () -> Void

    @FocusState private var focused: Bool
    @Environment(\.hudHandlesHotkeys) private var inLivePanel
    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(ClaudeHUDTheme.creamText)
                .lineLimit(1...4)
                .focused($focused)
                .onSubmit { if !isEmpty { onSubmit() } }
            Button(action: dictate) {
                Image(systemName: "mic.fill").font(.system(size: 11))
                    .foregroundColor(ClaudeHUDTheme.secondaryText)
            }
            .buttonStyle(.plain)
            .help("Dictate (uses macOS Dictation)")
            if showsSend {
                Button(action: onSubmit) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 16))
                        .foregroundColor(isEmpty ? ClaudeHUDTheme.subtleText : ClaudeHUDTheme.terracottaGlow)
                }
                .buttonStyle(.plain)
                .disabled(isEmpty)
                .help("Send")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.black.opacity(0.35)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .stroke(focused ? ClaudeHUDTheme.terracotta.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 0.8))
        .onAppear { if autoFocus { takeFocus() } }
    }

    /// The panel never takes focus by itself; typing and Dictation need it to be the key window.
    private func takeFocus() {
        if inLivePanel {
            NSApp.activate()
            LiveNotchPanelController.shared.focusPanel()
        }
        DispatchQueue.main.async { focused = true }
    }

    private func dictate() {
        takeFocus()
        // Same as Edit ▸ Start Dictation; macOS shows its own mic window, or a note if Dictation is off.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.sendAction(Selector(("startDictation:")), to: nil, from: nil)
        }
    }
}
