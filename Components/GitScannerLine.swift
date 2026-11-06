//
//  GitScannerLine.swift
//  ClaudeHUD
//
//  Animated light along the bottom edge of a card. Every pattern is a function of time drawn
//  into one Canvas, so a new pattern is a few lines and all of them share the same knobs:
//  color, speed, thickness, beam width, glow, trail and direction.
//

import SwiftUI

public struct GitScannerLine: View {
    @ObservedObject private var settings = HUDSettingsStore.shared

    public init() {}

    public var body: some View {
        if settings.gitLineEnabled {
            let h = settings.gitLineThickness
            TimelineView(.animation(paused: settings.gitLineStyle == .staticNeon)) { timeline in
                Canvas { ctx, size in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    Self.draw(ctx: &ctx, size: size, time: t, s: Self.Params(settings))
                }
            }
            .frame(height: max(4, h * 3)) // room for the glow above and below the line
        }
    }

    // MARK: - Drawing

    struct Params {
        let style: GitLineStyle
        let color: Color, glowColor: Color, nsColor: NSColor
        let speed: Double, thickness: CGFloat, beam: Double, glow: Double, trail: Double, reverse: Bool

        @MainActor init(_ s: HUDSettingsStore) {
            style = s.gitLineStyle
            color = s.gitLineTheme.primaryColor
            glowColor = s.gitLineTheme.glowColor
            nsColor = s.gitLineTheme.nsColor
            speed = s.gitLineSpeed; thickness = s.gitLineThickness
            beam = s.gitLineBeamWidth; glow = s.gitLineGlow; trail = s.gitLineTrail; reverse = s.gitLineReverse
        }
    }

    static func draw(ctx: inout GraphicsContext, size: CGSize, time: TimeInterval, s: Params) {
        let W = size.width, h = s.thickness, midY = size.height / 2
        let cycle = 1.6 / max(0.2, s.speed)
        let p = (time / cycle).truncatingRemainder(dividingBy: 1)          // 0…1 per cycle
        let tri = p < 0.5 ? p * 2 : 2 - p * 2                               // 0→1→0
        let smooth = 0.5 - 0.5 * cos(.pi * tri)                             // eased ping-pong
        let bw = max(12, W * s.beam)
        func X(_ x: CGFloat) -> CGFloat { s.reverse ? W - x : x }

        // faint track
        ctx.fill(Path(CGRect(x: 0, y: midY - h / 2, width: W, height: h)), with: .color(.white.opacity(0.06)))

        switch s.style {
        case .gitScanner:
            let x = bw / 2 + smooth * (W - bw)
            let movingRight = p < 0.5
            trailBehind(&ctx, x: x, toRight: movingRight, s: s, W: W, midY: midY)
            beam(&ctx, cx: x, width: bw, alpha: 1, s: s, midY: midY)

        case .fluidSweep:
            let x = X(-bw + p * (W + 2 * bw))
            beam(&ctx, cx: x, width: bw * 2.2, alpha: 1, s: s, midY: midY)

        case .comet:
            let x = X(-bw / 2 + p * (W + bw))
            trailBehind(&ctx, x: x, toRight: !s.reverse, s: s, W: W, midY: midY, lengthScale: 2)
            beam(&ctx, cx: x, width: bw * 0.5, alpha: 1, s: s, midY: midY)

        case .dualBeams:
            let x = bw / 2 + smooth * (W / 2 - bw / 2)
            beam(&ctx, cx: x, width: bw * 0.8, alpha: 1, s: s, midY: midY)
            beam(&ctx, cx: W - x, width: bw * 0.8, alpha: 1, s: s, midY: midY)

        case .centerBurst:
            let half = p * W / 2, a = 1 - p
            ctx.fill(Path(roundedRect: CGRect(x: W / 2 - half, y: midY - h / 2, width: half * 2, height: h), cornerRadius: h / 2),
                     with: .color(s.color.opacity(0.35 * a)))
            beam(&ctx, cx: W / 2 - half, width: bw * 0.5, alpha: a, s: s, midY: midY)
            beam(&ctx, cx: W / 2 + half, width: bw * 0.5, alpha: a, s: s, midY: midY)

        case .heartbeat:
            func bump(_ c: Double) -> Double { max(0, 1 - abs(p - c) / 0.07) }
            let a = 0.15 + 0.85 * max(bump(0.1), bump(0.28) * 0.8)
            fullLine(&ctx, alpha: a, s: s, W: W, midY: midY)

        case .breathingGlow:
            fullLine(&ctx, alpha: 0.25 + 0.75 * (0.5 - 0.5 * cos(2 * .pi * p)), s: s, W: W, midY: midY)

        case .marchingDots:
            let step = max(8, h * 4)
            var x = step / 2
            while x < W {
                let wave = cos(2 * .pi * (Double(X(x) / W) * 1.5 - p))
                let a = 0.15 + 0.85 * max(0, wave)
                let r = h * (0.7 + 0.5 * a)
                ctx.fill(Path(ellipseIn: CGRect(x: x - r / 2, y: midY - r / 2, width: r, height: r)), with: .color(s.glowColor.opacity(a)))
                x += step
            }

        case .rainbow:
            var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, al: CGFloat = 0
            (s.nsColor.usingColorSpace(.sRGB) ?? s.nsColor).getHue(&hue, saturation: &sat, brightness: &bri, alpha: &al)
            let shift = s.reverse ? -p : p
            let stops = (0...6).map { i -> Gradient.Stop in
                let hh = (Double(hue) + Double(i) / 6 + shift).truncatingRemainder(dividingBy: 1)
                return .init(color: Color(hue: hh < 0 ? hh + 1 : hh, saturation: max(0.6, Double(sat)), brightness: 1), location: Double(i) / 6)
            }
            let rect = CGRect(x: 0, y: midY - h / 2, width: W, height: h)
            halo(&ctx, rect: rect, s: s, shading: .linearGradient(Gradient(stops: stops), startPoint: .zero, endPoint: CGPoint(x: W, y: 0)))
            ctx.fill(Path(roundedRect: rect, cornerRadius: h / 2), with: .linearGradient(Gradient(stops: stops), startPoint: .zero, endPoint: CGPoint(x: W, y: 0)))

        case .staticNeon:
            fullLine(&ctx, alpha: 1, s: s, W: W, midY: midY)
        }
    }

