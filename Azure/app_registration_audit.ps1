<#
.SYNOPSIS
    Audit Azure AD App Registrations and disable inactive ones (>90 days no sign-in).

.DESCRIPTION
    - Lists all applications
    - Retrieves last sign-in date
    - Flags inactive apps (90+ days)
    - Optionally disables Service Principals for inactive apps
    - Exports audit report to CSV

.NOTES
    Requires Microsoft Graph PowerShell SDK and Admin consent.
#>

# === Configuration ===
$InactiveDaysThreshold = 90
$OutputCsv = "app_registration_audit.csv"
$DRY_RUN = $true  # Set to $false to actually disable inactive apps

# === Connect to Microsoft Graph ===
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -Scopes `
    "Application.Read.All", `
    "AppRoleAssignment.Read.All", `
    "Directory.Read.All", `
    "AuditLog.Read.All", `
    "User.Read.All", `
    "Application.ReadWrite.All"

# === Get all applications ===
Write-Host "Fetching App Registrations..." -ForegroundColor Cyan
$applications = Get-MgApplication -All
$today = Get-Date
$report = @()

foreach ($app in $applications) {
    $appId = $app.AppId
    $displayName = $app.DisplayName
    $createdDate = $app.CreatedDateTime
    $appObjectId = $app.Id

    # === Get Service Principal ===
    $sp = Get-MgServicePrincipal -Filter "AppId eq '$appId'" -ErrorAction SilentlyContinue

    $lastSignIn = $null
    $inactive = "Unknown"
    $disabled = "N/A"

    if ($sp) {
        # === Get last sign-in ===
        $signIn = Get-MgAuditLogSignIn -Filter "ServicePrincipalId eq '$($sp.Id)'" -Top 1 -Sort "createdDateTime desc" -ErrorAction SilentlyContinue
        $lastSignIn = $signIn.CreatedDateTime

        if ($lastSignIn) {
            $daysSince = ($today - $lastSignIn).Days
            $inactive = if ($daysSince -gt $InactiveDaysThreshold) { "Yes" } else { "No" }
        } else {
            $inactive = "Yes"
        }

        # === Disable inactive SP ===
        if ($inactive -eq "Yes") {
            if (-not $DRY_RUN) {
                try {
                    Update-MgServicePrincipal -ServicePrincipalId $sp.Id -AccountEnabled:$false
                    $disabled = "Yes"
                    Write-Host "Disabled SP for inactive app: $displayName" -ForegroundColor Yellow
                } catch {
                    $disabled = "Failed"
                    Write-Warning "Failed to disable SP: $($sp.Id)"
                }
            } else {
                $disabled = "WouldDisable (DryRun)"
                Write-Host "DRY_RUN: Would disable SP for: $displayName"
            }
        } else {
            $disabled = "No"
        }
    }

    # === Get Owners ===
    $owners = (Get-MgApplicationOwner -ApplicationId $appObjectId -ErrorAction SilentlyContinue | Select-Object -ExpandProperty UserPrincipalName) -join "; "

    # === Get Permissions ===
    $permissions = $app.RequiredResourceAccess | ForEach-Object {
        $_.ResourceAccess | ForEach-Object {
            "$($_.Type): $($_.Id)"
        }
    } -join "; "

    # === Add to Report ===
    $report += [PSCustomObject]@{
        AppDisplayName      = $displayName
        AppId               = $appId
        CreatedDate         = $createdDate
        LastSignInDate      = $lastSignIn
        InactiveOver90Days  = $inactive
        DisabledServicePrincipal = $disabled
        Owners              = $owners
        Permissions         = $permissions
    }
}

# === Export report ===
$report | Sort-Object InactiveOver90Days, AppDisplayName | Export-Csv -Path $OutputCsv -NoTypeInformation
Write-Host "`nReport saved to: $OutputCsv" -ForegroundColor Green
Write-Host "`nInactive apps (>$InactiveDaysThreshold days) have been flagged." -ForegroundColor Cyan
if ($DRY_RUN) {
    Write-Host "No service principals were actually disabled (DRY_RUN = true)." -ForegroundColor Yellow
} else {
    Write-Host "Inactive service principals have been disabled." -ForegroundColor Red
}
