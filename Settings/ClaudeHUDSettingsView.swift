//
//  ClaudeHUDSettingsView.swift
//  ClaudeHUD
//
//  Every setting in one scrolling column. Used as the main window's left sidebar and as the
//  standalone Settings window, so the first thing people see is what they can change.
//

import ApplicationServices
import SwiftUI

public struct ClaudeHUDSettingsView: View {
    @ObservedObject private var settings = HUDSettingsStore.shared
    @ObservedObject private var overlay = LiveNotchPanelController.shared
    @ObservedObject private var queue = HUDQueueManager.shared
    @State private var axGranted = AXIsProcessTrusted()
    @State private var hookInstalled = HUDHookInstaller.isInstalled
    @State private var hookError: String?
    @State private var permHookInstalled = HUDHookInstaller.isInstalled(.permissions)
    private let poll = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    public init() {}

    public var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape.fill").foregroundColor(ClaudeHUDTheme.terracottaGlow)
                    Text("Settings").font(.system(size: 15, weight: .bold)).foregroundColor(ClaudeHUDTheme.creamText)
                }
                .padding(.top, 4)

                section("Display", icon: "macwindow") {
                    Picker("", selection: $settings.displayPosition) {
                        Text("Notch").tag(HUDDisplayPosition.notch)
                        Text("Top right").tag(HUDDisplayPosition.topRight)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    toggle("Show in Dock", "Off: Claude HUD lives only in the menu bar.", isOn: $settings.showInDock)

                    toggle("Live panel", "Show cards on screen. Turn off to pause the HUD.",
                           isOn: Binding(get: { overlay.isOverlayActive },
                                         set: { $0 ? overlay.startOverlay() : overlay.stopOverlay() }))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            label("Notch offset")
                            Spacer()
                            Text(String(format: "%+.0f pt", settings.notchVerticalOffset))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(ClaudeHUDTheme.terracottaGlow)
                        }
                        Slider(value: $settings.notchVerticalOffset, in: -20...30, step: 1)
                        hint("0 puts the card right under the physical notch.")
                    }
                }

                section("Permissions", icon: "lock.shield") {
                    status(ok: hookInstalled, "Question hook", ok: "Installed", wait: "Not installed")
                    hint("Lets you answer Claude Code's multiple-choice questions from the HUD.")
                    if !hookInstalled {
                        Button("Install hook") {
                            do { try HUDHookInstaller.install(); hookError = nil } catch { hookError = error.localizedDescription }
                            hookInstalled = HUDHookInstaller.isInstalled
                        }
                        .buttonStyle(HUDSecondaryButtonStyle(prominent: true))
                    }
                    if let hookError { Text(hookError).font(.system(size: 10)).foregroundColor(ClaudeHUDTheme.ruby) }

                    toggle("Approve tool permissions here", "Allow / Always allow / Deny Claude's permission prompts from a card. No answer in 2 minutes: Claude asks as usual.",
                           isOn: $settings.approvePermissions)
                    if settings.approvePermissions {
                        status(ok: permHookInstalled, "Permission hook", ok: "Installed", wait: "Not installed")
                        if !permHookInstalled {
                            Button("Install permission hook") {
                                do { try HUDHookInstaller.install([.permissions]); hookError = nil } catch { hookError = error.localizedDescription }
                                permHookInstalled = HUDHookInstaller.isInstalled(.permissions)
                            }
                            .buttonStyle(HUDSecondaryButtonStyle(prominent: true))
                        }
                    }

                    status(ok: axGranted, "Accessibility", ok: "Allowed", wait: "Not allowed")
                    hint("Lets next-step card buttons type the reply into Claude and press Send.")
                    if !axGranted {
                        Button("Open Accessibility Settings") {
                            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                            _ = AXIsProcessTrustedWithOptions(opts)
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                        .buttonStyle(HUDSecondaryButtonStyle(prominent: true))
                    }
                    Button("Show welcome again") { HUDOnboardingController.shared.show() }
                        .buttonStyle(HUDSecondaryButtonStyle())
                }

                section("Cards & queue", icon: "square.stack.3d.up") {
                    toggle("Compact pill", "Show a waiting card as one line; hover or press a shortcut to open it.", isOn: $settings.compactCards)
                    toggle("Stacked depth", "Show card layers behind the current one when more are waiting.", isOn: $settings.showQueueStackedDepth)
                    tune("Stack depth", value: $settings.stackDepth, in: 6...24, format: { "\(Int($0)) pt" })
                    hint("One layer per waiting card, up to four, within this depth.")

                    HStack {
                        label("Card transition")
                        Spacer()
                        Button("Try it") { HUDTransitionDemo.run() }.buttonStyle(HUDSecondaryButtonStyle())
                    }
                    VStack(spacing: 2) {
                        ForEach(CardTransitionStyle.allCases) { style in
                            choice(style.rawValue, style.description, selected: settings.cardTransition == style) {
                                settings.cardTransition = style
                            }
                        }
                    }
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.35)))

                    toggle("Swipe gestures", "Two fingers on a card: swipe left to skip, right for the next card.", isOn: $settings.swipeGestures)
                    toggle("Haptics", "A trackpad tap when a swipe lands.", isOn: $settings.haptics)
                    toggle("Sounds", "Play a soft sound when a card arrives.", isOn: $settings.soundEnabled)
                    if settings.soundEnabled {
                        soundRow("Questions", $settings.soundQuestion)
                        soundRow("Permission prompts", $settings.soundPermission)
                        soundRow("Next-step asks", $settings.soundSession)
                        tune("Volume", value: $settings.soundVolume, in: 0...1, format: { "\(Int($0 * 100))%" })
                    }
                    HStack(spacing: 10) {
                        stat("Waiting", "\(queue.totalCount)", ClaudeHUDTheme.terracottaGlow)
                        stat("Answered", "\(queue.completedHistory.count)", ClaudeHUDTheme.emerald)
                    }
                }

                section("Quiet", icon: "moon.zzz") {
                    if settings.isSnoozed {
                        HStack {
                            label("Snoozed until \((settings.snoozeUntil ?? Date()).formatted(date: .omitted, time: .shortened))")
                            Spacer()
                            Button("Resume") { HUDQuiet.resume() }.buttonStyle(HUDSecondaryButtonStyle(prominent: true))
                        }
                    } else {
                        label("Snooze cards")
                        HStack(spacing: 6) {
                            Button("15 min") { HUDQuiet.snooze(minutes: 15) }.buttonStyle(HUDSecondaryButtonStyle())
                            Button("1 hour") { HUDQuiet.snooze(minutes: 60) }.buttonStyle(HUDSecondaryButtonStyle())
                            Button("Until tomorrow") { HUDQuiet.snoozeUntilTomorrow() }.buttonStyle(HUDSecondaryButtonStyle())
                        }
                        hint("Cards stay in the queue and come back when the snooze ends.")
                    }
                    toggle("Quiet during calls", "No sounds while the microphone is in use.", isOn: $settings.quietDuringCalls)
                    toggle("Hide from screen sharing", "Keep the panel out of screen shares and recordings.", isOn: $settings.hideFromScreenShare)
                }

                section("Replies", icon: "text.bubble") {
                    toggle("Reply box", "Type or dictate a free-text reply on session cards.", isOn: $settings.replyBox)
                    toggle("Drop files for paths", "Drop files on a card to add their paths to the reply.", isOn: $settings.fileDropPaths)
                }

                section("Scanner line", icon: "waveform.path.ecg") {
                    toggle("Scanner line", "A light that sweeps along the bottom edge of the card.", isOn: $settings.gitLineEnabled)
                    if settings.gitLineEnabled {
                        VStack { Spacer(); GitScannerLine() }
                            .frame(height: 34).frame(maxWidth: .infinity)
                            .background(Color.black.opacity(0.6)).cornerRadius(8)

                        HStack {
                            label("Pattern")
                            Spacer()
                            Text("\(GitLineStyle.allCases.count) patterns").font(.system(size: 10)).foregroundColor(ClaudeHUDTheme.subtleText)
                        }
                        // The pattern list scrolls inside its own box so the sidebar stays short.
                        ScrollView(.vertical, showsIndicators: true) {
                            VStack(spacing: 2) {
                                ForEach(GitLineStyle.allCases) { style in
                                    choice(style.rawValue, style.description, selected: settings.gitLineStyle == style) {
                                        settings.gitLineStyle = style
                                    }
                                }
                            }
                            .padding(4)
                        }
                        .frame(height: 190)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.35)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.06), lineWidth: 0.8))

                        label("Color")
                        FlowChips(items: GitLineColorTheme.presets, selected: settings.gitLineTheme) { settings.gitLineTheme = $0 }
                        HStack(spacing: 8) {
                            ColorPicker("Custom color", selection: Binding(
                                get: { settings.gitLineTheme.primaryColor },
                                set: { settings.gitLineTheme = .custom($0) }), supportsOpacity: false)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundColor(ClaudeHUDTheme.creamText)
                            Spacer()
                            Text(settings.gitLineTheme.hex)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(ClaudeHUDTheme.secondaryText)
                                .textSelection(.enabled)
                        }

                        HStack {
                            label("Speed"); Spacer()
                            Text(String(format: "%.1fx", settings.gitLineSpeed)).font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(ClaudeHUDTheme.secondaryText)
                        }
                        Slider(value: $settings.gitLineSpeed, in: 0.5...2.5, step: 0.1)
                        HStack {
                            label("Thickness"); Spacer()
                            Text("\(Int(settings.gitLineThickness)) pt").font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(ClaudeHUDTheme.secondaryText)
                        }
                        Slider(value: $settings.gitLineThickness, in: 1.5...4.5, step: 0.5)
                        tune("Beam width", value: $settings.gitLineBeamWidth, in: 0.06...0.5, format: { "\(Int($0 * 100))%" })
                        tune("Glow", value: $settings.gitLineGlow, in: 0...1, format: { "\(Int($0 * 100))%" })
                        tune("Trail", value: $settings.gitLineTrail, in: 0...1, format: { "\(Int($0 * 100))%" })
                        toggle("Reverse direction", "Run right to left.", isOn: $settings.gitLineReverse)
                        Button("Reset line settings") {
                            settings.gitLineSpeed = 1; settings.gitLineThickness = 2.5; settings.gitLineBeamWidth = 0.2
                            settings.gitLineGlow = 0.6; settings.gitLineTrail = 0.4; settings.gitLineReverse = false
                        }
                        .buttonStyle(HUDSecondaryButtonStyle())
                    }
                }

                section("Shortcuts", icon: "command") {
                    hint("Work from any app while a card is on screen. Click a shortcut, then press the new keys (⌃, ⌥ or ⌘ plus a key). ⎋ cancels.")
                    shortcut("⌃⌥1 – 9", "Pick an option")
                    ForEach(HUDHotkeyAction.configurable, id: \.self) { action in
                        HotkeyRow(action: action)
                    }
                    hint("With the panel focused, plain keys work too: 1–9, ↵.")
                }
            }
            .padding(18)
        }
        .background(ClaudeHUDTheme.darkCharcoal)
        .onReceive(poll) { _ in
            axGranted = AXIsProcessTrusted()
            hookInstalled = HUDHookInstaller.isInstalled
            permHookInstalled = HUDHookInstaller.isInstalled(.permissions)
        }
    }

    // MARK: - Building blocks

    private func section<Content: View>(_ title: String, icon: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 10, weight: .bold))
                Text(title.uppercased()).font(.system(size: 10, weight: .bold, design: .monospaced))
            }
            .foregroundColor(ClaudeHUDTheme.subtleText)
            VStack(alignment: .leading, spacing: 10) { content() }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.035)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.07), lineWidth: 0.8))
        }
    }

    private func label(_ s: String) -> some View {
        Text(s).font(.system(size: 12, weight: .semibold)).foregroundColor(ClaudeHUDTheme.creamText)
    }

    private func hint(_ s: String) -> some View {
        Text(s).font(.system(size: 10.5)).foregroundColor(ClaudeHUDTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
    }

    private func toggle(_ title: String, _ detail: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) { label(title); hint(detail) }
            Spacer(minLength: 0)
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }

    private func status(ok: Bool, _ title: String, ok okText: String, wait: String) -> some View {
        HStack {
            label(title)
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle")
                Text(ok ? okText : wait)
            }
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundColor(ok ? ClaudeHUDTheme.emerald : ClaudeHUDTheme.amber)
        }
    }

    private func stat(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10)).foregroundColor(ClaudeHUDTheme.secondaryText)
            Text(value).font(.system(size: 15, weight: .bold, design: .monospaced)).foregroundColor(color)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.4)).cornerRadius(8)
    }

    private func choice(_ title: String, _ detail: String, selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(ClaudeHUDTheme.snappySpring, action) }) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(selected ? ClaudeHUDTheme.terracottaGlow : ClaudeHUDTheme.secondaryText)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 11.5, weight: .semibold)).foregroundColor(ClaudeHUDTheme.creamText)
                    Text(detail).font(.system(size: 10)).foregroundColor(ClaudeHUDTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(7)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? ClaudeHUDTheme.terracotta.opacity(0.12) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func tune(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, format: @escaping (Double) -> String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                label(title); Spacer()
                Text(format(value.wrappedValue)).font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(ClaudeHUDTheme.secondaryText)
            }
            Slider(value: value, in: range)
        }
    }

    private static let chooseFileTag = "__choose_file__"

    /// A sound picker (system sounds, your own files, "Choose file…") with a play button.
    private func soundRow(_ title: String, _ name: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 11.5)).foregroundColor(ClaudeHUDTheme.secondaryText)
            Spacer(minLength: 4)
            Picker("", selection: Binding(get: { name.wrappedValue },
                                          set: { new in
                                              if new == Self.chooseFileTag {
                                                  // Keep the old sound if the file dialog is cancelled.
                                                  if let picked = HUDQuiet.chooseCustomSound() { name.wrappedValue = picked; HUDQuiet.play(picked) }
                                              } else { name.wrappedValue = new; HUDQuiet.play(new) }
                                          })) {
                Text("None").tag("None")
                ForEach(HUDQuiet.systemSounds, id: \.self) { Text($0).tag($0) }
                let custom = Set(HUDQuiet.customSounds() + [name.wrappedValue].filter { $0.hasPrefix(HUDQuiet.customPrefix) })
                if !custom.isEmpty {
                    Divider()
                    ForEach(custom.sorted(), id: \.self) { Text("♪ " + HUDQuiet.displayName($0)).tag($0) }
                }
                Divider()
                Text("Choose file…").tag(Self.chooseFileTag)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            Button { HUDQuiet.play(name.wrappedValue) } label: {
                Image(systemName: "play.circle.fill").font(.system(size: 14))
                    .foregroundColor(ClaudeHUDTheme.terracottaGlow)
            }
            .buttonStyle(.plain)
            .help("Play")
        }
    }

    private func shortcut(_ key: String, _ desc: String) -> some View {
        HStack(spacing: 8) {
            Text(key).font(.system(size: 10.5, weight: .bold, design: .monospaced)).foregroundColor(ClaudeHUDTheme.creamText)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.1)))
            Text(desc).font(.system(size: 11)).foregroundColor(ClaudeHUDTheme.secondaryText)
            Spacer(minLength: 0)
        }
    }
}

