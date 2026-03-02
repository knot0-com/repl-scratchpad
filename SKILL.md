---
name: repl-scratchpad
description: >
  This skill should be used when the user asks to "start a scratchpad", "use the REPL",
  "scratchpad mode", "persistent Python session", or when a task involves multi-step data
  processing, exploration, or analysis that would benefit from composing operations in code
  rather than making individual tool calls. It creates a persistent Python REPL via tmux
  where variables survive across turns and only print() output enters context.
version: 1.0.0
---

# REPL Scratchpad

A persistent Python REPL session that acts as a scratchpad for coding agents. Compose multi-step
operations in code. Variables persist across turns. Only `print()` output enters context.

Based on the [Recursive Language Models](https://arxiv.org/abs/2512.24601) (RLM) approach by
Zhang, Kraska, and Khattab — extended with cross-turn persistence via tmux.

## The Problem

Coding agents waste context on raw data. Every tool call result — file contents, API responses,
query results — lands in the conversation and stays there forever. By turn 30, the model has
forgotten why it started.

The REPL scratchpad fixes this: the agent writes code that processes data inside the REPL and
only `print()`s what matters. The raw data never enters the conversation.

## When to Use

- Multi-step data exploration (query -> filter -> analyze -> summarize)
- Tasks requiring 3+ sequential tool calls that could be composed in one code block
- Working with structured data (JSON, CSV, API responses, database results)
- Accumulating state across turns (storing intermediate results for later use)
- Any task where raw tool output would bloat context unnecessarily

## When NOT to Use

- Simple single-file reads or edits (use Read/Edit tools directly)
- Git operations (use Bash directly)
- Tasks with no intermediate data to process

## Prerequisites

- `tmux` installed and available in PATH
- `python3` installed and available in PATH

## Setup

Start the scratchpad session by running:

```bash
bash <skill-path>/scripts/setup.sh
```

Where `<skill-path>` is the directory where you cloned this skill (e.g., `~/.claude/skills/repl-scratchpad`).

This creates a tmux session named `scratchpad` with a persistent Python interpreter.

## Core Workflow

### Sending code to the scratchpad

1. Write the code to a temp file
2. Tell the scratchpad to execute it
3. Read only the output

```bash
# Step 1: Write code to temp file
cat > /tmp/scratchpad_cmd.py << 'PYEOF'
import json
data = json.loads(open("/path/to/file.json").read())
filtered = [x for x in data if x["status"] == "error"]
print(f"{len(filtered)} errors found")
for item in filtered[:5]:
    print(f"  - {item['name']}: {item['message']}")
PYEOF

# Step 2: Execute in persistent session
tmux send-keys -t scratchpad "_scratchpad_exec('/tmp/scratchpad_cmd.py')" Enter

# Step 3: Wait and capture output
sleep 1
tmux capture-pane -t scratchpad -p -S -30 | sed -n '1,/DONE/p' | grep -v -e DONE -e '>>>' -e '_scratchpad_exec'
```

### The Print Contract

**CRITICAL PRINCIPLE:** Only `print()` output should enter the conversation context.

- DO: `print(f"{len(results)} items found")` — summary enters context
- DO: `print(json.dumps(summary, indent=2))` — structured summary enters context
- DO NOT: return raw query results, file contents, or API responses into context
- DO NOT: use the Bash tool to `cat` large files — read them inside the scratchpad instead

The scratchpad processes everything. Context sees only what was explicitly printed.

### Variable Persistence

Variables assigned in the scratchpad persist across turns:

```python
# Turn 1
services = load_services()
print(f"Loaded {len(services)} services")

# Turn 2 — 'services' is still here
degraded = [s for s in services if s["error_rate"] > 0.05]
print(f"{len(degraded)} degraded")

# Turn 3 — both 'services' and 'degraded' are still here
for s in degraded:
    print(f"  {s['name']}: {s['error_rate']:.1%}")
```

Use this to build up working state incrementally. Store intermediate results in variables
instead of dumping them into the conversation.

### Composition Pattern

Instead of making individual tool calls:

```
BAD (3 turns, all output in context):
  Turn 1: Bash -> curl API -> full JSON response in context
  Turn 2: Bash -> jq filter -> filtered output in context
  Turn 3: Bash -> analyze -> analysis in context
```

Compose in one scratchpad execution:

```python
# GOOD (1 turn, only summary in context):
import urllib.request, json
resp = json.loads(urllib.request.urlopen("http://api/services").read())
broken = [s for s in resp if s["error_rate"] > 0.05]
deps = {s["id"]: get_deps(s["id"]) for s in broken}
print(f"{len(broken)} services degraded:")
for s in broken:
    print(f"  {s['name']} -> {', '.join(deps[s['id']])}")
```

## Commands Reference

| Action | Command |
|-|-|
| Start session | `bash <skill-path>/scripts/setup.sh` |
| Execute code | Write to `/tmp/scratchpad_cmd.py`, then `tmux send-keys -t scratchpad "_scratchpad_exec('/tmp/scratchpad_cmd.py')" Enter` |
| Read output | `sleep 1 && tmux capture-pane -t scratchpad -p -S -30 \| sed -n '1,/DONE/p' \| grep -v -e DONE -e '>>>' -e '_scratchpad_exec'` |
| Check if alive | `tmux has-session -t scratchpad 2>/dev/null && echo "alive" \|\| echo "dead"` |
| List variables | Execute `print([k for k in dir() if not k.startswith('_')])` in scratchpad |
| Reset state | `bash <skill-path>/scripts/setup.sh` (restarts clean) |
| Kill session | `tmux kill-session -t scratchpad` |

## Common Mistakes

| Mistake | Fix |
|-|-|
| Reading large files with Bash `cat` then processing | Read inside the scratchpad, print only the summary |
| Making 5 sequential Bash calls for one analysis | Compose all 5 steps in one scratchpad execution |
| Forgetting to print results | Always end with `print()` — silent code produces no context |
| Dumping raw data with `print(huge_list)` | Summarize first: `print(f"{len(data)} items, {len(errors)} errors")` |
| Starting new scratchpad when one exists | Check `tmux has-session -t scratchpad` first |
| Not waiting for output | Use `sleep 1` or check for `SCRATCHPAD_DONE` marker before reading |
