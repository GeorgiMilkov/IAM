<#
.SYNOPSIS
    Audit and disable inactive Azure App Registrations. Notify owners and IT.

.DESCRIPTION
    - Fetches all app registrations
    - Checks sign-in activity (last 90+ days)
    - Disables inactive apps (if DRY_RUN = $false)
    - Sends email to app owner(s) + IT department

.NOTES
    Requires:
        - Microsoft Graph PowerShell SDK
        - Mail setup via SMTP or Exchange Online
#>

# === CONFIGURATION ===
$InactiveDaysThreshold = 90
$OutputCsv = "app_registration_audit.csv"
$DRY_RUN = $true                      # Set to $false to disable apps
$ITEmail = "itsecurity@contoso.com"  # Change to your IT department's distribution list
$FromEmail = "noreply@contoso.com"   # Must be a valid sender in your org
$SmtpServer = "smtp.office365.com"
$SmtpPort = 587

# === CONNECT TO MICROSOFT GRAPH ===
Connect-MgGraph -Scopes `
    "Application.Read.All", `
    "AppRoleAssignment.Read.All", `
    "Directory.Read.All", `
    "AuditLog.Read.All", `
    "User.Read.All", `
    "Application.ReadWrite.All"

# === FETCH APPLICATIONS ===
Write-Host "Fetching app registrations..." -ForegroundColor Cyan
$applications = Get-MgApplication -All
$today = Get-Date
$report = @()

foreach ($app in $applications) {
    $appId = $app.AppId
    $displayName = $app.DisplayName
    $createdDate = $app.CreatedDateTime
    $appObjectId = $app.Id
    $disabled = "N/A"
    $emailSent = "No"

    # === FETCH SERVICE PRINCIPAL ===
    $sp = Get-MgServicePrincipal -Filter "AppId eq '$appId'" -ErrorAction SilentlyContinue
    $lastSignIn = $null
    $inactive = "Unknown"

    if ($sp) {
        $signIn = Get-MgAuditLogSignIn -Filter "ServicePrincipalId eq '$($sp.Id)'" -Top 1 -Sort "createdDateTime desc" -ErrorAction SilentlyContinue
        $lastSignIn = $signIn.CreatedDateTime

        if ($lastSignIn) {
            $daysSince = ($today - $lastSignIn).Days
            $inactive = if ($daysSince -gt $InactiveDaysThreshold) { "Yes" } else { "No" }
        } else {
            $inactive = "Yes"
        }

        # === DISABLE IF INACTIVE ===
        if ($inactive -eq "Yes") {
            if (-not $DRY_RUN) {
                try {
                    Update-MgServicePrincipal -ServicePrincipalId $sp.Id -AccountEnabled:$false
                    $disabled = "Yes"
                } catch {
                    $disabled = "Failed"
                    Write-Warning "Could not disable SP: $($sp.Id)"
                }
            } else {
                $disabled = "WouldDisable (DryRun)"
            }
        } else {
            $disabled = "No"
        }
    }

    # === GET OWNERS ===
    $owners = Get-MgApplicationOwner -ApplicationId $appObjectId -ErrorAction SilentlyContinue
    $ownerEmails = ($owners | Where-Object {$_.UserPrincipalName -ne $null} | Select-Object -ExpandProperty UserPrincipalName)

    # === SEND EMAIL IF DISABLED ===
    if (($disabled -eq "Yes" -or $disabled -eq "WouldDisable (DryRun)") -and $ownerEmails.Count -gt 0) {
        $to = $ownerEmails -join ","
        $subject = "Azure App '$displayName' Disabled Due to Inactivity"
        $body = @"
Hello,

Your Azure App Registration **$displayName** (App ID: $appId) has been identified as **inactive** (no sign-in in over $InactiveDaysThreshold days) and was **$disabled**.

If this was unintentional, please contact the IT department to review or reactivate the app.

Thank you,  
IT Security Team  
"@

        try {
            Send-MailMessage -From $FromEmail -To $to -Cc $ITEmail -Subject $subject -Body $body -SmtpServer $SmtpServer -Port $SmtpPort -UseSsl
            $emailSent = "Yes"
            Write-Host "Email sent to $to (cc: $ITEmail)" -ForegroundColor Green
        } catch {
            Write-Warning "Failed to send email to $to: $_"
            $emailSent = "Failed"
        }
    }

    # === GET PERMISSIONS ===
    $permissions = $app.RequiredResourceAccess | ForEach-Object {
        $_.ResourceAccess | ForEach-Object {
            "$($_.Type): $($_.Id)"
        }
    } -join "; "

    # === ADD TO REPORT ===
    $report += [PSCustomObject]@{
        AppDisplayName         = $displayName
        AppId                  = $appId
        CreatedDate            = $createdDate
        LastSignInDate         = $lastSignIn
        InactiveOver90Days     = $inactive
        DisabledServicePrincipal = $disabled
        EmailNotificationSent  = $emailSent
        Owners                 = $ownerEmails -join "; "
        Permissions            = $permissions
    }
}

# === EXPORT AUDIT CSV ===
$report | Sort-Object InactiveOver90Days, AppDisplayName | Export-Csv -Path $OutputCsv -NoTypeInformation
Write-Host "`nAudit complete. CSV saved to: $OutputCsv" -ForegroundColor Cyan
