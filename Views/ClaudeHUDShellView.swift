//
//  ClaudeHUDShellView.swift
//  ClaudeHUD
//
//  Unified Floating HUD & Dynamic Notch Master Shell
//  Supports dual-position rendering:
//  - Dynamic Notch (centered at top, expanding from physical notch)
//  - Top-Right Floating Glass HUD (floating 20pt from top-right corner)
//  Includes the bottom scanner line, queue depth stack and notch badge.
//

import AppKit
import SwiftUI

public struct ClaudeHUDShellView: View {
    @Binding public var currentEvent: HUDNotificationEvent?
    @Binding public var displayPosition: HUDDisplayPosition
    public var notchTopInset: CGFloat
    public var onActionLogged: ((String) -> Void)?
    
    @ObservedObject private var queueManager = HUDQueueManager.shared
    @ObservedObject private var settings = HUDSettingsStore.shared
    @State private var isCollapsed: Bool = false
    @State private var expanded = false
    @State private var hoverInside = false
    @Environment(\.hudHandlesHotkeys) private var handlesHotkeys
    
    public init(
        currentEvent: Binding<HUDNotificationEvent?>,
        displayPosition: Binding<HUDDisplayPosition>,
        notchTopInset: CGFloat = 0,
        onActionLogged: ((String) -> Void)? = nil
    ) {
        self._currentEvent = currentEvent
        self._displayPosition = displayPosition
        self.notchTopInset = notchTopInset
        self.onActionLogged = onActionLogged
        self._queueManager = ObservedObject(wrappedValue: HUDQueueManager.shared)
        self._settings = ObservedObject(wrappedValue: HUDSettingsStore.shared)
    }
    
    private var activeEvent: HUDNotificationEvent? {
        queueManager.currentEvent ?? currentEvent
    }
    
    public var body: some View {
        let currentTopInset = (displayPosition == .notch) ? (notchTopInset + settings.notchVerticalOffset) : 20
        let event = activeEvent
        let _ = hudLog("🖥️ ClaudeHUDShellView.body: activeEvent=\(event?.title ?? "nil"), queueCount=\(queueManager.totalCount)", category: "RENDER")
        
        ZStack(alignment: displayPosition == .notch ? .top : .topTrailing) {
            if event != nil, settings.isSnoozed {
                snoozedPill
                    .padding(.top, currentTopInset)
                    .padding(.trailing, displayPosition == .notch ? 0 : 20)
                    .transition(.opacity)
            } else if let event = event, settings.compactCards, !expanded {
                // Collapsed: one line with the question; hover (or a hot key) opens the card.
                compactPill(event)
                    .padding(.top, currentTopInset)
                    .padding(.trailing, displayPosition == .notch ? 0 : 20)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            } else if let event = event {
                mainCard(for: event, notchInset: currentTopInset)
                    .background(
                        StackedCardDepthView()
                    )
                    .frame(width: displayPosition == .notch ? 460 : 420)
                    .padding(.top, displayPosition == .notch ? 0 : currentTopInset)
                    .padding(.trailing, displayPosition == .notch ? 0 : 20)
                    // A new identity per card, so moving to the next card runs the chosen transition.
                    .id(event.sourceId)
                    .transition(Self.transition(settings.cardTransition))
            } else {
                // Idle Notch / Menubar Pill
                idlePill
                    .padding(.top, currentTopInset)
                    .padding(.trailing, displayPosition == .notch ? 0 : 20)
                    .transition(.opacity)
            }
        }
        .animation(settings.cardTransition == .none ? nil : ClaudeHUDTheme.fluidSpring, value: activeEvent)
        .animation(ClaudeHUDTheme.fluidSpring, value: displayPosition)
        .animation(ClaudeHUDTheme.fluidSpring, value: expanded)
        .onHover { inside in
            guard settings.compactCards else { return }
            if inside { expanded = true } else {
                // A short grace period so moving between the pill and the card does not flicker.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { if !hoverInside { expanded = false } }
            }
            hoverInside = inside
        }
        .onReceive(HUDHotkeys.shared.actions) { action in
            guard handlesHotkeys, let event = activeEvent else { return }
            if settings.compactCards && !expanded { expanded = true } // first key opens the pill
            switch (action, event) {
            case (.next, _):
                queueManager.rotate()
            case (.skip, .question(let q)):
                ClaudeSessionWatcher.shared.respond(toolUseId: q.id, answers: nil); handleDismissOrAdvance()
            case (.skip, .multiQuestion(let m)):
                ClaudeSessionWatcher.shared.respond(toolUseId: m.id, answers: nil); handleDismissOrAdvance()
            case (.skip, .permission(let p)):
                ClaudeSessionWatcher.shared.respondPermission(id: p.id, decision: nil); handleDismissOrAdvance()
            case (.submit, .permission(let p)):
                ClaudeSessionWatcher.shared.respondPermission(id: p.id, decision: .allow); handleDismissOrAdvance()
            case (.skip, _):
                handleDismissOrAdvance()
            case (.copy, _):
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(Self.questionText(event), forType: .string)
            case (.submit, .fileDiff), (.submit, .planChecklist), (.submit, .taskProposal):
                onActionLogged?("Hot key approved: \(event.title)"); handleDismissOrAdvance()
            default: break // pick/submit for questions are handled inside the cards
            }
        }
    }

