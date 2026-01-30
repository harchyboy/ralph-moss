# Engineering PRD Format for Remarkable Ralph Moss Execution

## Why This Matters

Ralph Moss spawns **fresh Claude instances per iteration** with **zero memory**. Each iteration must succeed with only:
- This PRD
- The codebase
- `progress.txt` learnings
- Archive patterns

A remarkable PRD compensates for this by being **maximally information-dense** and **surgically precise**.

---

## The Anatomy of a Remarkable PRD

### 1. The Golden Rule: One Story = One Iteration = One Victory

**Right-sized stories complete in a single context window:**
- Add one API endpoint
- Create one React component
- Write one database migration
- Fix one specific bug
- Add one integration test

**Too large (will fail):**
- "Build the dashboard" → Split into 5-8 stories
- "Add authentication" → Split into schema, middleware, UI, sessions
- "Refactor the module" → Split by file or by concern

### 2. Context Density Over Brevity

Each iteration starts blind. Provide:
- Exact file paths that will be touched
- Exact column/table names (databases lie about their schema)
- Exact function signatures to implement
- Exact patterns from similar existing code

**Bad:** "Add a filter to the contacts page"
**Remarkable:** "Add a contact_type filter dropdown to `src/pages/Contacts/List.tsx` using the existing FilterDropdown component from `src/components/ui/FilterDropdown.tsx`. The filter should query the `contact_type` column (NOT `type`) with values: 'Broker', 'Tenant', 'Landlord', 'Disposal Agent', 'Supplier', 'Internal'. See `src/pages/Properties/List.tsx:45-67` for the exact pattern."

### 3. Acceptance Criteria as Executable Specifications

Every criterion must be **objectively verifiable** by the agent:

**Weak criteria:**
- "Works correctly"
- "Handles errors gracefully"
- "Is performant"

**Remarkable criteria:**
- "Typecheck passes: `npm run typecheck` exits 0"
- "Filter shows 5 options matching contact_type enum"
- "Selecting 'Broker' reduces list from 47 to 12 contacts"
- "Browser verification: dev-browser shows filter dropdown at coordinates (250, 180)"
- "API returns 200 with shape: `{ contacts: Contact[], total: number }`"

### 4. Anti-Patterns Section (Prevent Repeated Mistakes)

Every PRD should include what NOT to do:

```markdown
## Anti-Patterns (Do NOT Do These)
- Do NOT use `type` column - the correct column is `contact_type`
- Do NOT join to `companies` table - use `accounts` table instead
- Do NOT use `company_id` - the correct FK is `account_id`
- Do NOT create new utility files - use existing `src/utils/formatters.ts`
- Do NOT add console.log statements - use existing logger from `src/lib/logger.ts`
```

### 5. Reference Anchors (Point to Existing Patterns)

```markdown
## Reference Patterns
- **Similar feature:** `src/pages/Properties/List.tsx` - filter implementation
- **API pattern:** `api/contacts.ts` - query builder pattern
- **Component pattern:** `src/components/contacts/ContactCard.tsx` - card layout
- **Test pattern:** `src/api/__tests__/contacts.test.ts` - API test structure
```

### 6. Dependency Graph (Explicit Ordering)

```markdown
## Story Dependencies
US-001 (schema) → US-002 (API) → US-003 (UI) → US-004 (tests)
                              ↘ US-005 (notifications)

Stories can run in parallel only if no arrow connects them.
```

---

## The Remarkable PRD Template

```json
{
  "project": "UNION Spaces Core",
  "branchName": "ralph-moss/[feature-name-kebab-case]",
  "description": "[2-3 sentences: What we're building and WHY it matters]",

  "context": {
    "businessGoal": "[What user/business problem does this solve?]",
    "technicalContext": "[Current state of the system relevant to this feature]",
    "relatedArchives": ["archive/2026-01-14-similar-feature/"],
    "keyFiles": [
      "src/pages/Contacts/List.tsx - main file to modify",
      "api/contacts.ts - API to extend",
      "src/types/contact.ts - types to update"
    ]
  },

  "antiPatterns": [
    "Do NOT use X - use Y instead",
    "Do NOT assume Z - verify with W"
  ],

  "referencePatterns": [
    {
      "description": "Filter dropdown pattern",
      "file": "src/pages/Properties/List.tsx",
      "lines": "45-67"
    }
  ],

  "userStories": [
    {
      "id": "US-001",
      "title": "[Verb] [Specific Thing] [Location]",
      "description": "As a [specific user], I want [specific capability] so that [specific benefit]",
      "technicalDetails": {
        "filesAffected": ["path/to/file.ts"],
        "approach": "Step-by-step implementation approach",
        "edgeCases": ["Edge case 1 and how to handle it"]
      },
      "acceptanceCriteria": [
        "VERIFY: [Specific observable outcome]",
        "TYPECHECK: npm run typecheck exits 0",
        "LINT: npm run lint exits 0",
        "BROWSER: [If UI] Use dev-browser to verify [specific element]"
      ],
      "antiPatterns": ["Story-specific things to avoid"],
      "priority": 1,
      "dependsOn": [],
      "passes": false,
      "notes": ""
    }
  ],

  "successVision": "[What does the completed feature look like? How will users interact with it?]",

  "testingStrategy": {
    "unit": "Which functions need unit tests",
    "integration": "Which flows need integration tests",
    "e2e": "Which user journeys need E2E tests",
    "manual": "What to verify manually in browser"
  }
}
```

---

## The 10 Principles of Remarkable PRDs

