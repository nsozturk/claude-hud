//
//  HUDOnboarding.swift
//  ClaudeHUD
//
//  First-launch walkthrough: what the HUD does, where it sits, the AskUserQuestion hook,
//  and the Accessibility permission the next-step buttons need. Shown once; reopen from the menu.
//

import AppKit
import ApplicationServices
import SwiftUI

@MainActor
public final class HUDOnboardingController {
    public static let shared = HUDOnboardingController()
    private static let doneKey = "onboardingDone.v1"
    private var window: NSWindow?

    public var isDone: Bool { UserDefaults.standard.bool(forKey: Self.doneKey) }

    public func showIfNeeded() { if !isDone { show() } }

    public func show() {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 470),
                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: HUDOnboardingView(onFinish: { [weak self] in self?.finish() }))
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate()
        hudLog("👋 Onboarding shown", category: "APP")
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        window?.close()
        window = nil
        hudLog("✅ Onboarding finished", category: "APP")
    }
}

// MARK: - Hook install (~/.claude/settings.json)

enum HUDHookInstaller {
    static var settingsURL: URL { URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/settings.json") }

    /// The hook ships inside the app; a dev build run from the repo falls back to bin/.
    static var hookPath: String? {
        if let p = Bundle.main.path(forResource: "claude-hud-hook", ofType: nil) { return p }
        let dev = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("bin/claude-hud-hook").path
        return FileManager.default.isExecutableFile(atPath: dev) ? dev : nil
    }

    /// One hook entry per event: the AskUserQuestion PreToolUse hook and the PermissionRequest hook.
    enum Kind { case questions, permissions
        var event: String { self == .questions ? "PreToolUse" : "PermissionRequest" }
        var matcher: String { self == .questions ? "AskUserQuestion" : "*" }
    }

    static func isInstalled(_ kind: Kind) -> Bool {
        guard let data = try? Data(contentsOf: settingsURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = (root["hooks"] as? [String: Any])?[kind.event] as? [[String: Any]] else { return false }
        return entries.contains { e in
            ((e["hooks"] as? [[String: Any]]) ?? []).contains { ($0["command"] as? String)?.contains("claude-hud-hook") == true }
        }
    }

    static var isInstalled: Bool { isInstalled(.questions) }

    /// Adds the missing hook entries. Keeps a .bak copy; leaves every other key alone.
    static func install(_ kinds: [Kind] = [.questions]) throws {
        guard let hook = hookPath else { throw NSError(domain: "HUD", code: 1, userInfo: [NSLocalizedDescriptionKey: "Hook script not found in the app bundle"]) }
        let missing = kinds.filter { !isInstalled($0) }
        guard !missing.isEmpty else { return }
        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL) {
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NSError(domain: "HUD", code: 2, userInfo: [NSLocalizedDescriptionKey: "settings.json is not a JSON object"])
            }
            root = obj
            try? FileManager.default.removeItem(at: settingsURL.appendingPathExtension("bak"))
            try FileManager.default.copyItem(at: settingsURL, to: settingsURL.appendingPathExtension("bak"))
        }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for kind in missing {
            var list = hooks[kind.event] as? [[String: Any]] ?? []
            list.append(["matcher": kind.matcher, "hooks": [["type": "command", "command": hook, "timeout": 150]]])
            hooks[kind.event] = list
            hudLog("🪝 Installed \(kind.event) hook → \(hook)", category: "APP")
        }
        root["hooks"] = hooks
        try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try out.write(to: settingsURL, options: .atomic)
    }
}

// MARK: - View

struct HUDOnboardingView: View {
    var onFinish: () -> Void

