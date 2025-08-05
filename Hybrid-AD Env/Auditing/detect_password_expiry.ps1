<#
.SYNOPSIS
    Detects AD users whose passwords will expire soon.

.DESCRIPTION
    Lists users with passwords expiring in X days. Useful in hybrid environments to pre-warn users or IT.

.NOTES
    Requires RSAT and domain permissions.
#>

param (
    [int]$DaysThreshold = 14,
    [string]$ExportPath = "password_expiry_report.csv"
)

Import-Module ActiveDirectory

$Today = Get-Date
$Users = Get-ADUser -Filter {Enabled -eq $true -and PasswordNeverExpires -eq $false} -Properties "DisplayName", "msDS-UserPasswordExpiryTimeComputed"

$ExpiringUsers = @()

foreach ($User in $Users) {
    $ExpiryFileTime = $User.'msDS-UserPasswordExpiryTimeComputed'
    if ($ExpiryFileTime -ne $null) {
        $ExpiryDate = [datetime]::FromFileTime($ExpiryFileTime)
        $DaysLeft = ($ExpiryDate - $Today).Days

        if ($DaysLeft -le $DaysThreshold -and $DaysLeft -ge 0) {
            $ExpiringUsers += [PSCustomObject]@{
                DisplayName  = $User.DisplayName
                SamAccount   = $User.SamAccountName
                ExpiryDate   = $ExpiryDate
                DaysLeft     = $DaysLeft
            }
        }
    }
}

# Export or display
if ($ExpiringUsers.Count -gt 0) {
    $ExpiringUsers | Sort-Object DaysLeft | Export-Csv -Path $ExportPath -NoTypeInformation
    Write-Host "Found $($ExpiringUsers.Count) users with passwords expiring in the next $DaysThreshold days." -ForegroundColor Yellow
    Write-Host "Report exported to: $ExportPath"
} else {
    Write-Host "No passwords expiring within $DaysThreshold days." -ForegroundColor Green
}
