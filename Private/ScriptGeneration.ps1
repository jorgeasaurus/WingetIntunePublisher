# ScriptGeneration.ps1
# Script generation functions for Win32 apps and Proactive Remediations

function Test-ProactiveRemediationLicense {
    <#
    .SYNOPSIS
    Checks if the tenant has proper licensing for Proactive Remediations (Device Health Scripts).
    .DESCRIPTION
    Proactive Remediations require one of:
    - Microsoft Intune Plan 2
    - Microsoft Intune Suite
    - Windows 365 Enterprise
    This function attempts to access the deviceHealthScripts endpoint to verify access.
    .OUTPUTS
    Returns $true if licensed, $false otherwise.
    #>
    [cmdletbinding()]
    param()

    try {
        # Try to query the deviceHealthScripts endpoint - this will fail if not licensed
        $response = Invoke-MgGraphRequest -Uri "beta/deviceManagement/deviceHealthScripts?`$top=1" -Method GET -ErrorAction Stop
        Write-Host "Proactive Remediation license check: PASSED" -ForegroundColor Green
        Write-Verbose "Proactive Remediation license check passed"
        return $true
    }
    catch {
        $errorMessage = $_.Exception.Message
        if ($errorMessage -match "403" -or $errorMessage -match "Forbidden" -or $errorMessage -match "license" -or $errorMessage -match "not enabled") {
            Write-Host "Proactive Remediation license check: FAILED - Feature requires Intune Plan 2 or Windows 365 Enterprise license" -ForegroundColor Yellow
            Write-Verbose "Proactive Remediation license check failed - requires Intune Plan 2 or Windows 365 Enterprise"
        }
        else {
            Write-Host "Proactive Remediation license check: FAILED - $errorMessage" -ForegroundColor Yellow
            Write-Verbose "Proactive Remediation license check failed: $errorMessage"
        }
        return $false
    }
}

function New-WinGetScript {
    <#
    .SYNOPSIS
    Generates PowerShell scripts for Winget app installation, uninstallation, and detection.
    .PARAMETER AppId
    The Winget package ID.
    .PARAMETER AppName
    The display name of the application.
    .PARAMETER ScriptType
    Type of script to generate: Install, Uninstall, Detection, Remediation, or DetectionRemediation.
    #>
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)] [string]$AppId,
        [Parameter(Mandatory = $true)] [string]$AppName,
        [Parameter(Mandatory = $true)] 
        [ValidateSet("Install", "Uninstall", "Detection", "Remediation", "DetectionRemediation")]
        [string]$ScriptType
    )

    # Common winget bootstrap code - uses 7zip extraction for reliable SYSTEM context
    $wingetBootstrap = @'
# WinGet Bootstrap - Downloads and extracts winget using 7zip for SYSTEM context
$WingetPath = "$env:ProgramData\Microsoft.DesktopAppInstaller"
$WingetExe = "$WingetPath\winget.exe"
$7zipFolder = "$env:WinDir\Temp\7zip"
$StagingFolder = "$env:WinDir\Temp\WinGet-Stage"

function Install-VisualCpp {
    # Install Visual C++ Redistributable (required for winget)
    $vcPath = "$env:TEMP\vc_redist.x64.exe"
    try {
        Invoke-WebRequest -Uri 'https://aka.ms/vs/17/release/vc_redist.x64.exe' -OutFile $vcPath -UseBasicParsing
        $result = Start-Process $vcPath -ArgumentList "/q /norestart" -Wait -PassThru
        # 0 = success, 1638 = already installed, 3010 = success but reboot needed
        if ($result.ExitCode -notin @(0, 1638, 3010)) {
            Write-Host "VC++ install returned: $($result.ExitCode)"
        }
        Remove-Item $vcPath -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Host "VC++ download/install failed: $_"
    }
}

