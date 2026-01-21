# Ralph Moss

An autonomous AI agent loop for Claude Code. Ralph Moss runs Claude repeatedly until all PRD tasks are complete, with fresh context per iteration.

Adapted from the [original Ralph pattern](https://github.com/snarktank/ralph) for use with Claude Code.

## Features

- **Autonomous execution** - Runs Claude Code in a loop until all tasks complete
- **Fresh context per iteration** - Each iteration starts clean (no context rot)
- **Memory via git** - Progress persists through git history and `progress.txt`
- **PRD-driven** - Structured JSON format for task management
- **Quality gates** - Automated typecheck, lint, and test validation
- **Agent-to-agent review** - Optional second Claude instance reviews code
- **Cost tracking** - Monitor token usage and costs per iteration
- **Archive search** - Learn from past PRDs to avoid repeating mistakes

## Security Warning

**Ralph Moss uses `--dangerously-skip-permissions` which grants Claude full control over your terminal.**

This means Claude can execute any shell command, read/write files, and make network requests.

**Recommendations:**
1. Run in a sandboxed environment (Docker, VM, or dedicated dev machine)
2. Never run on production systems
3. Review commits before pushing
4. Use `--max-cost` to prevent runaway spending
5. Monitor execution for unexpected behavior

## Quick Start

### 1. Install into your project

```bash
# Clone into your project
git clone https://github.com/harchyboy/ralph-moss.git .ralph-moss

# Or add as a submodule
git submodule add https://github.com/harchyboy/ralph-moss.git .ralph-moss
```

### 2. Copy skills to your project

```bash
mkdir -p .claude/skills
cp -r .ralph-moss/skills/* .claude/skills/
```

### 3. Create a PRD

Use the `/prd` skill in Claude Code:

```
/prd Add a dark mode toggle to settings
```

Or create manually in `scripts/ralph-moss/prds/[feature-name]/prd.json`

### 4. Run Ralph Moss

```bash
cd scripts/ralph-moss/prds/[feature-name]
../../scripts/ralph.sh
```

Or with options:
```bash
../../scripts/ralph.sh 20 --max-plan --quality-gate
```

## Directory Structure

```
ralph-moss/
├── scripts/           # Core execution scripts
│   ├── ralph.sh       # Main loop script (Linux/Mac)
│   ├── ralph.ps1      # Main loop script (Windows)
│   ├── preflight.sh   # PRD validation
│   ├── quality-gate.sh # Automated quality checks
│   ├── review-agent.sh # Agent-to-agent review
│   └── prompt-claude.md # Instructions for each iteration
├── skills/            # Claude Code skills
│   ├── prd/           # PRD generator
│   ├── ralph-moss/    # PRD-to-JSON converter
│   ├── bugfix/        # Bug fix PRD creator
│   └── task/          # Smart task router
├── examples/          # Example PRDs
└── docs/              # Documentation
```

## Usage

### Command Line Options

```bash
./ralph.sh [max_iterations] [options]
```

| Option | Description |
|--------|-------------|
| `--max-plan` | Anthropic Max plan mode (track iterations, not costs) |
| `--max-cost <n>` | Stop if cost exceeds $n |
| `--quality-gate` | Run typecheck/lint/tests after each iteration |
| `--review` | Enable agent-to-agent code review |
| `--strict` | Fail on lint warnings |
| `--skip-tests` | Skip tests in quality gate |
| `--skip-preflight` | Skip PRD validation |
| `--no-cost` | Disable cost tracking |

### Examples

```bash
# Basic run with 10 iterations (default)
./ralph.sh

# Max plan users (flat subscription)
./ralph.sh --max-plan

# With full quality pipeline
./ralph.sh 20 --max-plan --quality-gate --review

# API users with $5 budget
./ralph.sh 15 --max-cost 5.00
```

## PRD Format

```json
{
  "project": "MyProject",
  "branchName": "ralph-moss/feature-name",
  "description": "Feature description",
  "userStories": [
    {
      "id": "US-001",
      "title": "Story title",
      "description": "As a [user], I want [feature] so that [benefit]",
      "acceptanceCriteria": [
        "Specific criterion 1",
        "Specific criterion 2",
        "Typecheck passes"
      ],
      "priority": 1,
      "passes": false,
      "notes": ""
    }
  ]
}
```

### Story Sizing (Critical)

Each story must be completable in ONE iteration (~10 min of AI work).

**Right-sized:**
- Add a database column and migration
- Add a UI component to an existing page
- Update a server action with new logic

**Too big (split these):**
- "Build the entire dashboard"
- "Add authentication"
- "Refactor the API"

## Skills

### /prd - PRD Generator

Creates detailed PRDs with user stories. Asks clarifying questions, then outputs structured requirements.

```
/prd Add user notifications with email and in-app alerts
```

### /bugfix - Bug Fix PRD

Creates focused bug fix PRDs with verifiable acceptance criteria.

```
/bugfix The contact page crashes when company is null
```

### /task - Smart Router

Automatically classifies as bug or feature, then creates the appropriate PRD.

```
/task Add loading spinner to the dashboard
```

### /ralph-moss - PRD Converter

Converts existing markdown PRDs to Ralph Moss JSON format.

```
/ralph-moss Convert tasks/prd-notifications.md to JSON
```

## How It Works

1. **Preflight** - Validates PRD (file paths, JSON schema)
2. **Load PRD** - Read `prd.json` and `progress.txt`
3. **Pick story** - Select highest priority story where `passes: false`
4. **Implement** - Claude implements the single story
5. **Quality gate** - Run typecheck, lint, tests
6. **Commit** - If checks pass, commit and push
7. **Update PRD** - Mark story as `passes: true`
8. **Repeat** - Loop until all stories pass or max iterations reached

### Memory Between Iterations

Each iteration spawns a **new Claude instance** with clean context. Memory persists via:
- Git history (commits from previous iterations)
- `progress.txt` (learnings and patterns discovered)
- `prd.json` (which stories are done)

## Integration with Your Project

### Option 1: Copy Scripts

Copy the `scripts/` folder and `skills/` to your project:

```bash
cp -r ralph-moss/scripts ./scripts/ralph-moss
cp -r ralph-moss/skills .claude/skills/
```

### Option 2: Git Submodule

```bash
git submodule add https://github.com/harchyboy/ralph-moss.git .ralph-moss
ln -s .ralph-moss/scripts scripts/ralph-moss
cp -r .ralph-moss/skills .claude/skills/
```

### Customize for Your Project

1. Edit `scripts/ralph-moss/prompt-claude.md` to add project-specific patterns
2. Modify `scripts/ralph-moss/quality-gate.sh` for your test commands
3. Update skills to reference your project structure

## Contributing

Contributions welcome! Please open an issue or PR.

## Credits

- Original [Ralph pattern](https://github.com/snarktank/ralph) by [snarktank](https://github.com/snarktank)
- [Geoffrey Huntley's Ralph Article](https://ghuntley.com/ralph/)

## License

MIT
