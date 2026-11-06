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

    /// Sound for a new card, unless muted, snoozed, or in a call.
    public static func playArrivalSound() {
        let s = HUDSettingsStore.shared
        guard s.soundEnabled, !s.isSnoozed, !(s.quietDuringCalls && micInUse()) else { return }
        NSSound(named: "Glass")?.play()
    }

    public static func haptic() {
        guard HUDSettingsStore.shared.haptics else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
