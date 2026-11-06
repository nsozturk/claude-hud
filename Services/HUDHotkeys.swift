//
//  HUDHotkeys.swift
//  ClaudeHUD
//
//  System-wide shortcuts for the card on screen. The panel never takes focus, so plain keys
//  (1, ↵) only reach it after "Focus panel". These Carbon hot keys work from any app, need no
//  Accessibility permission, and are registered only while a card is showing, so they never
//  shadow other apps' shortcuts the rest of the time.
//

import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

/// Only the live panel reacts to hot keys; the same cards drawn in the settings preview must not,
/// or one key press would answer twice.
private struct HUDHandlesHotkeysKey: EnvironmentKey { static let defaultValue = false }
public extension EnvironmentValues {
    var hudHandlesHotkeys: Bool {
        get { self[HUDHandlesHotkeysKey.self] }
        set { self[HUDHandlesHotkeysKey.self] = newValue }
    }
}

public enum HUDHotkeyAction: Hashable {
    case pick(Int)          // 1…9, fixed: ⌃⌥1 … ⌃⌥9
    case submit, skip, next, open, copy, focus

    /// The actions people can rebind, in the order the settings list shows them.
    public static let configurable: [HUDHotkeyAction] = [.submit, .skip, .next, .open, .copy, .focus]

    public var title: String {
        switch self {
        case .pick(let n): return "Pick option \(n)"
        case .submit: return "Choose / Next / Submit"
        case .skip: return "Skip / Later"
        case .next: return "Next card in the queue"
        case .open: return "Open the session in Claude"
        case .copy: return "Copy the question"
        case .focus: return "Focus the panel (plain keys work)"
        }
    }

    var key: String {
        switch self {
        case .pick(let n): return "pick\(n)"
        case .submit: return "submit"
        case .skip: return "skip"
        case .next: return "next"
        case .open: return "open"
        case .copy: return "copy"
        case .focus: return "focus"
        }
    }

    var id: UInt32 {
        switch self {
        case .pick(let n): return UInt32(n)
        case .submit: return 20
        case .skip: return 21
        case .next: return 25
        case .open: return 22
        case .copy: return 23
        case .focus: return 24
        }
    }
}

public struct KeyCombo: Codable, Equatable {
    public var keyCode: UInt32
    public var modifiers: UInt32   // Carbon: cmdKey | optionKey | controlKey | shiftKey
    public var label: String       // the key itself, e.g. "↵", "O"

    public var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + label
    }

    static let ctrlOpt = UInt32(controlKey | optionKey)

    static func fromEvent(_ e: NSEvent) -> KeyCombo? {
        let f = e.modifierFlags
        var m: UInt32 = 0
        if f.contains(.control) { m |= UInt32(controlKey) }
        if f.contains(.option) { m |= UInt32(optionKey) }
        if f.contains(.shift) { m |= UInt32(shiftKey) }
        if f.contains(.command) { m |= UInt32(cmdKey) }
        // At least one of ⌃ ⌥ ⌘: a system-wide shortcut without one would swallow normal typing.
        guard m & UInt32(controlKey | optionKey | cmdKey) != 0 else { return nil }
        return KeyCombo(keyCode: UInt32(e.keyCode), modifiers: m, label: keyLabel(e))
    }

    static func keyLabel(_ e: NSEvent) -> String {
        switch Int(e.keyCode) {
        case kVK_Return: return "↵"
        case kVK_Escape: return "⎋"
        case kVK_Space: return "Space"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default: return (e.charactersIgnoringModifiers ?? "?").uppercased()
        }
    }
}

@MainActor
public final class HUDHotkeys: ObservableObject {
    public static let shared = HUDHotkeys()

    /// Cards and the shell listen here.
    public let actions = PassthroughSubject<HUDHotkeyAction, Never>()
    @Published public private(set) var combos: [String: KeyCombo] = [:]
    /// Combos macOS refused because another app already owns them.
    @Published public private(set) var unavailable: Set<String> = []

