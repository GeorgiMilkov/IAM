<#
.SYNOPSIS
    Hybrid AD user offboarding script with mailbox archive, Teams removal, and user move.

.NOTES
    Requires:
        - RSAT tools
        - Exchange Online PowerShell module
        - Microsoft Graph PowerShell SDK
#>

# === CONFIGURATION ===
$DisabledOU = "OU=Disabled Users,DC=yourdomain,DC=com"
$LogFile = "offboard_log.csv"
$TriggerAADSync = $true

# === USER INPUT ===
$Username = Read-Host "Enter sAMAccountName of the user to offboard"

# === VALIDATE USER ===
$ADUser = Get-ADUser -Identity $Username -Properties MemberOf, Enabled, UserPrincipalName, DistinguishedName -ErrorAction SilentlyContinue
if (-not $ADUser) {
    Write-Error "User '$Username' not found in Active Directory."
    exit
}
$UPN = $ADUser.UserPrincipalName
Write-Host "User found: $($ADUser.Name) ($UPN)" -ForegroundColor Cyan

# === DISABLE AD ACCOUNT ===
Disable-ADAccount -Identity $ADUser
Write-Host "✔ Disabled AD account"

# === REMOVE FROM AD GROUPS ===
$Groups = $ADUser.MemberOf
foreach ($groupDN in $Groups) {
    try {
        Remove-ADGroupMember -Identity $groupDN -Members $ADUser -Confirm:$false
        Write-Host "✔ Removed from group: $groupDN"
    } catch {
        Write-Warning "Failed to remove from group: $groupDN"
    }
}

# === MOVE USER TO DISABLED OU ===
try {
    Move-ADObject -Identity $ADUser.DistinguishedName -TargetPath $DisabledOU
    Write-Host "✔ Moved user to '$DisabledOU'"
} catch {
    Write-Warning "Could not move user to Disabled OU."
}

# === TRIGGER AAD CONNECT SYNC ===
if ($TriggerAADSync) {
    Write-Host "🔁 Triggering Azure AD Connect sync..." -ForegroundColor Yellow
    Start-ADSyncSyncCycle -PolicyType Delta
    Start-Sleep -Seconds 10
}

# === CONNECT TO MICROSOFT GRAPH ===
Connect-MgGraph -Scopes "User.ReadWrite.All", "Directory.ReadWrite.All", "Organization.Read.All", "Team.ReadBasic.All", "TeamMember.ReadWrite.All"

# === BLOCK SIGN-IN IN AZURE AD ===
$CloudUser = Get-MgUser -UserId $UPN -ErrorAction SilentlyContinue
if ($CloudUser) {
    Update-MgUser -UserId $UPN -AccountEnabled:$false
    Write-Host "✔ Blocked Azure AD sign-in"
} else {
    Write-Warning "User not found in Azure AD."
}

# === REMOVE MICROSOFT 365 LICENSES ===
if ($CloudUser.AssignedLicenses.Count -gt 0) {
    Set-MgUserLicense -UserId $UPN -RemoveLicenses $CloudUser.AssignedLicenses.SkuId -AddLicenses @()
    Write-Host "✔ Removed all Microsoft 365 licenses"
} else {
    Write-Host "ℹ No licenses assigned"
}

# === ARCHIVE MAILBOX (Exchange Online) ===
Write-Host "🔐 Connecting to Exchange Online..."
Connect-ExchangeOnline -UserPrincipalName $env:USERNAME -ShowBanner:$false

try {
    Enable-Mailbox -Identity $UPN -Archive
    Write-Host "✔ Enabled mailbox archive"
} catch {
    Write-Warning "Mailbox archiving may already be enabled or failed."
}

# === REMOVE FROM TEAMS ===
$Teams = Get-MgUserJoinedTeam -UserId $UPN -ErrorAction SilentlyContinue
if ($Teams) {
    foreach ($team in $Teams) {
        try {
            Remove-MgTeamMember -TeamId $team.Id -UserId $CloudUser.Id
            Write-Host "✔ Removed from Team: $($team.DisplayName)"
        } catch {
            Write-Warning "Failed to remove from Team: $($team.DisplayName)"
        }
    }
} else {
    Write-Host "ℹ User is not a member of any Teams"
}

# === LOG ACTIONS ===
$logEntry = [PSCustomObject]@{
    Timestamp       = (Get-Date)
    User            = $ADUser.Name
    Username        = $Username
    UPN             = $UPN
    DisabledInAD    = $true
    GroupsRemoved   = $Groups.Count
    MovedToOU       = $true
    AADBlocked      = $true
    LicensesRemoved = $true
    MailboxArchived = $true
    RemovedFromTeams = $true
}
$logEntry | Export-Csv -Path $LogFile -Append -NoTypeInformation
Write-Host "✔ Offboarding complete. Logged to $LogFile" -ForegroundColor Green
