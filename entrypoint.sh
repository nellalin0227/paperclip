#!/bin/sh
# Fix volume permissions
chown -R node:node /paperclip

# Write Claude credentials if provided via env var
if [ -n "$CLAUDE_CREDENTIALS" ]; then
  mkdir -p /paperclip/.claude
  printf '%s' "$CLAUDE_CREDENTIALS" > /paperclip/.claude/.credentials.json
  chmod 600 /paperclip/.claude/.credentials.json
  chown -R node:node /paperclip/.claude
  echo "Claude credentials written to /paperclip/.claude/.credentials.json"
else
  echo "WARNING: CLAUDE_CREDENTIALS env var not set"
fi

# Switch to node user and start
exec su -s /bin/sh node -c 'HOME=/paperclip node --import ./server/node_modules/tsx/dist/loader.mjs server/dist/index.js'
