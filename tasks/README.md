# Task Queue

Tasks are plain markdown files placed in this directory.

## Format

```markdown
# Task: <short title>

**Priority:** high | normal | low
**Created:** YYYY-MM-DD
**Assigned:** codex

## Description
One paragraph describing what needs to be done.

## Acceptance criteria
- [ ] Criterion 1
- [ ] Criterion 2

## Context
Links to relevant files, vault notes, or prior work.
```

## Usage

1. Place a task file here (e.g., `fix-auth-bug.md`)
2. Open agentic-ui, select Codex persona
3. Say: "Pick up the next task from tasks/"
4. Codex reads the task, works on it, writes STATUS.md on completion

## Status reporting

Codex writes `~/projects/codex-drone/workspace/STATUS.md` after completing each task:

```markdown
# STATUS
**Task:** fix-auth-bug.md
**Status:** complete | failed | escalated
**Summary:** One sentence.
**Changed files:** list of files modified
**Tests:** passed / failed
```
