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
    .EXAMPLE
    Get-OrCreateAADGroup -AppId "Google.Chrome" -AppName "Google Chrome" -GroupType "Install"
    Creates or retrieves the "Google Chrome Required" group
    .EXAMPLE
    Get-OrCreateAADGroup -AppId "7zip.7zip" -AppName "7-Zip" -GroupType "Uninstall" -WhatIf
    Shows what would happen without creating the group
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='Low')]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$AppId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$AppName,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Install", "Uninstall")]
        [string]$GroupType,

        [Parameter(Mandatory = $false)]
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
    try {
        $escapedName = $GroupName.Replace("'", "''")
        $filter = [uri]::EscapeDataString("displayName eq '$escapedName'")
        $url = "beta/groups?`$filter=$filter"
        $existing = (Invoke-MgGraphRequest -Uri $url -Method GET -OutputType PSObject -SkipHttpErrorCheck -ErrorAction Stop).value

        if ($existing.id) {
            Write-Host "Found existing group: $GroupName" -ForegroundColor Green
            Write-Verbose "Found existing group: $GroupName"
            return $existing.id
        }
    }
    catch {
        Write-Warning "Error checking for existing group: $_"
        throw
    }

    # Create new group with ShouldProcess support
    if ($PSCmdlet.ShouldProcess("Azure AD", "Create security group '$GroupName'")) {
        try {
            $nickname = ($AppId + $GroupType.ToLower()) -replace '[^a-z0-9]', ''
            $descriptionSuffix = "Imported with Winget Intune Publisher - github.com/jorgeasaurus/WingetIntunePublisher"
            $description = if ($GroupType -eq "Install") {
                "Install group for $AppName - $descriptionSuffix"
            } else {
                "Uninstall group for $AppName - $descriptionSuffix"
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
            Write-Host "Created group: $GroupName ($($grp.id))" -ForegroundColor Green
            Write-Verbose "Created group: $GroupName ($($grp.id))"

            return $grp.id
        }
        catch {
            Write-Error "Failed to create group '$GroupName': $_"
            Write-Verbose "Failed to create group '$GroupName': $_"
            throw
        }
    }
    else {
        Write-Host "Group creation skipped due to -WhatIf" -ForegroundColor Yellow
        return $null
    }
}
