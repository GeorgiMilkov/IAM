<#
.SYNOPSIS
    Provision a new hybrid AD user and trigger Azure AD Connect sync.

.DESCRIPTION
    - Creates user in on-prem AD
    - Sets attributes
    - Assigns to groups
    - Sets password
    - Triggers sync to Azure AD

.NOTES
    Requires RSAT tools and permission to manage AD and Azure AD Connect.
#>

# === CONFIGURATION ===
$OU = "OU=Users,DC=yourdomain,DC=com"
$DefaultGroups = @("Domain Users", "HR", "AllEmployees")
$TriggerAADSync = $true

# === USER INPUT ===
$FirstName = Read-Host "First Name"
$LastName = Read-Host "Last Name"
$Department = Read-Host "Department"
$Title = Read-Host "Job Title"
$Username = ($FirstName.Substring(0,1) + $LastName).ToLower()
$UserPrincipalName = "$Username@yourdomain.com"
$DisplayName = "$FirstName $LastName"
$Email = "$Username@yourdomain.com"

# === PASSWORD GENERATION ===
Add-Type -AssemblyName System.Web
$Password = [System.Web.Security.Membership]::GeneratePassword(12,3)
$SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force

# === CREATE USER ===
Write-Host "`nCreating user $DisplayName ($UserPrincipalName)..." -ForegroundColor Cyan

New-ADUser `
    -Name $DisplayName `
    -GivenName $FirstName `
    -Surname $LastName `
    -DisplayName $DisplayName `
    -UserPrincipalName $UserPrincipalName `
    -SamAccountName $Username `
    -EmailAddress $Email `
    -Title $Title `
    -Department $Department `
    -Path $OU `
    -AccountPassword $SecurePassword `
    -ChangePasswordAtLogon $true `
    -Enabled $true

# === ADD TO GROUPS ===
foreach ($group in $DefaultGroups) {
    Add-ADGroupMember -Identity $group -Members $Username
    Write-Host "Added to group: $group"
}

# === DISPLAY PASSWORD (optional secure method for production needed) ===
Write-Host "`nTemporary password for $DisplayName is: $Password" -ForegroundColor Yellow

# === TRIGGER AAD SYNC ===
if ($TriggerAADSync) {
    Write-Host "`nTriggering Azure AD Connect sync..." -ForegroundColor Cyan
    Start-ADSyncSyncCycle -PolicyType Delta
}

Write-Host "`nProvisioning complete." -ForegroundColor Green
