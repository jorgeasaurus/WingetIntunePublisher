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
        [string[]]$appid = @(),
        [string[]]$appname = @(),
        [string]$tenant = "",
        [string]$clientid = "",
        [string]$clientsecret = "",
        [string]$installgroupname = "",
        [string]$uninstallgroupname = "",
        [ValidateSet('User', 'Device', 'Both', 'None')] [string]$availableinstall = "User",
        [switch]$Force
    )

    if (-not $availableinstall) {
        $availableinstall = "None"
    }

    $date = Get-Date -Format yyMMddmmss
    $global:LogFile = "$env:TEMP\intune-$date.log"
    $LogFile2 = "$env:TEMP\intuneauto-$date.log"

    try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}
    Start-Transcript -Path $LogFile2

    New-TempPath -Path "c:\temp" -Description "Base temp directory"

    $random = Get-Random -Maximum 1000
    $date = Get-Date -Format yyMMddmmss
    $path = "c:\temp\$random-$date"

    New-TempPath -Path $path -Description "Session temp directory"

    @(
        'Microsoft.Graph.Authentication'
        'SvRooij.ContentPrep.Cmdlet'
        'Microsoft.PowerShell.ConsoleGuiTools'
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

    if ($appid -and $appid.Count -gt 0) {
        $packs = @()
        for ($i = 0; $i -lt $appid.Count; $i++) {
            $resolvedName = if ($appname.Count -gt $i -and $appname[$i]) {
                $appname[$i]
            } elseif ($appname.Count -eq 1 -and $appname[0]) {
                $appname[0]
            } else {
                $null
            }

            if (-not $resolvedName -and (Get-Command Find-WinGetPackage -ErrorAction SilentlyContinue)) {
                try {
                    $pkg = Find-WinGetPackage -Id $appid[$i] -Exact -AcceptSourceAgreement
                    if ($pkg -and $pkg[0].Name) {
                        $resolvedName = $pkg[0].Name
                    }
                } catch {
                    $resolvedName = $null
                }
            }

            if (-not $resolvedName) {
                $resolvedName = $appid[$i]
            }

            $packs += [pscustomobject]@{
                Id   = $appid[$i].Trim()
                Name = $resolvedName.Trim()
            }
        }
    } else {
        Write-Progress "Loading Winget Packages" -PercentComplete 1
        $packs2 = Find-WinGetPackage '""' # This logic appears to not work, better to remove #TODO
        Write-Progress "Loading Winget Packages" -Completed
        $packs = $packs2 | Out-ConsoleGridView -Title "Available Applications" -OutputMode Multiple
    }

    foreach ($pack in $packs) {
        Deploy-WinGetApp `
            -AppId $pack.Id.Trim() `
            -AppName $pack.Name.Trim() `
            -BasePath $path `
            -InstallGroupName $installgroupname `
            -UninstallGroupName $uninstallgroupname `
            -AvailableInstall $availableinstall `
            -Force:$Force
    }

    Disconnect-MgGraph | Out-Null
    Write-Host "Selected apps have been deployed to Intune" -ForegroundColor Green

    Stop-Transcript
}
