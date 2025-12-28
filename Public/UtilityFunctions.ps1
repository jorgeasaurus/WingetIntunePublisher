# UtilityFunctions.ps1
# General utility functions

function Write-IntuneLog {
    param ([string]$LogString)
    
    # Use global LogFile if available, otherwise create one
    if (-not $global:LogFile) {
        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $global:LogFile = Join-Path -Path $env:TEMP -ChildPath "intune-$timestamp.log"
    }
    
    $Stamp = (Get-Date).toString("yyyy/MM/dd HH:mm:ss")
    $LogMessage = "$Stamp $LogString `n"
    Add-Content $global:LogFile -Value $LogMessage
}

function Assert-ModuleInstalled {
    <#
    .SYNOPSIS
    Ensures a PowerShell module is installed from PSGallery.
    #>
    param(
        [Parameter(Mandatory = $true)] [string]$ModuleName,
        [string]$RequiredVersion
    )

    $installed = Get-Module -ListAvailable -Name $ModuleName | Where-Object {
        if ($RequiredVersion) { $_.Version -eq $RequiredVersion } else { $true }
    }

    if ($installed) {
        Write-Host "$ModuleName Already Installed"
        Write-IntuneLog "$ModuleName Already Installed"
    } else {
        Write-Host "Installing module $ModuleName from PSGallery"
        Write-IntuneLog "Installing module $ModuleName from PSGallery"
        
        if ($RequiredVersion) {
            Install-Module $ModuleName -RequiredVersion $RequiredVersion -Scope CurrentUser -Force
        } else {
            Install-Module $ModuleName -Scope CurrentUser -Force
        }
    }
}

function New-TempPath {
    <#
    .SYNOPSIS
    Creates a new directory if it doesn't exist.
    #>
    param(
        [Parameter(Mandatory = $true)] [string]$Path,
        [string]$Description = "directory"
    )

    if (Test-Path $Path) {
        Write-Host "$Description already exists: $Path"
        Write-IntuneLog "$Description already exists: $Path"
    } else {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
        Write-Host "$Description created: $Path"
        Write-IntuneLog "$Description created: $Path"
    }

    return $Path
}
