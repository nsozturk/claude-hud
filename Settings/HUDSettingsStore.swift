//
//  HUDSettingsStore.swift
//  ClaudeHUD
//
//  Central Settings & Preferences Store
//  Controls Display Mode, bottom scanner line, Themes, and Queue Behaviors.
//

import AppKit
import SwiftUI
import Combine

// MARK: - Scanner line Animation Styles

public enum GitLineStyle: String, CaseIterable, Identifiable {
    case gitScanner = "Scanner (ping-pong)"
    case fluidSweep = "Fluid sweep"
    case comet = "Comet"
    case dualBeams = "Dual beams"
    case centerBurst = "Center burst"
    case heartbeat = "Heartbeat"
    case breathingGlow = "Breathing pulse"
    case marchingDots = "Marching dots"
    case rainbow = "Rainbow"
    case staticNeon = "Static neon"

    public var id: String { rawValue }

    public var description: String {
        switch self {
        case .gitScanner: return "A beam that bounces left and right, K.I.T.T. style."
        case .fluidSweep: return "A wide wave that keeps flowing in one direction."
        case .comet: return "A bright head with a long fading tail."
        case .dualBeams: return "Two beams meet in the middle and part again."
        case .centerBurst: return "Light opens out from the center to both edges."
        case .heartbeat: return "Two quick pulses, then a rest."
        case .breathingGlow: return "The whole line softly breathes in and out."
        case .marchingDots: return "A row of dots with a wave of light running through."
        case .rainbow: return "The color drifts around the color wheel as it flows."
        case .staticNeon: return "A thin, steady neon line."
        }
    }
}

// MARK: - Scanner line color (any color; presets are suggestions)

public struct GitLineColorTheme: Hashable, Identifiable {
    public let name: String
    public let hex: String          // "#RRGGBB"
    public var id: String { hex }

    public init(name: String, hex: String) { self.name = name; self.hex = hex.uppercased() }

    public static let presets: [GitLineColorTheme] = [
        .init(name: "Terracotta", hex: "#D96B43"),
        .init(name: "Ember", hex: "#FF5A36"),
        .init(name: "Coral", hex: "#FF7F6B"),
        .init(name: "Rose", hex: "#F43F5E"),
        .init(name: "Magenta", hex: "#FA59B3"),
        .init(name: "Lavender", hex: "#A78BFA"),
        .init(name: "Sapphire", hex: "#3C95F6"),
        .init(name: "Ice", hex: "#9AD8FF"),
        .init(name: "Mint", hex: "#5EEAD4"),
        .init(name: "Emerald", hex: "#34C78C"),
        .init(name: "Lime", hex: "#A3E635"),
        .init(name: "Gold", hex: "#F59F26"),
    ]
    public static let `default` = presets[0]

