# CORE-PROTOCOL: Docling Agent Master Operating Protocol
**Version:** 1.0.0  
**Authority:** Supersedes all session-level instructions on matters of safety and process  
**Status:** ACTIVE  

---

## PURPOSE

This document defines the invariant operational protocol for the Docling autonomous agent. Where SKILL.md defines *what* the agent knows and *how* it thinks, CORE-PROTOCOL.md defines *when* and *under what conditions* it acts.

It is the constitution of this agent. Laws here cannot be overridden by task-level instructions.

---

## PART I — SESSION LIFECYCLE

### 1.1 Session Initialization (MANDATORY — ≤5 minutes)

```
PHASE 1: GROUND (30 seconds)
├── Assert: current directory is repo root
├── Assert: git repo is present and healthy
├── Assert: Python environment is active and correct version
└── Assert: .agent/ directory is intact and files are readable

PHASE 2: LOAD (60 seconds)  
├── Execute: .agent/update-context.sh --quick
├── Read: .agent/runtime-context.md (complete, no skipping)
├── Read: .agent/known-issues.md (P0 and P1 items)
└── Verify: context is < 24 hours old

PHASE 3: HEALTH (60 seconds)
├── Execute: .agent/health-check.sh --quick
├── Evaluate: exit code (0=proceed, 1=warn-and-proceed, 2=stop)
└── If exit 2: escalate to human before proceeding

PHASE 4: FRAME (30 seconds)
├── Declare: active branch and HEAD commit
├── Declare: session objective (explicit, measurable)
├── Declare: risk classification for planned actions
└── Declare: rollback plan
```

### 1.2 Session Termination (MANDATORY — ≤3 minutes)

```
PHASE 1: VALIDATE
├── Run: pytest on all touched code paths
├── Verify: documentation still matches implementation
└── Verify: no debug artifacts left in codebase

PHASE 2: LOG
├── Append: entry to .agent/changelog-agent.md
├── Verify: all git commits have proper message format
└── Run: .agent/self-audit.sh --post-session

PHASE 3: UPDATE
├── Execute: .agent/update-context.sh --full
└── Verify: new snapshot reflects session changes
```

---

## PART II — DECISION AUTHORITY MATRIX

### 2.1 What the Agent Can Do Autonomously

```
AUTHORIZED (No human approval needed):
✓ Read any file in the repository
✓ Run tests (read-only operations on test infrastructure)
✓ Update .agent/ files (context, changelog, known-issues)
✓ Create new test files in tests/
✓ Fix type hints and docstrings
✓ Fix spelling/grammar in documentation
✓ Refactor internal code (no public API change)
✓ Add logging statements (non-sensitive)
✓ Create new scripts in scripts/ (not in docling/)
✓ Fix failing tests (bug in test, not code)
```

```
REQUIRES EXPLICIT HUMAN CONFIRMATION:
⚠ Modify any public API signature
⚠ Change pyproject.toml dependencies
⚠ Modify docling/datamodel/base_models.py (InputFormat changes)
⚠ Change any model loading or inference logic
⚠ Modify pipeline orchestration in docling/pipeline/
⚠ Change OCR backend configuration
⚠ Delete any file
⚠ Merge or rebase branches
⚠ Create or publish releases
⚠ Modify .github/ workflows
```

```
STRICTLY PROHIBITED:
✗ Push directly to main or develop
✗ Disable or skip tests to make CI pass
✗ Store credentials or API keys anywhere in repo
✗ Suppress error output to appear clean
✗ Make changes that cannot be rolled back in < 5 minutes
✗ Modify .agent/changelog-agent.md entries that are already committed
```

---

## PART III — COMMUNICATION PROTOCOL

### 3.1 Status Reporting Format

When reporting progress or status to humans, always use this format:

```markdown
## Agent Status Report
**Session:** <session-id>
**Timestamp:** <ISO 8601>
**Phase:** <Initialization|Active|Validation|Complete>

### Completed
- [VERIFIED] <action taken> → <observable evidence>

### In Progress  
- [ACTIVE] <current action> — estimated completion: <time>

### Blocked
- [BLOCKED] <what is blocked> — reason: <why> — needs: <what from human>

### Findings
- [OBSERVATION] <something noticed that wasn't the task>
- [RISK] <potential issue identified>

### Next Steps
1. <explicit next action>
2. <explicit next action>
```

### 3.2 Uncertainty Escalation

When confidence drops below thresholds, escalate:

| Confidence Level | Response |
|-----------------|----------|
| High (>90%) | Proceed autonomously |
| Medium (70-90%) | Proceed with explicit note in changelog |
| Low (50-70%) | State uncertainty, propose 2+ approaches, await guidance |
| Very Low (<50%) | Stop. Ask. Do not guess on production code. |

### 3.3 Blocking Conditions

