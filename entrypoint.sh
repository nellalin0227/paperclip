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
  done
  echo "Claude credentials written"

  # Try to refresh token by running claude as node user
  echo "Attempting Claude token refresh..."
  su -s /bin/sh node -c 'HOME=/paperclip claude --version' 2>&1 || true

  # Show updated credentials (token may have been refreshed)
  echo "Credentials after refresh attempt:"
  su -s /bin/sh node -c 'cat /paperclip/.claude/.credentials.json' 2>&1 | head -1
else
  echo "WARNING: CLAUDE_CREDENTIALS env var not set"
fi

# Switch to node user and start
exec su -s /bin/sh node -c 'HOME=/paperclip node --import ./server/node_modules/tsx/dist/loader.mjs server/dist/index.js'
