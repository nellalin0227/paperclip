#!/bin/sh
# Fix volume permissions
chown -R node:node /paperclip

write_credentials() {
  for dir in /paperclip /home/node /paperclip/workspace; do
    mkdir -p "$dir/.claude"
    printf '%s' "$CLAUDE_CREDENTIALS" > "$dir/.claude/.credentials.json"
    chmod 600 "$dir/.claude/.credentials.json"
    chown -R node:node "$dir/.claude"
  done
}

refresh_claude_token() {
  # Run claude --version which triggers an OAuth token refresh if needed
  su -s /bin/sh node -c 'HOME=/paperclip claude --version' >/dev/null 2>&1 || true
  # After refresh, sync the updated credentials to all HOME locations
  if [ -f /paperclip/.claude/.credentials.json ]; then
    for dir in /home/node /paperclip/workspace; do
      mkdir -p "$dir/.claude"
      cp /paperclip/.claude/.credentials.json "$dir/.claude/.credentials.json"
      chmod 600 "$dir/.claude/.credentials.json"
      chown -R node:node "$dir/.claude"
    done
  fi
}

# Write Claude credentials to all possible HOME locations
if [ -n "$CLAUDE_CREDENTIALS" ]; then
  write_credentials
  echo "Claude credentials written"

  # Initial token refresh
  echo "Attempting Claude token refresh..."
  refresh_claude_token
  echo "Credentials after refresh attempt:"
  su -s /bin/sh node -c 'cat /paperclip/.claude/.credentials.json' 2>&1 | head -1

  # Background loop: refresh token every 30 minutes to prevent expiry
  REFRESH_INTERVAL="${CLAUDE_TOKEN_REFRESH_INTERVAL:-1800}"
  (
    while true; do
      sleep "$REFRESH_INTERVAL"
      echo "[claude-refresh] Periodic token refresh at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      refresh_claude_token
    done
  ) &
  echo "Claude token refresh loop started (interval: ${REFRESH_INTERVAL}s)"
else
  echo "WARNING: CLAUDE_CREDENTIALS env var not set"
fi

# Switch to node user and start
exec su -s /bin/sh node -c 'HOME=/paperclip node --import ./server/node_modules/tsx/dist/loader.mjs server/dist/index.js'
