//
//  SegmentedQuestionView.swift
//  ClaudeHUD
//
//  3-Segment Dynamic Notch Question View
//  Divides the notch into interactive segments for rapid 1-click option selection.
//  Hovering/selecting an option cascades the detailed rationale downwards from the notch.
//

import SwiftUI

public struct SegmentedQuestionView: View {
    @Environment(\.hudHandlesHotkeys) private var handlesHotkeys
    public let prompt: QuestionPrompt
    public let displayPosition: HUDDisplayPosition
    public var onSelect: (QuestionOption) -> Void
    
    @State private var hoveredOptionId: String? = nil
    @State private var selectedOptionId: String? = nil
    @State private var otherSelected = false
    @State private var otherText = ""
    
    public init(
        prompt: QuestionPrompt,
        displayPosition: HUDDisplayPosition = .notch,
        onSelect: @escaping (QuestionOption) -> Void
    ) {
        self.prompt = prompt
        self.displayPosition = displayPosition
        self.onSelect = onSelect
        // Default to the first option or the one with "Recommended" tag
        let defaultId = prompt.options.first(where: { $0.tag?.lowercased().contains("rec") == true })?.id ?? prompt.options.first?.id
        _selectedOptionId = State(initialValue: defaultId)
        _hoveredOptionId = State(initialValue: defaultId)
    }
    
    private var activeOption: QuestionOption? {
        if let h = hoveredOptionId, let opt = prompt.options.first(where: { $0.id == h }) {
            return opt
        }
        if let s = selectedOptionId, let opt = prompt.options.first(where: { $0.id == s }) {
            return opt
        }
        return prompt.options.first
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: - Header & Question
            HStack(spacing: 6) {
                Text(prompt.header.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.0)
                    .foregroundColor(ClaudeHUDTheme.terracottaGlow)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(ClaudeHUDTheme.terracotta.opacity(0.18)))
                    .overlay(Capsule().stroke(ClaudeHUDTheme.terracotta.opacity(0.35), lineWidth: 0.8))

                CopyButton(prompt.question, label: "Copy")

                Spacer(minLength: 4)

                Text("1–\(prompt.options.count) · ↵")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(ClaudeHUDTheme.subtleText)
                    .help("Click the card once, then press a number to pick or ↵ to choose")
            }

