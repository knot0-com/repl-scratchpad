# Example: Codebase Analysis

This example shows how a coding agent uses the REPL scratchpad to analyze a codebase
without polluting context with raw file listings.

## Without scratchpad (bad)

```
Turn 1: Bash -> find . -name "*.ts" -> 847 lines of file paths in context
Turn 2: Bash -> wc -l for each file -> 847 more lines in context
Turn 3: Bash -> grep for patterns -> hundreds more lines in context
Turn 4: Agent tries to summarize from 2000+ lines of raw output
```

4 turns. Context bloated with raw data. Agent loses track of the goal.

## With scratchpad (good)

```python
# Turn 1: Everything happens inside the REPL
import os, glob

files = glob.glob("src/**/*.ts", recursive=True)
by_dir = {}
for f in files:
    d = os.path.dirname(f)
    by_dir.setdefault(d, []).append(f)

total_lines = 0
big_files = []
for f in files:
    lines = len(open(f).readlines())
    total_lines += lines
    if lines > 300:
        big_files.append((f, lines))

print(f"{len(files)} TypeScript files across {len(by_dir)} directories")
print(f"{total_lines:,} total lines")
print(f"\nLargest files:")
for f, lines in sorted(big_files, key=lambda x: -x[1])[:10]:
    print(f"  {lines:>5} lines  {f}")
print(f"\nDirectory breakdown:")
for d in sorted(by_dir, key=lambda d: -len(by_dir[d]))[:10]:
    print(f"  {len(by_dir[d]):>3} files  {d}")
```

Output (what enters context):

```
142 TypeScript files across 23 directories
28,451 total lines

Largest files:
  1,203 lines  src/agent/turn-loop.ts
    847 lines  src/store/index.ts
    632 lines  src/server/routes.ts

Directory breakdown:
   18 files  src/capabilities
   14 files  src/agent
   12 files  src/store
```

1 turn. 8 lines of output. Agent has full picture. Raw file paths never entered context.

```python
# Turn 2: 'files', 'by_dir', 'big_files' are all still available
# Drill into the largest file
with open(big_files[0][0]) as f:
    content = f.read()

imports = [l.strip() for l in content.split('\n') if l.startswith('import')]
exports = [l.strip() for l in content.split('\n') if 'export' in l and ('function' in l or 'class' in l)]

print(f"turn-loop.ts analysis:")
print(f"  {len(imports)} imports, {len(exports)} exports")
print(f"\nExported symbols:")
for e in exports:
    print(f"  {e[:80]}")
```

Variables from Turn 1 persist. No re-reading needed.
