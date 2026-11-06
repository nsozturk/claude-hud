//
//  SessionAskCardView.swift
//  ClaudeHUD
//
//  A Claude desktop session is waiting in its next-step box. Its buttons type the chosen
//  label into that session's own reply box (the person's click, sent as their message);
//  "Open" just opens the session.
//

import AppKit
import SwiftUI

public struct SessionAskCardView: View {
    @Environment(\.hudHandlesHotkeys) private var handlesHotkeys
    public let ask: SessionAsk
    public var onAnswer: (String) -> Void
    @ObservedObject private var settings = HUDSettingsStore.shared
    @State private var reply = ""
    @State private var dropTargeted = false
    public var onOpen: () -> Void
    public var onDismiss: () -> Void

    public init(ask: SessionAsk, onAnswer: @escaping (String) -> Void, onOpen: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.ask = ask
        self.onAnswer = onAnswer
        self.onOpen = onOpen
        self.onDismiss = onDismiss
    }

    private func sendReply() {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        onAnswer(text)
        reply = ""
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.exclamationmark.bubble.right.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(ClaudeHUDTheme.amber)
                Text(ask.sessionTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(ClaudeHUDTheme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Text("waiting for you")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(ClaudeHUDTheme.amber.opacity(0.9))
            }

            Text(ask.question)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ClaudeHUDTheme.creamText)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if !ask.recap.isEmpty {
                Text(ask.recap)
                    .font(.system(size: 11))
                    .foregroundColor(ClaudeHUDTheme.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if settings.replyBox {
                // Free-text reply (typed, dictated, or with dropped file paths), sent like a button.
                HUDReplyField(text: $reply, onSubmit: sendReply)
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(dropTargeted ? ClaudeHUDTheme.terracotta : .clear, lineWidth: 1.5))
            }

            HStack(spacing: 8) {
                Button("Later", action: onDismiss)
                    .buttonStyle(HUDSecondaryButtonStyle())
                Spacer(minLength: 4)
                ForEach(Array(ask.actions.prefix(2).enumerated()), id: \.offset) { idx, label in
                    Button(label) { onAnswer(label) }
                        .buttonStyle(HUDSecondaryButtonStyle(prominent: idx == 0))
                        .help("Send \"\(label)\" to this session in Claude")
                }
                Button(action: onOpen) {
                    HStack(spacing: 4) {
                        Text("Open")
                        Image(systemName: "arrow.up.forward.app")
                    }
                }
                .buttonStyle(HUDSecondaryButtonStyle(prominent: ask.actions.isEmpty))
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(14)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard settings.fileDropPaths, settings.replyBox else { return false }
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let path = url?.path else { return }
                    DispatchQueue.main.async { reply += (reply.isEmpty || reply.hasSuffix(" ") ? "" : " ") + path }
                }
            }
            return true
        }
        .onReceive(HUDHotkeys.shared.actions) { action in
            guard handlesHotkeys else { return }
            switch action {
            case .pick(let n) where n <= min(ask.actions.count, 2): onAnswer(ask.actions[n - 1])
            case .submit: if let first = ask.actions.first { onAnswer(first) } else { onOpen() }
            case .open: onOpen()
            default: break
            }
        }
    }
}

struct HUDSecondaryButtonStyle: ButtonStyle {
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: prominent ? .bold : .medium))
            .lineLimit(1)
            .foregroundColor(prominent ? ClaudeHUDTheme.creamText : ClaudeHUDTheme.secondaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(prominent ? ClaudeHUDTheme.terracotta.opacity(configuration.isPressed ? 0.7 : 0.9)
                                    : Color.white.opacity(configuration.isPressed ? 0.12 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
            )
    }
}
