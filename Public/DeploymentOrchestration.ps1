# DeploymentOrchestration.ps1
# Main orchestration function for deploying Winget apps to Intune

function Deploy-WinGetApp {
    <#
    .SYNOPSIS
    Deploys a Winget application to Intune as a Win32 app with proactive remediation.
    .DESCRIPTION
    Orchestrates the full deployment workflow: creates directory, groups, scripts,
    proactive remediation, IntuneWin package, uploads to Intune, and assigns groups.
    #>
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)] [string]$AppId,
        [Parameter(Mandatory = $true)] [string]$AppName,
        [Parameter(Mandatory = $true)] [string]$BasePath,
        [string]$InstallGroupName,
        [string]$UninstallGroupName,
        [ValidateSet("Device", "User", "Both", "None")] [string]$AvailableInstall = "None",
        [switch]$Force
    )

    Write-Host "========== Deploying $AppName ($AppId) ==========" -ForegroundColor Cyan
    Write-IntuneLog "Starting deployment for $AppName ($AppId)"
    
    # Check if app already exists
    $existingApp = Test-ExistingIntuneApp -AppName $AppName
    if ($existingApp.Exists) {
        Write-Host "WARNING: App '$AppName' already exists in Intune:" -ForegroundColor Yellow
        foreach ($app in $existingApp.Apps) {
            Write-Host "  - $($app.displayName) [ID: $($app.id)]" -ForegroundColor Yellow
        }
        
        if (-not $Force) {
            Write-Host "Skipping deployment. Use -Force parameter to override." -ForegroundColor Yellow
            Write-Host "========== Skipped $AppName ==========" -ForegroundColor Yellow
            return
        }
        else {
            Write-Host "Force parameter detected. Proceeding with deployment..." -ForegroundColor Green
        }
    }

    # 1. Create app directory
    $appPath = New-TempPath -Path (Join-Path $BasePath $AppId) -Description "App directory for $AppName"

    # 2. Create/get groups
    $installGroupId = Get-OrCreateAADGroup -AppId $AppId -AppName $AppName -GroupType "Install" -GroupName $InstallGroupName
    $uninstallGroupId = Get-OrCreateAADGroup -AppId $AppId -AppName $AppName -GroupType "Uninstall" -GroupName $UninstallGroupName

    # 3. Create scripts
    # Sanitize AppId for filenames - remove special characters that cause issues
    $safeAppId = $AppId -replace '[^a-zA-Z0-9._-]', '_'

    $installFilename = "install$safeAppId.ps1"
    $installScriptFile = Join-Path $appPath $installFilename
    New-WinGetScript -AppId $AppId -AppName $AppName -ScriptType "Install" | Out-File $installScriptFile -Encoding utf8
    Write-Host "Created: $installScriptFile"

    $uninstallFilename = "uninstall$safeAppId.ps1"
    $uninstallScriptFile = Join-Path $appPath $uninstallFilename
    New-WinGetScript -AppId $AppId -AppName $AppName -ScriptType "Uninstall" | Out-File $uninstallScriptFile -Encoding utf8
    Write-Host "Created: $uninstallScriptFile"

    $detectionFilename = "detection$safeAppId.ps1"
    $detectionScriptFile = Join-Path $appPath $detectionFilename
    New-WinGetScript -AppId $AppId -AppName $AppName -ScriptType "DetectionRemediation" | Out-File $detectionScriptFile -Encoding utf8
    Write-Host "Created: $detectionScriptFile"

    # 4. Create proactive remediation (if licensed)
    if (Test-ProactiveRemediationLicense) {
        $remediationId = New-ProactiveRemediation -AppId $AppId -AppName $AppName -GroupId $installGroupId
    } else {
        Write-Host "Skipping Proactive Remediation creation - not licensed" -ForegroundColor Yellow
        $remediationId = $null
    }

    # 5. Create IntuneWin package
    # The IntuneWin file will be created without the .ps1 extension in the name
    $intunewinFilename = $installFilename -replace '\.ps1$', ''
    $intunewinPath = Join-Path $BasePath "$intunewinFilename.intunewin"
    New-IntuneWinFile -appid $AppId -appname $AppName -apppath $appPath -setupfilename $installFilename -destpath $BasePath
    Write-Host "Created: $intunewinPath"

    # Brief pause for file system
    Start-Sleep -Seconds 10

    # 5.5. Search for app icon
    $appIcon = Get-AppIcon -AppId $AppId -AppName $AppName

    # 6. Upload Win32 app
    $installCmd = "powershell.exe -ExecutionPolicy Bypass -File $installFilename"
    $uninstallCmd = "powershell.exe -ExecutionPolicy Bypass -File $uninstallFilename"

    try {
        $appUploadResult = New-Win32App -appid $AppId -appname $AppName -appfile $intunewinPath -installcmd $installCmd -uninstallcmd $uninstallCmd -detectionfile $detectionScriptFile -largeIcon $appIcon
        
        if ($appUploadResult) {
            Write-Host "Uploaded $AppName to Intune successfully" -ForegroundColor Green
            
            # 7. Assign groups
            Grant-Win32AppAssignment -AppName $AppName -InstallGroupId $installGroupId -UninstallGroupId $uninstallGroupId -AvailableInstall $AvailableInstall
            Write-Host "Assigned groups to $AppName"
        }
        else {
            Write-Host "Failed to upload $AppName to Intune - no app returned" -ForegroundColor Red
            Write-IntuneLog "Failed to upload $AppName - no app returned"
        }
    }
    catch {
        Write-Host "Error uploading $AppName to Intune: $_" -ForegroundColor Red
        Write-IntuneLog "Error uploading $AppName`: $_"
    }

    Write-Host "========== Completed $AppName ==========" -ForegroundColor Green
    Write-IntuneLog "Completed deployment for $AppName"
}
