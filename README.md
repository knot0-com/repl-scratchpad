# REPL Scratchpad

**Persistent Python REPL for coding agents — variables survive across turns, only `print()` enters context.**

Coding agents waste context on raw data. Every file read, API response, and query result lands in the conversation window and stays forever. By turn 30, the model has forgotten why it started.

The REPL scratchpad fixes this: the agent writes code that processes data inside a persistent Python session and only `print()`s what matters. The raw data never enters context.

## How It Works

```
1. Agent writes Python code to a temp file
2. Code executes in a persistent tmux-backed Python REPL
3. Variables survive across turns — no re-querying, no re-reading
4. Only print() output enters the conversation context
5. Everything else stays in the scratchpad's memory
```

Based on [Recursive Language Models](https://arxiv.org/abs/2512.24601) (Zhang, Kraska, Khattab 2025) — extended with cross-turn persistence.

## Why

Without a scratchpad, an agent analyzing 142 files produces 2000+ lines of raw output across 4 turns. With a scratchpad, the same analysis takes 1 turn and 8 lines of output:

```python
# Everything processed inside the REPL
files = glob.glob("src/**/*.ts", recursive=True)
by_dir = {}
for f in files:
    d = os.path.dirname(f)
    by_dir.setdefault(d, []).append(f)

# Only the summary enters context
print(f"{len(files)} TypeScript files across {len(by_dir)} directories")
for d in sorted(by_dir, key=lambda d: -len(by_dir[d]))[:5]:
    print(f"  {len(by_dir[d]):>3} files  {d}")
```

```
142 TypeScript files across 23 directories
   18 files  src/capabilities
   14 files  src/agent
   12 files  src/store
    9 files  src/server
    8 files  src/cli
```

## Prerequisites

- `tmux` — session management ([install guide](https://github.com/tmux/tmux/wiki/Installing))
- `python3` — Python 3.8+

Both are pre-installed on most Linux/macOS systems and available in WSL on Windows.

## Install as Agent Skill

Works with Claude Code, OpenAI Codex, Gemini CLI, Cursor, GitHub Copilot, OpenCode, and any tool supporting the Agent Skills open standard.

### Claude Code

```bash
git clone https://github.com/knot0-com/repl-scratchpad.git ~/.claude/skills/repl-scratchpad
```

### OpenAI Codex

```bash
git clone https://github.com/knot0-com/repl-scratchpad.git ~/.codex/skills/repl-scratchpad
```

### Gemini CLI

```bash
git clone https://github.com/knot0-com/repl-scratchpad.git ~/.gemini/skills/repl-scratchpad
```

### Universal (works with most agents)

```bash
git clone https://github.com/knot0-com/repl-scratchpad.git ~/.agent/skills/repl-scratchpad
```

### Project-level (shared with team)

```bash
git clone https://github.com/knot0-com/repl-scratchpad.git .claude/skills/repl-scratchpad
```

## Usage

Once installed, the skill activates when you ask your coding agent to use the scratchpad:

```
> /repl-scratchpad

> "Start a scratchpad session"

> "Use the REPL to analyze these files"

> "Process this data in the scratchpad"
```

Or configure your agent to use it by default for multi-step tasks (recommended).

## What's Included

```
repl-scratchpad/
├── SKILL.md            # The skill definition (Agent Skills standard)
├── scripts/
│   └── setup.sh        # Creates the persistent tmux + Python session
└── examples/
    └── codebase-analysis.md  # Complete example: analyzing a TypeScript codebase
```

## The Print Contract

The core principle that makes scratchpads work:

| Agent Type | What enters context |
|------------|-------------------|
| Tool-call agent | Every tool result, permanently |
| Coding agent (shell) | Every command output, permanently |
| **REPL scratchpad** | **Only `print()` output** |

The agent processes everything inside the REPL — file reads, API calls, data transformations — and prints only a summary. Raw data never touches the conversation.

## License

MIT

---

Built by [Knot0](https://knot0.com) — software that assembles itself.
