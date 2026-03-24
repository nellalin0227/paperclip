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

setup_api_key_helper() {
  # Configure Claude CLI to use our refresh script as apiKeyHelper.
  # Claude CLI calls this script every 5 min or on 401, so tokens stay fresh.
  for dir in /paperclip /home/node /paperclip/workspace; do
    mkdir -p "$dir/.claude"
    cat > "$dir/.claude/settings.json" <<SETTINGS
{
  "apiKeyHelper": "$REFRESH_SCRIPT"
}
SETTINGS
    chmod 644 "$dir/.claude/settings.json"
    chown -R node:node "$dir/.claude"
  done
  echo "Claude apiKeyHelper configured -> $REFRESH_SCRIPT"
}

refresh_token_now() {
  # Run our refresh script as node user
  su -s /bin/sh node -c "HOME=/paperclip CLAUDE_CREDENTIALS_FILE=/paperclip/.claude/.credentials.json $REFRESH_SCRIPT" 2>&1 || true
}

# Write Claude credentials to all possible HOME locations
if [ -n "$CLAUDE_CREDENTIALS" ]; then
  write_credentials
  echo "Claude credentials written"

  # Initial token refresh via OAuth endpoint
  echo "Attempting Claude OAuth token refresh..."
  refresh_token_now

  # Set up apiKeyHelper so Claude CLI auto-refreshes on every 401
  setup_api_key_helper

  # Background loop: proactively refresh token every 30 minutes
  REFRESH_INTERVAL="${CLAUDE_TOKEN_REFRESH_INTERVAL:-1800}"
  (
    while true; do
      sleep "$REFRESH_INTERVAL"
      echo "[claude-refresh] Periodic token refresh at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      su -s /bin/sh node -c "HOME=/paperclip CLAUDE_CREDENTIALS_FILE=/paperclip/.claude/.credentials.json $REFRESH_SCRIPT" 2>&1 || true
    done
  ) &
  echo "Claude token refresh loop started (interval: ${REFRESH_INTERVAL}s)"
else
  echo "WARNING: CLAUDE_CREDENTIALS env var not set"
fi

# Switch to node user and start
exec su -s /bin/sh node -c 'HOME=/paperclip node --import ./server/node_modules/tsx/dist/loader.mjs server/dist/index.js'
