//
//  ClaudeHUDTheme.swift
//  ClaudeHUD
//
//  Premium Liquid Glass Design Tokens & Color Palette
//  Matching Claude Code Terracotta, Apple Glassmorphism & High-Contrast Micro-Typography
//

import SwiftUI

public enum ClaudeHUDTheme {
    // MARK: - Core Palette
    
    /// Anthropic's iconic warm terracotta/rust accent
    public static let terracotta = Color(red: 0.851, green: 0.420, blue: 0.263) // #D96B43
    public static let terracottaGlow = Color(red: 0.933, green: 0.522, blue: 0.353) // #EE855A
    public static let terracottaDark = Color(red: 0.620, green: 0.280, blue: 0.160)
    
    /// Deep warm charcoal / night canvas
    public static let darkCharcoal = Color(red: 0.078, green: 0.078, blue: 0.090) // #141417
    public static let deepCanvas = Color(red: 0.051, green: 0.051, blue: 0.059) // #0D0D0F
    public static let cardSurface = Color(red: 0.118, green: 0.118, blue: 0.133, opacity: 0.72)
    
    /// High-contrast typography colors
    public static let creamText = Color(red: 0.961, green: 0.961, blue: 0.949) // #F5F5F2
    public static let secondaryText = Color(red: 0.682, green: 0.682, blue: 0.710) // #AEAEB5
    public static let subtleText = Color(red: 0.451, green: 0.451, blue: 0.478) // #73737A
    
    /// Status Colors
    public static let emerald = Color(red: 0.204, green: 0.780, blue: 0.549) // #34C78C (Success, Start)
    public static let ruby = Color(red: 0.937, green: 0.329, blue: 0.314)    // #EF5450 (Deny, Danger)
    public static let amber = Color(red: 0.961, green: 0.624, blue: 0.149)   // #F59F26 (Warning, Question)
    public static let sapphire = Color(red: 0.235, green: 0.584, blue: 0.965)// #3C95F6 (Info, Session link)

    // MARK: - Glassmorphism Borders & Shadows
    
    public static var borderGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.24),
                Color.white.opacity(0.08),
                terracotta.opacity(0.18),
                Color.white.opacity(0.04)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public static var activeSegmentBorder: LinearGradient {
        LinearGradient(
            colors: [
                terracottaGlow.opacity(0.75),
                terracotta.opacity(0.40),
                Color.white.opacity(0.15)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Animation Springs
    
    public static let fluidSpring = Animation.spring(response: 0.36, dampingFraction: 0.76, blendDuration: 0)
    public static let bounceSpring = Animation.spring(response: 0.44, dampingFraction: 0.68, blendDuration: 0)
    public static let snappySpring = Animation.spring(response: 0.24, dampingFraction: 0.82, blendDuration: 0)
}

// MARK: - View Modifiers for Glass Effects

/// Set by `ClaudeHUDShellView`: the shell owns the one card surface, so inner cards
/// skip their own glass instead of stacking a second rounded panel inside it.
private struct HUDSurfaceOwnedKey: EnvironmentKey { static let defaultValue = false }

public extension EnvironmentValues {
    var hudSurfaceOwnedByShell: Bool {
        get { self[HUDSurfaceOwnedKey.self] }
        set { self[HUDSurfaceOwnedKey.self] = newValue }
    }
}

public struct LiquidGlassModifier: ViewModifier {
    @Environment(\.hudSurfaceOwnedByShell) private var surfaceOwnedByShell
    var cornerRadius: CGFloat
    var borderOpacity: CGFloat
    var isHovered: Bool
    
    public init(cornerRadius: CGFloat = 20, borderOpacity: CGFloat = 0.18, isHovered: Bool = false) {
        self.cornerRadius = cornerRadius
        self.borderOpacity = borderOpacity
        self.isHovered = isHovered
    }
    
    public func body(content: Content) -> some View {
        if surfaceOwnedByShell {
            content
        } else {
            glass(content)
        }
    }

    private func glass(_ content: Content) -> some View {
        content
            .background(
                ZStack {
                    // Apple native ultra-thin frosted glass
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    
                    // Dark atmospheric tint
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(ClaudeHUDTheme.darkCharcoal.opacity(0.82))
                    
                    // Subtle terracotta gradient glow from top
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    ClaudeHUDTheme.terracotta.opacity(isHovered ? 0.08 : 0.03),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        isHovered ? ClaudeHUDTheme.activeSegmentBorder : ClaudeHUDTheme.borderGradient,
                        lineWidth: isHovered ? 1.2 : 0.8
                    )
            )
            .shadow(
                color: Color.black.opacity(isHovered ? 0.55 : 0.40),
                radius: isHovered ? 24 : 14,
                x: 0,
                y: isHovered ? 10 : 6
            )
    }
}

public extension View {
    func liquidGlass(cornerRadius: CGFloat = 20, borderOpacity: CGFloat = 0.18, isHovered: Bool = false) -> some View {
        self.modifier(LiquidGlassModifier(cornerRadius: cornerRadius, borderOpacity: borderOpacity, isHovered: isHovered))
    }
}
