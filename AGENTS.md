# AGENTS.md — working on Claude HUD

Contract for AI coding agents (Claude Code, Codex, Gemini CLI, Cursor, OpenCode, Antigravity) changing this repository.

Claude HUD is a native macOS menu-bar app (Swift, SwiftUI, AppKit; no Xcode project, no packages) that shows Claude Code's questions and permission prompts in the MacBook notch and sends the user's answers back.

## Commands

| Task | Command | Notes |
|---|---|---|
| Build the app | `./scripts/build-app.sh` | → `build/Claude HUD.app`; ad-hoc signed. `SIGN_IDENTITY=…` signs with a real certificate (keeps macOS permissions across rebuilds). |
| Replay test | `./scripts/test.sh <session-id>` | Needs the `sessionId` of a running Claude Code session from `~/.claude/sessions/*.json`. Prints `PASS`/`FAIL` lines and `ALL PASS`; exit code 1 on any failure. |
| What the HUD would show now | `./scripts/test.sh --real` | Read-only scan of the real transcripts. |
| Hook smoke test | `echo '{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"ls"}}' \| python3 bin/claude-hud-hook` | Prints nothing and exits 0 when the HUD is not running or the feature is off — that is correct. |
| Live log | `tail -f /tmp/claude-hud.log` | Every queue change, hook, hot key and send is logged here. |

There is no other build system. Do not add Swift packages, CocoaPods or an Xcode project.

## How the parts fit

- `bin/claude-hud-hook` (Python 3 standard library only) is the Claude Code hook. It handles `PreToolUse` for `AskUserQuestion` and `PermissionRequest`. It sends the payload plus `"wait_for_answer": true` to `/tmp/claude-hud.sock` and waits up to 140 s.
  - The HUD replies `{"answers": {question: label}}` for questions, or `{"decision": "allow"|"always"|"deny"}` for permissions.
  - Anything else → the hook prints nothing and exits 0, so Claude falls back to its own UI.
- `Services/ClaudeSessionWatcher.swift`: Unix socket server + transcript poller (`~/.claude/projects/*/*.jsonl`, tail only). Next-step asks come from `mcp__ccd_turn__wrap_up` tool calls in transcripts. `answerSession` types a reply into the Claude desktop app through Accessibility and presses its own `send` button.
- `Services/HUDHotkeys.swift`: Carbon hot keys on `GetEventDispatcherTarget()`, registered only while a card is shown and the HUD is not snoozed.
- `Models/HUDQueueManager.swift`: the card queue. `showNow` is for test scenarios; any real `enqueue` drops scenario cards.
- `Views/ClaudeHUDShellView.swift`: card chrome, pills, transitions, hot key routing. `Window/LiveNotchPanelController.swift`: the borderless panel.
- `Settings/`: `HUDSettingsStore` (UserDefaults, keys `hud_*`) and the sidebar UI. `Onboarding/`: welcome + `HUDHookInstaller` (edits `~/.claude/settings.json`, keeps `.bak`).

## Rules that must hold

1. **Never answer for the user.** Every answer, allow or deny comes from a click or key press. Timeouts hand the question back to Claude (`respond(…, nil)`), never a default answer.
2. **Fail open.** The hook must exit 0 with no output on any error, so Claude Code works exactly as without the HUD.
3. **No network access, no telemetry.** Do not add any.
4. **Hot keys only in the live panel.** The same cards render in the settings preview; anything reacting to `HUDHotkeys.shared.actions` must check `@Environment(\.hudHandlesHotkeys)`, or one key press answers twice.
5. **Text goes only to live sessions.** `answerSession` refuses a session that is not in `~/.claude/sessions` (prevents typing into whatever session is on screen).
6. **Hook installs are additive.** Never remove or rewrite other entries in `~/.claude/settings.json`; always keep the `.bak`.
7. Keep the app dependency-free and English-only in UI strings.

## Gotchas

- Screenshots of the live panel come out blank when **Hide from screen sharing** is on (`sharingType = .none`). Check the settings preview instead, or turn it off while testing.
- Ad-hoc signing changes the code identity on every build, so macOS forgets the Accessibility grant. Use `SIGN_IDENTITY` while developing.
- `NSScreen.main` is the external display when one is primary; the notch height must come from the panel's own screen.
- SwiftUI reuses a view when only its data changes; cards need `.id(event.sourceId)` for transitions to run.
- `scaleEffect` + `offset` on the stacked layers must scale width only, or the layers sit flush behind the card.

## Before you finish a change

1. `./scripts/build-app.sh` builds with no errors.
2. `./scripts/test.sh <session-id>` prints `ALL PASS`.
3. If you touched the hook: run the smoke test above, with and without the HUD running.
4. Grep your diff for absolute home paths, emails and tokens; there must be none.
