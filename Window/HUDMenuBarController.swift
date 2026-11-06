//
//  HUDMenuBarController.swift
//  ClaudeHUD
//
//  macOS Menu Bar (Status Bar / Navbar) Controller
//  Provides native persistent status item in macOS top bar with:
//  - Live dynamic queue count badge
//  - Live Overlay & Position toggles
//  - Scanner line controls & theme picker
//  - One-click access to Design Lab & Settings windows
//  - Instant test queue generators and log viewer
//

import AppKit
import SwiftUI
import Combine

@MainActor
public final class HUDMenuBarController: NSObject, NSMenuDelegate {
    public static let shared = HUDMenuBarController()
    
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private var cancellables = Set<AnyCancellable>()
    
    private var settingsWindow: NSWindow?
    private var playgroundWindow: NSWindow?
    
    override private init() {
        super.init()
    }
    
    // MARK: - Setup
    
    public func setupStatusBarItem() {
        guard statusItem == nil else { return }
        
        hudLog("📌 Initializing macOS Menu Bar (Status Bar) Item...", category: "NAVBAR")
        
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = Self.menuBarIcon
            button.imagePosition = .imageLeft
            button.toolTip = "Claude HUD — right-click to open"
        }
        
        self.statusItem = item
        
        buildMenu()
        setupObservers()
        updateBadge()
        
