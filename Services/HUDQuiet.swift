//
//  HUDQuiet.swift
//  ClaudeHUD
//
//  Staying out of the way: snooze, "is the mic in use" (a call), and haptics.
//  Focus mode is not read on purpose: macOS only shares it with apps that hold a
//  communication-notifications entitlement, so snooze covers that case instead.
//

import AppKit
import CoreAudio
import UniformTypeIdentifiers

@MainActor
public enum HUDQuiet {
    /// Hide cards until `minutes` from now; they stay in the queue.
    public static func snooze(minutes: Int) {
        let until = Date().addingTimeInterval(TimeInterval(minutes * 60))
        HUDSettingsStore.shared.snoozeUntil = until
        hudLog("😴 Snoozed until \(until.formatted(date: .omitted, time: .shortened))", category: "QUIET")
        DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(minutes * 60) + 0.5) {
            if let u = HUDSettingsStore.shared.snoozeUntil, u <= Date() { resume() }
        }
    }

    /// Snooze until 9:00 tomorrow.
    public static func snoozeUntilTomorrow() {
        let cal = Calendar.current
        let nine = cal.date(bySettingHour: 9, minute: 0, second: 0, of: cal.date(byAdding: .day, value: 1, to: Date())!)!
        snooze(minutes: max(1, Int(nine.timeIntervalSinceNow / 60)))
    }

    public static func resume() {
        HUDSettingsStore.shared.snoozeUntil = nil
        hudLog("🔔 Snooze ended", category: "QUIET")
    }

    /// True while any app records from the default input device: a call or a recording.
    public nonisolated static func micInUse() -> Bool {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device) == noErr,
              device != 0 else { return false }
        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        addr.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }

    /// macOS system sounds people can pick from (System Settings uses the same set).
    public static let systemSounds: [String] = {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? []
        let list = names.filter { $0.hasSuffix(".aiff") }.map { String($0.dropLast(5)) }.sorted()
        return list.isEmpty ? ["Glass", "Funk", "Pop", "Ping", "Tink"] : list
    }()

    public static func soundName(for event: HUDNotificationEvent) -> String {
        let s = HUDSettingsStore.shared
        switch event {
        case .permission: return s.soundPermission
        case .sessionAsk: return s.soundSession
        default: return s.soundQuestion
        }
    }

    /// Sounds still playing; held so a copy is not freed mid-play.
    private static var playing: [NSSound] = []

    /// Custom sounds are stored as "file:<path>" and live in the app's own folder.
    public static let customPrefix = "file:"
    public static var customSoundsFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Claude HUD/Sounds", isDirectory: true)
    }

    /// Display name: the system sound name, or the custom file's name without extension.
    public static func displayName(_ value: String) -> String {
        value.hasPrefix(customPrefix)
            ? URL(fileURLWithPath: String(value.dropFirst(customPrefix.count))).deletingPathExtension().lastPathComponent
            : value
    }

    /// Ask for an audio file, copy it into the app's folder (so moving the original never
    /// breaks it) and return the value to store, or nil if cancelled / not playable.
    public static func chooseCustomSound() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a sound for Claude HUD"
        NSApp.activate()
        guard panel.runModal() == .OK, let src = panel.url, NSSound(contentsOf: src, byReference: true) != nil else { return nil }
        do {
            try FileManager.default.createDirectory(at: customSoundsFolder, withIntermediateDirectories: true)
            let dest = customSoundsFolder.appendingPathComponent(src.lastPathComponent)
            if dest.path != src.path {
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.copyItem(at: src, to: dest)
            }
            hudLog("🔈 Custom sound added: \(dest.lastPathComponent)", category: "QUIET")
            return customPrefix + dest.path
        } catch {
            hudLog("⚠️ Could not copy sound: \(error.localizedDescription)", category: "QUIET")
            return nil
        }
    }

    /// Custom sounds already copied into the app's folder, offered again in every picker.
    public static func customSounds() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(at: customSoundsFolder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { !$0.lastPathComponent.hasPrefix(".") }.map { customPrefix + $0.path }.sorted()
    }

    private static func sound(for value: String) -> NSSound? {
        if value.hasPrefix(customPrefix) {
            return NSSound(contentsOf: URL(fileURLWithPath: String(value.dropFirst(customPrefix.count))), byReference: true)
        }
        return NSSound(named: value)?.copy() as? NSSound
    }

    /// Plays a sound at the chosen volume (a copy, so quick arrivals can overlap).
    public static func play(_ name: String) {
        guard name != "None", let sound = sound(for: name) else { return }
        sound.volume = Float(HUDSettingsStore.shared.soundVolume)
        playing.removeAll { !$0.isPlaying }
        playing.append(sound)
        sound.play()
    }

    /// Sound for a new card, unless muted, snoozed, or in a call.
    public static func playArrivalSound(for event: HUDNotificationEvent) {
        let s = HUDSettingsStore.shared
        guard s.soundEnabled, !s.isSnoozed, !(s.quietDuringCalls && micInUse()) else { return }
        play(soundName(for: event))
    }

    public static func haptic() {
        guard HUDSettingsStore.shared.haptics else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
