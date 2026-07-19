#!/usr/bin/env bash
# One-time Mac install: exec bits, PATH line in ~/.zshrc, seed the user
# config. Safe to re-run.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$(cd "$SCRIPT_DIR/../bin" && pwd)"

chmod +x "$BIN_DIR/pull.pc" "$BIN_DIR/push.pc" "$BIN_DIR/pull.pc.claude" "$BIN_DIR/push.pc.claude"

RC="$HOME/.zshrc"
if ! grep -Fq '# machine-sync' "$RC" 2>/dev/null; then
    printf '\nexport PATH="%s:$PATH"  # machine-sync\n' "$BIN_DIR" >> "$RC"
    echo "Added $BIN_DIR to PATH in $RC"
else
    echo "PATH line already in $RC (marker '# machine-sync'), left untouched."
    echo 'If the repo moved, update that line by hand.'
fi

CONFIG="$HOME/.machine-sync.env"
if [ ! -f "$CONFIG" ]; then
    cp "$SCRIPT_DIR/../config/machine-sync.env.example" "$CONFIG"
    echo "Seeded config at $CONFIG, edit it before first use."
else
    echo "Config already present at $CONFIG, left untouched."
fi

echo 'Open a new terminal (or: source ~/.zshrc) and test: pull.pc --help'
