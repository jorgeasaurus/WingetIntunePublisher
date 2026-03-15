# PortfolioHelpers.ps1
# Internal helpers for declarative portfolio sync

function Read-PortfolioFile {
    <#
    .SYNOPSIS
    Parses and validates an Intune portfolio YAML file.
    .PARAMETER Path
    Path to the portfolio YAML file.
    .OUTPUTS
    Array of PSCustomObjects with resolved app entries (Id, Name, AvailableInstall, InstallGroupName, UninstallGroupName).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$Path
    )

    Install-RequiredModule -ModuleName 'powershell-yaml'

    $raw = Get-Content -Path $Path -Raw -ErrorAction Stop
    $portfolio = ConvertFrom-Yaml -Yaml $raw -ErrorAction Stop

    if (-not $portfolio.apps -or $portfolio.apps.Count -eq 0) {
        throw "Portfolio file contains no apps. Add an 'apps' list with at least one entry."
    }

    # Resolve defaults
    $defaultAvailableInstall = 'User'
    if ($portfolio.defaults -and $portfolio.defaults.availableInstall) {
        $valid = @('User', 'Device', 'Both', 'None')
        if ($portfolio.defaults.availableInstall -notin $valid) {
            throw "Invalid defaults.availableInstall '$($portfolio.defaults.availableInstall)'. Must be one of: $($valid -join ', ')"
        }
        $defaultAvailableInstall = $portfolio.defaults.availableInstall
    }

    $entries = [System.Collections.Generic.List[PSCustomObject]]::new()
    $seenIds = @{}

    foreach ($app in $portfolio.apps) {
        if (-not $app.id) {
            throw "Each app entry must have an 'id' field (WinGet package ID)."
        }

        $appId = $app.id.Trim()
        if ($seenIds.ContainsKey($appId.ToLower())) {
            throw "Duplicate app ID in portfolio: '$appId'"
        }
        $seenIds[$appId.ToLower()] = $true

        # Per-app availableInstall overrides default
        $availableInstall = $defaultAvailableInstall
        if ($app.availableInstall) {
            $valid = @('User', 'Device', 'Both', 'None')
            if ($app.availableInstall -notin $valid) {
                throw "Invalid availableInstall '$($app.availableInstall)' for app '$appId'. Must be one of: $($valid -join ', ')"
            }
            $availableInstall = $app.availableInstall
        }

        $entry = [PSCustomObject]@{
            Id                 = $appId
            Name               = if ($app.name) { $app.name.Trim() } else { $null }
            AvailableInstall   = $availableInstall
            InstallGroupName   = if ($app.groups -and $app.groups.install) { $app.groups.install } else { $null }
            UninstallGroupName = if ($app.groups -and $app.groups.uninstall) { $app.groups.uninstall } else { $null }
            Force              = if ($app.force) { [bool]$app.force } else { $false }
        }

        $entries.Add($entry)
    }

    return $entries.ToArray()
}

