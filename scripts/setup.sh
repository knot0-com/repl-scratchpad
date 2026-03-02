#!/usr/bin/env bash
# Input: tmux, python3
# Output: persistent Python REPL session in tmux
# Position: setup script for repl-scratchpad skill

SESSION="scratchpad"
BOOTSTRAP="/tmp/_scratchpad_bootstrap.py"

# Kill existing session if present
tmux kill-session -t "$SESSION" 2>/dev/null

# Write bootstrap script to file (avoids noisy interactive echo)
cat > "$BOOTSTRAP" << 'PYEOF'
import sys, json, io

def _scratchpad_exec(code_file):
    """Execute code from file, capture only print() output."""
    _old = sys.stdout
    _buf = io.StringIO()
    sys.stdout = _buf
    try:
        with open(code_file) as f:
            exec(compile(f.read(), code_file, 'exec'), globals())
        sys.stdout = _old
        output = _buf.getvalue()
        if output:
            print(output, end='')
        else:
            print('[no output]')
    except Exception as e:
        sys.stdout = _old
        print(f'ERROR: {type(e).__name__}: {e}')
    print('---DONE---')
PYEOF

# Start Python with bootstrap loaded via -i (interactive after script)
tmux new-session -d -s "$SESSION" -x 200 -y 50 "python3 -u -i $BOOTSTRAP 2>/dev/null"
sleep 0.5

echo "scratchpad session started"
