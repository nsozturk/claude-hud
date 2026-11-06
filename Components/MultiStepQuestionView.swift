//
//  MultiStepQuestionView.swift
//  ClaudeHUD
//
//  Multi-Step Interactive Question View
//  Direct implementation of Claude Desktop's Question & Option Modal:
//  - Pagination indicator (< 1 of 2 >)
//  - Context text with inline code highlights
//  - Vertical radio option cards with rich sub-descriptions and (Recommended) badges
//  - "Other" option with expandable custom text field
//  - "Skip" & "Next ⌘↵" action buttons with keyboard shortcuts
//

import SwiftUI

public struct MultiStepQuestionView: View {
    @Environment(\.hudHandlesHotkeys) private var handlesHotkeys
    public let session: MultiQuestionSession
    public let displayPosition: HUDDisplayPosition
    public var onAnswerSubmitted: (Int, String) -> Void // (questionIndex, selectedAnswerOrOtherText)
    public var onSkip: () -> Void
    public var onFinishAll: ([Int: String]) -> Void
    
    @State private var currentIndex: Int = 0
    @State private var selectedOptionIndices: [Int: Int] = [:] // questionIndex -> optionIndex
    @State private var otherTexts: [Int: String] = [:] // questionIndex -> custom text
    @State private var isOtherSelected: [Int: Bool] = [:] // questionIndex -> isOther
    @State private var answersMap: [Int: String] = [:]
    
    @State private var isSkipHovered: Bool = false
    @State private var isNextHovered: Bool = false
    
    public init(
        session: MultiQuestionSession,
        displayPosition: HUDDisplayPosition = .notch,
        onAnswerSubmitted: @escaping (Int, String) -> Void = { _, _ in },
        onSkip: @escaping () -> Void = {},
        onFinishAll: @escaping ([Int: String]) -> Void = { _ in }
    ) {
        self.session = session
        self.displayPosition = displayPosition
        self.onAnswerSubmitted = onAnswerSubmitted
        self.onSkip = onSkip
        self.onFinishAll = onFinishAll
        _currentIndex = State(initialValue: session.currentQuestionIndex)
    }
    
    private var currentPrompt: QuestionPrompt {
        if currentIndex < session.questions.count {
            return session.questions[currentIndex]
        }
        return session.questions[0]
    }
    
