//
//  ClaudeSessionWatcher.swift
//  ClaudeHUD
//
//  Live Claude Code & Claude Desktop Interceptor
//  Listens on Unix Domain Socket (/tmp/claude-hud.sock) AND
//  Watches ~/.claude/projects/*/*.jsonl transcripts for questions, diffs, and approvals.
//

import AppKit
import ApplicationServices
import Combine

public final class ClaudeSessionWatcher: @unchecked Sendable {
    public static let shared = ClaudeSessionWatcher()
    
    private let socketPath = "/tmp/claude-hud.sock"
    private var serverSource: DispatchSourceRead?
    private var serverSocketFd: Int32 = -1
    private var isRunning: Bool = false
    
    private let watcherQueue = DispatchQueue(label: "com.claudehud.sessionwatcher", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var fileOffsets: [String: UInt64] = [:]

    // Answer return path (all touched only on watcherQueue).
    // A PreToolUse hook (bin/claude-hud-hook) connects, sends the payload and waits;
    // we keep its socket open, keyed by tool_use_id, until the user answers in the HUD.
    private var waitingHooks: [String: Int32] = [:]
    private var seenToolUseIds: Set<String> = []
    /// After this the hook gets an empty reply and Claude shows its own question UI.
    public static let hookAnswerTimeout: TimeInterval = 120
    
    private init() {}
    
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        
        hudLog("🔌 Starting ClaudeSessionWatcher services...", category: "WATCHER")
        startUnixSocketServer()
        startJSONLPoller()
    }
    
    public func stop() {
        isRunning = false
        timer?.cancel()
        timer = nil
        
        if serverSocketFd != -1 {
            serverSource?.cancel()
            serverSource = nil
            close(serverSocketFd)
            serverSocketFd = -1
            unlink(socketPath)
        }
        hudLog("🛑 ClaudeSessionWatcher stopped", category: "WATCHER")
    }
    
    // MARK: - 1. Unix Domain Socket Server (/tmp/claude-hud.sock)
    
