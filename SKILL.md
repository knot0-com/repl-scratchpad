---
name: repl-scratchpad
description: >
  Use instead of chaining 3+ Bash calls, grep/cat/find pipelines, or any multi-step data
  processing. This skill should be used when the user asks to "start a scratchpad", "use the REPL",
  "scratchpad mode", "persistent Python session", or when a task involves exploration, analysis,
  or file processing that would benefit from composing operations in code rather than making
  individual tool calls. It creates a persistent Python REPL via tmux where variables survive
  across turns and only print() output enters context — a context-efficient alternative to Bash
  for data-heavy work.
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

# Step 3: Wait and read output file (each execution overwrites cleanly)
sleep 1
cat /tmp/_scratchpad_output.txt
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

## Advanced Patterns

### Map-Reduce: Fan-Out Processing

Use Python's built-in concurrency to process many files/items in parallel inside the REPL.
All processing stays in the scratchpad — only the summary enters context.

```python
import concurrent.futures, os, glob

def analyze_file(path):
    with open(path) as f:
        lines = f.readlines()
    imports = [l for l in lines if l.startswith("import") or l.startswith("from")]
    classes = [l for l in lines if l.strip().startswith("class ")]
    return {"path": path, "lines": len(lines), "imports": len(imports), "classes": len(classes)}

files = glob.glob("src/**/*.py", recursive=True)
with concurrent.futures.ThreadPoolExecutor(max_workers=10) as pool:
    results = list(pool.map(analyze_file, files))

# 200 files processed, zero context used. Only summary prints:
print(f"{len(results)} files: {sum(r['lines'] for r in results):,} lines")
big = sorted(results, key=lambda r: -r['lines'])[:5]
for r in big:
    print(f"  {r['lines']:>5} lines  {r['path']}")
```

### Recursive Drill-Down

Process data in a loop, drilling deeper on each iteration. The REPL accumulates
state without re-querying.

```python
# Turn 1: broad scan
import os, glob
all_files = glob.glob("**/*.ts", recursive=True)
by_dir = {}
for f in all_files:
    d = os.path.dirname(f)
    by_dir.setdefault(d, []).append(f)
print(f"{len(all_files)} files across {len(by_dir)} dirs")
for d in sorted(by_dir, key=lambda d: -len(by_dir[d]))[:5]:
    print(f"  {len(by_dir[d]):>3} files  {d}")
```

```python
# Turn 2: drill into the largest directory (by_dir still in memory)
target = sorted(by_dir, key=lambda d: -len(by_dir[d]))[0]
details = []
for f in by_dir[target]:
    with open(f) as fh:
        content = fh.read()
    exports = [l for l in content.split('\n') if 'export' in l]
    details.append({"file": os.path.basename(f), "lines": content.count('\n'), "exports": len(exports)})
print(f"\n{target}/ deep dive:")
for d in sorted(details, key=lambda x: -x['lines']):
    print(f"  {d['lines']:>4} lines  {d['exports']:>2} exports  {d['file']}")
```

### Spawning Subagents for Heavy Lifting

When the REPL hits limits (needs LLM reasoning, must read hundreds of files, or
requires framework-specific tools), delegate to subagents. The REPL orchestrates
the work and collects results.

#### Claude Code

Claude Code subagents are spawned via the **Agent tool** from the main conversation.
The scratchpad prepares the work, the main agent fans out subagents, and results
flow back.

Pattern: use the REPL to identify what needs processing, then ask the main agent
to spawn subagents for each item.

```python
# Step 1: REPL identifies the targets
import glob, os
files = glob.glob("src/**/*.ts", recursive=True)
large = [f for f in files if os.path.getsize(f) > 10000]
print("Files needing deep review:")
for f in large:
    print(f"  {f} ({os.path.getsize(f)//1000}KB)")
```

Then tell the main agent:

```
Spawn parallel subagents to review each of these files:
- src/agent/turn-loop.ts
- src/store/index.ts
- src/server/routes.ts
Each subagent should analyze imports, exports, and complexity.
```

