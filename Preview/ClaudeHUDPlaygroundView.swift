//
//  ClaudeHUDPlaygroundView.swift
//  ClaudeHUD
//
//  Interactive Preview & Design Laboratory
//  Provides a clean, non-overlapping stage to test and verify all Claude Code
//  interaction archetypes (Multi-step questions, 3-segment notch, task cards, bash approvals).
//  Settings sidebar, live card preview and test scenarios.
//

import SwiftUI

public struct ClaudeHUDPlaygroundView: View {
    @State private var currentEvent: HUDNotificationEvent? = nil
    @State private var actionLogs: [String] = []
    
    @ObservedObject private var queueManager = HUDQueueManager.shared
    @AppStorage("hud_showSidebar") private var showSidebar = true
    @ObservedObject private var settings = HUDSettingsStore.shared
    @ObservedObject private var overlayController = LiveNotchPanelController.shared
    
    // MARK: - Mock Scenarios

    /// cliSessionId is not a live session, so its buttons never type into a real Claude session.
    private let mockSessionAsk = SessionAsk(
        id: "test-session-ask",
        cliSessionId: "test-session",
        sessionTitle: "Test: shop-api deploy",
        question: "Will you run the production deploy from this branch?",
        recap: "The new schema is written and all 128 tests pass. It is not in production yet.",
        actions: ["Deploy done", "Not now"]
    )

    private var scenarioEvents: [HUDNotificationEvent] {
        [.multiQuestion(mockMultiQuestion), .question(mockQuestion), .taskProposal(mockTaskCard),
         .permission(mockBashPermission), .fileDiff(mockFileDiff),
         .planChecklist(mockPlanChecklist), .sessionAsk(mockSessionAsk)]
    }

    /// Shows the scenario where it really appears: the live notch / top-right panel.
    private func show(_ events: [HUDNotificationEvent]) {
        overlayController.startOverlay()
        queueManager.showNow(events)
        currentEvent = events.first
        actionLogs.insert("[\(timestamp())] Live panel (\(settings.displayPosition.rawValue)): \(events.map(\.title).joined(separator: " → "))", at: 0)
    }
    
    private let mockMultiQuestion = MultiQuestionSession(
        questions: [
            QuestionPrompt(
                question: "shop-api is built, tested (29/29) and deployed to staging, but the DNS writes were blocked by a permission rule. They are:\napi.example.com A → 203.0.113.10, plus DKIM/SPF/MX records for mail.example.com and a DMARC record. How should I proceed?",
                header: "DNS records",
                options: [
                    QuestionOption(
                        keyNumber: 1,
                        label: "I'll allow it, retry",
                        description: "You approve the DNS writes (or add a permission rule); I re-run the same API calls.",
                        tag: "Recommended"
                    ),
                    QuestionOption(
                        keyNumber: 2,
                        label: "I'll add records myself",
                        description: "I write the exact records to a file for you to add in your DNS dashboard, then I verify and continue."
                    )
                ]
            ),
            QuestionPrompt(
                question: "Should I also set up automatic TLS renewal with Certbot and a PM2 startup service on the server?",
                header: "SSL & Daemons",
                options: [
                    QuestionOption(
                        keyNumber: 1,
                        label: "Enable PM2 & Certbot",
                        description: "Persists across server reboots and ensures HTTPS certificates never expire.",
                        tag: "Recommended"
                    ),
                    QuestionOption(
                        keyNumber: 2,
                        label: "Manual restart only",
                        description: "Leaves PM2 unmanaged by systemd."
                    )
                ]
            )
        ]
    )
    
    private let mockQuestion = QuestionPrompt(
        question: "Which database should the shop API use?",
        header: "Architecture",
        options: [
            QuestionOption(
                keyNumber: 1,
                label: "SQLite + WAL",
                description: "Single-file local embedded DB with WAL mode, zero configuration, and sub-millisecond reads.",
                tag: "Fastest"
            ),
            QuestionOption(
                keyNumber: 2,
                label: "PostgreSQL",
                description: "Full relational ACID database with connection pool, JSONB support, and migration tooling.",
                tag: "Recommended"
            ),
            QuestionOption(
                keyNumber: 3,
                label: "SpacetimeDB",
                description: "Realtime multiplayer database engine written in Rust with direct Unity 3D client sync.",
                tag: "Realtime 3D"
            )
        ]
    )
    