            // Question gets its own full-width row: it is the payload, never truncate it to one line.
            Text(prompt.question)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ClaudeHUDTheme.creamText)
                .lineLimit(4)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.horizontal, 2)

            // MARK: - 3-Segment Notch Split
            HStack(spacing: 8) {
                ForEach(prompt.options) { option in
                    let isHovered = hoveredOptionId == option.id
                    let isSelected = selectedOptionId == option.id
                    
                    OptionSegmentCell(
                        option: option,
                        isHovered: isHovered,
                        isSelected: isSelected
                    )
                    .onHover { hovering in
                        withAnimation(ClaudeHUDTheme.fluidSpring) {
                            if hovering {
                                hoveredOptionId = option.id
                            } else if hoveredOptionId == option.id {
                                hoveredOptionId = nil
                            }
                        }
                    }
                    .onTapGesture {
                        withAnimation(ClaudeHUDTheme.snappySpring) {
                            otherSelected = false
                            selectedOptionId = option.id
                            onSelect(option)
                        }
                    }
                }
            }
            
            // "Other": answer in your own words (typed or dictated), like Claude's own question UI.
            HStack {
                Button {
                    withAnimation(ClaudeHUDTheme.snappySpring) { otherSelected.toggle(); selectedOptionId = nil }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: otherSelected ? "pencil.circle.fill" : "pencil.circle")
                        Text("Other…")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(otherSelected ? ClaudeHUDTheme.terracottaGlow : ClaudeHUDTheme.secondaryText)
                }
                .buttonStyle(.plain)
                .help("Answer in your own words")
                Spacer()
            }

            if otherSelected {
                HUDReplyField(placeholder: "Type your answer…", text: $otherText, autoFocus: true) {
                    let answer = otherText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !answer.isEmpty else { return }
                    onSelect(QuestionOption(keyNumber: 0, label: answer))
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else if let active = activeOption {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(ClaudeHUDTheme.terracotta)
                        
                        Text(active.label)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(ClaudeHUDTheme.creamText)
                        
                        if let tag = active.tag {
                            Text(tag)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(ClaudeHUDTheme.emerald)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(ClaudeHUDTheme.emerald.opacity(0.15)))
                        }
                        
                        Spacer()
                        
                        // One-click Confirm Button
                        Button(action: {
                            withAnimation(ClaudeHUDTheme.snappySpring) {
                                onSelect(active)
                            }
                        }) {
                            HStack(spacing: 4) {
                                Text("Choose  ↵")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundColor(ClaudeHUDTheme.creamText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [ClaudeHUDTheme.terracotta, ClaudeHUDTheme.terracottaDark],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.3), lineWidth: 0.8)
                            )
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.return, modifiers: [])
                    }
                    
                    // Detailed explanation text
                    Text(active.description)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(ClaudeHUDTheme.secondaryText)
                        .lineLimit(3)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.40))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(ClaudeHUDTheme.terracotta.opacity(0.25), lineWidth: 0.8)
                        )
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
            }
        }
        .padding(14)
        .liquidGlass(cornerRadius: displayPosition == .notch ? 22 : 18, isHovered: false)
        .background(numberKeyShortcuts)
        .onReceive(HUDHotkeys.shared.actions) { action in
            guard handlesHotkeys else { return }
            switch action {
            case .pick(let n):
                if let o = prompt.options.first(where: { $0.keyNumber == n }) {
                    withAnimation(ClaudeHUDTheme.snappySpring) { otherSelected = false; selectedOptionId = o.id; hoveredOptionId = nil }
                }
            case .submit:
                let answer = otherText.trimmingCharacters(in: .whitespacesAndNewlines)
                if otherSelected, !answer.isEmpty { onSelect(QuestionOption(keyNumber: 0, label: answer)) }
                else if let active = activeOption { onSelect(active) }
            default: break
            }
        }
    }

    /// Invisible buttons so 1…9 actually highlight an option (shown in the cascade drawer).
    private var numberKeyShortcuts: some View {
        ZStack {
            ForEach(prompt.options.filter { (1...9).contains($0.keyNumber) }) { option in
                Button("") {
                    withAnimation(ClaudeHUDTheme.snappySpring) {
                        selectedOptionId = option.id
                        hoveredOptionId = nil
                    }
                }
                .keyboardShortcut(KeyEquivalent(Character("\(option.keyNumber)")), modifiers: [])
            }
        }
        .opacity(0)
        .allowsHitTesting(false)
    }
}

// MARK: - Option Segment Cell

private struct OptionSegmentCell: View {
    let option: QuestionOption
    let isHovered: Bool
    let isSelected: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Key Number Badge & Tag Row
            HStack(spacing: 4) {
                // [ 1 ] Badge
                Text("\(option.keyNumber)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(isSelected || isHovered ? ClaudeHUDTheme.terracottaGlow : ClaudeHUDTheme.secondaryText)
                    .frame(width: 18, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(isSelected || isHovered ? ClaudeHUDTheme.terracotta.opacity(0.25) : Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(
                                isSelected || isHovered ? ClaudeHUDTheme.terracotta.opacity(0.5) : Color.white.opacity(0.1),
                                lineWidth: 0.8
                            )
                    )
                
                Spacer(minLength: 0)
                
                if let tag = option.tag {
                    Text(tag)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(ClaudeHUDTheme.emerald)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(ClaudeHUDTheme.emerald.opacity(0.12)))
                        .lineLimit(1)
                }
            }
            
            // Label
            Text(option.label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isSelected || isHovered ? ClaudeHUDTheme.creamText : ClaudeHUDTheme.secondaryText)
                .lineLimit(1)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    isSelected || isHovered
                    ? ClaudeHUDTheme.terracotta.opacity(0.15)
                    : Color.white.opacity(0.04)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isSelected || isHovered
                    ? ClaudeHUDTheme.activeSegmentBorder
                    : LinearGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.02)], startPoint: .top, endPoint: .bottom),
                    lineWidth: isSelected || isHovered ? 1.2 : 0.8
                )
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(ClaudeHUDTheme.fluidSpring, value: isHovered)
        .animation(ClaudeHUDTheme.snappySpring, value: isSelected)
    }
}