function Compare-PortfolioState {
    <#
    .SYNOPSIS
    Compares desired portfolio entries against current Intune state.
    .PARAMETER DesiredApps
    Array of portfolio entries from Read-PortfolioFile.
    .PARAMETER CurrentApps
    Array of Intune app objects from Get-IntuneApplication.
    .OUTPUTS
    PSCustomObject with ToDeploy, UpToDate, and Unmanaged arrays.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject[]]$DesiredApps,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$CurrentApps
    )

    # Filter to only apps managed by this module
    $managedApps = $CurrentApps | Where-Object {
        $_.description -and $_.description -match [regex]::Escape($script:PublisherTag)
    }

    # Build lookup of managed app display names (lowercase) for matching
    $managedLookup = @{}
    foreach ($app in $managedApps) {
        $managedLookup[$app.displayName.ToLower()] = $app
    }

    $toDeploy = [System.Collections.Generic.List[PSCustomObject]]::new()
    $upToDate = [System.Collections.Generic.List[PSCustomObject]]::new()
    $matchedNames = @{}

    foreach ($desired in $DesiredApps) {
        $displayName = if ($desired.Name) { $desired.Name } else { $desired.Id }
        $found = $false

        # Try matching by display name
        if ($managedLookup.ContainsKey($displayName.ToLower())) {
            $found = $true
            $matchedNames[$displayName.ToLower()] = $true
        }

        # Also try matching by app ID in display name (some apps use the ID as name)
        if (-not $found -and $managedLookup.ContainsKey($desired.Id.ToLower())) {
            $found = $true
            $matchedNames[$desired.Id.ToLower()] = $true
        }

        # Search managed apps for partial match in displayName or description containing the app ID
        if (-not $found) {
            foreach ($mApp in $managedApps) {
                if ($mApp.displayName -like "*$($desired.Id)*" -or
                    ($mApp.description -and $mApp.description -like "*$($desired.Id)*")) {
                    $found = $true
                    $matchedNames[$mApp.displayName.ToLower()] = $true
                    break
                }
            }
        }

        if ($found -and -not $desired.Force) {
            $upToDate.Add($desired)
        } else {
            $toDeploy.Add($desired)
        }
    }

    # Unmanaged: managed apps in Intune not present in the portfolio
    $toRemove = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($mApp in $managedApps) {
        if (-not $matchedNames.ContainsKey($mApp.displayName.ToLower())) {
            $toRemove.Add([PSCustomObject]@{
                IntuneId    = $mApp.id
                DisplayName = $mApp.displayName
            })
        }
    }

    return [PSCustomObject]@{
        ToDeploy  = $toDeploy.ToArray()
        UpToDate  = $upToDate.ToArray()
        ToRemove  = $toRemove.ToArray()
    }
}

function Format-PortfolioReport {
    <#
    .SYNOPSIS
    Displays a formatted sync plan to the console.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$DiffResult,

        [Parameter(Mandatory = $false)]
        [switch]$RemoveAbsent
    )

    $totalDesired = $DiffResult.ToDeploy.Count + $DiffResult.UpToDate.Count

    Write-Host "`n═══════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  Intune Portfolio Sync Plan" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  Portfolio apps: $totalDesired | Deploy: $($DiffResult.ToDeploy.Count) | Up to date: $($DiffResult.UpToDate.Count) | Orphaned: $($DiffResult.ToRemove.Count)" -ForegroundColor Gray
    Write-Host ""

    if ($DiffResult.ToDeploy.Count -gt 0) {
        Write-Host "  TO DEPLOY:" -ForegroundColor Green
        foreach ($app in $DiffResult.ToDeploy) {
            $label = if ($app.Force) { "(force)" } else { "(new)" }
            $name = if ($app.Name) { "$($app.Id) ($($app.Name))" } else { $app.Id }
            Write-Host "    + $name $label" -ForegroundColor Green
        }
        Write-Host ""
    }

    if ($DiffResult.UpToDate.Count -gt 0) {
        Write-Host "  UP TO DATE:" -ForegroundColor DarkGray
        foreach ($app in $DiffResult.UpToDate) {
            $name = if ($app.Name) { "$($app.Id) ($($app.Name))" } else { $app.Id }
            Write-Host "    = $name" -ForegroundColor DarkGray
        }
        Write-Host ""
    }

    if ($DiffResult.ToRemove.Count -gt 0) {
        $color = if ($RemoveAbsent) { 'Red' } else { 'Yellow' }
        $label = if ($RemoveAbsent) { 'TO REMOVE:' } else { 'ORPHANED (use -RemoveAbsent to remove):' }
        Write-Host "  $label" -ForegroundColor $color
        foreach ($app in $DiffResult.ToRemove) {
            Write-Host "    - $($app.DisplayName)" -ForegroundColor $color
        }
        Write-Host ""
    }

    Write-Host "═══════════════════════════════════════════`n" -ForegroundColor Cyan
}