Claude Code spawns subagents using the Agent tool with these key parameters:
- `subagent_type`: built-in types (`Explore`, `Plan`, `general-purpose`) or custom agents
- `run_in_background`: set `true` for parallel execution
- `model`: `haiku` for fast/cheap tasks, `sonnet`/`opus` for complex analysis
- `isolation: "worktree"` for subagents that modify files

Custom subagents are defined as markdown files in `.claude/agents/` or `~/.claude/agents/`.
See [Claude Code subagent docs](https://code.claude.com/docs/en/sub-agents) for full reference.

#### OpenAI Codex

Codex supports multi-agent workflows (experimental, enable with `/experimental`).
The main agent can spawn specialized agents in parallel and collect results.

Pattern: REPL prepares a task list, Codex fans out workers.

```python
# REPL prepares work items
tasks = [
    {"file": f, "size": os.path.getsize(f)}
    for f in glob.glob("src/**/*.py", recursive=True)
    if os.path.getsize(f) > 5000
]
# Write task manifest for Codex to process
import json
with open("/tmp/review_tasks.json", "w") as f:
    json.dump(tasks, f, indent=2)
print(f"{len(tasks)} files queued for parallel review")
```

Then tell Codex: "Read /tmp/review_tasks.json and spawn agents to review each file in parallel."

Codex can also fan out work from CSV files with `spawn_agents_on_csv` for batch processing.
See [Codex multi-agent docs](https://developers.openai.com/codex/multi-agent/) for details.

#### Gemini CLI

Gemini CLI subagents are defined as markdown files in `.gemini/agents/` with YAML frontmatter.
Enable with `"experimental": {"enableAgents": true}` in settings.json.

```yaml
# .gemini/agents/file-reviewer.md
---
name: file-reviewer
description: Reviews a single file for quality and patterns
tools:
  - read_file
  - search_code
model: gemini-2.5-pro
---
Review the specified file for code quality, patterns, and potential issues.
```

The main agent delegates to subagents automatically based on the description.
Parallel execution support is being actively developed.
See [Gemini CLI subagent docs](https://geminicli.com/docs/core/subagents/) for details.

### Combining REPL + Subagents: The Full Pattern

The most powerful pattern chains the REPL and subagents together:

1. **REPL scans** — broad sweep, identifies targets (1 turn, no context waste)
2. **Subagents analyze** — deep dive on each target in parallel (isolated context per agent)
3. **REPL synthesizes** — collect results, compute aggregates, print final summary

```python
# Step 1 (REPL): Identify what needs work
files = glob.glob("src/**/*.ts", recursive=True)
large = [(f, os.path.getsize(f)) for f in files if os.path.getsize(f) > 10000]
print(f"{len(large)} files need deep analysis")
for f, sz in sorted(large, key=lambda x: -x[1])[:10]:
    print(f"  {sz//1000:>3}KB  {f}")
```

```
# Step 2: Ask the agent to spawn parallel subagents
"Review the top 5 files from the scratchpad output using parallel subagents.
For each, report: complexity score, key exports, and potential issues."
```

```python
# Step 3 (REPL): Synthesize subagent results
# (paste or load the subagent summaries)
reviews = {
    "turn-loop.ts": {"complexity": "high", "issues": 3},
    "store/index.ts": {"complexity": "medium", "issues": 1},
    "routes.ts": {"complexity": "high", "issues": 5},
}
total_issues = sum(r["issues"] for r in reviews.values())
high_complexity = [f for f, r in reviews.items() if r["complexity"] == "high"]
print(f"{total_issues} issues across {len(reviews)} files")
print(f"High complexity: {', '.join(high_complexity)}")
```

## Commands Reference

| Action | Command |
|-|-|
| Start session | `bash <skill-path>/scripts/setup.sh` |
| Execute code | Write to `/tmp/scratchpad_cmd.py`, then `tmux send-keys -t scratchpad "_scratchpad_exec('/tmp/scratchpad_cmd.py')" Enter` |
| Read output | `sleep 1 && cat /tmp/_scratchpad_output.txt` |
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
| Not waiting for output | Use `sleep 1` before reading, or `sleep 2` for longer operations |
