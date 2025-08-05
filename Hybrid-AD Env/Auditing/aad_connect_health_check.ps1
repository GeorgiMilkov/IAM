<#
.SYNOPSIS
    Checks Azure AD Connect health and notifies Teams if sync is stale or failed.

.NOTES
    Run this on the Azure AD Connect server.
#>

# === Configuration ===
$WarningThresholdMins = 60
$TeamsWebhookUrl = "https://outlook.office.com/webhook/your-webhook-url-here"  # <-- Replace this

function Send-TeamsAlert($message, $color = "FF0000") {
    $payload = @{
        "@type" = "MessageCard"
        "@context" = "https://schema.org/extensions"
        "summary" = "Azure AD Connect Health Alert"
        "themeColor" = $color
        "title" = "⚠ Azure AD Connect Sync Issue"
        "sections" = @(@{
            "text" = $message
        })
    }
    Invoke-RestMethod -Uri $TeamsWebhookUrl -Method Post -ContentType 'application/json' -Body (ConvertTo-Json $payload -Depth 10)
}

try {
    $SyncStatus = Get-ADSyncConnectorRunStatus
    $Scheduler = Get-ADSyncScheduler
    $LastSyncTime = $Scheduler.LastSyncTime
    $NextSyncTime = $Scheduler.NextSyncCycleStartTime
    $SyncEnabled = $Scheduler.SyncCycleEnabled
    $SyncResult = $Scheduler.LastSyncCycleResult

    Write-Host "Azure AD Connect Health Status" -ForegroundColor Cyan
    Write-Host "--------------------------------"
    Write-Host "Last Sync Time     : $LastSyncTime"
    Write-Host "Next Sync Time     : $NextSyncTime"
    Write-Host "Sync Enabled       : $SyncEnabled"
    Write-Host "Last Sync Result   : $SyncResult"

    $MinutesSinceLastSync = ((Get-Date) - $LastSyncTime).TotalMinutes

    $AlertNeeded = $false
    $Message = ""

    if (-not $SyncEnabled) {
        $AlertNeeded = $true
        $Message += "`n❌ Sync is currently *disabled*."
    }

    if ($SyncResult -ne "Success") {
        $AlertNeeded = $true
        $Message += "`n❌ Last sync result was *$SyncResult*."
    }

    if ($MinutesSinceLastSync -gt $WarningThresholdMins) {
        $AlertNeeded = $true
        $Message += "`n❌ Last sync was $([int]$MinutesSinceLastSync) minutes ago."
    }

    if ($AlertNeeded) {
        $Message += "`n\n🔁 Please check the AAD Connect server."
        Write-Host "`nSending alert to Teams..." -ForegroundColor Yellow
        Send-TeamsAlert -message $Message
        Write-Host "✔ Alert sent to Teams." -ForegroundColor Green
    } else {
        Write-Host "`n✅ Azure AD Connect sync appears healthy." -ForegroundColor Green
    }
}
catch {
    $ErrorMsg = "❌ Azure AD Connect not found or script failed: $($_.Exception.Message)"
    Write-Error $ErrorMsg
    Send-TeamsAlert -message $ErrorMsg
}
