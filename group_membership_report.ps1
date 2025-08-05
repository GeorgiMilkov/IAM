<#
.SYNOPSIS
    Combines group membership reports from On-Prem AD and Azure AD into one CSV.

.PARAMETER GroupDisplayName
    Optional. If specified, filters to this group name only (for both sources).

.PARAMETER OutputFile
    Default: group_membership_report_combined.csv

.NOTES
    Requires:
    - RSAT / AD module
    - Microsoft.Graph module and connection to Graph API
#>

param (
    [string]$GroupDisplayName,
    [string]$OutputFile = "group_membership_report_combined.csv"
)

# ====== ON-PREM AD PART ======
Import-Module ActiveDirectory -ErrorAction SilentlyContinue
$CombinedResults = @()

function Get-OnPremGroupMembersRecursive {
    param (
        [string]$GroupDN,
        [string]$GroupName,
        [int]$Depth = 0
    )

    $Members = Get-ADGroupMember -Identity $GroupDN -ErrorAction SilentlyContinue

    foreach ($Member in $Members) {
        if ($Member.objectClass -eq "user") {
            $User = Get-ADUser $Member.SamAccountName -Properties mail
            $CombinedResults += [PSCustomObject]@{
                Source         = "OnPrem"
                GroupName      = $GroupName
                UserName       = $User.Name
                UserPrincipal  = $User.UserPrincipalName
                Email          = $User.mail
                NestedDepth    = $Depth
            }
        }
        elseif ($Member.objectClass -eq "group") {
            Get-OnPremGroupMembersRecursive -GroupDN $Member.DistinguishedName -GroupName $GroupName -Depth ($Depth + 1)
        }
    }
}

Write-Host "`n[On-Prem AD] Processing..." -ForegroundColor Cyan

if ($GroupDisplayName) {
    $Group = Get-ADGroup -Filter "Name -eq '$GroupDisplayName'" -ErrorAction SilentlyContinue
    if ($Group) {
        Get-OnPremGroupMembersRecursive -GroupDN $Group.DistinguishedName -GroupName $Group.Name
    } else {
        Write-Warning "On-Prem group '$GroupDisplayName' not found."
    }
} else {
    $Groups = Get-ADGroup -Filter * | Sort-Object Name
    foreach ($Group in $Groups) {
        Get-OnPremGroupMembersRecursive -GroupDN $Group.DistinguishedName -GroupName $Group.Name
    }
}

# ====== AAD PART ======
Import-Module Microsoft.Graph -ErrorAction SilentlyContinue

if (-not (Get-MgContext)) {
    Connect-MgGraph -Scopes "Group.Read.All", "User.Read.All", "Directory.Read.All"
}

function Get-AADGroupMembersRecursive {
    param (
        [string]$GroupId,
        [string]$GroupName,
        [int]$Depth = 0
    )

    try {
        $Members = Get-MgGroupMember -GroupId $GroupId -All
    } catch {
        Write-Warning "Failed to fetch AAD members for group $GroupName"
        return
    }

    foreach ($Member in $Members) {
        if ($Member.'@odata.type' -eq "#microsoft.graph.user") {
            $CombinedResults += [PSCustomObject]@{
                Source         = "AzureAD"
                GroupName      = $GroupName
                UserName       = $Member.DisplayName
                UserPrincipal  = $Member.UserPrincipalName
                Email          = $Member.Mail
                NestedDepth    = $Depth
            }
        }
        elseif ($Member.'@odata.type' -eq "#microsoft.graph.group") {
            Get-AADGroupMembersRecursive -GroupId $Member.Id -GroupName $GroupName -Depth ($Depth + 1)
        }
    }
}

Write-Host "`n[Azure AD] Processing..." -ForegroundColor Cyan

if ($GroupDisplayName) {
    $AADGroup = Get-MgGroup -Filter "displayName eq '$GroupDisplayName'" -ErrorAction SilentlyContinue
    if ($AADGroup) {
        Get-AADGroupMembersRecursive -GroupId $AADGroup.Id -GroupName $AADGroup.DisplayName
    } else {
        Write-Warning "AAD group '$GroupDisplayName' not found."
    }
} else {
    $AADGroups = Get-MgGroup -All
    foreach ($Group in $AADGroups) {
        Get-AADGroupMembersRecursive -GroupId $Group.Id -GroupName $Group.DisplayName
    }
}

# ====== EXPORT ======
if ($CombinedResults.Count -gt 0) {
    $CombinedResults | Sort-Object Source, GroupName, UserName | Export-Csv -Path $OutputFile -NoTypeInformation
    Write-Host "`n✅ Combined group membership report saved to: $OutputFile" -ForegroundColor Green
} else {
    Write-Warning "No memberships found in either directory."
}