    /// One beam: transparent → glow → white core → glow → transparent, with a blurred halo.
    private static func beam(_ ctx: inout GraphicsContext, cx: CGFloat, width: CGFloat, alpha: Double, s: Params, midY: CGFloat) {
        let h = s.thickness
        let rect = CGRect(x: cx - width / 2, y: midY - h / 2, width: width, height: h)
        let g = Gradient(stops: [
            .init(color: s.color.opacity(0), location: 0),
            .init(color: s.glowColor.opacity(alpha), location: 0.35),
            .init(color: Color.white.opacity(0.9 * alpha), location: 0.5),
            .init(color: s.glowColor.opacity(alpha), location: 0.65),
            .init(color: s.color.opacity(0), location: 1),
        ])
        let shading = GraphicsContext.Shading.linearGradient(g, startPoint: CGPoint(x: rect.minX, y: 0), endPoint: CGPoint(x: rect.maxX, y: 0))
        halo(&ctx, rect: rect, s: s, shading: shading)
        ctx.fill(Path(roundedRect: rect, cornerRadius: h / 2), with: shading)
    }

    private static func halo(_ ctx: inout GraphicsContext, rect: CGRect, s: Params, shading: GraphicsContext.Shading) {
        guard s.glow > 0.01 else { return }
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 1 + s.glow * 6))
            layer.opacity = s.glow
            layer.fill(Path(roundedRect: rect.insetBy(dx: 0, dy: -s.thickness * 0.8), cornerRadius: s.thickness), with: shading)
        }
    }

    private static func trailBehind(_ ctx: inout GraphicsContext, x: CGFloat, toRight: Bool, s: Params, W: CGFloat, midY: CGFloat, lengthScale: Double = 1) {
        let len = W * s.trail * 0.5 * lengthScale
        guard len > 2 else { return }
        let h = s.thickness
        let from = toRight ? x - len : x + len
        let rect = CGRect(x: min(from, x), y: midY - h / 2, width: len, height: h)
        let g = Gradient(colors: [s.color.opacity(0), s.glowColor.opacity(0.75)])
        ctx.fill(Path(roundedRect: rect, cornerRadius: h / 2),
                 with: .linearGradient(g, startPoint: CGPoint(x: from, y: 0), endPoint: CGPoint(x: x, y: 0)))
    }

    private static func fullLine(_ ctx: inout GraphicsContext, alpha: Double, s: Params, W: CGFloat, midY: CGFloat) {
        let h = s.thickness
        let rect = CGRect(x: 0, y: midY - h / 2, width: W, height: h)
        let g = Gradient(colors: [s.color.opacity(0.3 * alpha), s.glowColor.opacity(alpha), s.color.opacity(0.3 * alpha)])
        let shading = GraphicsContext.Shading.linearGradient(g, startPoint: .zero, endPoint: CGPoint(x: W, y: 0))
        halo(&ctx, rect: rect, s: s, shading: shading)
        ctx.fill(Path(roundedRect: rect, cornerRadius: h / 2), with: shading)
    }
}