    public static let defaults: [String: KeyCombo] = [
        "submit": KeyCombo(keyCode: UInt32(kVK_Return), modifiers: KeyCombo.ctrlOpt, label: "↵"),
        "skip": KeyCombo(keyCode: UInt32(kVK_Escape), modifiers: KeyCombo.ctrlOpt, label: "⎋"),
        "next": KeyCombo(keyCode: UInt32(kVK_RightArrow), modifiers: KeyCombo.ctrlOpt, label: "→"),
        "open": KeyCombo(keyCode: UInt32(kVK_ANSI_O), modifiers: KeyCombo.ctrlOpt, label: "O"),
        "copy": KeyCombo(keyCode: UInt32(kVK_ANSI_C), modifiers: KeyCombo.ctrlOpt, label: "C"),
        "focus": KeyCombo(keyCode: UInt32(kVK_Space), modifiers: KeyCombo.ctrlOpt, label: "Space"),
    ]
    private static let digitCodes = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                                     kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
    private static let storeKey = "hud_hotkeys.v1"

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlerInstalled = false
    private var registered = false
    private var cancellable: AnyCancellable?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storeKey),
           let saved = try? JSONDecoder().decode([String: KeyCombo].self, from: data) {
            combos = Self.defaults.merging(saved) { _, s in s }
        } else {
            combos = Self.defaults
        }
    }

    public func combo(for action: HUDHotkeyAction) -> KeyCombo? {
        if case .pick(let n) = action {
            return KeyCombo(keyCode: UInt32(Self.digitCodes[n - 1]), modifiers: KeyCombo.ctrlOpt, label: "\(n)")
        }
        return combos[action.key]
    }

    public func set(_ combo: KeyCombo, for action: HUDHotkeyAction) {
        combos[action.key] = combo
        save()
        reregister()
    }

    public func reset(_ action: HUDHotkeyAction) {
        combos[action.key] = Self.defaults[action.key]
        save()
        reregister()
    }

    /// Register while the queue has a card, unregister when it empties.
    public func start() {
        installHandler()
        // On only while a card is showing and the HUD is not snoozed.
        cancellable = HUDQueueManager.shared.$queue.combineLatest(HUDSettingsStore.shared.$snoozeUntil)
            .map { queue, until in !queue.isEmpty && (until ?? .distantPast) <= Date() }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] hasCard in hasCard ? self?.register() : self?.unregister() }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(combos) { UserDefaults.standard.set(data, forKey: Self.storeKey) }
    }

    private func reregister() { if registered { unregister(); register() } }

    private func allActions() -> [HUDHotkeyAction] { (1...9).map { .pick($0) } + HUDHotkeyAction.configurable }

    private func register() {
        guard !registered else { return }
        registered = true
        var failed: Set<String> = []
        for action in allActions() {
            guard let c = combo(for: action) else { continue }
            var ref: EventHotKeyRef?
            let hkID = EventHotKeyID(signature: OSType(0x4855_4421), id: action.id) // 'HUD!'
            let status = RegisterEventHotKey(c.keyCode, c.modifiers, hkID, GetEventDispatcherTarget(), 0, &ref)
            if status == noErr, let ref { refs[action.id] = ref } else { failed.insert(action.key) }
        }
        unavailable = failed
        hudLog("⌨️ Hot keys on (\(refs.count))\(failed.isEmpty ? "" : ", taken by another app: \(failed.sorted())")", category: "KEYS")
    }

    private func unregister() {
        guard registered else { return }
        registered = false
        refs.values.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        hudLog("⌨️ Hot keys off", category: "KEYS")
    }

    fileprivate func fire(id: UInt32) {
        guard let action = allActions().first(where: { $0.id == id }) else { return }
        hudLog("⌨️ \(action.title)", category: "KEYS")
        if action == .focus {
            NSApp.activate()
            LiveNotchPanelController.shared.focusPanel()
        }
        actions.send(action)
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let id = hkID.id
            DispatchQueue.main.async { HUDHotkeys.shared.fire(id: id) }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
