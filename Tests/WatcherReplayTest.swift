// Replay test for ClaudeSessionWatcher's transcript parsing.
// Build: swiftc -parse-as-library -o <out> $(ls */*.swift | grep -v App/ClaudeHUDApp.swift) Tests/WatcherReplayTest.swift
// Run:   <out> <live-cli-session-id>          (synthetic asserts)
//        <out> --real                          (what the HUD would show right now from real transcripts)
import AppKit

@main struct WatcherReplayTest {
    @MainActor static func pump() { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
    @MainActor static var ids: [String] { HUDQueueManager.shared.queue.map(\.sourceId) }

    static func line(_ obj: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: obj) + Data([0x0A])
    }

    @MainActor static func main() {
        let args = CommandLine.arguments
        let w = ClaudeSessionWatcher.shared
        if args.count > 1 && args[1] == "--real" {
            let root = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")
            let files = ((try? FileManager.default.subpathsOfDirectory(atPath: root.path)) ?? [])
                .filter { $0.hasSuffix(".jsonl") && !$0.contains("/subagents/") && $0.split(separator: "/").count == 2 }
                .map { root.appendingPathComponent($0) }
                .filter { (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    .map { Date().timeIntervalSince($0!) < 12 * 3600 } ?? false }
            w.replayForTesting(files)
            pump()
            print("Would show \(HUDQueueManager.shared.queue.count) card(s) now:")
            for e in HUDQueueManager.shared.queue {
                if case .sessionAsk(let a) = e { print("  WAIT  [\(a.sessionTitle)] \(a.question.prefix(70)) | \(a.actions)") }
                else { print("  ASK   \(e.title)") }
            }
            return
        }

        guard args.count > 1 else { print("usage: <live-session-id> | --real"); exit(2) }
        let sid = args[1]
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hud-replay-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(sid).jsonl")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let h = try! FileHandle(forWritingTo: file)
        func append(_ d: Data) { h.seekToEndOfFile(); h.write(d); w.replayForTesting([file]); pump() }
        var failures = 0
        func check(_ ok: Bool, _ what: String) { print(ok ? "PASS  \(what)" : "FAIL  \(what)"); if !ok { failures += 1 } }

        // 1. Next-step ask shows up, with its buttons.
        append(line(["type": "assistant", "sessionId": sid, "cwd": "/tmp/x", "message": ["content": [[
            "type": "tool_use", "id": "toolu_wrap_1", "name": "mcp__ccd_turn__wrap_up",
            "input": ["recap": "Did the thing.", "ask": "Kuyruğu temizleyeyim mi?", "actions": [["label": "Evet, temizle"], ["action": "commit"]]]]]]]))
        check(ids == ["toolu_wrap_1"], "wrap_up ask becomes a card")
        if case .sessionAsk(let a)? = HUDQueueManager.shared.queue.first {
            check(a.actions == ["Evet, temizle", "Commit"], "buttons: label kept, app action prettified")
        } else { check(false, "card is a sessionAsk") }

        // 2. Its immediate tool_result does NOT remove it.
        append(line(["type": "user", "sessionId": sid, "message": ["content": [["type": "tool_result", "tool_use_id": "toolu_wrap_1", "content": "ok"]]]]))
        check(ids == ["toolu_wrap_1"], "wrap_up's own tool_result keeps the card")

        // 3. Same tool_use seen again (duplicate project dir) is not shown twice.
        append(line(["type": "assistant", "sessionId": sid, "message": ["content": [[
            "type": "tool_use", "id": "toolu_wrap_1", "name": "mcp__ccd_turn__wrap_up", "input": ["ask": "Kuyruğu temizleyeyim mi?"]]]]]))
        check(ids.count == 1, "duplicate tool_use is deduped")

        // 4. A meta/system user line does not count as the person's answer.
        append(line(["type": "user", "isMeta": true, "sessionId": sid, "message": ["content": "<system-reminder>x</system-reminder>"]]))
        check(ids == ["toolu_wrap_1"], "isMeta user line keeps the card")

        // 5. The person's reply removes it.
        append(line(["type": "user", "sessionId": sid, "message": ["content": "Evet, temizle"]]))
        check(ids.isEmpty, "human reply removes the card")

        // 5b. A desktop button reply is written WITHOUT sessionId; the file name carries it.
        append(line(["type": "assistant", "sessionId": sid, "message": ["content": [[
            "type": "tool_use", "id": "toolu_wrap_2", "name": "mcp__ccd_turn__wrap_up", "input": ["ask": "Tekrar?"]]]]]))
        check(ids == ["toolu_wrap_2"], "second ask becomes a card")
        append(line(["type": "user", "message": ["content": "Evet"]]))
        check(ids.isEmpty, "button reply without sessionId removes the card")

        // 6. AskUserQuestion written in two pieces, split inside a multi-byte character.
        let ask = line(["type": "assistant", "sessionId": sid, "message": ["content": [[
            "type": "tool_use", "id": "toolu_ask_1", "name": "AskUserQuestion",
            "input": ["questions": [["header": "Şehir", "question": "Hangi şehir? Çanakkale mi İğdır mı?",
                                      "options": [["label": "Çanakkale"], ["label": "Iğdır"]]]]]]]]])
        let cut = ask.firstRange(of: Data("Ç".utf8))!.lowerBound + 1 // middle of the 2-byte "Ç"
        append(ask.prefix(upTo: cut))
        check(ids.isEmpty, "half-written line is not parsed yet")
        append(ask.suffix(from: cut))
        check(ids == ["toolu_ask_1"], "line completed across writes (UTF-8 split) is parsed")

        // 7. Answered in Claude: tool_result removes the question card.
        append(line(["type": "user", "sessionId": sid, "message": ["content": [["type": "tool_result", "tool_use_id": "toolu_ask_1", "content": "answered"]]]]))
        check(ids.isEmpty, "AskUserQuestion tool_result removes the card")

        // 8. A session that is not running is ignored for next-step asks.
        let dead = dir.appendingPathComponent("00000000-0000-0000-0000-000000000000.jsonl")
        try! line(["type": "assistant", "sessionId": "00000000-0000-0000-0000-000000000000", "message": ["content": [[
            "type": "tool_use", "id": "toolu_wrap_dead", "name": "mcp__ccd_turn__wrap_up", "input": ["ask": "Old?"]]]]]).write(to: dead)
        w.replayForTesting([dead]); pump()
        check(ids.isEmpty, "ask from a session that is not running is skipped")
        try! line(["type": "assistant", "sessionId": "00000000-0000-0000-0000-000000000000", "message": ["content": [[
            "type": "tool_use", "id": "toolu_ask_dead", "name": "AskUserQuestion",
            "input": ["questions": [["header": "x", "question": "Old?", "options": [["label": "a"]]]]]]]]]).write(to: dead)
        w.replayForTesting([dead]); pump()
        check(ids.isEmpty, "AskUserQuestion from a session that is not running is skipped")

        try? FileManager.default.removeItem(at: dir)
        print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
