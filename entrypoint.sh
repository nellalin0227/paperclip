#!/bin/sh
# Fix volume permissions
chown -R node:node /paperclip

REFRESH_SCRIPT="/app/scripts/claude-token-refresh.sh"

write_credentials() {
  for dir in /paperclip /home/node /paperclip/workspace; do
    mkdir -p "$dir/.claude"
    printf '%s' "$CLAUDE_CREDENTIALS" > "$dir/.claude/.credentials.json"
    chmod 600 "$dir/.claude/.credentials.json"
    chown -R node:node "$dir/.claude"
  done
}

# Remove any stale apiKeyHelper settings that interfere with OAuth auth
cleanup_settings() {
  for dir in /paperclip /home/node /paperclip/workspace; do
    if [ -f "$dir/.claude/settings.json" ]; then
      rm -f "$dir/.claude/settings.json"
    fi
  done
}

refresh_token_now() {
  su -s /bin/sh node -c "HOME=/paperclip CLAUDE_CREDENTIALS_FILE=/paperclip/.claude/.credentials.json $REFRESH_SCRIPT" 2>&1 || true
}

# Write Claude credentials to all possible HOME locations
if [ -n "$CLAUDE_CREDENTIALS" ]; then
  write_credentials
  cleanup_settings
  echo "Claude credentials written"

  # Initial token refresh via OAuth endpoint
  echo "Attempting Claude OAuth token refresh..."
  refresh_token_now

  # Background loop: proactively refresh token every 30 minutes
  REFRESH_INTERVAL="${CLAUDE_TOKEN_REFRESH_INTERVAL:-1800}"
  (
    while true; do
      sleep "$REFRESH_INTERVAL"
      echo "[claude-refresh] Periodic token refresh at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      refresh_token_now
    done
  ) &
  echo "Claude token refresh loop started (interval: ${REFRESH_INTERVAL}s)"
else
  echo "WARNING: CLAUDE_CREDENTIALS env var not set"
fi

# Switch to node user and start
exec su -s /bin/sh node -c 'HOME=/paperclip node --import ./server/node_modules/tsx/dist/loader.mjs server/dist/index.js'
