//
//  HUDTypes.swift
//  ClaudeHUD
//
//  Data Models for Claude Code Interactive Events & Positioning
//

import Foundation

// MARK: - Display Positioning

public enum HUDDisplayPosition: String, CaseIterable, Identifiable {
    case notch = "Dynamic Notch"
    case topRight = "Top-Right Floating HUD"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .notch: return "macbook.and.ipad"
        case .topRight: return "inset.filled.topright.rectangle"
        }
    }
}

// MARK: - Interactive Question Models

public struct QuestionOption: Identifiable, Hashable {
    public let id: String
    public let keyNumber: Int
    public let label: String
    public let description: String
    public let tag: String?
    
    public init(id: String = UUID().uuidString, keyNumber: Int, label: String, description: String = "", tag: String? = nil) {
        self.id = id
        self.keyNumber = keyNumber
        self.label = label
        self.description = description
        self.tag = tag
    }
}

public struct QuestionPrompt: Identifiable, Hashable {
    public let id: String
    public let question: String
    public let header: String
    public let options: [QuestionOption]
    public let multiSelect: Bool
    
    public init(id: String = UUID().uuidString, question: String, header: String, options: [QuestionOption], multiSelect: Bool = false) {
        self.id = id
        self.question = question
        self.header = header
        self.options = options
        self.multiSelect = multiSelect
    }
}

public struct MultiQuestionSession: Identifiable, Hashable {
    public let id: String
    public let questions: [QuestionPrompt]
    public var currentQuestionIndex: Int
    
    public init(id: String = UUID().uuidString, questions: [QuestionPrompt], currentQuestionIndex: Int = 0) {
        self.id = id
        self.questions = questions
        self.currentQuestionIndex = currentQuestionIndex
    }
}

// MARK: - Task Proposal (Screenshot Replica)

public struct TaskProposal: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let tldr: String
    public let prompt: String
    public let parentSessionName: String
    public let proposalId: String
    
    public init(
        id: String = UUID().uuidString,
        title: String,
        tldr: String,
        prompt: String,
        parentSessionName: String,
        proposalId: String = "task_" + UUID().uuidString.prefix(8).lowercased()
    ) {
        self.id = id
        self.title = title
        self.tldr = tldr
        self.prompt = prompt
        self.parentSessionName = parentSessionName
        self.proposalId = proposalId
    }
}

// MARK: - Tool Permission Request

public struct ToolPermission: Identifiable, Hashable {
    public let id: String
    public let toolName: String
    public let command: String
    public let workingDir: String
    public let reason: String?
    public let isDestructive: Bool
    public let sessionId: String?
    /// Claude offered an "always allow" rule for this call (permission_suggestions).
    public let canAlwaysAllow: Bool

    public init(
        id: String = UUID().uuidString,
        toolName: String,
        command: String,
        workingDir: String,
        reason: String? = nil,
        isDestructive: Bool = false,
        sessionId: String? = nil,
        canAlwaysAllow: Bool = true
    ) {
        self.canAlwaysAllow = canAlwaysAllow
        self.id = id
        self.toolName = toolName
        self.command = command
        self.workingDir = workingDir
        self.reason = reason
        self.isDestructive = isDestructive
        self.sessionId = sessionId
    }
}

// MARK: - File Diff Approval Model

public enum DiffLineType: Hashable {
    case context
    case addition
    case deletion
}

public struct DiffLine: Identifiable, Hashable {
    public let id: String
    public let type: DiffLineType
    public let text: String
    
    public init(id: String = UUID().uuidString, type: DiffLineType, text: String) {
        self.id = id
        self.type = type
        self.text = text
    }
}

public struct FileDiffData: Identifiable, Hashable {
    public let id: String
    public let filePath: String
    public let additionsCount: Int
    public let deletionsCount: Int
    public let lines: [DiffLine]
    
    public init(
        id: String = UUID().uuidString,
        filePath: String,
        additionsCount: Int,
        deletionsCount: Int,
        lines: [DiffLine]
    ) {
        self.id = id
        self.filePath = filePath
        self.additionsCount = additionsCount
        self.deletionsCount = deletionsCount
        self.lines = lines
    }
}

// MARK: - Plan Checklist Model

public enum PlanStepStatus: String, Hashable {
    case completed = "Done"
    case active = "Active"
    case pending = "Pending"
}

public struct PlanStepItem: Identifiable, Hashable {
    public let id: String
    public let index: Int
    public let title: String
    public let status: PlanStepStatus
    
    public init(id: String = UUID().uuidString, index: Int, title: String, status: PlanStepStatus) {
        self.id = id
        self.index = index
        self.title = title
        self.status = status
    }
}

public struct PlanChecklistData: Identifiable, Hashable {
    public let id: String
    public let planTitle: String
    public let steps: [PlanStepItem]
    
    public init(id: String = UUID().uuidString, planTitle: String, steps: [PlanStepItem]) {
        self.id = id
        self.planTitle = planTitle
        self.steps = steps
    }
}

// MARK: - Session waiting for the user (desktop "next step" question)

/// A question a Claude desktop session put in its next-step box (mcp__ccd_turn__wrap_up `ask`).
/// It is answered in Claude itself; the HUD shows it and opens that session.
public struct SessionAsk: Identifiable, Hashable {
    public let id: String            // tool_use id
    public let cliSessionId: String
    public let sessionTitle: String
    public let question: String
    public let recap: String
    public let actions: [String]     // button labels as the desktop shows them

    public init(id: String, cliSessionId: String, sessionTitle: String, question: String, recap: String, actions: [String]) {
        self.id = id
        self.cliSessionId = cliSessionId
        self.sessionTitle = sessionTitle
        self.question = question
        self.recap = recap
        self.actions = actions
    }
}

// MARK: - Master HUD Event

public enum HUDNotificationEvent: Identifiable, Hashable {
    case question(QuestionPrompt)
    case multiQuestion(MultiQuestionSession)
    case taskProposal(TaskProposal)
    case permission(ToolPermission)
    case fileDiff(FileDiffData)
    case planChecklist(PlanChecklistData)
    case sessionAsk(SessionAsk)
    
    public var id: String {
        switch self {
        case .question(let q): return "q_\(q.id)"
        case .multiQuestion(let m): return "m_\(m.id)"
        case .taskProposal(let t): return "t_\(t.id)"
        case .permission(let p): return "p_\(p.id)"
        case .fileDiff(let f): return "f_\(f.id)"
        case .planChecklist(let pc): return "pc_\(pc.id)"
        case .sessionAsk(let a): return "s_\(a.id)"
        }
    }
    
    /// Id shared with the originating tool call (tool_use_id for questions).
    public var sourceId: String {
        switch self {
        case .question(let q): return q.id
        case .multiQuestion(let m): return m.id
        case .taskProposal(let t): return t.id
        case .permission(let p): return p.id
        case .fileDiff(let f): return f.id
        case .planChecklist(let pc): return pc.id
        case .sessionAsk(let a): return a.id
        }
    }

    public var isQuestion: Bool {
        switch self {
        case .question, .multiQuestion, .sessionAsk: return true
        default: return false
        }
    }

    public var title: String {
        switch self {
        case .question(let q): return q.header
        case .multiQuestion(let m): return m.questions.first?.header ?? "Question"
        case .taskProposal(let t): return t.title
        case .permission(let p): return "Approval: \(p.toolName)"
        case .fileDiff(let f): return "Diff: \(f.filePath)"
        case .planChecklist(let pc): return "Plan: \(pc.planTitle)"
        case .sessionAsk(let a): return a.sessionTitle
        }
    }
}
