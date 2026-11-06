//
//  LiveNotchPanelController.swift
//  ClaudeHUD
//
//  True macOS Floating Screen Overlay Window Controller
//  Mounts transparently over the physical MacBook notch or floats at top-right
//  Level: .statusBar + 2, Joins all spaces, Zero focus-stealing.
//

import AppKit
import SwiftUI
import Combine

public final class LiveNotchPanel: NSPanel {
    public init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.isFloatingPanel = true
        self.becomesKeyOnlyIfNeeded = false
        self.isOpaque = false
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.backgroundColor = .clear
        self.hasShadow = false
        self.isMovable = false
        
        // Appear on all desktop spaces and during mission control
        self.collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle
        ]
        
        // Floats above normal apps and menu bar
        self.level = .statusBar + 2
        self.allowsToolTipsWhenApplicationIsInactive = true
        self.isReleasedWhenClosed = false
    }
    
    // Borderless panels refuse key status by default, which silently broke the
    // "Other" text field and every ⌘↵ shortcut. Non-activating, so Claude keeps app focus.
    public override var canBecomeKey: Bool { true }

    // Two-finger swipe on a card: left = skip / later, right = next card. Vertical scrolls pass through.
    private var swipeDX: CGFloat = 0
    private var swipeDY: CGFloat = 0
    public override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        guard HUDSettingsStore.shared.swipeGestures, event.hasPreciseScrollingDeltas else { return }
        if event.phase == .began { swipeDX = 0; swipeDY = 0 }
        swipeDX += event.scrollingDeltaX
        swipeDY += event.scrollingDeltaY
        guard event.phase == .ended else { return }
        defer { swipeDX = 0; swipeDY = 0 }
        guard abs(swipeDX) > 70, abs(swipeDX) > abs(swipeDY) * 1.5, HUDQueueManager.shared.currentEvent != nil else { return }
        HUDQuiet.haptic()
        // Natural scrolling: fingers moving left give a negative delta.
        HUDHotkeys.shared.actions.send(swipeDX < 0 ? .skip : .next)
        hudLog("👆 Swipe \(swipeDX < 0 ? "left → skip" : "right → next")", category: "USER")
    }
    // No updateConstraintsIfNeeded() override: a no-op there stalls the window's
    // update→layout→display pass, so SwiftUI state changed but the pixels never did.
}

// MARK: - Live Notch Overlay Manager

@MainActor
public final class LiveNotchPanelController: ObservableObject {
    public static let shared = LiveNotchPanelController()
    