        hudLog("✅ macOS Menu Bar Item active and visible in top bar", category: "NAVBAR")
    }
    
    // MARK: - Observers
    
    private func setupObservers() {
        // Observe queue changes to update badge count and menu dynamically
        HUDQueueManager.shared.$queue
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateBadge()
                self?.rebuildMenuState()
            }
            .store(in: &cancellables)
            
        // Observe display position changes
        HUDSettingsStore.shared.$displayPosition
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenuState()
            }
            .store(in: &cancellables)
            
        // Observe scanner line changes
        HUDSettingsStore.shared.$gitLineEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenuState()
            }
            .store(in: &cancellables)
            
        HUDSettingsStore.shared.$gitLineTheme
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenuState()
            }
            .store(in: &cancellables)
            
        HUDSettingsStore.shared.$gitLineStyle
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenuState()
            }
            .store(in: &cancellables)
            
        HUDSettingsStore.shared.$snoozeUntil
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenuState()
            }
            .store(in: &cancellables)

        // Observe overlay controller state
        LiveNotchPanelController.shared.$isOverlayActive
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenuState()
            }
            .store(in: &cancellables)
    }
    
    /// The app icon reduced to a menu-bar glyph: notch tab and status dot in the app's terracotta,
    /// card outline and text lines in the menu bar's own label color (drawn per appearance, so
    /// it stays white on a dark menu bar and black on a light one).
    static let menuBarIcon: NSImage = {
        let terracotta = NSColor(srgbRed: 0.851, green: 0.420, blue: 0.263, alpha: 1)
        let img = NSImage(size: NSSize(width: 18, height: 16), flipped: true) { _ in
            terracotta.setFill()
            NSBezierPath(roundedRect: NSRect(x: 5, y: 0, width: 8, height: 2.6), xRadius: 1.2, yRadius: 1.2).fill()
            NSBezierPath(ovalIn: NSRect(x: 4.4, y: 6.2, width: 2.6, height: 2.6)).fill()

            NSColor.labelColor.setStroke()
            let card = NSBezierPath(roundedRect: NSRect(x: 1.75, y: 3.75, width: 14.5, height: 10.5), xRadius: 2.6, yRadius: 2.6)
            card.lineWidth = 1.5
            card.stroke()
            NSColor.labelColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: 4.4, y: 9.6, width: 9.2, height: 1.5), xRadius: 0.75, yRadius: 0.75).fill()
            NSBezierPath(roundedRect: NSRect(x: 8.2, y: 6.8, width: 5.4, height: 1.5), xRadius: 0.75, yRadius: 0.75).fill()
            return true
        }
        img.isTemplate = false   // keep the terracotta; the label-color parts follow the menu bar
        img.accessibilityDescription = "Claude HUD"
        return img
    }()

    // MARK: - Badge & Status Update
    
    private func updateBadge() {
        guard let button = statusItem?.button else { return }
        let count = HUDQueueManager.shared.totalCount
        if count > 0 {
            button.title = " \(count)"
            button.toolTip = "Claude HUD: \(count) waiting"
        } else {
            button.title = ""
            button.toolTip = "Claude HUD — Ready"
        }
    }
    
    // MARK: - Menu Construction
    
    private func buildMenu() {
        let newMenu = NSMenu(title: "Claude HUD Menu")
        newMenu.delegate = self
        self.menu = newMenu
        // No fixed menu on the item: left click shows it, right click opens the window directly.
        if let button = statusItem?.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        rebuildMenuState()
    }
    
    public func rebuildMenuState() {
        guard let menu = self.menu else { return }
        menu.removeAllItems()
        let queueCount = HUDQueueManager.shared.totalCount
        let isOverlayOn = LiveNotchPanelController.shared.isOverlayActive
        let settings = HUDSettingsStore.shared

        func item(_ title: String, _ action: Selector?, key: String = "", mods: NSEvent.ModifierFlags = .command,
                  state: Bool? = nil, symbol: String? = nil) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            i.target = self
            if let state { i.state = state ? .on : .off }
            if let symbol { i.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
            return i
        }

        // 1. The window first, where people look: open settings & live preview.
        let open = item("Open Claude HUD…", #selector(openDesignLabWindow), key: ",", symbol: "macwindow")
        open.attributedTitle = NSAttributedString(string: "Open Claude HUD…",
                                                  attributes: [.font: NSFont.menuFont(ofSize: 0).bold()])
        menu.addItem(open)

        let status = NSMenuItem(title: settings.isSnoozed
            ? "Snoozed until \((settings.snoozeUntil ?? Date()).formatted(date: .omitted, time: .shortened)) · \(queueCount) waiting"
            : (queueCount > 0 ? "\(queueCount) waiting" : "Ready — no questions waiting"), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        // 2. Answer the front card right here (same paths as the card itself).
        if let current = HUDQueueManager.shared.currentEvent, !settings.isSnoozed {
            menu.addItem(.separator())
            let header = NSMenuItem(title: current.title, action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            switch current {
            case .question(let q):
                for option in q.options {
                    let i = item("   \(option.label)", #selector(menuBarOptionClicked(_:)))
                    i.representedObject = option
                    menu.addItem(i)
                }
            case .permission:
                menu.addItem(item("   Allow", #selector(menuBarAllowPermission)))
                menu.addItem(item("   Deny", #selector(menuBarDenyPermission)))
            default:
                menu.addItem(item("   Show the card", #selector(showPanelClicked)))
            }
        }

        menu.addItem(.separator())
        menu.addItem(item("Live panel", #selector(toggleOverlayClicked), key: "o", mods: [.command, .control], state: isOverlayOn))

        let position = NSMenu(title: "Position")
        position.addItem(item("MacBook notch", #selector(setPositionToNotch), state: settings.displayPosition == .notch))
        position.addItem(item("Top right", #selector(setPositionToTopRight), state: settings.displayPosition == .topRight))
        let positionItem = NSMenuItem(title: "Position", action: nil, keyEquivalent: "")
        positionItem.submenu = position
        menu.addItem(positionItem)

        if settings.isSnoozed {
            menu.addItem(item("Resume", #selector(resumeClicked), symbol: "bell"))
        } else {
            let snooze = NSMenu(title: "Snooze")
            for (title, minutes) in [("15 minutes", 15), ("1 hour", 60)] {
                let i = item(title, #selector(snoozeClicked(_:)))
                i.tag = minutes
                snooze.addItem(i)
            }
            snooze.addItem(item("Until tomorrow", #selector(snoozeTomorrowClicked)))
            let snoozeItem = NSMenuItem(title: "Snooze", action: nil, keyEquivalent: "")
            snoozeItem.image = NSImage(systemSymbolName: "moon.zzz", accessibilityDescription: nil)
            snoozeItem.submenu = snooze
            menu.addItem(snoozeItem)
        }

        // 3. Help: welcome, demos, log. Everything else lives in the window.
        menu.addItem(.separator())
        let help = NSMenu(title: "Help")
        help.addItem(item("Welcome & Permissions…", #selector(showOnboardingClicked)))
        help.addItem(.separator())
        help.addItem(item("Send a 3-card demo queue", #selector(triggerDemoQueueBatch)))
        help.addItem(item("Send a Bash approval demo", #selector(triggerBashPermissionDemo)))
        help.addItem(item("Send a file diff demo", #selector(triggerDiffApprovalDemo)))
        let clear = item("Clear queue (\(queueCount))", #selector(clearQueueClicked))
        clear.isEnabled = queueCount > 0
        help.addItem(clear)
        help.addItem(.separator())
        help.addItem(item("Open log", #selector(openLogFileClicked)))
        let helpItem = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        helpItem.submenu = help
        menu.addItem(helpItem)

        menu.addItem(.separator())
        menu.addItem(item("Quit Claude HUD", #selector(quitAppClicked), key: "q"))
    }

    // MARK: - Direct Action Handlers (From Navbar)
    
    @objc private func menuBarOptionClicked(_ sender: NSMenuItem) {
        guard let opt = sender.representedObject as? QuestionOption,
              case .question(let q)? = HUDQueueManager.shared.currentEvent else { return }
        hudLog("⚡️ Answered from the menu bar: \(opt.label)", category: "NAVBAR")
        ClaudeSessionWatcher.shared.respond(toolUseId: q.id, answers: [q.question: opt.label])
        HUDQueueManager.shared.resolveCurrent()
    }

    @objc private func menuBarAllowPermission() { decidePermission(.allow) }
    @objc private func menuBarDenyPermission() { decidePermission(.deny) }

    private func decidePermission(_ d: ClaudeSessionWatcher.PermissionDecision) {
        guard case .permission(let p)? = HUDQueueManager.shared.currentEvent else { return }
        hudLog("⚡️ Permission \(d.rawValue) from the menu bar", category: "NAVBAR")
        ClaudeSessionWatcher.shared.respondPermission(id: p.id, decision: d)
        HUDQueueManager.shared.resolveCurrent()
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            openDesignLabWindow()
        } else if let menu, let item = statusItem {
            item.menu = menu
            item.button?.performClick(nil)
            item.menu = nil
        }
    }

    @objc private func showPanelClicked() { LiveNotchPanelController.shared.startOverlay() }
    @objc private func snoozeTomorrowClicked() { HUDQuiet.snoozeUntilTomorrow() }

    // MARK: - Actions
    
    @objc private func toggleOverlayClicked() {
        LiveNotchPanelController.shared.toggleOverlay()
        rebuildMenuState()
    }
    
    @objc private func setPositionToNotch() {
        HUDSettingsStore.shared.displayPosition = .notch
        rebuildMenuState()
    }
    
    @objc private func setPositionToTopRight() {
        HUDSettingsStore.shared.displayPosition = .topRight
        rebuildMenuState()
    }
    
    @objc private func toggleGitLineClicked() {
        HUDSettingsStore.shared.gitLineEnabled.toggle()
        rebuildMenuState()
    }
    
    @objc private func selectGitStyle(_ sender: NSMenuItem) {
        if let style = sender.representedObject as? GitLineStyle {
            HUDSettingsStore.shared.gitLineStyle = style
            rebuildMenuState()
        }
    }
    
    @objc private func selectGitTheme(_ sender: NSMenuItem) {
        if let theme = sender.representedObject as? GitLineColorTheme {
            HUDSettingsStore.shared.gitLineTheme = theme
            rebuildMenuState()
        }
    }
    
    @objc private func snoozeClicked(_ sender: NSMenuItem) { HUDQuiet.snooze(minutes: sender.tag) }
    @objc private func resumeClicked() { HUDQuiet.resume() }

    @objc private func showOnboardingClicked() {
        HUDOnboardingController.shared.show()
    }

    @objc public func openDesignLabWindow() {
        hudLog("🪟 Opening settings window", category: "WINDOW")
        NSApp.activate()
        if let existing = playgroundWindow {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude HUD"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ClaudeHUDPlaygroundView())
        window.center()
        playgroundWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    @objc public func openSettingsWindow() {
        hudLog("⚙️ Opening Claude HUD Settings window...", category: "WINDOW")
        
        NSApp.activate(ignoringOtherApps: true)
        
        if let existing = settingsWindow {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 620, height: 540),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude HUD Settings"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: ClaudeHUDSettingsView())
        self.settingsWindow = window
        window.makeKeyAndOrderFront(nil)
    }
    
    public func closeSettingsWindow() {
        settingsWindow?.orderOut(nil)
    }
    
    @objc private func triggerDemoQueueBatch() {
        hudLog("⚡️ Injecting 3-event demo sequence via Menu Bar...", category: "TEST")
        
        let q1 = QuestionPrompt(
            question: "Alignment check: does the card sit right under the MacBook notch?",
            header: "Notch check",
            options: [
                QuestionOption(keyNumber: 1, label: "Yes, flush", description: "The pill and card sit right under the notch with no gap.", tag: "Correct"),
                QuestionOption(keyNumber: 2, label: "There is a gap", description: "Adjust the notch offset in Settings.")
            ]
        )
        
        let perm = ToolPermission(
            toolName: "Bash",
            command: "git push origin main --force-with-lease",
            workingDir: "~/Development/Fun/cc",
            reason: "Updates history from the remote.",
            isDestructive: true
        )
        
        let diff = FileDiffData(
            filePath: "ClaudeHUD/Window/HUDMenuBarController.swift",
            additionsCount: 180,
            deletionsCount: 0,
            lines: [
                DiffLine(type: .addition, text: "+ public final class HUDMenuBarController: NSObject {"),
                DiffLine(type: .addition, text: "+     public static let shared = HUDMenuBarController()"),
                DiffLine(type: .addition, text: "+     public func setupStatusBarItem() { ... }"),
                DiffLine(type: .addition, text: "+ }")
            ]
        )
        
        HUDQueueManager.shared.enqueueBatch([
            .question(q1),
            .permission(perm),
            .fileDiff(diff)
        ])
    }
    
    @objc private func triggerBashPermissionDemo() {
        let perm = ToolPermission(
            toolName: "Bash",
            command: "rm -rf build/ && swift build -c release",
            workingDir: "~/Development/Fun/cc/ClaudeHUD",
            reason: "Clears the build cache and rebuilds.",
            isDestructive: true
        )
        HUDQueueManager.shared.enqueue(.permission(perm))
    }
    
    @objc private func triggerDiffApprovalDemo() {
        let diff = FileDiffData(
            filePath: "ClaudeHUD/App/ClaudeHUDApp.swift",
            additionsCount: 4,
            deletionsCount: 1,
            lines: [
                DiffLine(type: .context, text: "    public func applicationDidFinishLaunching(_ notification: Notification) {"),
                DiffLine(type: .addition, text: "+         HUDMenuBarController.shared.setupStatusBarItem()"),
                DiffLine(type: .context, text: "    }")
            ]
        )
        HUDQueueManager.shared.enqueue(.fileDiff(diff))
    }
    
    @objc private func clearQueueClicked() {
        hudLog("🗑️ Clearing queue via Menu Bar...", category: "TEST")
        HUDQueueManager.shared.clearAll()
    }
    
    @objc private func openLogFileClicked() {
        hudLog("📄 Opening /tmp/claude-hud.log...", category: "NAVBAR")
        let fileURL = URL(fileURLWithPath: "/tmp/claude-hud.log")
        NSWorkspace.shared.open(fileURL)
    }
    
    @objc private func quitAppClicked() {
        hudLog("👋 Quitting Claude HUD via Menu Bar...", category: "NAVBAR")
        NSApp.terminate(nil)
    }
}

private extension NSFont {
    func bold() -> NSFont { NSFontManager.shared.convert(self, toHaveTrait: .boldFontMask) }
}