    public var nsColor: NSColor {
        let v = UInt32(hex.dropFirst(), radix: 16) ?? 0xD96B43
        return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
    public var primaryColor: Color { Color(nsColor: nsColor) }
    /// Glow = the same hue lifted toward white, so any custom color gets a matching highlight.
    public var glowColor: Color { Color(nsColor: nsColor.blended(withFraction: 0.35, of: .white) ?? nsColor) }

    public static func custom(_ color: Color) -> GitLineColorTheme {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .orange
        let hex = String(format: "#%02X%02X%02X", Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
        return presets.first { $0.hex == hex } ?? .init(name: "Custom", hex: hex)
    }
}

// MARK: - Card transitions

public enum CardTransitionStyle: String, CaseIterable, Identifiable {
    case deck = "Card deck"
    case flyRight = "Fly right"
    case tossUp = "Toss up"
    case flip = "Flip"
    case drop = "Drop in"
    case fade = "Fade"
    case none = "None"

    public var id: String { rawValue }
    public var description: String {
        switch self {
        case .deck: return "The answered card flies left; the next one rises from the stack."
        case .flyRight: return "The answered card flies off to the right."
        case .tossUp: return "The answered card goes back up into the notch."
        case .flip: return "Cards flip over like a page."
        case .drop: return "The next card drops down from the top."
        case .fade: return "A soft fade and scale."
        case .none: return "Switch instantly."
        }
    }
}

// MARK: - Settings Store Observable Object

@MainActor
public class HUDSettingsStore: ObservableObject {
    public static let shared = HUDSettingsStore()
    
    private let defaults = UserDefaults.standard
    
    @Published public var displayPosition: HUDDisplayPosition {
        didSet { defaults.set(displayPosition.rawValue, forKey: "hud_displayPosition") }
    }
    @Published public var gitLineEnabled: Bool {
        didSet { defaults.set(gitLineEnabled, forKey: "hud_gitLineEnabled") }
    }
    @Published public var gitLineStyle: GitLineStyle {
        didSet { defaults.set(gitLineStyle.rawValue, forKey: "hud_gitLineStyle") }
    }
    @Published public var gitLineTheme: GitLineColorTheme {
        didSet { defaults.set(gitLineTheme.hex, forKey: "hud_gitLineColorHex") }
    }
    @Published public var gitLineThickness: CGFloat {
        didSet { defaults.set(Double(gitLineThickness), forKey: "hud_gitLineThickness") }
    }
    @Published public var gitLineSpeed: Double {
        didSet { defaults.set(gitLineSpeed, forKey: "hud_gitLineSpeed") }
    }
    /// Beam length as a share of the line (0.06…0.5).
    @Published public var gitLineBeamWidth: Double {
        didSet { defaults.set(gitLineBeamWidth, forKey: "hud_gitLineBeamWidth") }
    }
    /// Halo strength around the beam (0…1).
    @Published public var gitLineGlow: Double {
        didSet { defaults.set(gitLineGlow, forKey: "hud_gitLineGlow") }
    }
    /// Length of the fading trail behind moving beams (0…1).
    @Published public var gitLineTrail: Double {
        didSet { defaults.set(gitLineTrail, forKey: "hud_gitLineTrail") }
    }
    /// Run right to left instead of left to right.
    @Published public var gitLineReverse: Bool {
        didSet { defaults.set(gitLineReverse, forKey: "hud_gitLineReverse") }
    }
    /// Answer Claude's permission prompts from the HUD (PermissionRequest hook).
    @Published public var approvePermissions: Bool {
        didSet { defaults.set(approvePermissions, forKey: "hud_approvePermissions") }
    }
    /// Show waiting cards as a small pill; hover to open.
    @Published public var compactCards: Bool {
        didSet { defaults.set(compactCards, forKey: "hud_compactCards") }
    }
    /// Two-finger swipe on a card: left skips, right shows the next card.
    @Published public var swipeGestures: Bool {
        didSet { defaults.set(swipeGestures, forKey: "hud_swipeGestures") }
    }
    /// Trackpad tap when a swipe lands.
    @Published public var haptics: Bool {
        didSet { defaults.set(haptics, forKey: "hud_haptics") }
    }
    /// No sounds while the microphone is in use.
    @Published public var quietDuringCalls: Bool {
        didSet { defaults.set(quietDuringCalls, forKey: "hud_quietDuringCalls") }
    }
    /// Keep the panel out of screen shares and recordings.
    @Published public var hideFromScreenShare: Bool {
        didSet { defaults.set(hideFromScreenShare, forKey: "hud_hideFromScreenShare") }
    }
    /// Free-text reply box (with dictation) on session cards.
    @Published public var replyBox: Bool {
        didSet { defaults.set(replyBox, forKey: "hud_replyBox") }
    }
    /// Drop files on a card to add their paths to the reply.
    @Published public var fileDropPaths: Bool {
        didSet { defaults.set(fileDropPaths, forKey: "hud_fileDropPaths") }
    }
    /// Cards stay queued but hidden until this time (not persisted: a restart wakes the HUD).
    @Published public var snoozeUntil: Date? = nil
    public var isSnoozed: Bool { (snoozeUntil ?? .distantPast) > Date() }
    @Published public var cardTransition: CardTransitionStyle {
        didSet { defaults.set(cardTransition.rawValue, forKey: "hud_cardTransition") }
    }
    /// How far the stack of waiting cards reaches below the card, in points (layers share it).
    @Published public var stackDepth: Double {
        didSet { defaults.set(stackDepth, forKey: "hud_stackDepth") }
    }
    /// Sound per card type (a macOS system sound name) and one volume for all.
    @Published public var soundQuestion: String {
        didSet { defaults.set(soundQuestion, forKey: "hud_soundQuestion") }
    }
    @Published public var soundPermission: String {
        didSet { defaults.set(soundPermission, forKey: "hud_soundPermission") }
    }
    @Published public var soundSession: String {
        didSet { defaults.set(soundSession, forKey: "hud_soundSession") }
    }
    @Published public var soundVolume: Double {
        didSet { defaults.set(soundVolume, forKey: "hud_soundVolume") }
    }
    @Published public var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: "hud_soundEnabled") }
    }
    @Published public var showQueueStackedDepth: Bool {
        didSet { defaults.set(showQueueStackedDepth, forKey: "hud_showQueueStackedDepth") }
    }
    /// Off by default: the app lives in the menu bar and only opens its window from there.
    @Published public var showInDock: Bool {
        didSet { defaults.set(showInDock, forKey: "hud_showInDock"); applyDockPolicy() }
    }

    public func applyDockPolicy() {
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
        if !showInDock { NSApp.activate() } // keep any open window in front after leaving the Dock
    }

    @Published public var notchVerticalOffset: CGFloat {
        didSet { defaults.set(Double(notchVerticalOffset), forKey: "hud_notchVerticalOffset") }
    }
    
    private init() {
        let posStr = defaults.string(forKey: "hud_displayPosition") ?? HUDDisplayPosition.notch.rawValue
        self.displayPosition = HUDDisplayPosition(rawValue: posStr) ?? .notch
        
        self.gitLineEnabled = defaults.object(forKey: "hud_gitLineEnabled") != nil ? defaults.bool(forKey: "hud_gitLineEnabled") : true
        
        let styleStr = defaults.string(forKey: "hud_gitLineStyle") ?? GitLineStyle.gitScanner.rawValue
        self.gitLineStyle = GitLineStyle(rawValue: styleStr) ?? .gitScanner
        
        let hex = defaults.string(forKey: "hud_gitLineColorHex") ?? GitLineColorTheme.default.hex
        self.gitLineTheme = GitLineColorTheme.presets.first { $0.hex == hex.uppercased() } ?? GitLineColorTheme(name: "Custom", hex: hex)
        
        let thick = defaults.double(forKey: "hud_gitLineThickness")
        self.gitLineThickness = thick > 0 ? CGFloat(thick) : 2.5
        
        let speed = defaults.double(forKey: "hud_gitLineSpeed")
        self.gitLineSpeed = speed > 0 ? speed : 1.0
        
        self.soundEnabled = defaults.object(forKey: "hud_soundEnabled") != nil ? defaults.bool(forKey: "hud_soundEnabled") : true
        self.showQueueStackedDepth = defaults.object(forKey: "hud_showQueueStackedDepth") != nil ? defaults.bool(forKey: "hud_showQueueStackedDepth") : true
        
        self.notchVerticalOffset = CGFloat(defaults.double(forKey: "hud_notchVerticalOffset"))
        self.showInDock = defaults.bool(forKey: "hud_showInDock")
        self.soundQuestion = defaults.string(forKey: "hud_soundQuestion") ?? "Glass"
        self.soundPermission = defaults.string(forKey: "hud_soundPermission") ?? "Funk"
        self.soundSession = defaults.string(forKey: "hud_soundSession") ?? "Pop"
        self.soundVolume = defaults.object(forKey: "hud_soundVolume") as? Double ?? 0.7
        self.cardTransition = CardTransitionStyle(rawValue: defaults.string(forKey: "hud_cardTransition") ?? "") ?? .deck
        let depth = defaults.double(forKey: "hud_stackDepth"); self.stackDepth = depth > 0 ? depth : 14
        self.approvePermissions = defaults.object(forKey: "hud_approvePermissions") as? Bool ?? false
        self.compactCards = defaults.object(forKey: "hud_compactCards") as? Bool ?? false
        self.swipeGestures = defaults.object(forKey: "hud_swipeGestures") as? Bool ?? true
        self.haptics = defaults.object(forKey: "hud_haptics") as? Bool ?? true
        self.quietDuringCalls = defaults.object(forKey: "hud_quietDuringCalls") as? Bool ?? true
        self.hideFromScreenShare = defaults.object(forKey: "hud_hideFromScreenShare") as? Bool ?? true
        self.replyBox = defaults.object(forKey: "hud_replyBox") as? Bool ?? true
        self.fileDropPaths = defaults.object(forKey: "hud_fileDropPaths") as? Bool ?? true
        let bw = defaults.double(forKey: "hud_gitLineBeamWidth"); self.gitLineBeamWidth = bw > 0 ? bw : 0.2
        self.gitLineGlow = defaults.object(forKey: "hud_gitLineGlow") as? Double ?? 0.6
        self.gitLineTrail = defaults.object(forKey: "hud_gitLineTrail") as? Double ?? 0.4
        self.gitLineReverse = defaults.bool(forKey: "hud_gitLineReverse")
    }
}
