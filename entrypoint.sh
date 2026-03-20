#!/bin/sh
# Fix volume permissions
chown -R node:node /paperclip

# Write Claude credentials to all possible HOME locations
if [ -n "$CLAUDE_CREDENTIALS" ]; then
  for dir in /paperclip /home/node /paperclip/workspace; do
    mkdir -p "$dir/.claude"
    printf '%s' "$CLAUDE_CREDENTIALS" > "$dir/.claude/.credentials.json"
    chmod 600 "$dir/.claude/.credentials.json"
    chown -R node:node "$dir/.claude"
    echo "Claude credentials written to $dir/.claude/.credentials.json"
  done
else
  echo "WARNING: CLAUDE_CREDENTIALS env var not set"
fi

# Debug: verify credentials exist
echo "Checking credentials files:"
ls -la /paperclip/.claude/.credentials.json 2>&1 || true
ls -la /home/node/.claude/.credentials.json 2>&1 || true

# Switch to node user and start
exec su -s /bin/sh node -c 'HOME=/paperclip node --import ./server/node_modules/tsx/dist/loader.mjs server/dist/index.js'
