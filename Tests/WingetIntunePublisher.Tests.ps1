$moduleNames = @(
    'Microsoft.Graph.Authentication',
    'SvRooij.ContentPrep.Cmdlet',
    'Microsoft.PowerShell.ConsoleGuiTools'
)

foreach ($name in $moduleNames) {
    if (-not (Get-Module -ListAvailable -Name $name)) {
        New-Module -Name $name -ScriptBlock {
            function Connect-MgGraph {}
            function Get-MgContext {}
        } | Import-Module -Force
    }
}

$ModulePath = Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..') -ChildPath 'WingetIntunePublisher.psd1'
Import-Module $ModulePath -Force -ErrorAction Stop

Describe 'WingetIntunePublisher module' {
    It 'imports without error and is loaded' {
        Get-Module WingetIntunePublisher | Should -Not -BeNullOrEmpty
    }

    It 'exports the expected public functions' {
        $expected = @(
            'Invoke-WingetIntunePublisher',
            'Assert-ModuleInstalled',
            'Connect-ToGraph',
            'Deploy-WinGetApp',
            'Find-WinGetPackage',
            'Get-WinGetPackage',
            'Install-WingetIfNeeded',
            'Install-WinGetPackage',
            'New-TempPath',
            'Uninstall-WinGetPackage',
            'Update-WinGetPackage',
            'Write-IntuneLog'
        )

        $exported = (Get-Module WingetIntunePublisher).ExportedFunctions.Keys
        foreach ($fn in $expected) {
            $exported | Should -Contain $fn
        }
    }

    Context 'Invoke-WingetIntunePublisher' {
        InModuleScope WingetIntunePublisher {
            It 'calls Deploy-WinGetApp for provided app ids' {
                Mock -CommandName Start-Transcript
                Mock -CommandName Stop-Transcript
                Mock -CommandName Install-WingetIfNeeded
                Mock -CommandName Write-IntuneLog
                Mock -CommandName New-TempPath { param($Path, $Description) $Path }
                Mock -CommandName Connect-ToGraph
                Mock -CommandName Disconnect-MgGraph
                Mock -CommandName Deploy-WinGetApp

                $apps = @('Test.App1', 'Test.App2')
                $names = @('App One', 'App Two')

                Invoke-WingetIntunePublisher -appid $apps -appname $names -availableinstall User

                Assert-MockCalled Deploy-WinGetApp -Times $apps.Count -Exactly -ParameterFilter {
                    $AppId -in $apps -and $AppName -in $names -and $BasePath
                }
                Assert-MockCalled Connect-ToGraph -Times 1 -Exactly
                Assert-MockCalled Disconnect-MgGraph -Times 1 -Exactly
            }
        }
    }
}