/// Color chips that wrap onto as many rows as the sidebar width needs.
private struct FlowChips: View {
    let items: [GitLineColorTheme]
    let selected: GitLineColorTheme
    let onPick: (GitLineColorTheme) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(items) { theme in
                Button { onPick(theme) } label: {
                    HStack(spacing: 5) {
                        Circle().fill(theme.primaryColor).frame(width: 9, height: 9)
                        Text(theme.name).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                    }
                    .foregroundColor(selected == theme ? ClaudeHUDTheme.creamText : ClaudeHUDTheme.secondaryText)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Capsule().fill(selected == theme ? theme.primaryColor.opacity(0.25) : Color.white.opacity(0.04)))
                    .overlay(Capsule().stroke(selected == theme ? theme.glowColor.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
            }
        }
    }
}


/// One rebindable shortcut: click to record, press keys, ⎋ cancels; ↺ restores the default.
private struct HotkeyRow: View {
    let action: HUDHotkeyAction
    @ObservedObject private var hotkeys = HUDHotkeys.shared
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Button {
                recording ? stop() : start()
            } label: {
                Text(recording ? "Press keys…" : (hotkeys.combo(for: action)?.display ?? "—"))
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundColor(recording ? ClaudeHUDTheme.amber : ClaudeHUDTheme.creamText)
                    .frame(minWidth: 74)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5).fill(recording ? ClaudeHUDTheme.amber.opacity(0.15) : Color.white.opacity(0.1)))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(recording ? ClaudeHUDTheme.amber : .clear, lineWidth: 1))
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 1) {
                Text(action.title).font(.system(size: 11)).foregroundColor(ClaudeHUDTheme.secondaryText)
                if hotkeys.unavailable.contains(action.key) {
                    Text("Taken by another app").font(.system(size: 9.5, weight: .semibold)).foregroundColor(ClaudeHUDTheme.ruby)
                }
            }
            Spacer(minLength: 0)
            if hotkeys.combo(for: action) != HUDHotkeys.defaults[action.key] {
                Button { hotkeys.reset(action) } label: { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(.plain).foregroundColor(ClaudeHUDTheme.subtleText).help("Restore default")
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == 53 && e.modifierFlags.intersection([.command, .control, .option]).isEmpty { stop(); return nil } // ⎋
            if let combo = KeyCombo.fromEvent(e) { hotkeys.set(combo, for: action); stop() }
            return nil // swallow while recording
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// "Try it": three throwaway cards, then two advances one second apart, so the chosen
/// transition and the stack shrinking can be watched on the live panel.
@MainActor
enum HUDTransitionDemo {
    static func run() {
        let cards = (1...3).map { n in
            HUDNotificationEvent.question(QuestionPrompt(
                id: "demo-transition-\(n)",
                question: "Transition demo card \(n) of 3",
                header: "Demo",
                options: [QuestionOption(keyNumber: 1, label: "OK", description: "Nothing is sent anywhere.")]))
        }
        LiveNotchPanelController.shared.startOverlay()
        HUDQueueManager.shared.showNow(cards)
        for step in 1...2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2 * Double(step)) {
                guard HUDQueueManager.shared.currentEvent?.sourceId == "demo-transition-\(step)" else { return }
                HUDQueueManager.shared.resolveCurrent()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) {
            HUDQueueManager.shared.remove(ids: ["demo-transition-3"])
        }
    }
}