### 1. **Assume Amnesia**
Every iteration starts fresh. Write as if explaining to a new developer on their first day.

### 2. **Name Everything Explicitly**
Column names, table names, file paths, function names, variable names. Never say "the field" - say "`contact_type` column in `contacts` table".

### 3. **Show, Don't Tell**
Instead of "follow the existing pattern", say "follow the pattern in `src/pages/Properties/List.tsx:45-67`".

### 4. **Make Criteria Binary**
Every acceptance criterion should have a yes/no answer. "Is performant" is not binary. "Query executes in <100ms" is binary.

### 5. **Anticipate Gotchas**
If you know the schema is weird, say so. If there's a common mistake, document it. The anti-patterns section prevents repeated failures.

### 6. **Order by Risk**
Put the riskiest/most uncertain stories first. If they fail, fail fast. Don't build a UI on a broken API.

### 7. **Size Stories Ruthlessly**
When in doubt, split. A story that's "probably" one iteration will "definitely" be two. Err on the side of smaller.

### 8. **Include the Why**
"Add contact_type filter" tells WHAT. "Add contact_type filter so users can quickly find their broker contacts without scrolling through 200+ records" tells WHY. The why helps with edge case decisions.

### 9. **Reference the Archive**
If a similar feature was built before, reference it. "See archive/2026-01-14-property-filters/ for similar implementation and lessons learned."

### 10. **Write for Verification**
Every story should end with the agent being able to PROVE it worked. Browser screenshots, test outputs, API responses. No story is complete until verification is documented.

---

## Example: A Remarkable Story

```json
{
  "id": "US-002",
  "title": "Add contact_type filter dropdown to Contacts List",
  "description": "As a property manager, I want to filter contacts by type so that I can quickly find brokers when I need to discuss a deal",

  "technicalDetails": {
    "filesAffected": [
      "src/pages/Contacts/List.tsx",
      "src/api/contacts.ts"
    ],
    "approach": "1. Add FilterDropdown component import. 2. Add contact_type to useContacts params. 3. Add dropdown to filters section. 4. Connect onChange to setSearchParams",
    "edgeCases": [
      "Empty selection should show all contacts (don't filter)",
      "Multiple selections should use OR logic"
    ]
  },

  "acceptanceCriteria": [
    "VERIFY: FilterDropdown renders with 6 options: All, Broker, Tenant, Landlord, Disposal Agent, Supplier, Internal",
    "VERIFY: Selecting 'Broker' updates URL to ?contact_type=Broker",
    "VERIFY: Page refreshes with filter applied (URL persistence)",
    "TYPECHECK: npm run typecheck exits 0",
    "LINT: npm run lint exits 0",
    "BROWSER: Use dev-browser skill to verify dropdown is visible and clickable"
  ],

  "antiPatterns": [
    "Do NOT query the 'type' column - use 'contact_type'",
    "Do NOT create a custom dropdown - use existing FilterDropdown from src/components/ui/"
  ],

  "priority": 2,
  "dependsOn": ["US-001"],
  "passes": false,
  "notes": ""
}
```

---

## The Progress File: Ralph's Memory

`progress.txt` is the only persistent memory between iterations. Make it count:

```markdown
## Iteration 3 - US-002: Add contact_type filter

### What Was Done
- Added FilterDropdown to src/pages/Contacts/List.tsx
- Updated useContacts hook to accept contact_type param
- Connected filter to URL search params

### Codebase Patterns Discovered
- FilterDropdown requires options array with {value, label} shape
- useSearchParams hook handles all URL state persistence
- contact_type column uses string enum, not numeric

### What Almost Went Wrong
- Initially used 'type' column - got 500 error
- Fixed by using 'contact_type' column per api/contacts.ts pattern

### Verification
- Screenshot: filter-dropdown-visible.png
- Typecheck: PASS
- Lint: PASS

### Files Modified
- src/pages/Contacts/List.tsx (added filter)
- src/api/contacts.ts (added param handling)
```

---

## Quick Reference: Story Sizing Examples

| Too Big | Right-Sized Stories |
|---------|---------------------|
| Build user dashboard | 1. Add dashboard route and empty page<br>2. Add summary stats cards<br>3. Add recent activity list<br>4. Add quick actions panel |
| Add authentication | 1. Create auth schema/migration<br>2. Add login API endpoint<br>3. Add login UI form<br>4. Add auth context provider<br>5. Add protected route wrapper |
| Refactor contacts module | 1. Extract ContactCard component<br>2. Extract ContactFilters component<br>3. Add unit tests for extracted components |
| Fix all form validation | 1. Fix email validation on contact form<br>2. Fix phone validation on contact form<br>3. Fix required fields on company form |

---

## The Checklist Before Submitting a PRD

- [ ] Every story can complete in ONE iteration
- [ ] Every file path is exact and verified to exist
- [ ] Every column/table name is verified against actual schema
- [ ] Every acceptance criterion is binary (yes/no answer)
- [ ] Anti-patterns section documents known gotchas
- [ ] Reference patterns point to exact line numbers
- [ ] Dependencies between stories are explicit
- [ ] Similar archives are referenced if they exist
- [ ] Success vision describes the end state clearly
- [ ] Testing strategy covers unit, integration, and browser verification

---

## Final Thought

A remarkable PRD treats each Ralph Moss iteration like a **precision instrument**. The PRD is the blueprint, the instructions, and the memory all in one. When the PRD is remarkable, Ralph Moss becomes remarkable.

**Write PRDs as if the developer has amnesia, infinite capability, but zero context.**

That's the secret to remarkable autonomous engineering.