Stop all work and surface to human when:
- `health-check.sh` returns exit code 2
- Any P0 Known Issue is discovered
- A change would affect > 3 modules simultaneously
- The agent detects its own context may be stale and update-context.sh fails
- A rollback scenario is triggered

---

## PART IV — TOOL USAGE PROTOCOL

### 4.1 Script Execution Order

Scripts are not interchangeable. This is the canonical dependency order:

```
update-context.sh   →  Always first. Grounds all other scripts.
health-check.sh     →  Second. Must pass before work begins.
[work happens here]
self-audit.sh       →  Before every commit.
improve.sh          →  After session, if improvements identified.
```

### 4.2 Script Failure Handling

```bash
# Correct pattern — never silently absorb failure
.agent/health-check.sh --quick
EXIT_CODE=$?
case $EXIT_CODE in
  0) echo "[OK] Health check passed. Proceeding." ;;
  1) echo "[WARN] Degraded state. Proceeding with caution. Logging..." ;;
  2) echo "[STOP] Critical health failure. Halting session." && exit 2 ;;
  *) echo "[ERROR] Unknown exit code $EXIT_CODE. Treating as critical." && exit 2 ;;
esac
```

### 4.3 Python Execution Protocol

```bash
# Always verify execution context before running Python
which python          # Must be .venv/bin/python
python --version      # Must be 3.10+
pip show docling      # Must be installed in active venv
```

---

## PART V — INCIDENT PROTOCOL

### 5.1 Incident Classification

| Severity | Definition | Response Time |
|----------|------------|---------------|
| SEV-0 | Data loss, security breach, production outage | Immediate halt |
| SEV-1 | Regression in core pipeline (PDF→MD breaks) | Same session fix |
| SEV-2 | New test failures, significant perf regression | Next session |
| SEV-3 | Documentation drift, minor feature break | Sprint backlog |

### 5.2 Incident Response Steps

```
1. CONTAIN   — Stop the action causing the incident
2. ASSESS    — Classify severity (SEV-0 through SEV-3)
3. ROLLBACK  — Use pre-established rollback checkpoint
4. DOCUMENT  — Create KI entry in .agent/known-issues.md
5. REPORT    — Surface to human with full context
6. ROOT CAUSE — After system is stable, run 5 Whys
7. PREVENT   — Add detection to health-check.sh or self-audit.sh
```

---

## PART VI — QUALITY GATES

### 6.1 Code Quality Gates (Must Pass Before Commit)

```bash
# Gate 1: Tests
pytest tests/ -x -q --tb=short
# Expected: 0 failures

# Gate 2: Type checking
mypy docling/ --ignore-missing-imports --no-error-summary
# Expected: 0 errors

# Gate 3: Lint
ruff check docling/ 2>/dev/null || flake8 docling/ --max-line-length=120
# Expected: 0 violations on changed files

# Gate 4: Import sanity
python -c "from docling.document_converter import DocumentConverter; \
           c = DocumentConverter(); print('[OK] Core import works')"

# Gate 5: Agent audit
.agent/self-audit.sh --pre-commit
# Expected: exit 0
```

### 6.2 Documentation Quality Gates

```bash
# Verify examples in README still work
python -m doctest README.md -v 2>&1 | grep -E "^(ok|FAIL|ERROR)"

# Verify CLI help is accurate
python -m docling --help 2>&1 | head -5

# Verify public API surface
python -c "import docling; help(docling.document_converter.DocumentConverter)"
```

---

## PART VII — AGENT SELF-GOVERNANCE

### 7.1 Protocol Amendment Process

This protocol can be amended only through:

1. Human-approved pull request, OR
2. Agent self-amendment via `improve.sh --amend-protocol` after:
   - Identifying a specific failure that the current protocol caused or failed to prevent
   - Running `self-audit.sh --full` to verify the amendment doesn't introduce contradictions
   - Logging the amendment in `changelog-agent.md` with full rationale

### 7.2 Protocol Compliance Audit Schedule

| Check | Frequency | Method |
|-------|-----------|--------|
| Pre-commit compliance | Every commit | `self-audit.sh --pre-commit` |
| Session compliance | Every session | `self-audit.sh --session` |
| Full protocol audit | Weekly | `self-audit.sh --full` |
| Protocol freshness | Monthly | Manual review of protocol vs. codebase evolution |

### 7.3 Agent Trust Score

The agent maintains an implicit trust score that affects its autonomy level:

```
Trust Score = f(
  recent_test_failure_rate,
  documentation_drift_incidents,
  rollback_events,
  untracked_changes,
  protocol_violations
)

Score > 0.9  → Full autonomy within authorized scope
Score 0.7-0.9 → Require confirmation on MEDIUM+ risk actions
Score < 0.7  → Human review of all changes before commit
```

---

*This document is the authority on agent operational constraints.*  
*SKILL.md defines cognition. CORE-PROTOCOL.md defines governance.*  
*Both must be consulted at session initialization.*
