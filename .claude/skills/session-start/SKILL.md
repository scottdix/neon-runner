---
name: session-start
description: Begin a work session — read PROJECT_STATE.yaml + the last handoff and present a short "where was I / what's next" greeting. Invoke when the user runs /session-start, says "begin", or asks to pick up where they left off.
---

# /session-start — Begin a Session

Solo project. The job is to restore context fast: read the manifest + the last
handoff, give a 2-line greeting, and only pull the full issue detail once the
user says "begin." This is read-only — it does not write files or commit.

## Steps

1. **Read `PROJECT_STATE.yaml`** and extract:
   - `last_updated.session` → this session is **N = that value + 1**.
   - `focus.active_milestone`, `focus.active_epic`, `focus.current_issue`, `focus.next_issue`.

2. **Read the last handoff** at `docs/handoff/SESSION-{NNN}.md` (zero-padded, where
   `NNN` = `last_updated.session`). If it's missing, check `docs/handoff/_archive/`.
   Pull out: what was accomplished, and the next task.

3. **Present a SHORT greeting** and stop:

   ```
   Session {N} ready. Milestone: {active_milestone}.
   Current: {current_issue}.

   Anything to flag, or begin?
   ```

   Do NOT fetch issue bodies, run git, or recap the last session yet — wait for "begin."

## On "begin" (or "go" / "start" / a request for detail)

4. **Fetch the current issue** for full context:

   ```bash
   gh issue view {current_issue_number} --json title,body,labels,milestone
   ```

5. **Present the full briefing:**

   ```
   ## Session {N} Briefing

   **Date:** {YYYY-MM-DD}
   **Milestone:** {active_milestone}  ·  **Epic:** {active_epic}

   ### Last Session
   {2-3 sentences from the previous handoff}

   ### Today's Focus: {current_issue}
   {Acceptance criteria / tasks from the GitHub issue body}

   ### Up Next
   {next_issue}
   ```

## Key Principles

- **Short startup.** Greeting is 2 lines; full briefing only after "begin."
- **GitHub Issues is the tracker.** Use `gh issue view` / `gh issue list` for task detail.
- **One issue at a time** — work on `focus.current_issue`.
- **Read-only.** No writes, no commits. If the user wants to change focus, edit the
  `focus` block of `PROJECT_STATE.yaml`.
- If `PROJECT_STATE.yaml` is missing, say so and suggest running `/handoff` to create it.