    @ObservedObject private var settings = HUDSettingsStore.shared
    @State private var step = 0
    @State private var axGranted = AXIsProcessTrusted()
    @State private var hookInstalled = HUDHookInstaller.isInstalled
    @State private var hookError: String?
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let steps = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(ClaudeHUDTheme.terracotta).frame(width: 8, height: 8)
                Text("Claude HUD").font(.system(size: 12, weight: .semibold)).foregroundColor(ClaudeHUDTheme.secondaryText)
                Spacer()
                HStack(spacing: 5) {
                    ForEach(0..<steps, id: \.self) { i in
                        Capsule().fill(i == step ? ClaudeHUDTheme.terracotta : Color.white.opacity(0.15))
                            .frame(width: i == step ? 18 : 6, height: 6)
                    }
                }
            }
            .padding(.top, 6)

            Group {
                switch step {
                case 0: welcome
                case 1: position
                case 2: hook
                default: accessibility
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, 26)
            .transition(.opacity)

            HStack {
                if step > 0 {
                    Button("Back") { withAnimation(ClaudeHUDTheme.snappySpring) { step -= 1 } }
                        .buttonStyle(HUDSecondaryButtonStyle())
                }
                Spacer()
                if step == 3 && !axGranted {
                    Button("Skip for now", action: onFinish).buttonStyle(HUDSecondaryButtonStyle())
                }
                Button(step == steps - 1 ? "Done" : "Continue") {
                    if step == steps - 1 { onFinish() } else { withAnimation(ClaudeHUDTheme.snappySpring) { step += 1 } }
                }
                .buttonStyle(HUDSecondaryButtonStyle(prominent: true))
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 26)
        .frame(width: 560, height: 470)
        .background(
            ZStack {
                ClaudeHUDTheme.deepCanvas
                RadialGradient(colors: [ClaudeHUDTheme.terracotta.opacity(0.16), .clear],
                               center: .top, startRadius: 10, endRadius: 360)
            }
            .ignoresSafeArea()
        )
        .preferredColorScheme(.dark)
        .onReceive(poll) { _ in
            axGranted = AXIsProcessTrusted()
            hookInstalled = HUDHookInstaller.isInstalled
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("Answer Claude without switching windows")
            para("When a Claude Code session stops to ask you something, a card drops out of the notch with the question and its choices. Pick an answer there and keep working.")
            miniCard
                .padding(.top, 6)
        }
    }

    private var position: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("Where should cards appear?")
            para("You can change this any time from the menu bar.")
            HStack(spacing: 12) {
                positionTile(.notch, icon: "macbook", name: "Notch", note: "Grows out of the MacBook notch")
                positionTile(.topRight, icon: "rectangle.inset.topright.filled", name: "Top right", note: "Floats on your main display")
            }
        }
    }

    private var hook: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("Answer Claude's questions here")
            para("Claude Code asks multiple-choice questions through a hook. Installing it adds one entry to ~/.claude/settings.json (a .bak copy is kept). Your answer goes straight back to Claude. If the HUD is closed, Claude simply asks in its own window.")
            statusRow(ok: hookInstalled, okText: "Hook installed", waitText: "Hook not installed")
            if !hookInstalled {
                Button("Install hook") {
                    do { try HUDHookInstaller.install(); hookInstalled = HUDHookInstaller.isInstalled; hookError = nil }
                    catch { hookError = error.localizedDescription }
                }
                .buttonStyle(HUDSecondaryButtonStyle(prominent: true))
            }
            if let hookError {
                Text(hookError).font(.system(size: 11)).foregroundColor(ClaudeHUDTheme.ruby)
            }
        }
    }

    private var accessibility: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("Let card buttons reply for you")
            para("Claude's next-step box has no API, so to send a button's reply the HUD types it into that session's reply box and presses Send, exactly as you would. macOS calls this Accessibility. Without it, those buttons just open the session.")
            statusRow(ok: axGranted, okText: "Accessibility allowed", waitText: "Waiting for permission…")
            if !axGranted {
                VStack(alignment: .leading, spacing: 8) {
                    Button("Open Accessibility Settings") {
                        // The prompt option adds Claude HUD to the list, switch off, ready to flip.
                        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                        _ = AXIsProcessTrustedWithOptions(opts)
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                    .buttonStyle(HUDSecondaryButtonStyle(prominent: true))
                    Text("Turn on the switch next to Claude HUD. This page updates on its own.")
                        .font(.system(size: 11)).foregroundColor(ClaudeHUDTheme.subtleText)
                }
            }
        }
    }

    // MARK: Pieces

    private func title(_ s: String) -> some View {
        Text(s).font(.system(size: 22, weight: .bold)).foregroundColor(ClaudeHUDTheme.creamText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func para(_ s: String) -> some View {
        Text(s).font(.system(size: 13)).foregroundColor(ClaudeHUDTheme.secondaryText)
            .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
    }

    private func statusRow(ok: Bool, okText: String, waitText: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dotted")
                .foregroundColor(ok ? ClaudeHUDTheme.emerald : ClaudeHUDTheme.amber)
            Text(ok ? okText : waitText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(ok ? ClaudeHUDTheme.emerald : ClaudeHUDTheme.amber)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.05)))
        .animation(ClaudeHUDTheme.snappySpring, value: ok)
    }

    private func positionTile(_ pos: HUDDisplayPosition, icon: String, name: String, note: String) -> some View {
        let selected = settings.displayPosition == pos
        return Button { settings.displayPosition = pos } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).font(.system(size: 22)).foregroundColor(selected ? ClaudeHUDTheme.terracottaGlow : ClaudeHUDTheme.secondaryText)
                Text(name).font(.system(size: 13, weight: .semibold)).foregroundColor(ClaudeHUDTheme.creamText)
                Text(note).font(.system(size: 11)).foregroundColor(ClaudeHUDTheme.subtleText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(selected ? 0.07 : 0.03)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(selected ? ClaudeHUDTheme.terracotta : Color.white.opacity(0.1), lineWidth: selected ? 1.5 : 0.8))
        }
        .buttonStyle(.plain)
    }

    /// A static sketch of a card so the first screen shows what will appear.
    private var miniCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(ClaudeHUDTheme.terracotta).frame(width: 6, height: 6)
                Text("Claude").font(.system(size: 11, weight: .semibold)).foregroundColor(ClaudeHUDTheme.creamText)
                Spacer()
                Text("waiting for you").font(.system(size: 10, design: .monospaced)).foregroundColor(ClaudeHUDTheme.amber)
            }
            Text("Run the prod deploy now?").font(.system(size: 13, weight: .semibold)).foregroundColor(ClaudeHUDTheme.creamText)
            HStack(spacing: 8) {
                Spacer()
                Text("Not now").modifier(MiniButton(prominent: false))
                Text("Deploy").modifier(MiniButton(prominent: true))
            }
        }
        .padding(14)
        .frame(width: 320)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ClaudeHUDTheme.darkCharcoal))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 0.8))
        .shadow(color: ClaudeHUDTheme.terracotta.opacity(0.25), radius: 18, y: 6)
    }
}

private struct MiniButton: ViewModifier {
    var prominent: Bool
    func body(content: Content) -> some View {
        content.font(.system(size: 11, weight: prominent ? .bold : .medium))
            .foregroundColor(prominent ? ClaudeHUDTheme.creamText : ClaudeHUDTheme.secondaryText)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(prominent ? ClaudeHUDTheme.terracotta.opacity(0.9) : Color.white.opacity(0.06)))
    }
}
