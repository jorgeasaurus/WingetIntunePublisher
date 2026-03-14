$moduleNames = @(
    'Microsoft.Graph.Authentication',
    'SvRooij.ContentPrep.Cmdlet'
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
            'Invoke-PopularAppsDeployment',
            'Install-RequiredModule',
            'Connect-ToGraph',
            'Deploy-WinGetApp',
            'Find-WinGetPackage',
            'Get-PopularAppsByCategory',
            'Get-WinGetPackage',
            'Install-WingetIfNeeded',
            'Install-WinGetPackage',
            'Remove-WingetIntuneApps',
            'Uninstall-WinGetPackage',
            'Update-WinGetPackage'
        )

        $exported = (Get-Module WingetIntunePublisher).ExportedFunctions.Keys
        foreach ($fn in $expected) {
            $exported | Should -Contain $fn
        }
    }

    It 'exports the backwards compatibility alias' {
        $aliases = (Get-Module WingetIntunePublisher).ExportedAliases.Keys
        $aliases | Should -Contain 'Assert-ModuleInstalled'
    }

    Context 'Invoke-WingetIntunePublisher' {
        InModuleScope WingetIntunePublisher {
            It 'calls Deploy-WinGetApp for provided app ids' {
                Mock -CommandName Start-Transcript
                Mock -CommandName Stop-Transcript
                Mock -CommandName Install-WingetIfNeeded
                Mock -CommandName Install-RequiredModule
                Mock -CommandName Connect-ToGraph
                Mock -CommandName Disconnect-MgGraph
                Mock -CommandName Deploy-WinGetApp
                Mock -CommandName Find-WinGetPackage { $null }

                $apps = @('Test.App1', 'Test.App2')
                $names = @('App One', 'App Two')

                Invoke-WingetIntunePublisher -appid $apps -appname $names -availableinstall User

                Assert-MockCalled Deploy-WinGetApp -Times $apps.Count -Exactly -ParameterFilter {
                    $AppId -in $apps -and $AppName -in $names -and $BasePath
                }
                Assert-MockCalled Connect-ToGraph -Times 1 -Exactly
                Assert-MockCalled Disconnect-MgGraph -Times 1 -Exactly
            }

            It 'returns only deployment results without pipeline leaks' {
                Mock -CommandName Start-Transcript
                Mock -CommandName Stop-Transcript
                Mock -CommandName Install-WingetIfNeeded
                Mock -CommandName Install-RequiredModule
                Mock -CommandName Connect-ToGraph
                Mock -CommandName Disconnect-MgGraph
                Mock -CommandName Deploy-WinGetApp
                Mock -CommandName Find-WinGetPackage { $null }

                $results = Invoke-WingetIntunePublisher -appid @('Test.App1') -appname @('App One') -availableinstall User

                # Results should only contain deployment result objects, not transcript strings
                $results | ForEach-Object {
                    $_ | Should -BeOfType [PSCustomObject]
                    $_.PSObject.Properties.Name | Should -Contain 'Status'
                }
            }
        }
    }
}

Describe 'Get-Win32AppBody' {
    InModuleScope WingetIntunePublisher {
        It 'creates EXE app body with required fields' {
            $body = Get-Win32AppBody -displayName 'Test' -publisher 'Pub' -description 'Desc' `
                -filename 'test.intunewin' -SetupFileName 'install.ps1' -installExperience 'system' `
                -installCommandLine 'install.ps1' -uninstallCommandLine 'uninstall.ps1'

            $body.'@odata.type' | Should -Be '#microsoft.graph.win32LobApp'
            $body.displayName | Should -Be 'Test'
            $body.publisher | Should -Be 'Pub'
            $body.installCommandLine | Should -Be 'install.ps1'
            $body.uninstallCommandLine | Should -Be 'uninstall.ps1'
        }

        It 'includes largeIcon when provided' {
            $icon = @{ type = 'image/png'; value = 'abc123' }
            $body = Get-Win32AppBody -displayName 'Test' -publisher 'Pub' -description 'Desc' `
                -filename 'test.intunewin' -SetupFileName 'install.ps1' -installExperience 'system' `
                -installCommandLine 'install.ps1' -uninstallCommandLine 'uninstall.ps1' -largeIcon $icon

            $body.largeIcon | Should -Not -BeNullOrEmpty
            $body.largeIcon.type | Should -Be 'image/png'
        }
    }
}