function Install-WingetWith7Zip {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ProgressPreference = 'SilentlyContinue'

    # Install VC++ first
    Install-VisualCpp

    # Download WinGet msixbundle
    try {
        New-Item -ItemType Directory -Path $StagingFolder -Force | Out-Null
        Invoke-WebRequest -Uri 'https://aka.ms/getwinget' -OutFile "$StagingFolder\Microsoft.DesktopAppInstaller.msixbundle" -UseBasicParsing
    } catch {
        Write-Host "Failed to download WinGet: $_"
        return
    }

    # Download 7zip CLI
    try {
        New-Item -ItemType Directory -Path $7zipFolder -Force | Out-Null
        Invoke-WebRequest -Uri 'https://www.7-zip.org/a/7zr.exe' -OutFile "$7zipFolder\7zr.exe" -UseBasicParsing
        Invoke-WebRequest -Uri 'https://www.7-zip.org/a/7z2408-extra.7z' -OutFile "$7zipFolder\7zr-extra.7z" -UseBasicParsing
        & "$7zipFolder\7zr.exe" x "$7zipFolder\7zr-extra.7z" -o"$7zipFolder" -y | Out-Null
    } catch {
        Write-Host "Failed to download 7zip: $_"
        return
    }

    # Extract WinGet using 7zip
    try {
        New-Item -ItemType Directory -Path $WingetPath -Force | Out-Null
        & "$7zipFolder\7za.exe" x "$StagingFolder\Microsoft.DesktopAppInstaller.msixbundle" -o"$StagingFolder" -y | Out-Null
        & "$7zipFolder\7za.exe" x "$StagingFolder\AppInstaller_x64.msix" -o"$WingetPath" -y | Out-Null
    } catch {
        Write-Host "Failed to extract WinGet: $_"
        return
    }

    # Cleanup
    Remove-Item $StagingFolder -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $7zipFolder -Recurse -Force -ErrorAction SilentlyContinue
}

# Clean up old broken extraction path if it exists
$oldWingetPath = "$env:ProgramData\WinGet"
if (Test-Path "$oldWingetPath\winget.exe") {
    Remove-Item $oldWingetPath -Recurse -Force -ErrorAction SilentlyContinue
}

# Check if running as SYSTEM (WindowsApps winget doesn't work in SYSTEM context)
$isSystem = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name -eq "NT AUTHORITY\SYSTEM"

# Check if winget is available - try multiple locations
$Winget = $null

# Option 1: Extracted winget in ProgramData (preferred for SYSTEM context)
if (Test-Path $WingetExe) {
    $Winget = $WingetExe
}

# Option 2: WindowsApps folder - ONLY for non-SYSTEM context (UWP apps don't work as SYSTEM)
if (-not $Winget -and -not $isSystem) {
    $wingetFolders = Get-ChildItem -Path "$env:ProgramFiles\WindowsApps" -Directory -Filter "Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe" -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending
    foreach ($folder in $wingetFolders) {
        $testPath = Join-Path $folder.FullName "winget.exe"
        if (Test-Path $testPath) {
            $Winget = $testPath
            break
        }
    }
}

# Option 3: User context path
if (-not $Winget) {
    $userPath = "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe"
    if (Test-Path $userPath) { $Winget = $userPath }
}

# If winget not found, install it using 7zip extraction
if (-not $Winget -or -not (Test-Path $Winget)) {
    Install-WingetWith7Zip
    if (Test-Path $WingetExe) {
        $Winget = $WingetExe
    }
}

# Verify winget exists
if (-not $Winget -or -not (Test-Path $Winget)) {
    Write-Host "ERROR: WinGet not available"
    exit 1
}

