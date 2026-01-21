---
name: bugfix
description: "Create a bug fix PRD for Ralph Moss autonomous execution. Use when you have a bug to fix and want Ralph Moss to handle it autonomously. Triggers on: fix bug, bugfix, create bug fix, bug fix prd."
---

# Bug Fix PRD Generator

Creates a focused bug fix PRD in Ralph Moss JSON format for autonomous execution with high confidence.

---

## The Job

1. Receive bug description from user
2. Ask 2-3 clarifying questions (quick, focused)
3. Generate prd.json with verifiable acceptance criteria
4. Save to `scripts/ralph-moss/prds/fix-[bug-name]/`

**Important:** Do NOT start fixing. Just create the bug fix PRD.

---

## Step 1: Quick Clarifying Questions

Ask only what's needed to verify the fix:

```
1. How do you reproduce this bug?
   A. [Specific steps if known]
   B. I'm not sure - needs investigation first

2. Is this a UI bug or backend bug?
   A. UI (visible in browser)
   B. Backend (API/data/logic)
   C. Both

3. Should this include a regression test?
   A. Yes, add a test to prevent recurrence
   B. No, just fix it
```

---

## Step 2: Generate Bug Fix PRD

### Directory Structure

Create:
```
scripts/ralph-moss/prds/fix-[bug-name-kebab-case]/
├── prd.json       # Bug fix task
└── progress.txt   # Empty progress log
```

### prd.json Format

```json
{
  "project": "[Your Project Name]",
  "branchName": "ralph-moss/fix-[bug-name-kebab-case]",
  "description": "Bug fix: [Short description of the bug]",
  "userStories": [
    {
      "id": "BUG-001",
      "title": "Fix: [Bug description]",
      "description": "[What's broken, where it happens, and impact]",
      "acceptanceCriteria": [
        "[Reproduction scenario now works without error]",
        "[Related happy path still works - no regression]",
        "[Add test to prevent recurrence - if requested]",
        "Typecheck passes",
        "All existing tests pass",
        "[UI bugs only] Verify in browser using dev-browser skill"
      ],
      "priority": 1,
      "passes": false,
      "notes": ""
    }
  ]
}
```

---

## Acceptance Criteria Rules

### Always Include:
- **Reproduction scenario works**: The exact case that was broken now works
- **No regression**: Related functionality still works
- **Typecheck passes**: Always required
- **All tests pass**: Always required

### Conditionally Include:
- **Add regression test**: If user selected "Yes" to test question
- **Browser verification**: If UI bug (user selected A or C for bug type)

### Make Criteria Specific:

**Good (verifiable):**
- "Navigate to PropertyDetails with no landlord assigned - page loads without error"
- "PropertyDetails with landlord assigned still displays landlord name"
- "Add test: PropertyDetails.test.tsx covers null landlordId case"

**Bad (vague):**
- "Bug is fixed"
- "Works correctly"
- "Handles the edge case"

---

## Example

**User Input:**
```
/bugfix PropertyDetails crashes when landlord is null
```

**Questions:**
```
1. How do you reproduce this?
   A. Go to a property with no landlord assigned
   B. Needs investigation

2. Bug type?
   A. UI (visible in browser)
   B. Backend
   C. Both

3. Add regression test?
   A. Yes
   B. No
```

**User Response:** "1A, 2A, 3A"

**Output prd.json:**
```json
{
  "project": "MyProject",
  "branchName": "ralph-moss/fix-property-details-null-landlord",
  "description": "Bug fix: PropertyDetails crashes when landlord is null",
  "userStories": [
    {
      "id": "BUG-001",
      "title": "Fix: PropertyDetails crash on null landlord",
      "description": "PropertyDetails component throws null pointer error when a property has no landlord contact assigned. This breaks the property details page entirely.",
      "acceptanceCriteria": [
        "Navigate to a property with no landlord assigned - page loads without error",
        "Navigate to a property WITH landlord - landlord name displays correctly",
        "Add test: PropertyDetails.test.tsx covers landlordId=null case",
        "Typecheck passes",
        "All existing tests pass",
        "Verify in browser using dev-browser skill"
      ],
      "priority": 1,
      "passes": false,
      "notes": ""
    }
  ]
}
```

**Output progress.txt:**
```markdown
# Ralph Moss Progress Log
Started: [date]
Feature: ralph-moss/fix-property-details-null-landlord

## Codebase Patterns
(Patterns discovered during implementation)

---
```

---

## Running the Fix

After creating the PRD, tell the user:

```
Bug fix PRD created at: scripts/ralph-moss/prds/fix-[name]/

To run Ralph Moss:

  Linux/Mac:
    cd scripts/ralph-moss/prds/fix-[name]
    ../../ralph.sh

  Windows (PowerShell):
    cd scripts\ralph-moss\prds\fix-[name]
    ..\..\ralph.ps1

Ralph Moss will:
1. Investigate and fix the bug
2. Verify all acceptance criteria pass
3. Commit the fix automatically
```

---

## Checklist Before Saving

- [ ] Asked clarifying questions
- [ ] Bug name is kebab-case
- [ ] Acceptance criteria include reproduction scenario
- [ ] Acceptance criteria include regression check
- [ ] Typecheck + tests pass included
- [ ] Browser verification included (if UI bug)
- [ ] Regression test included (if requested)
- [ ] Saved to scripts/ralph-moss/prds/fix-[name]/
