@{
    # Script module or binary module file associated with this manifest.
    RootModule        = 'WingetIntunePublisher.psm1'

    # Version number of this module.
    ModuleVersion     = '0.1.0'

    # Supported PSEditions
    CompatiblePSEditions = @('Desktop', 'Core')

    # ID used to uniquely identify this module
    GUID              = 'b918bea8-eed2-41b3-b9b2-24deef437e41'

    # Author of this module
    Author            = 'Jorgeasaurus'

    # Company or vendor of this module
    CompanyName       = 'WingetIntunePublisher'

    # Copyright statement for this module
    Copyright         = '(c) 2025 Jorgeasaurus. All rights reserved.'

    # Description of the functionality provided by this module
    Description       = 'Utilities to package and publish WinGet applications to Microsoft Intune as Win32 apps, create AAD groups, and optionally set up Proactive Remediations in one run.'

    # Minimum version of the Windows PowerShell engine required by this module
    PowerShellVersion = '6.0'

    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules   = @(
        'Microsoft.Graph.Authentication'
        'SvRooij.ContentPrep.Cmdlet'
        'Microsoft.PowerShell.ConsoleGuiTools'
    )

    # Functions to export from this module
    FunctionsToExport = @(
        'Invoke-WingetIntunePublisher'
        'Assert-ModuleInstalled'
        'Connect-ToGraph'
        'Deploy-WinGetApp'
        'Find-WinGetPackage'
        'Get-WinGetPackage'
        'Install-WingetIfNeeded'
        'Install-WinGetPackage'
        'New-TempPath'
        'Uninstall-WinGetPackage'
        'Update-WinGetPackage'
        'Write-IntuneLog'
    )

    # Cmdlets to export from this module
    CmdletsToExport   = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module
    AliasesToExport   = @()

    PrivateData       = @{
        PSData = @{
            Tags        = @('Winget', 'Intune', 'Graph', 'Win32App', 'Automation')
            ReleaseNotes = 'Initial module packaging.'
        }
    }
}