    private func startUnixSocketServer() {
        unlink(socketPath)
        
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            hudLog("❌ Failed to create Unix socket: \(errno)", category: "SOCKET")
            return
        }
        
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            hudLog("❌ Socket path too long", category: "SOCKET")
            close(fd)
            return
        }
        
        _ = withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                socketPath.withCString { pathPtr in
                    _ = strncpy(dest, pathPtr, pathBytes.count)
                }
            }
        }
        
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(fd, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        
        guard bindResult == 0 else {
            hudLog("❌ Failed to bind socket: \(errno)", category: "SOCKET")
            close(fd)
            return
        }
        
        guard listen(fd, 10) == 0 else {
            hudLog("❌ Failed to listen on socket: \(errno)", category: "SOCKET")
            close(fd)
            return
        }
        
        // Grant permissions
        chmod(socketPath, 0o777)
        self.serverSocketFd = fd
        
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: watcherQueue)
        source.setEventHandler { [weak self] in
            self?.acceptConnection(serverFd: fd)
        }
        source.resume()
        self.serverSource = source
        
        hudLog("✅ Unix Socket Server listening at \(socketPath)", category: "SOCKET")
    }
    
    private func acceptConnection(serverFd: Int32) {
        var clientAddr = sockaddr_un()
        var len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let clientFd = withUnsafeMutablePointer(to: &clientAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                accept(serverFd, sa, &len)
            }
        }
        
        guard clientFd >= 0 else { return }

        // Read until the client half-closes (hook payloads can exceed one read).
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = read(clientFd, &buffer, buffer.count)
            if n <= 0 { break }
            data.append(contentsOf: buffer[0..<n])
            if data.count > 4_000_000 { break }
        }
        guard !data.isEmpty else {
            close(clientFd)
            return
        }

        hudLog("📥 Received Hook Payload (\(data.count) bytes): \(String(decoding: data.prefix(120), as: UTF8.self))...", category: "SOCKET")
        if let keptFor = processRawPayload(data, clientFd: clientFd) {
            hudLog("⏳ Hook waiting for HUD answer: \(keptFor)", category: "SOCKET")
            return // fd stays open until respond(...) or the timeout
        }
        close(clientFd)
    }

    // MARK: - Answer Return

    /// Sends the user's HUD answer back to the waiting hook. `nil` = let Claude ask instead.
    public func respond(toolUseId: String, answers: [String: String]?) {
        watcherQueue.async { [weak self] in
            guard let self, let fd = self.waitingHooks.removeValue(forKey: toolUseId) else { return }
            let reply: [String: Any] = answers.map { ["answers": $0] } ?? [:]
            if let out = try? JSONSerialization.data(withJSONObject: reply) {
                out.withUnsafeBytes { _ = write(fd, $0.baseAddress, out.count) }
            }
            close(fd)
            hudLog(answers == nil ? "↩️ Hook released without answer (Claude will ask): \(toolUseId)"
                                  : "✅ Answer sent back to Claude: \(toolUseId)", category: "SOCKET")
        }
    }
    
    public enum PermissionDecision: String { case allow, always, deny }

    /// Answers a waiting PermissionRequest hook. nil = no decision (Claude shows its own dialog).
    public func respondPermission(id: String, decision: PermissionDecision?) {
        watcherQueue.async { [weak self] in
            guard let self, let fd = self.waitingHooks.removeValue(forKey: id) else { return }
            let reply: [String: Any] = decision.map { ["decision": $0.rawValue] } ?? [:]
            if let out = try? JSONSerialization.data(withJSONObject: reply) {
                out.withUnsafeBytes { _ = write(fd, $0.baseAddress, out.count) }
            }
            close(fd)
            hudLog("🔐 Permission \(decision?.rawValue ?? "handed back to Claude"): \(id)", category: "SOCKET")
        }
    }

    static func permission(id: String, tool: String, input: [String: Any], json: [String: Any]) -> ToolPermission {
        let text: String
        switch tool {
        case "Bash": text = input["command"] as? String ?? ""
        case "ExitPlanMode": text = input["plan"] as? String ?? ""
        case "Edit", "Write", "MultiEdit", "NotebookEdit", "Read": text = input["file_path"] as? String ?? input["notebook_path"] as? String ?? ""
        case "WebFetch": text = input["url"] as? String ?? ""
        default:
            let data = (try? JSONSerialization.data(withJSONObject: input, options: [.prettyPrinted, .sortedKeys])) ?? Data()
            text = String(data: data, encoding: .utf8) ?? ""
        }
        let suggestions = (json["permission_suggestions"] as? [Any])?.isEmpty == false
        return ToolPermission(
            id: id,
            toolName: tool == "ExitPlanMode" ? "Plan" : tool,
            command: text,
            workingDir: json["cwd"] as? String ?? "~",
            reason: input["description"] as? String,
            isDestructive: tool == "Bash" && (text.contains("rm ") || text.contains(" drop ") || text.contains("--force")),
            sessionId: json["session_id"] as? String,
            canAlwaysAllow: suggestions
        )
    }

    // MARK: - 2. JSONL File Poller for Live Sessions
    
    private func startJSONLPoller() {
        let timer = DispatchSource.makeTimerSource(queue: watcherQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(1200))
        timer.setEventHandler { [weak self] in
            self?.scanRecentJSONLFiles()
        }
        timer.resume()
        self.timer = timer
        
        hudLog("🔍 JSONL Transcript scanner started for ~/.claude/projects/", category: "TRANSCRIPT")
    }
    
    // MARK: Transcript scanning
    //
    // Every Claude Code session (terminal or desktop) appends to
    // ~/.claude/projects/<project>/<sessionId>.jsonl. We tail those files and turn
    // two things into notch cards:
    //   - AskUserQuestion tool calls (answerable from the HUD via the hook), and
    //   - the desktop's next-step box (mcp__ccd_turn__wrap_up with an `ask`),
    //     which is answered in Claude itself; the card opens that session.

    /// How far back a file may have been touched to be read at all.
    private static let fileWindow: TimeInterval = 12 * 3600
    /// On first sight of a file, read this much of its tail to find questions still pending.
    private static let firstReadTail: UInt64 = 512 * 1024

    private var lineRemainders: [String: Data] = [:]
    /// Card changes from one read, applied together so answered questions never flash on screen.
    private var batchAdds: [HUDNotificationEvent] = []
    private var batchRemovals: Set<String> = []

    private func emit(add event: HUDNotificationEvent) { batchAdds.append(event) }
    private func emit(remove id: String) {
        if let i = batchAdds.firstIndex(where: { $0.sourceId == id }) { batchAdds.remove(at: i) }
        else { batchRemovals.insert(id) }
    }
    private func flushBatch() {
        let adds = batchAdds, removals = batchRemovals
        batchAdds = []; batchRemovals = []
        guard !adds.isEmpty || !removals.isEmpty else { return }
        DispatchQueue.main.async {
            removals.forEach { HUDQueueManager.shared.remove(id: $0) }
            adds.forEach { HUDQueueManager.shared.enqueue($0) }
        }
    }
    /// Open next-step asks per CLI session id (tool_use ids), cleared by the next human prompt.
    private var openSessionAsks: [String: Set<String>] = [:]
    /// AskUserQuestion cards per CLI session, dropped if that session ends unanswered.
    private var questionCardsBySession: [String: Set<String>] = [:]
    private var liveSessions: [String: LiveSession] = [:]
    private var liveSessionsLoadedAt: Date = .distantPast

    struct LiveSession { let pid: Int32; let hostSessionId: String?; let name: String? }

    private func scanRecentJSONLFiles() {
        refreshLiveSessionsIfStale()

        let projectsURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")
        guard let subdirs = try? FileManager.default.contentsOfDirectory(at: projectsURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else {
            return
        }
        let now = Date()
        for subdir in subdirs {
            guard let files = try? FileManager.default.contentsOfDirectory(at: subdir, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles) else {
                continue
            }
            for file in files where file.pathExtension == "jsonl" {
                if let modDate = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                   now.timeIntervalSince(modDate) < Self.fileWindow {
                    readNewLines(from: file)
                }
            }
        }
    }

    private func readNewLines(from fileURL: URL) {
        let path = fileURL.path
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return }
        defer { try? handle.close() }

        let endOffset = handle.seekToEndOfFile()
        let firstSight = fileOffsets[path] == nil
        var start = fileOffsets[path] ?? (endOffset > Self.firstReadTail ? endOffset - Self.firstReadTail : 0)
        if endOffset < start { start = 0; lineRemainders[path] = nil } // file was rewritten
        guard endOffset > start else { return }

        handle.seek(toFileOffset: start)
        var data = (lineRemainders[path] ?? Data()) + handle.readData(ofLength: Int(endOffset - start))
        fileOffsets[path] = endOffset

        // A tail read starts mid-line: drop the fragment before the first newline.
        if firstSight && start > 0, let nl = data.firstIndex(of: 0x0A) {
            data = data.suffix(from: data.index(after: nl))
        }
        // Only complete lines are parsed; a half-written last line waits for the next tick.
        // (Splitting on bytes also keeps a multi-byte UTF-8 character from being cut in two.)
        guard let lastNL = data.lastIndex(of: 0x0A) else {
            lineRemainders[path] = data
            return
        }
        lineRemainders[path] = Data(data.suffix(from: data.index(after: lastNL)))
        for line in data.prefix(upTo: lastNL).split(separator: 0x0A) where !line.isEmpty {
            parseTranscriptLine(Data(line), fileSessionId: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
        }
        flushBatch()
    }

    // MARK: - 3. Parsing Events into HUDNotificationEvent

    private func parseTranscriptLine(_ data: Data, fileSessionId: String = "") {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any] else {
            return
        }
        // Desktop button replies are written without a sessionId; the file is named after the session.
        let sessionId = json["sessionId"] as? String ?? fileSessionId
        let blocks = message["content"] as? [[String: Any]] ?? []

        if json["type"] as? String == "user" {
            // A real prompt from the person answers whatever the session was asking.
            let isPrompt = json["isMeta"] as? Bool != true &&
                (message["content"] is String || blocks.contains { $0["type"] as? String == "text" }) &&
                !blocks.contains { $0["type"] as? String == "tool_result" }
            if isPrompt, let open = openSessionAsks.removeValue(forKey: sessionId) {
                open.forEach { emit(remove: $0) }
            }
        }

        for block in blocks {
            switch block["type"] as? String {
            case "tool_use":
                guard let name = block["name"] as? String, let id = block["id"] as? String,
                      let input = block["input"] as? [String: Any] else { continue }
                if name == "AskUserQuestion" {
                    if liveSessions[sessionId] == nil { liveSessionsLoadedAt = .distantPast; refreshLiveSessionsIfStale() }
                    guard liveSessions[sessionId] != nil else { seenToolUseIds.insert(id); continue }
                    questionCardsBySession[sessionId, default: []].insert(id)
                    parseAskUserQuestion(input: input, toolUseId: id)
                } else if name.hasSuffix("__wrap_up") {
                    parseNextStepAsk(input: input, toolUseId: id, sessionId: sessionId, cwd: json["cwd"] as? String)
                }
            case "tool_result":
                guard let id = block["tool_use_id"] as? String, seenToolUseIds.contains(id) else { continue }
                // Next-step asks get their tool_result at once; they stay until the next prompt.
                if openSessionAsks[sessionId]?.contains(id) == true { continue }
                // AskUserQuestion answered (or dismissed) in Claude itself: the card is stale.
                if let fd = waitingHooks.removeValue(forKey: id) { close(fd) }
                emit(remove: id)
            default:
                continue
            }
        }
    }

    private func parseNextStepAsk(input: [String: Any], toolUseId: String, sessionId: String, cwd: String?) {
        guard let ask = (input["ask"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !ask.isEmpty,
              !seenToolUseIds.contains(toolUseId) else { return }
        if liveSessions[sessionId] == nil { // a brand-new session may not be in the list yet
            liveSessionsLoadedAt = .distantPast
            refreshLiveSessionsIfStale()
        }
        // Only sessions that are still running can still be waiting.
        guard let live = liveSessions[sessionId] else { return }
        seenToolUseIds.insert(toolUseId)

        let actions = (input["actions"] as? [[String: Any]] ?? []).compactMap { a -> String? in
            if let label = a["label"] as? String, !label.isEmpty { return label }
            return (a["action"] as? String).map { $0.replacingOccurrences(of: "_", with: " ").capitalized }
        }
        let title = live.name ?? cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Claude"
        openSessionAsks[sessionId, default: []].insert(toolUseId)
        let card = SessionAsk(id: toolUseId, cliSessionId: sessionId, sessionTitle: title, question: ask,
                              recap: input["recap"] as? String ?? "", actions: actions)
        hudLog("🔔 Session waiting: [\(title)] \(ask.prefix(60))", category: "EVENT")
        emit(add: .sessionAsk(card))
    }

    // MARK: Live sessions (~/.claude/sessions/<pid>.json)

    private func refreshLiveSessionsIfStale() {
        guard Date().timeIntervalSince(liveSessionsLoadedAt) > 5 else { return }
        liveSessionsLoadedAt = Date()
        let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/sessions")
        var fresh: [String: LiveSession] = [:]
        for f in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        where f.pathExtension == "json" {
            guard let d = try? Data(contentsOf: f),
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let sid = j["sessionId"] as? String, let pid = (j["pid"] as? NSNumber)?.int32Value,
                  kill(pid, 0) == 0 || errno == EPERM else { continue }
            fresh[sid] = LiveSession(pid: pid, hostSessionId: j["hostSessionId"] as? String, name: j["name"] as? String)
        }
        liveSessions = fresh
        // A session that ended can no longer be waiting for anyone.
        var gone = openSessionAsks.filter { fresh[$0.key] == nil }
        gone.merge(questionCardsBySession.filter { fresh[$0.key] == nil }) { $0.union($1) }
        for (sid, ids) in gone {
            openSessionAsks[sid] = nil
            questionCardsBySession[sid] = nil
            ids.forEach { if let fd = waitingHooks.removeValue(forKey: $0) { close(fd) } }
            DispatchQueue.main.async { ids.forEach { HUDQueueManager.shared.remove(id: $0) } }
        }
    }

    /// Test entry: feed files through the same incremental reader without starting the socket server.
    public func replayForTesting(_ files: [URL]) {
        watcherQueue.sync {
            liveSessionsLoadedAt = .distantPast
            refreshLiveSessionsIfStale()
            files.forEach(readNewLines(from:))
        }
    }

    /// Brings that session to the front in the Claude desktop app.
    public func openSession(cliSessionId: String) {
        watcherQueue.async { [weak self] in
            self?.liveSessionsLoadedAt = .distantPast
            self?.refreshLiveSessionsIfStale()
            // The desktop only accepts its own ids here: claude://code/continue?session=local_<uuid>
            let host = self?.liveSessions[cliSessionId]?.hostSessionId
            let target = host.flatMap { URL(string: "claude://code/continue?session=\($0)&source=desktop_action") }
                ?? URL(string: "claude://code/needs-input?source=desktop_action")!
            hudLog("↗️ Opening session \(cliSessionId) via \(target.absoluteString)", category: "USER")
            DispatchQueue.main.async { NSWorkspace.shared.open(target) }
        }
    }

    // MARK: - Answer a waiting session as the person

    private static let claudeBundleId = "com.anthropic.claudefordesktop"

    /// The person clicked one of the session's own buttons in the HUD: open that session and
    /// type the label into its reply box, then press Return — the same as typing it themselves.
    /// Anything unexpected (no Accessibility permission, Claude not in front, no empty reply box)
    /// leaves the session open with nothing typed.
    public func answerSession(cliSessionId: String, text: String) {
        watcherQueue.async { [weak self] in
            guard let self else { return }
            self.liveSessionsLoadedAt = .distantPast
            self.refreshLiveSessionsIfStale()
            // Only a live desktop session can be opened by id; otherwise the link would land on
            // whatever session is showing and the text would go to the wrong place.
            guard self.liveSessions[cliSessionId]?.hostSessionId != nil else {
                hudLog("🚫 \(cliSessionId) is not a live desktop session — nothing sent", category: "USER")
                return
            }
            DispatchQueue.main.async {
                guard !self.sendInFlight else { hudLog("⏳ A reply is already being sent — click ignored", category: "USER"); return }
                let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                let trusted = AXIsProcessTrustedWithOptions(opts)
                self.openSession(cliSessionId: cliSessionId)
                guard trusted else {
                    hudLog("🔒 No Accessibility permission for Claude HUD — opened the session, typed nothing", category: "USER")
                    return
                }
                self.sendInFlight = true
                self.returnTo = NSWorkspace.shared.frontmostApplication
                self.broughtForward = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.typeWhenReady(text, attempt: 0, frontSince: nil) }
            }
        }
    }

    private var sendInFlight = false   // main thread only
    private var returnTo: NSRunningApplication?
    private var broughtForward = false

    /// macOS won't let a non-active app pull another forward, and the HUD panel never becomes
    /// active. The click is the person's, so take activation for a moment and hand it to Claude.
    private func bringClaudeForward(_ claude: NSRunningApplication) {
        guard !claude.isActive else { return }
        NSApp.activate()
        NSApp.yieldActivation(to: claude)
        claude.activate()
        broughtForward = true
        hudLog("↗️ Brought Claude forward to type the reply", category: "USER")
    }

    /// Put back the app the person was using, if we pulled Claude forward for the send.
    private func restoreFront() {
        guard broughtForward, let prev = returnTo, prev.bundleIdentifier != Self.claudeBundleId else { return }
        NSApp.activate()
        NSApp.yieldActivation(to: prev)
        prev.activate()
    }

    private func typeWhenReady(_ text: String, attempt: Int, frontSince: Date?) {
        let finish = { (msg: String) in hudLog(msg, category: "USER"); self.sendInFlight = false; self.restoreFront() }
        let retry = { (since: Date?, why: String) in
            guard attempt < 40 else { return finish("⚠️ Could not reach Claude's reply box (\(why)) — session left open, nothing typed") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { self.typeWhenReady(text, attempt: attempt + 1, frontSince: since) }
        }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.claudeBundleId).first else {
            return retry(nil, "Claude not running")
        }
        // Let the desktop switch to the session (it does, even in the background) first,
        // so the text can't land in the reply box of the session that was showing before.
        let since = frontSince ?? Date()
        guard Date().timeIntervalSince(since) >= 0.35 else { return retry(since, "settling") }

        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(appEl, "AXManualAccessibility" as CFString, kCFBooleanTrue) // Electron exposes AX only on request
        guard let box = Self.replyBox(in: appEl) else { return retry(since, "no reply box in AX tree") }
        hudLog("🔎 Reply box: \(Self.describe(box)) value-readable=\(Self.ax(box, kAXValueAttribute) != nil)", category: "USER")
        if let v = Self.ax(box, kAXValueAttribute) as? String, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return finish("✋ Reply box already has a draft — left it alone, nothing typed")
        }
        AXUIElementSetAttributeValue(box, kAXFocusedAttribute as CFString, kCFBooleanTrue)

        // No synthetic keys if avoidable: insert through AX, send by pressing Claude's own
        // "send" button next to the box. (Synthetic ⌘V / Return were ignored and beeped.)
        // The box was empty a moment ago (draft check above), so "has text" means our text landed.
        let filled = { !((Self.ax(box, kAXValueAttribute) as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        func typeOnce() {
            let src = CGEventSource(stateID: .hidSystemState)
            let units = Array(text.utf16)
            for start in stride(from: 0, to: units.count, by: 16) {
                var chunk = Array(units[start..<min(start + 16, units.count)])
                for down in [true, false] {
                    let ev = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down)
                    ev?.flags = []
                    ev?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
                    ev?.post(tap: .cghidEventTap)
                }
            }
        }
        var area = box
        for _ in 0..<8 { if let p = Self.ax(area, kAXParentAttribute) { area = p as! AXUIElement } }
        // No synthetic Return: insert through AX (re-tried while the box stays empty; injected
        // keystrokes once as a fallback), then press Claude's own "send" button.
        func step(_ tries: Int) {
            if !filled() {
                guard tries < 30 else { return finish("⚠️ \"\(text)\" not sent — it never landed in the reply box") }
                // AX text insertion never takes in this editor (seen in the log); keep one try, then type.
                if tries == 1 { self.bringClaudeForward(app) }
                AXUIElementSetAttributeValue(box, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                if tries == 2 { typeOnce() } else if tries < 2 {
                    AXUIElementSetAttributeValue(box, kAXSelectedTextAttribute as CFString, text as CFString)
                }
                return DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { step(tries + 1) }
            }
            let send = Self.find(in: area, depth: 0, all: false) {
                (Self.ax($0, kAXRoleAttribute) as? String) == "AXButton" && Self.label($0).hasPrefix("send")
                    && (Self.ax($0, kAXEnabledAttribute) as? Bool ?? true)
            }.first
            guard let send else {
                guard tries < 40 else { return finish("⚠️ \"\(text)\" typed but no send button found — press Return in Claude") }
                return DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { step(tries + 1) }
            }
            let r = AXUIElementPerformAction(send, kAXPressAction as CFString)
            finish("📨 Sent \"\(text)\" via Claude's send button (AX \(r.rawValue), try \(tries))")
        }
        step(0)
    }

    private static func label(_ el: AXUIElement) -> String {
        [kAXDescriptionAttribute, kAXTitleAttribute, kAXHelpAttribute].compactMap { ax(el, $0) as? String }
            .joined(separator: " ").lowercased()
    }

    private static func describe(_ el: AXUIElement) -> String {
        let role = ax(el, kAXRoleAttribute) as? String ?? "?"
        let ph = ax(el, kAXPlaceholderValueAttribute) as? String ?? ""
        return "\(role) '\(label(el))'\(ph.isEmpty ? "" : " placeholder='\(ph)'")"
    }

    private static func buttons(in appEl: AXUIElement) -> [AXUIElement] {
        guard let w = ax(appEl, kAXFocusedWindowAttribute), CFGetTypeID(w) == AXUIElementGetTypeID() else { return [] }
        return find(in: w as! AXUIElement, depth: 0, all: true) { (ax($0, kAXRoleAttribute) as? String) == "AXButton" }
    }

    private static func ax(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success ? v : nil
    }

    /// The focused text input if there is one, else the last editable text area in the focused
    /// window (the composer sits at the bottom of the session view).
    private static func window(of appEl: AXUIElement) -> AXUIElement? {
        for attr in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            if let w = ax(appEl, attr), CFGetTypeID(w) == AXUIElementGetTypeID() { return (w as! AXUIElement) }
        }
        return (ax(appEl, kAXWindowsAttribute) as? [AXUIElement])?.first
    }

    private static func replyBox(in appEl: AXUIElement) -> AXUIElement? {
        if let f = ax(appEl, kAXFocusedUIElementAttribute), CFGetTypeID(f) == AXUIElementGetTypeID(),
           NSRunningApplication.runningApplications(withBundleIdentifier: claudeBundleId).first?.isActive == true {
            let el = f as! AXUIElement
            if let r = ax(el, kAXRoleAttribute) as? String, ["AXTextArea", "AXTextField"].contains(r) { return el }
        }
        guard let w = window(of: appEl) else { return nil }
        return find(in: w, depth: 0, all: true) { el in
            (ax(el, kAXRoleAttribute) as? String) == "AXTextArea"
        }.last
    }

    // ponytail: plain DFS capped at depth 80; fine for one window, cache if it ever shows up in a profile.
    private static func find(in el: AXUIElement, depth: Int, all: Bool, _ match: (AXUIElement) -> Bool) -> [AXUIElement] {
        if depth > 80 { return [] }
        var out: [AXUIElement] = match(el) ? [el] : []
        if !all && !out.isEmpty { return out }
        for child in (ax(el, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
            out += find(in: child, depth: depth + 1, all: all, match)
            if !all && !out.isEmpty { return out }
        }
        return out
    }

    /// Returns the tool_use_id when the caller is a hook that waits for the answer
    /// (the socket must then stay open); nil when the connection can be closed.
    private func processRawPayload(_ data: Data, clientFd: Int32) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        // Real Claude Code hook payloads use hook_event_name/tool_name; older test payloads event/tool.
        let event = json["hook_event_name"] as? String ?? json["event"] as? String ?? ""
        let tool = json["tool_name"] as? String ?? json["tool"] as? String ?? ""
        let input = json["tool_input"] as? [String: Any] ?? [:]
        let toolUseId = json["tool_use_id"] as? String
        let wantsAnswer = (json["wait_for_answer"] as? Bool) == true

        hudLog("⚙️ Processing hook event: '\(event)', tool: '\(tool)'", category: "HOOK")

        if event == "PermissionRequest" {
            // Off in settings → release at once so Claude shows its own dialog without waiting.
            guard wantsAnswer, UserDefaults.standard.bool(forKey: "hud_approvePermissions") else { return nil } // caller closes the fd
            let id = toolUseId ?? UUID().uuidString
            waitingHooks[id] = clientFd
            let perm = Self.permission(id: id, tool: tool, input: input, json: json)
            DispatchQueue.main.async { HUDQueueManager.shared.enqueue(.permission(perm)) }
            watcherQueue.asyncAfter(deadline: .now() + Self.hookAnswerTimeout) { [weak self] in
                guard let self, self.waitingHooks[id] != nil else { return }
                hudLog("⌛️ No HUD decision in \(Int(Self.hookAnswerTimeout))s, handing back to Claude: \(id)", category: "SOCKET")
                self.respondPermission(id: id, decision: nil)
                DispatchQueue.main.async { HUDQueueManager.shared.remove(id: id) }
            }
            return id
        }

        if tool == "AskUserQuestion" || event.contains("Question") {
            guard wantsAnswer, let id = toolUseId else {
                parseAskUserQuestion(input: input, toolUseId: toolUseId)
                flushBatch()
                return nil
            }
            waitingHooks[id] = clientFd
            parseAskUserQuestion(input: input, toolUseId: id)
            flushBatch()
            watcherQueue.asyncAfter(deadline: .now() + Self.hookAnswerTimeout) { [weak self] in
                guard let self, self.waitingHooks[id] != nil else { return }
                hudLog("⌛️ No HUD answer in \(Int(Self.hookAnswerTimeout))s, handing back to Claude: \(id)", category: "SOCKET")
                self.respond(toolUseId: id, answers: nil)
                DispatchQueue.main.async { HUDQueueManager.shared.remove(id: id) }
            }
            return id
        } else if tool == "Bash" || event.contains("Permission") {
            let cmd = input["command"] as? String ?? "Command"
            let perm = ToolPermission(
                toolName: "Bash",
                command: cmd,
                workingDir: json["cwd"] as? String ?? "~",
                reason: "Automated security policy interception",
                isDestructive: cmd.contains("rm ") || cmd.contains("drop ")
            )
            DispatchQueue.main.async {
                HUDQueueManager.shared.enqueue(.permission(perm))
            }
        }
        return nil
    }

    private func handleToolUse(name: String, input: [String: Any]) {
        switch name {
        case "AskUserQuestion":
            parseAskUserQuestion(input: input, toolUseId: nil)
            flushBatch()
        case "Bash":
            if let command = input["command"] as? String {
                let perm = ToolPermission(
                    toolName: "Bash",
                    command: command,
                    workingDir: "~",
                    reason: "Interactive Command Approval Required",
                    isDestructive: command.contains("rm ") || command.contains("drop ") || command.contains("kill ")
                )
                DispatchQueue.main.async {
                    hudLog("🚨 Enqueueing Bash Approval: \(command.prefix(60))...", category: "EVENT")
                    HUDQueueManager.shared.enqueue(.permission(perm))
                }
            }
        default:
            break
        }
    }
    
    private func parseAskUserQuestion(input: [String: Any], toolUseId: String?) {
        guard let questionsRaw = input["questions"] as? [[String: Any]], !questionsRaw.isEmpty else {
            return
        }
        // Transcript scanner and hook both deliver the same call: show it once.
        if let id = toolUseId {
            guard seenToolUseIds.insert(id).inserted else { return }
        }
        let eventId = toolUseId ?? UUID().uuidString
        
        var parsedQuestions: [QuestionPrompt] = []
        for (qIdx, q) in questionsRaw.enumerated() {
            let questionText = q["question"] as? String ?? "Question"
            let header = q["header"] as? String ?? "Step \(qIdx + 1)"
            var options: [QuestionOption] = []
            
            if let rawOptions = q["options"] as? [Any] {
                for (optIdx, opt) in rawOptions.enumerated() {
                    if let optDict = opt as? [String: Any] {
                        let label = optDict["label"] as? String ?? "Option"
                        let desc = optDict["description"] as? String ?? ""
                        let tag = optDict["tag"] as? String
                        options.append(QuestionOption(keyNumber: optIdx + 1, label: label, description: desc, tag: tag))
                    } else if let optStr = opt as? String {
                        let isRec = optStr.contains("(Recommended)")
                        let clean = optStr.replacingOccurrences(of: "(Recommended)", with: "").trimmingCharacters(in: .whitespaces)
                        options.append(QuestionOption(keyNumber: optIdx + 1, label: clean, description: "", tag: isRec ? "Recommended" : nil))
                    }
                }
            }
            parsedQuestions.append(QuestionPrompt(
                id: parsedQuestions.isEmpty && questionsRaw.count == 1 ? eventId : UUID().uuidString,
                question: questionText, header: header, options: options,
                multiSelect: q["multiSelect"] as? Bool ?? false))
        }
        
        if parsedQuestions.count == 1, parsedQuestions[0].options.count <= 3 {
            hudLog("🎯 Question: \(parsedQuestions[0].question.prefix(50))...", category: "EVENT")
            emit(add: .question(parsedQuestions[0]))
        } else {
            hudLog("📋 Multi-step question (\(parsedQuestions.count) steps)", category: "EVENT")
            emit(add: .multiQuestion(MultiQuestionSession(id: eventId, questions: parsedQuestions)))
        }
    }
}
