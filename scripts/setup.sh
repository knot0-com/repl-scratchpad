#!/usr/bin/env bash
# Input: tmux, python3
# Output: persistent Python REPL session in tmux
# Position: setup script for repl-scratchpad skill

SESSION="scratchpad"
BOOTSTRAP="/tmp/_scratchpad_bootstrap.py"
OUTPUT_FILE="/tmp/_scratchpad_output.txt"

# Kill existing session if present
tmux kill-session -t "$SESSION" 2>/dev/null

# Clean output file
> "$OUTPUT_FILE"

# Write bootstrap script to file (avoids noisy interactive echo)
cat > "$BOOTSTRAP" << 'PYEOF'
import sys, io

_OUTPUT_FILE = "/tmp/_scratchpad_output.txt"

def _scratchpad_exec(code_file):
    """Execute code from file, capture only print() output to file."""
    _old = sys.stdout
    _buf = io.StringIO()
    sys.stdout = _buf
    try:
        with open(code_file) as f:
            exec(compile(f.read(), code_file, 'exec'), globals())
        sys.stdout = _old
        output = _buf.getvalue()
        if not output:
            output = '[no output]\n'
    except Exception as e:
        sys.stdout = _old
        output = _buf.getvalue() + f'ERROR: {type(e).__name__}: {e}\n'
    # Write output to file for clean retrieval
    with open(_OUTPUT_FILE, 'w') as f:
        f.write(output)
    # Also print to terminal for visual feedback
    print(output, end='')
    print('---DONE---')
PYEOF

# Start Python with bootstrap loaded via -i (interactive after script)
tmux new-session -d -s "$SESSION" -x 200 -y 50 "python3 -u -i $BOOTSTRAP 2>/dev/null"
sleep 0.5

echo "scratchpad session started"