    private let mockTaskCard = TaskProposal(
        title: "Milestone 1: shop API, slice 1",
        tldr: "Build and ship the first slice of the shop API at https://api.example.com. The scope covers authentication and storefront endpoints.",
        prompt: "Setup express/fastify microservice with OpenAPI spec and JWT auth.",
        parentSessionName: "Shop launch planning",
        proposalId: "task_a4b91f0c"
    )
    
    private let mockBashPermission = ToolPermission(
        toolName: "Bash",
        command: """
curl -s -X POST "https://api.dns.example/v1/zones/$ZONE/records" \\
  -H "Authorization: Bearer $DNS_TOKEN" -H 'content-type: application/json' \\
  -d '{"type":"MX","name":"mail.example.com","content":"mx.example.net","priority":10}'
""",
        workingDir: "~/code/shop",
        reason: "Writes DNS records with an API token",
        isDestructive: false
    )

    private let mockFileDiff = FileDiffData(
        filePath: "shop/src/routes/auth.ts",
        additionsCount: 14,
        deletionsCount: 3,
        lines: [
            DiffLine(type: .context, text: "export async function registerRoutes(app: FastifyInstance) {"),
            DiffLine(type: .context, text: "  app.get('/health', async () => ({ status: 'ok' }));"),
            DiffLine(type: .deletion, text: "  // legacy session auth (insecure)"),
            DiffLine(type: .deletion, text: "  app.post('/api/login', handleLegacyCookieLogin);"),
            DiffLine(type: .deletion, text: "  app.post('/api/register', handleLegacyRegister);"),
            DiffLine(type: .addition, text: "  // v2 ed25519 token + turnstile verification"),
            DiffLine(type: .addition, text: "  app.post('/api/v2/login', { schema: loginSchema }, handleTokenLogin);"),
            DiffLine(type: .addition, text: "  app.post('/api/v2/register', { schema: registerSchema }, handleTokenRegister);"),
            DiffLine(type: .addition, text: "  app.post('/api/v2/verify-email', handleVerifyEmailRouting);"),
            DiffLine(type: .context, text: "}")
        ]
    )

    private let mockPlanChecklist = PlanChecklistData(
        planTitle: "Milestone 1: Shop API & storefront endpoints",
        steps: [
            PlanStepItem(index: 1, title: "Provision the staging server", status: .completed),
            PlanStepItem(index: 2, title: "Verify DNS and DKIM/SPF records", status: .completed),
            PlanStepItem(index: 3, title: "Set up mail routing for hello@example.com", status: .active),
            PlanStepItem(index: 4, title: "Add a WAF rate-limit rule (20 req/min)", status: .pending),
            PlanStepItem(index: 5, title: "Set up PM2 startup and automatic TLS renewal", status: .pending),
            PlanStepItem(index: 6, title: "Run the API tests (29/29) end to end", status: .pending)
        ]
    )
    
    public init() {
        _currentEvent = State(initialValue: .multiQuestion(mockMultiQuestion))
    }
    
