@{
    # Script module or binary module file associated with this manifest.
    RootModule        = 'WingetIntunePublisher.psm1'

    # Version number of this module.
    ModuleVersion     = '0.2.0'

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
    PowerShellVersion = '5.1'

    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules   = @(
        'Microsoft.Graph.Authentication'
        'SvRooij.ContentPrep.Cmdlet'
    )

    # Functions to export from this module
    FunctionsToExport = @(
        'Invoke-WingetIntunePublisher'
        'Install-RequiredModule'
        'Connect-ToGraph'
        'Deploy-WinGetApp'
        'Find-WinGetPackage'
        'Get-PopularAppsByCategory'
        'Get-WinGetPackage'
        'Install-WingetIfNeeded'
        'Install-WinGetPackage'
        'Remove-WingetIntuneApps'
        'Uninstall-WinGetPackage'
        'Update-WinGetPackage'
    )

    # Cmdlets to export from this module
    CmdletsToExport   = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module
    AliasesToExport   = @('Assert-ModuleInstalled')

    PrivateData       = @{
        PSData = @{
            Tags        = @('Winget', 'Intune', 'Graph', 'Win32App', 'Automation')
            ReleaseNotes = 'Pre-release version - Enterprise security improvements including input validation, code injection prevention, secure credential handling, comprehensive error handling, and performance optimization.'
        }
    }
}
