function Invoke-WingetIntunePublisher {
    <#
.SYNOPSIS
Deploy Winget applications to Microsoft Intune in one run.
.DESCRIPTION
Handles module prerequisite checks, connects to Microsoft Graph (interactive or app auth),
optionally prompts for app selection, and orchestrates deployment via Deploy-WinGetApp.
.PARAMETER appid
One or more Winget App IDs to deploy.
.PARAMETER appname
Optional display names aligned with App IDs (falls back to Winget lookup or AppId).
.PARAMETER tenant
Tenant ID/Name for app-based authentication.
.PARAMETER clientid
Azure AD app registration Client ID for app-based authentication.
.PARAMETER clientsecret
Azure AD app registration Client Secret for app-based authentication.
.PARAMETER installgroupname
Optional custom install group name (auto-generated if omitted).
.PARAMETER uninstallgroupname
Optional custom uninstall group name (auto-generated if omitted).
.PARAMETER availableinstall
Make app available to User, Device, Both, or None (default User).
.PARAMETER Force
Force deployment even if the app already exists in Intune.
#>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateScript({
            foreach ($id in $_) {
                if ([string]::IsNullOrWhiteSpace($id)) {
                    throw "App ID cannot be empty or whitespace"
                }
                if ($id.Length -gt 255) {
                    throw "App ID '$id' exceeds 255 characters"
                }
                if ($id -match '[<>:"|?*\\]') {
                    throw "App ID '$id' contains invalid characters"
                }
            }
            $true
        })]
        [string[]]$appid,

        [ValidateNotNullOrEmpty()]
        [string[]]$appname = @(),

        [ValidatePattern('^[a-zA-Z0-9.-]+$')]
        [string]$tenant = "",

        [ValidatePattern('^[a-fA-F0-9-]{36}$|^$')]
        [string]$clientid = "",

        [string]$clientsecret = "",
        [string]$installgroupname = "",
        [string]$uninstallgroupname = "",

        [ValidateSet('User', 'Device', 'Both', 'None')]
        [string]$availableinstall = "User",

        [switch]$Force
    )

    if (-not $availableinstall) {
        $availableinstall = "None"
    }

    # Use proper timestamp format and unique session ID
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $sessionId = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $global:LogFile = Join-Path -Path $env:TEMP -ChildPath "intune-$timestamp.log"
    $LogFile2 = Join-Path -Path $env:TEMP -ChildPath "intuneauto-$timestamp.log"

    try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}
    Start-Transcript -Path $LogFile2

    # Use system temp directory instead of hardcoded C:\temp
    $baseTempPath = Join-Path -Path $env:TEMP -ChildPath "WingetIntunePublisher"
    New-TempPath -Path $baseTempPath -Description "Base temp directory"

    $path = Join-Path -Path $baseTempPath -ChildPath "$sessionId-$timestamp"
    New-TempPath -Path $path -Description "Session temp directory"

    @(
        'Microsoft.Graph.Authentication'
        'SvRooij.ContentPrep.Cmdlet'
    ) | ForEach-Object {
        Assert-ModuleInstalled -ModuleName $_
    }

    Install-WingetIfNeeded

    Write-IntuneLog "Connecting to Microsoft Graph"

    if ($clientid -and $clientsecret -and $tenant) {
        Connect-ToGraph -Tenant $tenant -AppId $clientid -AppSecret $clientsecret
        Write-IntuneLog "Graph Connection Established"
    } else {
        Connect-ToGraph -Scopes "DeviceManagementApps.ReadWrite.All, DeviceManagementConfiguration.ReadWrite.All, Group.ReadWrite.All, GroupMember.ReadWrite.All, openid, profile, email, offline_access"
    }
    Write-IntuneLog "Graph connection established"

    # Resolve names and correct casing for each appid
    # Use List<T> for better performance instead of array +=
    $packs = [System.Collections.Generic.List[object]]::new()

    for ($i = 0; $i -lt $appid.Count; $i++) {
        $resolvedName = if ($appname.Count -gt $i -and $appname[$i]) {
            $appname[$i]
        } elseif ($appname.Count -eq 1 -and $appname[0]) {
            $appname[0]
        } else {
            $null
        }

        $correctedId = $appid[$i]  # Start with the original ID

        if (Get-Command Find-WinGetPackage -ErrorAction SilentlyContinue) {
            try {
                Write-Host "Resolving package info for: $($appid[$i])" -ForegroundColor Gray

                # Try exact match first
                $pkg = Find-WinGetPackage -Id $appid[$i] -Exact -AcceptSourceAgreement -ErrorAction SilentlyContinue 2>$null

                # If exact match fails, try finding case-insensitive match
                if (-not $pkg) {
                    Write-Host "  Exact match failed, trying case-insensitive search..." -ForegroundColor Gray
                    $allPkgs = Find-WinGetPackage -Id $appid[$i] -AcceptSourceAgreement -ErrorAction SilentlyContinue 2>$null

                    if ($allPkgs) {
                        Write-Host "  Found $($allPkgs.Count) potential matches" -ForegroundColor Gray
                        $pkg = $allPkgs | Where-Object { $_.Id -ieq $appid[$i] } | Select-Object -First 1

                        if (-not $pkg -and $allPkgs.Count -gt 0) {
                            # If no case-insensitive match, show what was found and use first result
                            Write-Host "  Available packages:" -ForegroundColor Yellow
                            $allPkgs | Select-Object -First 5 | ForEach-Object { Write-Host "    - $($_.Id): $($_.Name)" -ForegroundColor Yellow }
                            $pkg = $allPkgs[0]
                        }
                    }
                }

                if ($pkg) {
                    Write-Host "  Found package: $($pkg.Id)" -ForegroundColor Green

                    # Auto-correct the App ID casing
                    if ($pkg.Id -ne $appid[$i]) {
                        Write-Host "Auto-correcting App ID casing: '$($appid[$i])' → '$($pkg.Id)'" -ForegroundColor Cyan
                        $correctedId = $pkg.Id
                    }

                    # Resolve display name if not already provided
                    if (-not $resolvedName -and $pkg.Name) {
                        $resolvedName = $pkg.Name
                        Write-Host "  Resolved name: $resolvedName" -ForegroundColor Green
                    }
                } else {
                    Write-Host "  No package found for ID: $($appid[$i])" -ForegroundColor Yellow
                }
            } catch {
                Write-Warning "Failed to resolve package info for $($appid[$i]): $_"
            }
        }

        if (-not $resolvedName) {
            Write-Warning "Could not resolve display name for '$correctedId'. Using App ID as display name."
            $resolvedName = $correctedId
        }

        $packs.Add([pscustomobject]@{
            Id   = $correctedId.Trim()
            Name = $resolvedName.Trim()
        })
    }

    # Deploy apps with error handling and result tracking
    $deploymentResults = [System.Collections.Generic.List[object]]::new()

    foreach ($pack in $packs) {
        try {
            Write-Host "`nDeploying: $($pack.Name) ($($pack.Id))" -ForegroundColor Cyan

            Deploy-WinGetApp `
                -AppId $pack.Id.Trim() `
                -AppName $pack.Name.Trim() `
                -BasePath $path `
                -InstallGroupName $installgroupname `
                -UninstallGroupName $uninstallgroupname `
                -AvailableInstall $availableinstall `
                -Force:$Force `
                -ErrorAction Stop

            $deploymentResults.Add([PSCustomObject]@{
                AppId = $pack.Id
                AppName = $pack.Name
                Status = 'Success'
                Error = $null
            })

            Write-Host "✓ Successfully deployed: $($pack.Name)" -ForegroundColor Green
        }
        catch {
            $errorMessage = $_.Exception.Message
            Write-Error "✗ Failed to deploy $($pack.Name): $errorMessage"
            Write-IntuneLog "Deployment failed for $($pack.Name): $errorMessage"

            $deploymentResults.Add([PSCustomObject]@{
                AppId = $pack.Id
                AppName = $pack.Name
                Status = 'Failed'
                Error = $errorMessage
            })
        }
    }

    # Display summary
    Write-Host "`n========== Deployment Summary ==========" -ForegroundColor Cyan
    $successCount = ($deploymentResults | Where-Object Status -eq 'Success').Count
    $failedCount = ($deploymentResults | Where-Object Status -eq 'Failed').Count

    Write-Host "Total apps: $($deploymentResults.Count)" -ForegroundColor White
    Write-Host "Successful: $successCount" -ForegroundColor Green
    Write-Host "Failed: $failedCount" -ForegroundColor $(if ($failedCount -gt 0) { 'Red' } else { 'Gray' })

    if ($failedCount -gt 0) {
        Write-Host "`nFailed deployments:" -ForegroundColor Red
        $deploymentResults | Where-Object Status -eq 'Failed' | ForEach-Object {
            Write-Host "  - $($_.AppName): $($_.Error)" -ForegroundColor Red
        }
    }

    Disconnect-MgGraph | Out-Null
    Stop-Transcript

    # Return results for pipeline processing
    return $deploymentResults
}
