# GroupManagement.ps1
# Azure AD group management functions

function Get-OrCreateAADGroup {
    <#
    .SYNOPSIS
    Gets an existing AAD group by name, or creates a new one if it doesn't exist.
    .PARAMETER AppId
    The Winget package ID (used for mail nickname).
    .PARAMETER AppName
    The display name of the application.
    .PARAMETER GroupType
    Type of group: Install or Uninstall.
    .PARAMETER GroupName
    Optional custom group name. If not provided, uses default naming convention.
    #>
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)] [string]$AppId,
        [Parameter(Mandatory = $true)] [string]$AppName,
        [Parameter(Mandatory = $true)] [ValidateSet("Install", "Uninstall")] [string]$GroupType,
        [string]$GroupName
    )

    # Determine group name and description
    if (-not $GroupName -or $GroupName -eq "") {
        if ($GroupType -eq "Install") {
            $GroupName = "$AppName Required"
        } else {
            $GroupName = "$AppName Uninstall"
        }
    }

    # Check if group already exists
    $escapedName = $GroupName.Replace("'", "''")
    $filter = [uri]::EscapeDataString("displayName eq '$escapedName'")
    $url = "beta/groups?`$filter=$filter"
    $existing = (Invoke-MgGraphRequest -Uri $url -Method GET -OutputType PSObject -SkipHttpErrorCheck -ErrorAction Stop).value
    if ($existing.id) {
        Write-Host "Found existing group: $GroupName"
        Write-IntuneLog "Found existing group: $GroupName"
        return $existing.id
    }

    # Create new group
    $nickname = ($AppId + $GroupType.ToLower()) -replace '[^a-z]', ''
    $description = if ($GroupType -eq "Install") {
        "Group for installation and updating of $AppName application"
    } else {
        "Group for uninstallation of $AppName application"
    }

    $body = @{
        displayName     = $GroupName
        description     = $description
        mailEnabled     = $false
        mailNickname    = $nickname
        securityEnabled = $true
        groupTypes      = @()
    }

    $grp = Invoke-MgGraphRequest -Method POST -Uri "beta/groups" -Body ($body | ConvertTo-Json) -OutputType PSObject -ErrorAction Stop
    Write-Host "Created group: $GroupName ($($grp.id))"
    Write-IntuneLog "Created group: $GroupName ($($grp.id))"

    return $grp.id
}