    public var body: some View {
        HStack(spacing: 0) {
            // Settings live in the sidebar so the first window people see is where they change things.
            if showSidebar {
                        ClaudeHUDSettingsView()
                    .frame(width: 320)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                Divider().background(Color.white.opacity(0.12))
            }
            stage
        }
        // Solid title-bar strip over the sidebar: scrolled settings never show through
        // behind the traffic lights and the sidebar toggle.
        .overlay(alignment: .topLeading) {
            if showSidebar {
                ClaudeHUDTheme.darkCharcoal
                    .frame(width: 320, height: 38)
                    .overlay(alignment: .bottom) { Color.white.opacity(0.06).frame(height: 0.5) }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        // Sidebar toggle sits right of the window's traffic lights, in the same spot either way.
        .overlay(alignment: .topLeading) {
            Button {
                withAnimation(ClaudeHUDTheme.snappySpring) { showSidebar.toggle() }
            } label: {
                Image(systemName: "sidebar.left").font(.system(size: 13, weight: .semibold))
                    .foregroundColor(showSidebar ? ClaudeHUDTheme.terracottaGlow : ClaudeHUDTheme.secondaryText)
                    .frame(width: 26, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(showSidebar ? "Hide settings (⌃⌘S)" : "Show settings (⌃⌘S)")
            .keyboardShortcut("s", modifiers: [.command, .control])
            .padding(.leading, 76)
            .padding(.top, 5)
            .ignoresSafeArea() // sit in the title bar, level with the traffic lights
        }
        .frame(minWidth: showSidebar ? 860 : 540, minHeight: 640)
        .background(ClaudeHUDTheme.deepCanvas)
    }

    private var stage: some View {
        VStack(spacing: 0) {
            // MARK: - Top Header & Control Toolbar
            topControlBar
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.85))
            
            Divider()
                .background(Color.white.opacity(0.12))
            
            // MARK: - Main Canvas Stage (Simulated Desktop)
            ScrollView(.vertical, showsIndicators: false) {
                MacScreenBackdrop(accent: settings.gitLineTheme.primaryColor) {
                    // Notch: the card's header sits beside the drawn notch, like the real panel.
                    // Top right: the card sits under the drawn menu bar.
                    ClaudeHUDShellView(
                        currentEvent: $currentEvent,
                        displayPosition: $settings.displayPosition,
                        notchTopInset: settings.displayPosition == .notch ? MacScreenBackdrop<EmptyView>.menuBarHeight : 0,
                        onActionLogged: { log in
                            withAnimation { actionLogs.insert("[\(timestamp())] \(log)", at: 0) }
                        }
                    )
                    .padding(.top, settings.displayPosition == .notch ? 0 : MacScreenBackdrop<EmptyView>.menuBarHeight - 12)
                    .frame(maxWidth: .infinity, alignment: settings.displayPosition == .notch ? .top : .topTrailing)
                }
                .padding(16)
            }
            
            Divider()
                .background(Color.white.opacity(0.12))
            
            // MARK: - Bottom Status & Action Bus Console
            bottomStatusFooter
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.90))
        }
    }
    
    // MARK: - Top Toolbar
    
    private var topControlBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                // App Title
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(ClaudeHUDTheme.terracottaGlow)
                    
                    Text("Claude HUD")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(ClaudeHUDTheme.creamText)
                    
