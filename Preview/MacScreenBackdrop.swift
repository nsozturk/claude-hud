//
//  MacScreenBackdrop.swift
//  ClaudeHUD
//
//  A drawn MacBook display (bezel, wallpaper, menu bar, notch) behind the live preview, so a
//  card shows where it really appears: out of the notch, or under the menu bar on the right.
//  Drawn, not a photo: no image rights to worry about in the public repo.
//

import SwiftUI

struct MacScreenBackdrop<Content: View>: View {
    static var menuBarHeight: CGFloat { 30 }
    static var notchWidth: CGFloat { 190 }

    var accent: Color
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .top) {
            wallpaper
            menuBar
            UnevenRoundedRectangle(bottomLeadingRadius: 11, bottomTrailingRadius: 11, style: .continuous)
                .fill(Color.black)
                .frame(width: Self.notchWidth, height: Self.menuBarHeight)
            content
        }
        .frame(maxWidth: .infinity, minHeight: 560, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(9) // bezel
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.black))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
    }

    private var wallpaper: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.10, green: 0.11, blue: 0.22), Color(red: 0.20, green: 0.10, blue: 0.22),
                                    Color(red: 0.06, green: 0.05, blue: 0.10)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            // Soft color fields, in the spirit of the default macOS wallpapers.
            Ellipse().fill(accent.opacity(0.35)).frame(width: 520, height: 300).blur(radius: 90).offset(x: 220, y: 160)
            Ellipse().fill(Color(red: 0.25, green: 0.35, blue: 0.85).opacity(0.35)).frame(width: 480, height: 280).blur(radius: 90).offset(x: -260, y: 260)
            Ellipse().fill(Color(red: 0.55, green: 0.25, blue: 0.65).opacity(0.25)).frame(width: 420, height: 240).blur(radius: 80).offset(x: -60, y: 40)
        }
    }

    private var menuBar: some View {
        HStack(spacing: 16) {
            Image(systemName: "circle.hexagongrid.fill").font(.system(size: 12))
            Text("Finder").fontWeight(.bold)
            ForEach(["File", "Edit", "View"], id: \.self) { Text($0) }
            Spacer()
            Image(systemName: "magnifyingglass")
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            Text(Date.now, format: .dateTime.weekday(.abbreviated).hour().minute())
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(.white.opacity(0.9))
        .padding(.horizontal, 16)
        .frame(height: Self.menuBarHeight)
        .background(Color.black.opacity(0.22))
    }
}
