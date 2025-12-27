function Invoke-PopularAppsDeployment {
    <#
    .SYNOPSIS
        Deploys popular applications by category to Microsoft Intune.

    .DESCRIPTION
        This function provides a streamlined way to deploy curated collections of popular enterprise
        applications to Intune. It uses Get-PopularAppsByCategory to retrieve apps and
        Invoke-WingetIntunePublisher to deploy them efficiently in a single authenticated session.

    .PARAMETER Category
        The category of apps to deploy. Valid categories:
        - Browsers (8 apps)
        - Productivity (10 apps)
        - Communication (9 apps)
        - Development (14 apps)
        - Media (9 apps)
        - Utilities (13 apps)
        - Security (8 apps)
        - Graphics (8 apps)
        - Remote (7 apps)
        - All (86 apps)

    .PARAMETER AppName
        Optional filter to deploy only specific apps from the category. Supports wildcards.
        Can be a single string or array of app names.

    .PARAMETER Tenant
        Optional tenant ID for app-based authentication.

    .PARAMETER ClientId
        Optional Azure AD app registration Client ID for app-based authentication.

    .PARAMETER ClientSecret
        Optional Azure AD app registration Client Secret for app-based authentication.

    .PARAMETER AvailableInstall
        Installation availability. Valid values: User, Device, Both, None. Default: User.

    .PARAMETER Force
        Overwrite deployment even if an app with a matching name already exists.

    .PARAMETER WhatIf
        Shows what apps would be deployed without actually deploying them.

    .EXAMPLE
        Invoke-PopularAppsDeployment -Category Browsers
        Deploys all 8 browsers to Intune.

    .EXAMPLE
        Invoke-PopularAppsDeployment -Category Development -WhatIf
        Shows which development tools would be deployed without deploying them.

    .EXAMPLE
        Invoke-PopularAppsDeployment -Category Utilities -AppName "7-Zip","Everything Search"
        Deploys only 7-Zip and Everything Search from the Utilities category.

    .EXAMPLE
        Invoke-PopularAppsDeployment -Category Security -AppName "*Pass*"
        Deploys all password managers from the Security category (KeePassXC, 1Password).

    .EXAMPLE
        Invoke-PopularAppsDeployment -Category Browsers -Tenant "contoso.onmicrosoft.com" -ClientId "app-guid" -ClientSecret "secret"
        Deploys all browsers using app-based authentication.

    .EXAMPLE
        Invoke-PopularAppsDeployment -Category All -Force
        Force deploys all 86 popular apps, overwriting existing deployments.

    .NOTES
        Requires: Microsoft.Graph.Authentication, SvRooij.ContentPrep.Cmdlet
        Permissions: DeviceManagementApps.ReadWrite.All, Group.ReadWrite.All, DeviceManagementConfiguration.ReadWrite.All
    #>

    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateSet('Browsers', 'Productivity', 'Communication', 'Development', 'Media', 'Utilities', 'Security', 'Graphics', 'Remote', 'All')]
        [string]$Category,

        [Parameter(Mandatory = $false)]
        [string[]]$AppName,

        [Parameter(Mandatory = $false)]
        [string]$Tenant,

        [Parameter(Mandatory = $false)]
        [string]$ClientId,

        [Parameter(Mandatory = $false)]
        [string]$ClientSecret,

        [Parameter(Mandatory = $false)]
        [ValidateSet('User', 'Device', 'Both', 'None')]
        [string]$AvailableInstall = 'User',

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    # Get apps from the specified category
    Write-Host "`n=== Retrieving apps from category: $Category ===" -ForegroundColor Cyan
    $apps = Get-PopularAppsByCategory -Category $Category -ReturnAsObject

    if (-not $apps) {
        Write-Warning "No apps found in category: $Category"
        return
    }

    Write-Host "Found $($apps.Count) apps in category $Category" -ForegroundColor Gray

    # Filter by app name if specified
    if ($AppName) {
        $filteredApps = @()
        foreach ($filter in $AppName) {
            $filteredApps += $apps | Where-Object { $_.AppName -like $filter }
        }

        if (-not $filteredApps) {
            Write-Warning "No apps matched the filter(s): $($AppName -join ', ')"
            return
        }

        $apps = $filteredApps
        Write-Host "Filtered to $($apps.Count) apps matching: $($AppName -join ', ')" -ForegroundColor Yellow
    }

    # Display apps to be deployed
    Write-Host "`nApps to deploy:" -ForegroundColor Yellow
    $apps | ForEach-Object {
        Write-Host "  - $($_.AppName) ($($_.AppId))" -ForegroundColor Gray
    }

    # Confirm deployment
    $confirmMessage = if ($Category -eq 'All') {
        "Deploy all $($apps.Count) popular apps to Intune"
    } else {
        "Deploy $($apps.Count) apps from category '$Category' to Intune"
    }

    if (-not $PSCmdlet.ShouldProcess($confirmMessage, "Deploy apps")) {
        Write-Host "`nDeployment cancelled." -ForegroundColor Yellow
        return
    }

    # Build parameters for Invoke-WingetIntunePublisher
    $deployParams = @{
        appid            = $apps.AppId
        appname          = $apps.AppName
        availableinstall = $AvailableInstall
    }

    if ($Tenant) { $deployParams['tenant'] = $Tenant }
    if ($ClientId) { $deployParams['clientid'] = $ClientId }
    if ($ClientSecret) { $deployParams['clientsecret'] = $ClientSecret }
    if ($Force) { $deployParams['Force'] = $true }

    # Deploy apps
    Write-Host "`n=== Starting deployment ===" -ForegroundColor Cyan
    Write-Host "This will deploy $($apps.Count) apps in a single authenticated session`n" -ForegroundColor Green

    try {
        Invoke-WingetIntunePublisher @deployParams
        Write-Host "`n=== Deployment complete ===" -ForegroundColor Green
        Write-Host "Successfully processed $($apps.Count) apps from category: $Category" -ForegroundColor Cyan
    } catch {
        Write-Error "Deployment failed: $_"
        throw
    }
}
