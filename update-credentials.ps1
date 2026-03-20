$creds = Get-Content "$env:USERPROFILE\.claude\.credentials.json" -Raw
$creds = $creds.Trim()
Write-Host "Updating Railway CLAUDE_CREDENTIALS..."
railway variables set "CLAUDE_CREDENTIALS=$creds" --service paperclip
Write-Host "Done! Railway will redeploy automatically."
