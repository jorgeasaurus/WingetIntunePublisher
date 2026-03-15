# Sync-IntunePortfolio.ps1
# Declarative portfolio sync — GitOps for Intune app management

function Sync-IntunePortfolio {
    <#
    .SYNOPSIS
    Synchronizes Intune app deployments to match a declarative portfolio YAML file.

    .DESCRIPTION
    Reads a YAML portfolio file defining desired Intune app state, compares it against
    current Intune deployments, and reconciles the difference. New apps are deployed,
    existing apps are skipped (unless -Force), and orphaned apps can optionally be removed.

    Supports -WhatIf for dry-run drift detection without making changes.

    .PARAMETER Path
    Path to the portfolio YAML file.

    .PARAMETER Tenant
    Azure AD tenant ID or name (e.g., contoso.onmicrosoft.com) for app-based auth.

    .PARAMETER ClientId
    Azure AD application (client) ID for app-based authentication.

    .PARAMETER ClientSecret
    Azure AD application client secret for app-based authentication.

    .PARAMETER Force
    Force redeployment of all apps, even those already present in Intune.

    .PARAMETER RemoveAbsent
    Remove apps from Intune that are managed by WingetIntunePublisher but not in the portfolio file.
    Without this flag, orphaned apps are reported but not removed.

    .EXAMPLE
    Sync-IntunePortfolio -Path ./intune-portfolio.yml -WhatIf
    Shows what changes would be made without deploying anything (drift detection).

    .EXAMPLE
    Sync-IntunePortfolio -Path ./intune-portfolio.yml -Tenant "contoso.onmicrosoft.com" -ClientId $id -ClientSecret $secret
    Deploys new apps from the portfolio using app-based authentication.

    .EXAMPLE
    Sync-IntunePortfolio -Path ./intune-portfolio.yml -RemoveAbsent
    Syncs portfolio and removes any Intune apps no longer in the YAML file.

    .OUTPUTS
    PSCustomObject with Deployed, Skipped, Removed, and Failed arrays.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [ValidatePattern('^[a-zA-Z0-9.\-]+$')]
        [string]$Tenant,

        [Parameter(Mandatory = $false)]
        [ValidatePattern('^[a-fA-F0-9\-]{36}$')]
        [string]$ClientId,

        [Parameter(Mandatory = $false)]
        [string]$ClientSecret,

        [Parameter(Mandatory = $false)]
        [switch]$Force,

        [Parameter(Mandatory = $false)]
        [switch]$RemoveAbsent
    )

    begin {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        Write-Host "`nIntune Portfolio Sync" -ForegroundColor Cyan
        Write-Host "Portfolio: $Path" -ForegroundColor Gray
    }

    process {
        # 1. Parse portfolio file
        Write-Host "`n[1/5] Reading portfolio..." -ForegroundColor White
        try {
            $desiredApps = Read-PortfolioFile -Path $Path
        } catch {
            throw "Failed to read portfolio file: $_"
        }

        if ($Force) {
            foreach ($app in $desiredApps) {
                $app | Add-Member -NotePropertyName 'Force' -NotePropertyValue $true -Force
            }
        }

        Write-Host "  Found $($desiredApps.Count) app(s) in portfolio" -ForegroundColor Gray

        # 2. Connect to Graph
        Write-Host "[2/5] Connecting to Microsoft Graph..." -ForegroundColor White
        try {
            if ($ClientId) {
                Connect-ToGraph -Tenant $Tenant -AppId $ClientId -AppSecret $ClientSecret
            } else {
                $scopes = @(
                    "DeviceManagementApps.ReadWrite.All",
                    "DeviceManagementConfiguration.ReadWrite.All",
                    "Group.ReadWrite.All",
                    "GroupMember.ReadWrite.All",
                    "openid", "profile", "email", "offline_access"
                )
                Connect-ToGraph -Scopes $scopes
            }
        } catch {
            throw "Graph authentication failed: $_"
        }
        Write-Host "  Connected" -ForegroundColor Gray

        # 3. Query current Intune state
        Write-Host "[3/5] Querying Intune app inventory..." -ForegroundColor White
        try {
            $currentApps = @(Get-IntuneApplication)
        } catch {
            throw "Failed to query Intune apps: $_"
        }
        $managedCount = @($currentApps | Where-Object { $_.description -match [regex]::Escape($script:PublisherTag) }).Count
        Write-Host "  Found $($currentApps.Count) total app(s), $managedCount managed by WingetIntunePublisher" -ForegroundColor Gray

        # 4. Compute diff
        Write-Host "[4/5] Computing sync plan..." -ForegroundColor White
        $diff = Compare-PortfolioState -DesiredApps $desiredApps -CurrentApps $currentApps
        Format-PortfolioReport -DiffResult $diff -RemoveAbsent:$RemoveAbsent

        # 5. Execute sync
        Write-Host "[5/5] Executing sync..." -ForegroundColor White

        $results = [PSCustomObject]@{
            Deployed = [System.Collections.Generic.List[PSCustomObject]]::new()
            Skipped  = [System.Collections.Generic.List[PSCustomObject]]::new()
            Removed  = [System.Collections.Generic.List[PSCustomObject]]::new()
            Failed   = [System.Collections.Generic.List[PSCustomObject]]::new()
        }

        # Record skipped apps
        foreach ($app in $diff.UpToDate) {
            $results.Skipped.Add([PSCustomObject]@{
                AppId  = $app.Id
                Name   = $app.Name
                Action = 'Skipped'
                Reason = 'Already deployed'
            })
        }

        # Deploy new/forced apps
        foreach ($app in $diff.ToDeploy) {
            $displayName = if ($app.Name) { $app.Name } else { $app.Id }

            if (-not $PSCmdlet.ShouldProcess($displayName, "Deploy to Intune")) {
                $results.Skipped.Add([PSCustomObject]@{
                    AppId  = $app.Id
                    Name   = $displayName
                    Action = 'Skipped'
                    Reason = 'WhatIf'
                })
                continue
            }

            Write-Host "  Deploying: $($app.Id)" -ForegroundColor Green -NoNewline

            try {
                # Resolve app name from WinGet if not specified
                $appName = $app.Name
                if (-not $appName) {
                    $wingetInfo = Find-WinGetPackage -Id $app.Id
                    if ($wingetInfo) {
                        $appName = $wingetInfo.Name
                    } else {
                        $appName = $app.Id
                    }
                }

                $tempDir = [System.IO.Path]::GetTempPath()
                $sessionId = [guid]::NewGuid().ToString('N').Substring(0, 8)
                $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
                $baseTempPath = Join-Path -Path $tempDir -ChildPath 'WingetIntunePublisher'
                New-Item -Path $baseTempPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
                $basePath = Join-Path -Path $baseTempPath -ChildPath "$sessionId-$timestamp"
                New-Item -Path $basePath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
                $deployParams = @{
                    AppId            = $app.Id
                    AppName          = $appName
                    BasePath         = $basePath
                    AvailableInstall = $app.AvailableInstall
                }

                if ($app.InstallGroupName) { $deployParams['InstallGroupName'] = $app.InstallGroupName }
                if ($app.UninstallGroupName) { $deployParams['UninstallGroupName'] = $app.UninstallGroupName }
                if ($app.Force) { $deployParams['Force'] = $true }

                Deploy-WinGetApp @deployParams

                Write-Host " ✓" -ForegroundColor Green
                $results.Deployed.Add([PSCustomObject]@{
                    AppId  = $app.Id
                    Name   = $appName
                    Action = 'Deployed'
                })
            } catch {
                Write-Host " ✗ $_" -ForegroundColor Red
                $results.Failed.Add([PSCustomObject]@{
                    AppId  = $app.Id
                    Name   = $displayName
                    Action = 'Failed'
                    Error  = $_.ToString()
                })
            } finally {
                if ($basePath -and (Test-Path $basePath)) {
                    Remove-Item -Path $basePath -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }

        # Remove orphaned apps
        if ($RemoveAbsent -and $diff.ToRemove.Count -gt 0) {
            foreach ($orphan in $diff.ToRemove) {
                if (-not $PSCmdlet.ShouldProcess($orphan.DisplayName, "Remove from Intune")) {
                    continue
                }

                Write-Host "  Removing: $($orphan.DisplayName)" -ForegroundColor Red -NoNewline
                try {
                    Remove-WingetIntuneApps -AppName $orphan.DisplayName -Confirm:$false
                    Write-Host " ✓" -ForegroundColor Red
                    $results.Removed.Add([PSCustomObject]@{
                        AppId  = $orphan.IntuneId
                        Name   = $orphan.DisplayName
                        Action = 'Removed'
                    })
                } catch {
                    Write-Host " ✗ $_" -ForegroundColor Red
                    $results.Failed.Add([PSCustomObject]@{
                        AppId  = $orphan.IntuneId
                        Name   = $orphan.DisplayName
                        Action = 'RemoveFailed'
                        Error  = $_.ToString()
                    })
                }
            }
        }
    }

    end {
        $stopwatch.Stop()
        $elapsed = $stopwatch.Elapsed

        # Summary
        Write-Host "`n═══════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host "  Sync Complete ($([math]::Round($elapsed.TotalSeconds))s)" -ForegroundColor Cyan
        Write-Host "  Deployed: $($results.Deployed.Count) | Skipped: $($results.Skipped.Count) | Removed: $($results.Removed.Count) | Failed: $($results.Failed.Count)" -ForegroundColor Gray
        Write-Host "═══════════════════════════════════════════`n" -ForegroundColor Cyan

        if ($results.Failed.Count -gt 0) {
            Write-Warning "$($results.Failed.Count) operation(s) failed. Review the returned results for details."
        }

        return $results
    }
}
