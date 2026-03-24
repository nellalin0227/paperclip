#!/bin/sh
# Fix volume permissions
chown -R node:node /paperclip

# Write Claude credentials from env var to all possible HOME locations
if [ -n "$CLAUDE_CREDENTIALS" ]; then
  for dir in /paperclip /home/node /paperclip/workspace; do
    mkdir -p "$dir/.claude"
    printf '%s' "$CLAUDE_CREDENTIALS" > "$dir/.claude/.credentials.json"
    chmod 600 "$dir/.claude/.credentials.json"
    # Clean up any stale settings.json from previous deploys
    rm -f "$dir/.claude/settings.json"
    chown -R node:node "$dir/.claude"
  done
  echo "Claude credentials written"
else
  echo "WARNING: CLAUDE_CREDENTIALS env var not set"
fi

# Switch to node user and start
exec su -s /bin/sh node -c 'HOME=/paperclip node --import ./server/node_modules/tsx/dist/loader.mjs server/dist/index.js'
