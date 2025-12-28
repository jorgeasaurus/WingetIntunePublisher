# UtilityFunctions.ps1
# General utility functions

function Install-RequiredModule {
    <#
    .SYNOPSIS
    Installs a PowerShell module if not already present.

    .DESCRIPTION
    Checks if a module is installed and installs from PSGallery if missing.
    Supports WhatIf and Confirm for safety.

    .PARAMETER ModuleName
    Name of the module to install.

    .PARAMETER RequiredVersion
    Optional version requirement.

    .EXAMPLE
    Install-RequiredModule -ModuleName 'Microsoft.Graph.Authentication'

    .EXAMPLE
    Install-RequiredModule -ModuleName 'SvRooij.ContentPrep.Cmdlet' -RequiredVersion '0.4.0'
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ModuleName,

        [Parameter(Mandatory = $false)]
        [version]$RequiredVersion
    )

    begin {
        Write-Verbose "Checking module installation: $ModuleName"
    }

    process {
        try {
            $installed = Get-Module -ListAvailable -Name $ModuleName -ErrorAction Stop |
                Where-Object {
                    if ($RequiredVersion) { $_.Version -eq $RequiredVersion } else { $true }
                } | Select-Object -First 1

            if ($installed) {
                Write-Verbose "$ModuleName v$($installed.Version) already installed"
                Write-Host "$ModuleName v$($installed.Version) already installed" -ForegroundColor Green
                return
            }

            if ($PSCmdlet.ShouldProcess($ModuleName, 'Install module from PSGallery')) {
                $installParams = @{
                    Name  = $ModuleName
                    Scope = 'CurrentUser'
                    Force = $true
                    ErrorAction = 'Stop'
                }

                if ($RequiredVersion) {
                    $installParams['RequiredVersion'] = $RequiredVersion
                }

                Write-Verbose "Installing $ModuleName from PSGallery"
                Write-Host "Installing module $ModuleName from PSGallery" -ForegroundColor Cyan
                Install-Module @installParams
                Write-Verbose "$ModuleName installed successfully"
                Write-Host "$ModuleName installed successfully" -ForegroundColor Green
            }
        }
        catch {
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'ModuleInstallationFailed',
                [System.Management.Automation.ErrorCategory]::NotSpecified,
                $ModuleName
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
    }
}

# Legacy alias for backwards compatibility
Set-Alias -Name Assert-ModuleInstalled -Value Install-RequiredModule
