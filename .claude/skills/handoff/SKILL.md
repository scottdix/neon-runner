---
name: handoff
description: End a work session — validate the tree, write a session handoff doc, advance the issue pointer in PROJECT_STATE.yaml, update GitHub issues, and commit/push. Invoke when the user runs /handoff, says "wrap up", "end session", or "hand off".
---

# /handoff — End a Session

Solo project. One pass: validate → write the session doc → advance state → update
GitHub → commit + push. No security audits, no contributor lanes, no scripts.

## Steps

1. **Determine the session number (N).** Read `docs/handoff/session-number.txt`
   (the last completed session). This session is **N = that value + 1**. If the
   file is missing, N = 1.

2. **Validate the tree.** Run `git status --porcelain`.
   - If there are uncommitted changes from this session, that's expected — you'll
     commit them in step 6. Just confirm there's nothing surprising (stray build
     artifacts, files outside the work scope). The `.gitignore` already covers
     Godot's `.godot/`, `.import/`, exports, and OS junk.

3. **Archive the previous handoff.** Move the existing `docs/handoff/SESSION-*.md`
   (there should be at most one at top level) into `docs/handoff/_archive/`.

4. **Write the new handoff** to `docs/handoff/SESSION-{NNN}.md` (zero-padded) using
   the template below. Keep it short — `git log --stat` already shows files.

5. **Advance `PROJECT_STATE.yaml`** (the single source of session memory):
   - If `focus.current_issue` was completed this session → set `current_issue` to
     the former `next_issue`, and pick the new `next_issue` from the active epic /
     milestone (use `gh issue list` to find the next open issue in sequence). If
     not completed, keep it and note the blocker in the handoff doc.
   - Bump `last_updated.date` and `last_updated.session` to N.
   - **Rotate notes:** move the current `last_updated.notes` into `previous_notes`
     (dropping the old `previous_notes` — history depth is 2), and write this
     session's summary into `notes`.

6. **Update GitHub issues** for work done this session:
   - Close completed issues: `gh issue close {N} --comment "Done in session {N}: …"`.
   - Or comment progress: `gh issue comment {N} --body "…"`.
   - Adjust `status:` labels if useful (e.g. add `status: in-review`).

7. **Write the session counter:** put `N` into `docs/handoff/session-number.txt`.

8. **Commit + push.** `git add -A`, commit with a clear message referencing any
   issues (e.g. `feat: implement Events autoload (#3)`), then `git push origin HEAD`.
   This is `main` for now — fine for a solo repo. If a branch is checked out, push
   that branch.

9. **Report** the commit hash, what was handed off, and the next task.

## Handoff Template

```markdown
# Session {NNN} Handoff

**Date:** {YYYY-MM-DD}
**Milestone:** {active_milestone}  ·  **Epic:** {active_epic}

## Completed This Session
- {issue ref}: {one-line summary}

## Next Task
{current_issue after advance} — {one-line pointer}

## Notes / Blockers
{anything the next session needs to know, or "None"}
```

## Key Principles

- **One writer of state.** `/handoff` is the only thing that advances
  `PROJECT_STATE.yaml` and `session-number.txt`. `/session-start` only reads.
- **Short doc.** Files come from `git log --stat`; decisions go in GitHub issue
  comments; the manifest carries the rolling summary.
- **Always leave the next task explicit** — the next `/session-start` should know
  exactly what to pick up.
- **Don't skip the commit.** A handoff with an uncommitted tree creates context rot.