    static func transition(_ style: CardTransitionStyle) -> AnyTransition {
        switch style {
        case .deck:
            return .asymmetric(
                insertion: .scale(scale: 0.94, anchor: .bottom).combined(with: .offset(y: 14)).combined(with: .opacity),
                removal: .offset(x: -520).combined(with: .modifier(active: TiltModifier(angle: -14), identity: TiltModifier(angle: 0))).combined(with: .opacity))
        case .flyRight:
            return .asymmetric(
                insertion: .scale(scale: 0.96).combined(with: .opacity),
                removal: .offset(x: 520).combined(with: .modifier(active: TiltModifier(angle: 12), identity: TiltModifier(angle: 0))).combined(with: .opacity))
        case .tossUp:
            return .asymmetric(
                insertion: .scale(scale: 0.9, anchor: .top).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .scale(scale: 0.6, anchor: .top)).combined(with: .opacity))
        case .flip:
            return .asymmetric(
                insertion: .modifier(active: FlipModifier(angle: -90), identity: FlipModifier(angle: 0)).combined(with: .opacity),
                removal: .modifier(active: FlipModifier(angle: 90), identity: FlipModifier(angle: 0)).combined(with: .opacity))
        case .drop:
            return .asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .offset(y: 40).combined(with: .opacity))
        case .fade:
            return .asymmetric(
                insertion: .scale(scale: 0.85, anchor: .top).combined(with: .opacity),
                removal: .scale(scale: 0.9, anchor: .top).combined(with: .opacity))
        case .none:
            return .identity
        }
    }

    static func questionText(_ e: HUDNotificationEvent) -> String {
        switch e {
        case .question(let q): return q.question
        case .multiQuestion(let m): return m.questions.map(\.question).joined(separator: "\n\n")
        case .sessionAsk(let a): return a.question
        default: return e.title
        }
    }
    
    // MARK: - Snoozed / compact pills

    private var snoozedPill: some View {
        Button(action: { HUDQuiet.resume() }) {
            HStack(spacing: 7) {
                Image(systemName: "moon.zzz.fill").font(.system(size: 10, weight: .bold)).foregroundColor(ClaudeHUDTheme.amber)
                Text("Snoozed until \((settings.snoozeUntil ?? Date()).formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(ClaudeHUDTheme.creamText)
                Text("· \(queueManager.totalCount) waiting").font(.system(size: 10, weight: .medium)).foregroundColor(ClaudeHUDTheme.secondaryText)
            }
            .fixedSize()
            .padding(.horizontal, 14).padding(.vertical, 7)
            .liquidGlass(cornerRadius: 16)
        }
        .buttonStyle(.plain)
        .help("Click to wake the HUD")
    }

    private func compactPill(_ event: HUDNotificationEvent) -> some View {
        HStack(spacing: 8) {
            Circle().fill(ClaudeHUDTheme.amber).frame(width: 7, height: 7)
                .shadow(color: ClaudeHUDTheme.amber.opacity(0.8), radius: 4)
            Text(Self.questionText(event).components(separatedBy: .newlines).first ?? event.title)
                .font(.system(size: 11, weight: .semibold)).foregroundColor(ClaudeHUDTheme.creamText)
                .lineLimit(1).truncationMode(.tail)
            if queueManager.totalCount > 1 {
                Text("+\(queueManager.totalCount - 1)").font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(ClaudeHUDTheme.amber)
            }
        }
        .frame(maxWidth: 360)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 14).padding(.vertical, 7)
        .liquidGlass(cornerRadius: 16)
        .contentShape(Rectangle())
        .onTapGesture { expanded = true }
    }

    // MARK: - Idle Mini Capsule
    
    private var idlePill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(ClaudeHUDTheme.terracotta)
                .frame(width: 7, height: 7)
            
            Text("Claude Code")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(ClaudeHUDTheme.creamText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            
            Text("Ready")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(ClaudeHUDTheme.secondaryText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .liquidGlass(cornerRadius: 16)
        .shadow(color: Color.black.opacity(0.40), radius: 6, y: 2)
        .onTapGesture {
            // Can trigger test event
        }
    }
    
    // MARK: - Active Card Switcher
    
    @ViewBuilder
    private func mainCard(for event: HUDNotificationEvent, notchInset: CGFloat) -> some View {
        let isNotch = displayPosition == .notch
        return VStack(spacing: 0) {
            // Notch mode: the header lives in the strip beside the physical notch,
            // so the card reads as the notch growing downward. Floating mode: a normal top row.
            shellHeaderBar
                .frame(height: isNotch ? max(notchInset, 24) : 28)
                .padding(.bottom, -8) // inner cards already pad 14pt on top
            
            // Dynamic Content
            switch event {
            case .question(let q):
                SegmentedQuestionView(
                    prompt: q,
                    displayPosition: displayPosition,
                    onSelect: { option in
                        onActionLogged?("Selected option [\(option.keyNumber)]: \(option.label)")
                        ClaudeSessionWatcher.shared.respond(toolUseId: q.id, answers: [q.question: option.label])
                        handleDismissOrAdvance()
                    }
                )
                
            case .multiQuestion(let m):
                MultiStepQuestionView(
                    session: m,
                    displayPosition: displayPosition,
                    onAnswerSubmitted: { qIdx, answer in
                        onActionLogged?("Q\(qIdx + 1) Answered: \(answer)")
                    },
                    onSkip: {
                        onActionLogged?("Skipped question sequence")
                        ClaudeSessionWatcher.shared.respond(toolUseId: m.id, answers: nil)
                        handleDismissOrAdvance()
                    },
                    onFinishAll: { answers in
                        onActionLogged?("Submitted all answers: \(answers.values.joined(separator: ", "))")
                        // Claude expects { question text: answer }.
                        var byQuestion: [String: String] = [:]
                        for (i, a) in answers where m.questions.indices.contains(i) && !a.isEmpty {
                            byQuestion[m.questions[i].question] = a
                        }
                        ClaudeSessionWatcher.shared.respond(toolUseId: m.id, answers: byQuestion)
                        handleDismissOrAdvance()
                    }
                )
                
            case .taskProposal(let task):
                TaskProposalCardView(
                    task: task,
                    displayPosition: displayPosition,
                    onDoItHere: {
                        onActionLogged?("Injected 'Do this task here: \(task.title)' via UDS Socket")
                        handleDismissOrAdvance()
                    },
                    onStartNewSession: {
                        onActionLogged?("Spawned child worktree session for: \(task.title)")
                        handleDismissOrAdvance()
                    },
                    onOptions: {
                        onActionLogged?("Opened Task Options Menu")
                    },
                    onDismiss: {
                        onActionLogged?("Dismissed task suggestion")
                        handleDismissOrAdvance()
                    }
                )
                
            case .permission(let perm):
                PermissionApprovalView(
                    permission: perm,
                    displayPosition: displayPosition,
                    onAllow: {
                        onActionLogged?("Allowed \(perm.toolName)")
                        ClaudeSessionWatcher.shared.respondPermission(id: perm.id, decision: .allow)
                        handleDismissOrAdvance()
                    },
                    onAlwaysAllow: {
                        onActionLogged?("Always allowed \(perm.toolName)")
                        ClaudeSessionWatcher.shared.respondPermission(id: perm.id, decision: .always)
                        handleDismissOrAdvance()
                    },
                    onDeny: {
                        onActionLogged?("Denied \(perm.toolName)")
                        ClaudeSessionWatcher.shared.respondPermission(id: perm.id, decision: .deny)
                        handleDismissOrAdvance()
                    }
                )

            case .fileDiff(let diff):
                FileDiffApprovalView(
                    diff: diff,
                    displayPosition: displayPosition,
                    onApply: {
                        onActionLogged?("Applied diff for \(diff.filePath) (+\(diff.additionsCount)/-\(diff.deletionsCount))")
                        handleDismissOrAdvance()
                    },
                    onReject: {
                        onActionLogged?("Rejected diff for \(diff.filePath)")
                        handleDismissOrAdvance()
                    }
                )
                
            case .sessionAsk(let ask):
                SessionAskCardView(
                    ask: ask,
                    onAnswer: { label in
                        onActionLogged?("Answered waiting session: \(ask.sessionTitle) → \(label)")
                        ClaudeSessionWatcher.shared.answerSession(cliSessionId: ask.cliSessionId, text: label)
                        // The card leaves when the transcript shows the reply.
                    },
                    onOpen: {
                        onActionLogged?("Opened waiting session: \(ask.sessionTitle)")
                        ClaudeSessionWatcher.shared.openSession(cliSessionId: ask.cliSessionId)
                        // The card stays until the session gets a reply, so nothing is lost.
                    },
                    onDismiss: {
                        onActionLogged?("Snoozed waiting session: \(ask.sessionTitle)")
                        handleDismissOrAdvance()
                    }
                )

            case .planChecklist(let plan):
                PlanChecklistView(
                    plan: plan,
                    displayPosition: displayPosition,
                    onApprove: {
                        onActionLogged?("Approved plan: \(plan.planTitle)")
                        handleDismissOrAdvance()
                    },
                    onModify: {
                        onActionLogged?("Requested changes for plan: \(plan.planTitle)")
                        handleDismissOrAdvance()
                    }
                )
            }
            
            // Animated bottom scanner line (K.I.T.T. style)
            GitScannerLine()
        }
        .environment(\.hudSurfaceOwnedByShell, true)
        .background(cardSurface)
        .clipShape(cardShape)
    }

    /// Notch: flat top flush with the screen edge, rounded bottom (Dynamic Island style).
    private var cardShape: UnevenRoundedRectangle {
        displayPosition == .notch
        ? UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24, style: .continuous)
        : UnevenRoundedRectangle(cornerRadii: .init(topLeading: 18, bottomLeading: 18, bottomTrailing: 18, topTrailing: 18), style: .continuous)
    }

    @ViewBuilder
    private var cardSurface: some View {
        if displayPosition == .notch {
            // Pure black so it merges with the hardware notch; a hairline only on the sides/bottom.
            cardShape.fill(Color.black)
                .overlay(cardShape.stroke(Color.white.opacity(0.07), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
        } else {
            Color.clear.liquidGlass(cornerRadius: 18)
        }
    }
    
    // MARK: - Queue Resolution
    
    private func handleDismissOrAdvance() {
        withAnimation(ClaudeHUDTheme.fluidSpring) {
            if queueManager.hasNext {
                queueManager.resolveCurrent()
                currentEvent = queueManager.currentEvent
            } else {
                queueManager.clearAll()
                currentEvent = nil
            }
        }
    }
    
    // MARK: - Shell Header Bar
    
    private var shellHeaderBar: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(ClaudeHUDTheme.terracottaGlow)
                .frame(width: 6, height: 6)
                .shadow(color: ClaudeHUDTheme.terracottaGlow.opacity(0.8), radius: 4)

            Text("Claude")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(ClaudeHUDTheme.creamText)

            Spacer(minLength: displayPosition == .notch ? 200 : 8) // keep clear of the physical notch

            if queueManager.hasNext {
                HStack(spacing: 3) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 8, weight: .bold))
                    Text("\(queueManager.pendingBehindCount) more")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                }
                .foregroundColor(ClaudeHUDTheme.amber)
                .help("\(queueManager.pendingBehindCount) more waiting after this one")
            }

            if let event = activeEvent, event.isQuestion {
                Button(action: {
                    onActionLogged?("Handed question back to Claude")
                    ClaudeSessionWatcher.shared.respond(toolUseId: event.sourceId, answers: nil)
                    handleDismissOrAdvance()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(ClaudeHUDTheme.secondaryText)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Answer in Claude instead")
            }

            Menu {
                Button("Snooze 15 minutes") { HUDQuiet.snooze(minutes: 15) }
                Button("Snooze 1 hour") { HUDQuiet.snooze(minutes: 60) }
                Button("Snooze until tomorrow") { HUDQuiet.snoozeUntilTomorrow() }
            } label: {
                Image(systemName: "moon.zzz")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(ClaudeHUDTheme.secondaryText)
                    .frame(width: 18, height: 18)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Snooze cards")

            Button(action: {
                withAnimation(ClaudeHUDTheme.fluidSpring) {
                    displayPosition = (displayPosition == .notch) ? .topRight : .notch
                    onActionLogged?("Switched position to \(displayPosition.rawValue)")
                }
            }) {
                Image(systemName: displayPosition == .notch ? "arrow.up.right.square" : "arrow.up.square")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(ClaudeHUDTheme.secondaryText)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(displayPosition == .notch ? "Move to top-right corner" : "Move to notch")
        }
        .padding(.horizontal, 16)
    }
}


private struct TiltModifier: ViewModifier {
    let angle: Double
    func body(content: Content) -> some View { content.rotationEffect(.degrees(angle), anchor: .bottom) }
}

private struct FlipModifier: ViewModifier {
    let angle: Double
    func body(content: Content) -> some View {
        content.rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
    }
}