# Test that winget actually runs (catches DLL issues)
try {
    $testOutput = & $Winget --version 2>&1
    if ($LASTEXITCODE -ne 0 -and $testOutput -notmatch 'v\d') {
        # Winget exists but doesn't run - reinstall
        Write-Host "WinGet found but not functional, reinstalling..."
        Install-WingetWith7Zip
        if (Test-Path $WingetExe) { $Winget = $WingetExe }
    }
} catch {
    Write-Host "WinGet test failed, reinstalling..."
    Install-WingetWith7Zip
    if (Test-Path $WingetExe) { $Winget = $WingetExe }
}
'@

    # Escape AppId and AppName for safe interpolation in generated scripts
    $safeAppId = $AppId.Replace("'", "''").Replace('"', '""').Replace('`', '``')
    $safeAppName = $AppName.Replace("'", "''").Replace('"', '""').Replace('`', '``')

    switch ($ScriptType) {
        "Detection" {
            # Detection script for Proactive Remediation - checks if update is available
            # Escape regex special characters in AppId for -match operator
            $escapedAppId = [regex]::Escape($AppId)
            return @"
$wingetBootstrap
`$upgrades = & `$Winget upgrade --source winget --accept-source-agreements 2>&1
if (`$upgrades -match "$escapedAppId") {
    Write-Host "Upgrade available for $safeAppName"
    exit 1
} else {
    Write-Host "$safeAppName is up to date"
    exit 0
}
"@
        }
        "Remediation" {
            # Remediation script for Proactive Remediation - upgrades the app
            return @"
$wingetBootstrap
& `$Winget upgrade --id "$safeAppId" --source winget --silent --force --accept-package-agreements --accept-source-agreements
exit `$LASTEXITCODE
"@
        }
        "DetectionRemediation" {
            # Detection script for Win32 app - checks if app is installed
            # Escape regex special characters in AppId for -match operator
            $escapedAppId = [regex]::Escape($AppId)
            return @"
$wingetBootstrap
`$installed = & `$Winget list --id "$safeAppId" --source winget --accept-source-agreements 2>&1
if (`$installed -match "$escapedAppId") {
    Write-Host "$safeAppName is installed"
    exit 0
} else {
    Write-Host "$safeAppName is not installed"
    exit 1
}
"@
        }
        "Install" {
            $safeLogName = $AppId -replace '[^a-zA-Z0-9]', '_'
            return @"
# Install script using extracted winget.exe for reliable SYSTEM context
`$LogPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
if (-not (Test-Path `$LogPath)) { New-Item -Path `$LogPath -ItemType Directory -Force | Out-Null }
`$LogFile = Join-Path `$LogPath "${safeLogName}_Install.log"
function Write-Log {
    param([string]`$Message)
    `$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "`$Timestamp - `$Message" | Out-File -FilePath `$LogFile -Append -Encoding utf8
    Write-Host `$Message
}

Write-Log "Starting installation of $safeAppName ($safeAppId)"
Write-Log "Running as: `$([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"

$wingetBootstrap

Write-Log "WinGet executable: `$Winget"

# Run the installation
Write-Log "Installing $safeAppId..."
`$output = & `$Winget install --id "$safeAppId" --source winget --silent --force --accept-package-agreements --accept-source-agreements --scope machine 2>&1
`$exitCode = `$LASTEXITCODE

Write-Log "Output: `$output"
Write-Log "Exit code: `$exitCode"

switch (`$exitCode) {
    0 { Write-Log "Installation completed successfully" }
    -1978335189 { Write-Log "No applicable update found (app may already be installed)"; `$exitCode = 0 }
    -1978335215 { Write-Log "No package found matching the criteria" }
    default {
        `$hexCode = "0x{0:X8}" -f (`$exitCode -band 0xFFFFFFFF)
        Write-Log "Installation completed with exit code: `$exitCode (`$hexCode)"
    }
}