                    Text("LIVE PREVIEW")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(ClaudeHUDTheme.terracotta)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(ClaudeHUDTheme.terracotta.opacity(0.18)))
                }
                
                Spacer()
                
            }
            
            // Scenario chips wrap onto more rows as the window narrows, so all stay visible.
            FlowLayout(spacing: 8) {
                    Text("CARD SCENARIOS:")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(ClaudeHUDTheme.subtleText)
                    
                    // 3-Question FIFO Queue Simulation Button
                    scenarioButton(title: "⚡️ 3-card queue", icon: "square.stack.3d.up.fill", color: ClaudeHUDTheme.terracottaGlow) {
                        withAnimation(ClaudeHUDTheme.fluidSpring) {
                            show([
                                .multiQuestion(mockMultiQuestion),
                                .taskProposal(mockTaskCard),
                                .permission(mockBashPermission)
                            ])
                            actionLogs.insert("[\(timestamp())] Enqueued 3 events into FIFO Queue (Question -> Task Card -> Security Alert)", at: 0)
                        }
                    }
                    
                    scenarioButton(title: "Multi-question", icon: "list.bullet.circle.fill", color: ClaudeHUDTheme.sapphire) {
                        withAnimation(ClaudeHUDTheme.fluidSpring) {
                            show([.multiQuestion(mockMultiQuestion)])
                        }
                    }
                    
                    scenarioButton(title: "Single question", icon: "square.split.3x1.fill", color: ClaudeHUDTheme.amber) {
                        withAnimation(ClaudeHUDTheme.fluidSpring) {
                            show([.question(mockQuestion)])
                        }
                    }
                    
                    scenarioButton(title: "Task proposal", icon: "play.rectangle.fill", color: ClaudeHUDTheme.terracotta) {
                        withAnimation(ClaudeHUDTheme.fluidSpring) {
                            show([.taskProposal(mockTaskCard)])
                        }
                    }
                    
                    scenarioButton(title: "Bash approval", icon: "shield.lefthalf.filled", color: ClaudeHUDTheme.ruby) {
                        withAnimation(ClaudeHUDTheme.fluidSpring) {
                            show([.permission(mockBashPermission)])
                        }
                    }

                    scenarioButton(title: "File Diff (Edit)", icon: "doc.badge.plus", color: ClaudeHUDTheme.emerald) {
                        withAnimation(ClaudeHUDTheme.fluidSpring) {
                            show([.fileDiff(mockFileDiff)])
                        }
                    }

                    scenarioButton(title: "Plan Checklist", icon: "list.clipboard.fill", color: ClaudeHUDTheme.terracotta) {
                        withAnimation(ClaudeHUDTheme.fluidSpring) {
                            show([.planChecklist(mockPlanChecklist)])
                        }
                    }
                    
                    scenarioButton(title: "Session Waiting (next step)", icon: "bubble.left.and.exclamationmark.bubble.right.fill", color: ClaudeHUDTheme.amber) {
                        withAnimation(ClaudeHUDTheme.fluidSpring) {
                            show([.sessionAsk(mockSessionAsk)])
                        }
                    }

                    scenarioButton(title: "Clear Card", icon: "xmark.circle", color: ClaudeHUDTheme.subtleText) {
                        withAnimation(ClaudeHUDTheme.fluidSpring) {
                            queueManager.remove(ids: Set(scenarioEvents.map(\.sourceId)))
                            currentEvent = nil
                        }
                    }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Where the card shows, right above the screen it is drawn on.
            HStack(spacing: 8) {
                Text("SHOW ON:")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(ClaudeHUDTheme.subtleText)
                Picker("", selection: $settings.displayPosition) {
                    Label("Notch", systemImage: "macbook").tag(HUDDisplayPosition.notch)
                    Label("Top right", systemImage: "rectangle.inset.topright.filled").tag(HUDDisplayPosition.topRight)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
            }
        }
    }

    private func scenarioButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(ClaudeHUDTheme.creamText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.opacity(0.18))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(color.opacity(0.40), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Bottom Status Footer
    
    private var bottomStatusFooter: some View {
        HStack(spacing: 12) {
            // Live Status Indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(currentEvent != nil ? ClaudeHUDTheme.amber : ClaudeHUDTheme.emerald)
                    .frame(width: 7, height: 7)
                
                Text(currentEvent != nil ? "PROMPT ACTIVE (WAITING FOR USER)" : "IDLE (LISTENING FOR SESSIONS)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(currentEvent != nil ? ClaudeHUDTheme.amber : ClaudeHUDTheme.emerald)
            }
            
            Spacer()
            
            // Latest Action Log
            if let latest = actionLogs.first {
                Text(latest)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(ClaudeHUDTheme.creamText.opacity(0.75))
                    .lineLimit(1)
            } else {
                Text("Ready — Click buttons inside the HUD card to test UDS/Hook injection")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(ClaudeHUDTheme.subtleText)
            }
        }
    }
    
    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
}

#Preview {
    ClaudeHUDPlaygroundView()
}


/// Lays chips out left to right and wraps to a new row when the width runs out.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [(items: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(items: [Int], width: CGFloat, height: CGFloat)] = []
        var current: (items: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            let needed = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.items.isEmpty {
                rows.append(current)
                current = ([i], size.width, size.height)
            } else {
                current = (current.items + [i], needed, max(current.height, size.height))
            }
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}
