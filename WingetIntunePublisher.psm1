<#
.SYNOPSIS
    Module loader for WingetIntunePublisher.
.DESCRIPTION
    Dot sources all Private and Public function files and exports the intended public surface.
#>

$script:ModuleRoot = Split-Path -Parent $PSCommandPath

# Load private helpers first
$privatePath = Join-Path -Path $script:ModuleRoot -ChildPath 'Private'
if (Test-Path $privatePath) {
    Get-ChildItem -Path $privatePath -Filter '*.ps1' -File | ForEach-Object {
        . $_.FullName
    }
}

# Load public functions
$publicPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Public'
if (Test-Path $publicPath) {
    Get-ChildItem -Path $publicPath -Filter '*.ps1' -File | ForEach-Object {
        . $_.FullName
    }
}

# Explicitly export the public surface
$publicFunctions = @(
    'Invoke-WingetIntunePublisher'
    'Invoke-PopularAppsDeployment'
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

$publicAliases = @(
    'Assert-ModuleInstalled'
)

Export-ModuleMember -Function $publicFunctions -Alias $publicAliases