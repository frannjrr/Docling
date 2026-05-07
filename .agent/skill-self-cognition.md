# Skill: Project Self-Cognition & Continuous Improvement

## Purpose
This skill allows any agent interacting with this project to:
1. Understand the current state of the codebase dynamically.
2. Inject fresh context before making decisions or executing tasks.
3. Self-diagnose errors and suggest improvements.
4. Maintain an evolving knowledge of the system.

## How to Use This Skill (For Any Agent)
When invoked, the agent MUST:
1. Read `AGENTS.md` in the project root for the current architectural overview.
2. Read this file (`skill-self-cognition.md`) for the self-improvement protocol.
3. Execute `.agent/update-context.sh` to generate a fresh runtime snapshot.
4. Read the generated `.agent/context-snapshot.json` for current file contents.
5. Use this snapshot to answer user queries or perform tasks with up-to-date knowledge.

## Self-Improvement Protocol (Agent Instructions)
After completing ANY task involving this project, the agent should evaluate:

### 1. Documentation Accuracy
- Does `AGENTS.md` still accurately reflect the codebase?
- If any change was detected in `main.py`, `docling_actions.py`, `requirements.txt`, or `start.sh`, the agent MUST flag `AGENTS.md` for update.
- If the agent updates the code, it MUST also update the documentation.

### 2. Error Pattern Detection
- If a recurring error pattern is observed, the agent should APPEND to the "Known Issues" section of `AGENTS.md`.
- Format: `## Known Issues (Auto-generated)\n- **[YYYY-MM-DD]** Description of issue and workaround.`

### 3. Context Freshness
- Before asserting anything about the system state, ALWAYS check `.agent/context-snapshot.json` or run `update-context.sh`.
- Never rely on cached memory from previous sessions about this project unless verified against the live snapshot.

### 4. Capability Expansion
- When new features, endpoints, or actions are added to the project, the agent MUST update the "Available Agent Actions" section.
- If a new environment variable is discovered in the code, update the Configuration table.

## Runtime Context Injection Template
When an agent needs context before answering a question about this project, use this template:

```
SYSTEM: Loading live project context...
1. Read: AGENTS.md → architectural overview
2. Read: .agent/skill-self-cognition.md → self-improvement rules
3. Execute: bash .agent/update-context.sh → generate snapshot
4. Read: .agent/context-snapshot.json → current file state
5. Answer user query with verified context.