    private var isLastQuestion: Bool {
        currentIndex >= session.questions.count - 1
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // MARK: - Header & Pagination (< 1 of 2 >)
            HStack(alignment: .center, spacing: 8) {
                // Header Chip
                HStack(spacing: 6) {
                    Text(currentPrompt.header.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(ClaudeHUDTheme.terracottaGlow)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(ClaudeHUDTheme.terracotta.opacity(0.18)))
                        .overlay(Capsule().stroke(ClaudeHUDTheme.terracotta.opacity(0.35), lineWidth: 0.8))
                    
                    CopyButton(currentPrompt.question, label: "Copy Question")
                }
                
                Spacer()
                
                // Pagination Indicator: < 1 of 2 >
                HStack(spacing: 6) {
                    Button(action: {
                        if currentIndex > 0 {
                            withAnimation(ClaudeHUDTheme.fluidSpring) {
                                currentIndex -= 1
                            }
                        }
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(currentIndex > 0 ? ClaudeHUDTheme.creamText : ClaudeHUDTheme.subtleText.opacity(0.4))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .disabled(currentIndex == 0)
                    
                    Text("\(currentIndex + 1) of \(session.questions.count)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(ClaudeHUDTheme.secondaryText)
                    
                    Button(action: {
                        if currentIndex < session.questions.count - 1 {
                            withAnimation(ClaudeHUDTheme.fluidSpring) {
                                currentIndex += 1
                            }
                        }
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(currentIndex < session.questions.count - 1 ? ClaudeHUDTheme.creamText : ClaudeHUDTheme.subtleText.opacity(0.4))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .disabled(currentIndex >= session.questions.count - 1)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.04))
                )
            }
            
            // MARK: - Question Context Text with Code Formatting
            FormattedQuestionTextView(text: currentPrompt.question)
                .padding(.horizontal, 2)
            
            // MARK: - Vertical Radio Option List
            VStack(spacing: 8) {
                ForEach(Array(currentPrompt.options.enumerated()), id: \.element.id) { index, option in
                    let isSelected = (selectedOptionIndices[currentIndex] == index) && (isOtherSelected[currentIndex] != true)
                    
                    RadioOptionRow(
                        option: option,
                        isSelected: isSelected,
                        onSelect: {
                            withAnimation(ClaudeHUDTheme.snappySpring) {
                                selectedOptionIndices[currentIndex] = index
                                isOtherSelected[currentIndex] = false
                                answersMap[currentIndex] = option.label
                            }
                        }
                    )
                }
                
                // "Other" Option (Free text input)
                OtherOptionRow(
                    isSelected: isOtherSelected[currentIndex] == true,
                    customText: Binding(
                        get: { otherTexts[currentIndex] ?? "" },
                        set: {
                            otherTexts[currentIndex] = $0
                            answersMap[currentIndex] = $0
                        }
                    ),
                    onSelect: {
                        withAnimation(ClaudeHUDTheme.snappySpring) {
                            isOtherSelected[currentIndex] = true
                            selectedOptionIndices[currentIndex] = nil
                        }
                    },
                    onSubmit: handleNextOrSubmit
                )
            }
            
            // MARK: - Action Buttons (Skip & Next ⌘↵)
            HStack(spacing: 10) {
                // Skip Button
                Button(action: onSkip) {
                    Text("Skip")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isSkipHovered ? ClaudeHUDTheme.creamText : ClaudeHUDTheme.secondaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isSkipHovered ? Color.white.opacity(0.10) : Color.white.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)
                .onHover { isSkipHovered = $0 }
                
                Spacer()
                
                // Next / Submit Button with ⌘↵
                Button(action: handleNextOrSubmit) {
                    HStack(spacing: 5) {
                        Text(isLastQuestion ? "Submit" : "Next")
                            .font(.system(size: 11, weight: .bold))
                        
                        // ⌘↵ Keyboard Badge
                        HStack(spacing: 2) {
                            Text("⌘")
                                .font(.system(size: 10, weight: .bold))
                            Image(systemName: "return")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundColor(ClaudeHUDTheme.creamText.opacity(0.75))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.white.opacity(0.15))
                        )
                    }
                    .foregroundColor(ClaudeHUDTheme.creamText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [ClaudeHUDTheme.terracottaGlow, ClaudeHUDTheme.terracotta],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.35), lineWidth: 0.8)
                    )
                    .shadow(
                        color: ClaudeHUDTheme.terracotta.opacity(isNextHovered ? 0.45 : 0.20),
                        radius: 8,
                        y: 3
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .onHover { isNextHovered = $0 }
                .scaleEffect(isNextHovered ? 1.02 : 1.0)
                .animation(ClaudeHUDTheme.snappySpring, value: isNextHovered)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .liquidGlass(cornerRadius: displayPosition == .notch ? 22 : 18, isHovered: false)
        .onReceive(HUDHotkeys.shared.actions) { action in
            guard handlesHotkeys else { return }
            switch action {
            case .pick(let n) where n <= currentPrompt.options.count:
                withAnimation(ClaudeHUDTheme.snappySpring) {
                    selectedOptionIndices[currentIndex] = n - 1
                    isOtherSelected[currentIndex] = false
                    answersMap[currentIndex] = currentPrompt.options[n - 1].label
                }
            case .submit: handleNextOrSubmit()
            default: break
            }
        }
    }
    
    private func handleNextOrSubmit() {
        let answer: String
        if isOtherSelected[currentIndex] == true {
            answer = otherTexts[currentIndex] ?? "Other"
        } else if let selectedIdx = selectedOptionIndices[currentIndex],
                  selectedIdx < currentPrompt.options.count {
            answer = currentPrompt.options[selectedIdx].label
        } else {
            // Default to first option
            answer = currentPrompt.options.first?.label ?? "Acknowledged"
        }
        
        answersMap[currentIndex] = answer
        onAnswerSubmitted(currentIndex, answer)
        
        if isLastQuestion {
            onFinishAll(answersMap)
        } else {
            withAnimation(ClaudeHUDTheme.fluidSpring) {
                currentIndex += 1
            }
        }
    }
}

// MARK: - Radio Option Row

private struct RadioOptionRow: View {
    let option: QuestionOption
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isHovered: Bool = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Radio Circle
            ZStack {
                Circle()
                    .stroke(
                        isSelected ? ClaudeHUDTheme.terracottaGlow : Color.white.opacity(0.30),
                        lineWidth: isSelected ? 2 : 1.2
                    )
                    .frame(width: 16, height: 16)
                
                if isSelected {
                    Circle()
                        .fill(ClaudeHUDTheme.terracottaGlow)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 2)
            
            // Text Details
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(option.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isSelected ? ClaudeHUDTheme.creamText : ClaudeHUDTheme.creamText.opacity(0.9))
                        .textSelection(.enabled)
                    
                    if let tag = option.tag {
                        Text("(\(tag))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(ClaudeHUDTheme.emerald)
                    }
                }
                
                Text(option.description)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(ClaudeHUDTheme.secondaryText)
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    isSelected
                    ? ClaudeHUDTheme.terracotta.opacity(0.12)
                    : (isHovered ? Color.white.opacity(0.04) : Color.clear)
                )
        )
        .overlay(
            Group {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(ClaudeHUDTheme.activeSegmentBorder, lineWidth: 1.0)
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(isHovered ? 0.08 : 0.03), lineWidth: 0.8)
                }
            }
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: onSelect)
    }
}

// MARK: - "Other" Option Row

private struct OtherOptionRow: View {
    let isSelected: Bool
    @Binding var customText: String
    let onSelect: () -> Void
    var onSubmit: () -> Void = {}
    @State private var isHovered: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                // Radio Circle
                ZStack {
                    Circle()
                        .stroke(
                            isSelected ? ClaudeHUDTheme.terracottaGlow : Color.white.opacity(0.30),
                            lineWidth: isSelected ? 2 : 1.2
                        )
                        .frame(width: 16, height: 16)
                    
                    if isSelected {
                        Circle()
                            .fill(ClaudeHUDTheme.terracottaGlow)
                            .frame(width: 8, height: 8)
                    }
                }
                
                Text("Other")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isSelected ? ClaudeHUDTheme.creamText : ClaudeHUDTheme.creamText.opacity(0.9))
                
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
            
            // Expandable Text Field when selected
            if isSelected {
                HUDReplyField(placeholder: "Type your answer…", text: $customText, showsSend: false,
                              autoFocus: true, onSubmit: onSubmit)
                    .padding(.leading, 26)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    isSelected
                    ? ClaudeHUDTheme.terracotta.opacity(0.12)
                    : (isHovered ? Color.white.opacity(0.04) : Color.clear)
                )
        )
        .overlay(
            Group {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(ClaudeHUDTheme.activeSegmentBorder, lineWidth: 1.0)
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(isHovered ? 0.08 : 0.03), lineWidth: 0.8)
                }
            }
        )
        .onHover { isHovered = $0 }
    }
}

// MARK: - Formatted Question Text View (Highlighting inline code)

private struct FormattedQuestionTextView: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .default))
            .foregroundColor(ClaudeHUDTheme.creamText)
            .lineSpacing(3)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}
