#!/bin/sh
# Fix volume permissions
chown -R node:node /paperclip

# Write Claude credentials if provided via env var
if [ -n "$CLAUDE_CREDENTIALS" ]; then
  mkdir -p /paperclip/.claude
  echo "$CLAUDE_CREDENTIALS" > /paperclip/.claude/.credentials.json
  chown -R node:node /paperclip/.claude
fi

# Switch to node user and start
exec su -s /bin/sh node -c 'node --import ./server/node_modules/tsx/dist/loader.mjs server/dist/index.js'