    @Published public private(set) var isOverlayActive: Bool = false
    private var panel: LiveNotchPanel?
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupSettingsObserver()
    }
    
    public var targetScreen: NSScreen? { screen(for: HUDSettingsStore.shared.displayPosition) }

    // Takes the position explicitly: $displayPosition fires before the stored value changes.
    private func screen(for position: HUDDisplayPosition) -> NSScreen? {
        if position == .notch {
            if let physicalNotchScreen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
                return physicalNotchScreen
            }
        }
        return NSScreen.main ?? NSScreen.screens.first
    }
    
    public func startOverlay() {
        guard panel == nil else {
            panel?.orderFrontRegardless()
            isOverlayActive = true
            return
        }
        
        guard let screen = targetScreen else {
            hudLog("❌ No target screen found for Notch Panel", category: "OVERLAY")
            return
        }
        
        let initialWidth: CGFloat = LiveFloatingContainerView.panelSize.width
        let initialHeight: CGFloat = LiveFloatingContainerView.panelSize.height
        let frame = calculateFrame(for: screen, width: initialWidth, height: initialHeight, position: HUDSettingsStore.shared.displayPosition)
        
        hudLog("🖥️ Creating Live Floating Notch Panel at frame: \(frame) on screen: \(screen.localizedName)", category: "OVERLAY")
        
        let newPanel = LiveNotchPanel(contentRect: frame)
        newPanel.sharingType = HUDSettingsStore.shared.hideFromScreenShare ? .none : .readOnly
        let hostingView = NSHostingView(rootView: LiveFloatingContainerView())
        hostingView.sizingOptions = []
        newPanel.contentView = hostingView
        newPanel.orderFrontRegardless()
        
        self.panel = newPanel
        self.isOverlayActive = true
        
        hudLog("✅ Live Floating Notch Overlay ACTIVE and displayed on screen", category: "OVERLAY")
    }
    
    /// Make the panel key so plain keys (1…9, ↵) reach the card.
    public func focusPanel() {
        panel?.makeKeyAndOrderFront(nil)
    }

    public func stopOverlay() {
        panel?.orderOut(nil)
        panel = nil
        isOverlayActive = false
        hudLog("🛑 Live Floating Notch Overlay STOPPED", category: "OVERLAY")
    }
    
    public func toggleOverlay() {
        if isOverlayActive {
            stopOverlay()
        } else {
            startOverlay()
        }
    }
    
    public func updatePosition(position: HUDDisplayPosition) {
        guard let panel = panel, let screen = screen(for: position) else { return }
        let currentSize = panel.frame.size
        let newFrame = calculateFrame(for: screen, width: currentSize.width, height: currentSize.height, position: position)
        
        hudLog("🔄 Moving overlay to \(position.rawValue): \(newFrame)", category: "OVERLAY")
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(newFrame, display: true)
        }
    }
    
    private func calculateFrame(for screen: NSScreen, width: CGFloat, height: CGFloat, position: HUDDisplayPosition) -> NSRect {
        let screenRect = screen.frame
        switch position {
        case .notch:
            let notchX = screenRect.midX - (width / 2)
            let notchY = screenRect.maxY - height
            return NSRect(x: notchX, y: notchY, width: width, height: height)
        case .topRight:
            let rightX = screenRect.maxX - width - 20
            let rightY = screenRect.maxY - height - 20
            return NSRect(x: rightX, y: rightY, width: width, height: height)
        }
    }
    
    private func setupSettingsObserver() {
        HUDSettingsStore.shared.$hideFromScreenShare
            .sink { [weak self] hide in self?.panel?.sharingType = hide ? .none : .readOnly }
            .store(in: &cancellables)

        HUDSettingsStore.shared.$displayPosition
            .dropFirst()
            .sink { [weak self] newPos in
                self?.updatePosition(position: newPos)
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                hudLog("🖥️ Screen parameters changed, recalibrating overlay position...", category: "OVERLAY")
                self.updatePosition(position: HUDSettingsStore.shared.displayPosition)
            }
            .store(in: &cancellables)
    }
}

// MARK: - Live Floating SwiftUI Container View

public struct LiveFloatingContainerView: View {
    @ObservedObject private var queueManager = HUDQueueManager.shared
    @ObservedObject private var settings = HUDSettingsStore.shared
    
    private var notchHeight: CGFloat {
        // The screen the panel sits on, not NSScreen.main: with an external display as main,
        // main has no notch and the card header came out 4 pt short of the real notch.
        if let insets = LiveNotchPanelController.shared.targetScreen?.safeAreaInsets.top, insets > 0 {
            return insets // MacBook physical notch (32.0pt)
        }
        // External display or notchless Mac: sit directly beneath the macOS menu bar (28.0pt)
        return 28.0
    }
    
    /// Fixed canvas: without it the window shrank to the idle pill (155×56) and never
    /// grew back, so live cards were clipped. Transparent pixels still pass clicks through.
    public static let panelSize = CGSize(width: 480, height: 520)

    public init() {}
    
    public var body: some View {
        ClaudeHUDShellView(
            currentEvent: Binding(
                get: { queueManager.currentEvent },
                set: { _ in }
            ),
            displayPosition: $settings.displayPosition,
            notchTopInset: settings.displayPosition == .notch ? notchHeight : 0,
            onActionLogged: { action in
                hudLog("⚡️ User Action on Live Notch: \(action)", category: "USER")
            }
        )
        .frame(width: Self.panelSize.width, height: Self.panelSize.height,
               alignment: settings.displayPosition == .notch ? .top : .topTrailing)
        .environment(\.hudHandlesHotkeys, true)
        .onAppear {
            hudLog("👀 LiveFloatingContainerView mounted on notch overlay with notchTopInset: \(notchHeight)", category: "VIEW")
        }
    }
}
