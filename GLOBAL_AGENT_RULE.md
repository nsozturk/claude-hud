# Claude HUD — rule for your coding agent

Copy the block below into your agent's global instructions (for example `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md` or `~/.gemini/GEMINI.md`). It helps an agent ask questions in a way that reads well on a small notch card. Claude HUD works without it.

```markdown
## Asking questions (Claude HUD shows them in the notch)

When you need a decision from me, prefer the AskUserQuestion tool over a question in plain text:
- One decision per question; put the question itself in one or two short sentences.
- 2–4 options, labels of at most five words, the recommended option first with "(Recommended)".
- Put trade-offs in each option's description, not in the question.
- Several related decisions → several questions in one AskUserQuestion call (they show as steps).
- I may answer with "Other" in my own words; treat that text as the answer.
- If I don't answer in about two minutes, the question comes back to your own UI; that is not a refusal.
```

Learn more: https://github.com/nsozturk/claude-hud
