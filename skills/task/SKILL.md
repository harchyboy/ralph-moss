---
name: task
description: "Smart task router for Ralph Moss. Automatically decides if something is a bug fix or feature, then creates the appropriate PRD. Use for any task you want Ralph Moss to handle. Triggers on: task, do this, ralph moss task, add task."
---

# Ralph Moss Task Router

A single entry point for Ralph Moss. Describe what you want, and this skill decides if it's a bug fix or feature PRD.

---

## The Job

1. Receive task description from user
2. Classify: Bug fix or Feature?
3. Ask minimal clarifying questions (1-2 max)
4. Generate the appropriate prd.json
5. Save to `scripts/ralph-moss/prds/[task-name]/`

**Important:** Do NOT start implementing. Just create the PRD.

---

## Step 1: Classification

Analyze the task description to determine type:

**Bug Fix indicators:**
- "fix", "broken", "doesn't work", "error", "crash", "bug"
- "not working", "fails", "issue", "problem"
- References existing functionality that's broken

**Feature indicators:**
- "add", "create", "new", "implement", "build"
- "I want", "we need", "should have"
- Describes something that doesn't exist yet

**If unclear, ask:**
```
Is this:
A. A bug fix (something is broken)
B. A new feature (something to add)
```

---

## Step 2: Quick Questions (1-2 max)

### For Bug Fixes:
```
1. Is this a UI bug or backend bug?
   A. UI (visible in browser)
   B. Backend (API/data/logic)
   C. Both/Not sure
```

### For Features:
```
1. What's the scope?
   A. Small (single component/function)
   B. Medium (multiple components)
   C. Large (new page/system)
```

---

## Step 3: Generate PRD

### Bug Fix Format

Directory: `scripts/ralph-moss/prds/fix-[bug-name-kebab-case]/`

```json
{
  "project": "MyProject",
  "branchName": "ralph-moss/fix-[bug-name-kebab-case]",
  "description": "Bug fix: [Short description]",
  "userStories": [
    {
      "id": "BUG-001",
      "title": "Fix: [Bug description]",
      "description": "[What's broken and where]",
      "acceptanceCriteria": [
        "[Reproduction scenario now works]",
        "[Related functionality still works]",
        "Typecheck passes",
        "All existing tests pass",
        "[UI bugs] Verify in browser using dev-browser skill"
      ],
      "priority": 1,
      "passes": false,
      "notes": ""
    }
  ]
}
```

### Feature Format

Directory: `scripts/ralph-moss/prds/[feature-name-kebab-case]/`

```json
{
  "project": "MyProject",
  "branchName": "ralph-moss/[feature-name-kebab-case]",
  "description": "[Feature description]",
  "userStories": [
    {
      "id": "US-001",
      "title": "[Story title]",
      "description": "As a [user], I want [feature] so that [benefit]",
      "acceptanceCriteria": [
        "[Specific verifiable criterion]",
        "Typecheck passes",
        "[UI stories] Verify in browser using dev-browser skill"
      ],
      "priority": 1,
      "passes": false,
      "notes": ""
    }
  ]
}
```

---

## Story Sizing (Critical)

**Each story must be completable in ONE iteration (~10 min of AI work).**

Split large tasks:
- "Build dashboard" → schema, queries, UI, filters (4 stories)
- "Add auth" → schema, middleware, login UI, session (4 stories)
- "Fix complex bug" → investigate, fix, add test (2-3 stories)

---

## Examples

### Example 1: Bug Fix

**User:** "The pipeline page shows blank when navigating from sidebar"

**Classification:** Bug fix (something is broken)

**Question:**
```
Is this a UI bug or backend bug?
A. UI (visible in browser)
B. Backend
C. Both/Not sure
```

**User:** "A"

**Output:** Creates `scripts/ralph-moss/prds/fix-pipeline-blank-page/prd.json`

---

### Example 2: Feature

**User:** "Add a dark mode toggle to settings"

**Classification:** Feature (new functionality)

**Question:**
```
What's the scope?
A. Small (single component)
B. Medium (multiple components)
C. Large (new system)
```

**User:** "B"

**Output:** Creates `scripts/ralph-moss/prds/dark-mode-toggle/prd.json` with multiple user stories

---

### Example 3: Ambiguous

**User:** "The contact form needs validation"

**Question:**
```
Is this:
A. A bug fix (validation exists but is broken)
B. A new feature (add validation that doesn't exist)
```

**User:** "B"

**Output:** Creates feature PRD for adding validation

---

## Output Message

After creating the PRD, tell the user:

```
Created [Bug Fix / Feature] PRD at: scripts/ralph-moss/prds/[name]/

To run Ralph Moss:

  Linux/Mac:
    cd scripts/ralph-moss/prds/[name]
    ../../ralph.sh

  Windows (PowerShell):
    cd scripts\ralph-moss\prds\[name]
    ..\..\ralph.ps1

Ralph Moss will handle it from here.
```

---

## Checklist

- [ ] Classified as bug fix or feature
- [ ] Asked minimal questions (1-2 max)
- [ ] Stories are small enough for one iteration
- [ ] All stories have "Typecheck passes"
- [ ] UI stories have browser verification
- [ ] Saved to correct directory