exit `$exitCode
"@
        }
        "Uninstall" {
            $safeLogName = $AppId -replace '[^a-zA-Z0-9]', '_'
            return @"
# Uninstall script using extracted winget.exe for reliable SYSTEM context
`$LogPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
if (-not (Test-Path `$LogPath)) { New-Item -Path `$LogPath -ItemType Directory -Force | Out-Null }
`$LogFile = Join-Path `$LogPath "${safeLogName}_Uninstall.log"
function Write-Log {
    param([string]`$Message)
    `$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "`$Timestamp - `$Message" | Out-File -FilePath `$LogFile -Append -Encoding utf8
    Write-Host `$Message
}

Write-Log "Starting uninstallation of $safeAppName ($safeAppId)"
Write-Log "Running as: `$([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"

$wingetBootstrap

Write-Log "WinGet executable: `$Winget"

# Run the uninstallation
Write-Log "Uninstalling $safeAppId..."
`$output = & `$Winget uninstall --id "$safeAppId" --source winget --silent --force --accept-source-agreements 2>&1
`$exitCode = `$LASTEXITCODE

Write-Log "Output: `$output"
Write-Log "Exit code: `$exitCode"

switch (`$exitCode) {
    0 { Write-Log "Uninstallation completed successfully" }
    -1978335212 { Write-Log "Package not found (may already be uninstalled)"; `$exitCode = 0 }
    default {
        `$hexCode = "0x{0:X8}" -f (`$exitCode -band 0xFFFFFFFF)
        Write-Log "Uninstallation completed with exit code: `$exitCode (`$hexCode)"
    }
}

exit `$exitCode
"@
        }
    }
}

function New-ProactiveRemediation {
    <#
    .SYNOPSIS
    Creates a Proactive Remediation (Device Health Script) in Intune for automatic app updates.
    .PARAMETER AppId
    The Winget package ID.
    .PARAMETER AppName
    The display name of the application.
    .PARAMETER GroupId
    The Azure AD group ID to assign the remediation to.
    #>
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)] [string]$AppId,
        [Parameter(Mandatory = $true)] [string]$AppName,
        [Parameter(Mandatory = $true)] [string]$GroupId
    )

    $detectionScript = New-WinGetScript -AppId $AppId -AppName $AppName -ScriptType "Detection"
    $remediationScript = New-WinGetScript -AppId $AppId -AppName $AppName -ScriptType "Remediation"
    
    $detectionBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($detectionScript))
    $remediationBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($remediationScript))

    $descriptionSuffix = "Imported with Winget Intune Publisher - github.com/jorgeasaurus/WingetIntunePublisher"
    $body = @{
        "@odata.type"                       = "#microsoft.graph.deviceHealthScript"
        publisher                           = "Winget"
        displayName                        = "$AppName Proactive Update"
        description                        = "Auto-update remediation for $AppName - $descriptionSuffix"
        detectionScriptContent             = $detectionBase64
        remediationScriptContent           = $remediationBase64
        runAs32Bit                         = $false
        runAsAccount                       = "system"
        enforceSignatureCheck              = $false
        roleScopeTagIds                    = @("0")
        isGlobalScript                     = $false
        detectionScriptParameters          = @()
        remediationScriptParameters        = @()
    }
    
    $result = Invoke-MgGraphRequest -Uri "beta/deviceManagement/deviceHealthScripts" -Method POST -Body ($body | ConvertTo-Json) -ErrorAction Stop

    # Assign to group
    $assignBody = @{
        deviceHealthScriptAssignments = @(
            @{
                "@odata.type"      = "#microsoft.graph.deviceHealthScriptAssignment"
                runRemediationScript = $true
                runSchedule        = @{
                    "@odata.type" = "#microsoft.graph.deviceHealthScriptDailySchedule"
                    interval      = 1
                    time          = "09:00"
                    useUtc        = $false
                }
                target             = @{
                    "@odata.type" = "#microsoft.graph.groupAssignmentTarget"
                    groupId       = $GroupId
                }
            }
        )
    }

    $assignUri = "beta/deviceManagement/deviceHealthScripts/$($result.id)/assign"
    Invoke-MgGraphRequest -Uri $assignUri -Method POST -Body ($assignBody | ConvertTo-Json -Depth 10) -ErrorAction Stop

    Write-Verbose "Created proactive remediation: $($result.displayName) $($result.id)"

    return $result.id
}
