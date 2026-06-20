---
name: plan
description: Architecture and implementation planning. Invoke when the user asks to "design", "architect", "plan", or work through how to structure a feature, system, or refactor before building it.
---

# /plan — Delegate Planning to an Opus Agent

When this skill is invoked, delegate the planning to a dedicated Opus `Plan` agent
rather than planning inline. Planning is high-leverage thinking worth the focused
agent — it analyzes the codebase, weighs trade-offs, and returns a phased plan
without burning the main context on exploration.

## Action

Spawn the planner with the Agent tool:

```
Agent(
  description="Architecture/Planning",
  subagent_type="Plan",
  model="opus",
  prompt="You are the planning specialist for Neon Runner, a Godot 4.x neon
arcade vector-shooter (GDScript-first). Read IMPLEMENTATION_PLAN.md and the
relevant GitHub issues (via gh) for context. Produce a detailed, phased
implementation plan for the request below: the files/scenes/scripts to
create or change, key design decisions, risks, and a build sequence.

User request: [INSERT FULL USER REQUEST HERE]"
)
```

## After the agent returns

Present the plan and ask:
- "Ready to implement?" → build it (default model).
- "Adjust the plan?" → re-invoke the Plan agent with the feedback.

## Notes

- For game-architecture questions, point the agent at `IMPLEMENTATION_PLAN.md`
  (folder structure, autoload order, code stubs) and the relevant phase epic.
- Keep the performance posture from Session 1 in mind: batch large entity counts
  (MultiMesh / GPUParticles), don't reach for a custom engine.
