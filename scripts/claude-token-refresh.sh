#!/bin/sh
# claude-token-refresh.sh
# Refreshes Claude OAuth access token using the refresh_token from credentials.
# Designed to run as apiKeyHelper or standalone cron/background job.
#
# When used as apiKeyHelper (stdout mode): prints the valid access token to stdout.
# When used standalone: updates .credentials.json in-place.

set -e

CRED_FILE="${CLAUDE_CREDENTIALS_FILE:-${HOME}/.claude/.credentials.json}"
OAUTH_ENDPOINT="https://console.anthropic.com/v1/oauth/token"
CLIENT_ID="9d1c250a-e61b-44d9-88ed-5944d1962f5e"
# Buffer: refresh if token expires within this many seconds (default 10 min)
EXPIRY_BUFFER="${CLAUDE_TOKEN_EXPIRY_BUFFER:-600}"

log() {
  echo "[claude-token-refresh] $*" >&2
}

# Read a JSON field using node (available in our Docker image)
json_field() {
  node -e "
    const fs = require('fs');
    try {
      const data = JSON.parse(fs.readFileSync('$1', 'utf8'));
      const val = '$2'.split('.').reduce((o, k) => o && o[k], data);
      if (val !== undefined && val !== null) process.stdout.write(String(val));
    } catch {}
  "
}

# Check if we have a credentials file
if [ ! -f "$CRED_FILE" ]; then
  # Try to create from env var
  if [ -n "$CLAUDE_CREDENTIALS" ]; then
    mkdir -p "$(dirname "$CRED_FILE")"
    printf '%s' "$CLAUDE_CREDENTIALS" > "$CRED_FILE"
    chmod 600 "$CRED_FILE"
  else
    log "ERROR: No credentials file at $CRED_FILE and CLAUDE_CREDENTIALS not set"
    exit 1
  fi
fi

# Read current tokens
ACCESS_TOKEN=$(json_field "$CRED_FILE" "claudeAiOauth.accessToken")
REFRESH_TOKEN=$(json_field "$CRED_FILE" "claudeAiOauth.refreshToken")
EXPIRES_AT=$(json_field "$CRED_FILE" "claudeAiOauth.expiresAt")

if [ -z "$REFRESH_TOKEN" ]; then
  log "ERROR: No refresh token found in credentials"
  # Still output access token if we have one (might work)
  if [ -n "$ACCESS_TOKEN" ]; then
    echo "$ACCESS_TOKEN"
  fi
  exit 1
fi

# Check if token needs refresh
NEEDS_REFRESH=false
if [ -z "$ACCESS_TOKEN" ]; then
  NEEDS_REFRESH=true
  log "No access token, needs refresh"
elif [ -n "$EXPIRES_AT" ]; then
  # Check if expired or about to expire
  EXPIRED=$(node -e "
    const expiresAt = new Date('$EXPIRES_AT').getTime();
    const now = Date.now();
    const buffer = ${EXPIRY_BUFFER} * 1000;
    process.stdout.write(expiresAt - now < buffer ? 'true' : 'false');
  ")
  if [ "$EXPIRED" = "true" ]; then
    NEEDS_REFRESH=true
    log "Token expired or expiring soon, refreshing..."
  fi
else
  # No expiry info, try refresh to be safe
  NEEDS_REFRESH=true
  log "No expiry timestamp, refreshing to be safe"
fi

if [ "$NEEDS_REFRESH" = "true" ]; then
  log "Calling Anthropic OAuth refresh endpoint..."

  RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$OAUTH_ENDPOINT" \
    -H "Content-Type: application/json" \
    -d "{\"grant_type\":\"refresh_token\",\"refresh_token\":\"${REFRESH_TOKEN}\",\"client_id\":\"${CLIENT_ID}\"}" \
    2>/dev/null)

  HTTP_CODE=$(echo "$RESPONSE" | tail -1)
  BODY=$(echo "$RESPONSE" | sed '$d')

  if [ "$HTTP_CODE" != "200" ]; then
    log "ERROR: OAuth refresh failed (HTTP $HTTP_CODE): $BODY"
    # Output existing token as fallback
    if [ -n "$ACCESS_TOKEN" ]; then
      echo "$ACCESS_TOKEN"
    fi
    exit 1
  fi

  # Extract new tokens using node
  NEW_ACCESS_TOKEN=$(echo "$BODY" | node -e "
    let d=''; process.stdin.on('data',c=>d+=c); process.stdin.on('end',()=>{
      try { process.stdout.write(JSON.parse(d).access_token || ''); } catch {}
    });
  ")
  NEW_REFRESH_TOKEN=$(echo "$BODY" | node -e "
    let d=''; process.stdin.on('data',c=>d+=c); process.stdin.on('end',()=>{
      try { process.stdout.write(JSON.parse(d).refresh_token || ''); } catch {}
    });
  ")
  EXPIRES_IN=$(echo "$BODY" | node -e "
    let d=''; process.stdin.on('data',c=>d+=c); process.stdin.on('end',()=>{
      try { process.stdout.write(String(JSON.parse(d).expires_in || 0)); } catch {}
    });
  ")

  if [ -z "$NEW_ACCESS_TOKEN" ]; then
    log "ERROR: No access_token in refresh response"
    if [ -n "$ACCESS_TOKEN" ]; then
      echo "$ACCESS_TOKEN"
    fi
    exit 1
  fi

  # Calculate new expiry timestamp
  NEW_EXPIRES_AT=$(node -e "
    const expiresIn = parseInt('${EXPIRES_IN}', 10) || 3600;
    process.stdout.write(new Date(Date.now() + expiresIn * 1000).toISOString());
  ")

  # Update credentials file
  node -e "
    const fs = require('fs');
    const cred = JSON.parse(fs.readFileSync('${CRED_FILE}', 'utf8'));
    cred.claudeAiOauth.accessToken = '${NEW_ACCESS_TOKEN}';
    if ('${NEW_REFRESH_TOKEN}') cred.claudeAiOauth.refreshToken = '${NEW_REFRESH_TOKEN}';
    cred.claudeAiOauth.expiresAt = '${NEW_EXPIRES_AT}';
    fs.writeFileSync('${CRED_FILE}', JSON.stringify(cred, null, 2), { mode: 0o600 });
  "

  # Sync to other HOME locations
  for dir in /paperclip /home/node /paperclip/workspace; do
    TARGET="$dir/.claude/.credentials.json"
    if [ "$TARGET" != "$CRED_FILE" ] && [ -d "$dir" ]; then
      mkdir -p "$dir/.claude"
      cp "$CRED_FILE" "$TARGET" 2>/dev/null || true
      chmod 600 "$TARGET" 2>/dev/null || true
    fi
  done

  log "Token refreshed successfully (expires: $NEW_EXPIRES_AT)"
  ACCESS_TOKEN="$NEW_ACCESS_TOKEN"
else
  log "Token still valid, no refresh needed"
fi

# Output the valid access token (for apiKeyHelper mode)
echo "$ACCESS_TOKEN"
