# Module stubs and import must be at script level (not in BeforeAll)
# because InModuleScope runs during Pester 5 discovery phase
$moduleNames = @(
    'Microsoft.Graph.Authentication',
    'SvRooij.ContentPrep.Cmdlet'
)

foreach ($name in $moduleNames) {
    if (-not (Get-Module -ListAvailable -Name $name)) {
        New-Module -Name $name -ScriptBlock {
            function Connect-MgGraph {}
            function Get-MgContext {}
            function Invoke-MgGraphRequest {}
            function Disconnect-MgGraph {}
        } | Import-Module -Force
    }
}

$ModulePath = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'WingetIntunePublisher.psd1'
Import-Module $ModulePath -Force -ErrorAction Stop

Describe 'Get-PopularAppsByCategory' {
    It 'returns a hashtable for a specific category' {
        $result = Get-PopularAppsByCategory -Category Browsers
        $result | Should -BeOfType [hashtable]
        $result.Keys | Should -Contain 'Google.Chrome'
    }

    It 'returns all categories when All is specified' {
        $result = Get-PopularAppsByCategory -Category All
        $result | Should -BeOfType [hashtable]
        $result.Count | Should -BeGreaterThan 50
    }

    It 'returns objects when ReturnAsObject is specified' {
        $result = Get-PopularAppsByCategory -Category Browsers -ReturnAsObject
        $result | Should -Not -BeNullOrEmpty
        $result[0].PSObject.Properties.Name | Should -Contain 'AppId'
        $result[0].PSObject.Properties.Name | Should -Contain 'AppName'
    }

    It 'rejects invalid category' {
        { Get-PopularAppsByCategory -Category 'NotACategory' } | Should -Throw
    }
}

Describe 'New-WinGetScript' {
    InModuleScope WingetIntunePublisher {
        It 'generates an Install script containing the AppId' {
            $script = New-WinGetScript -AppId 'Test.App' -AppName 'Test App' -ScriptType 'Install'
            $script | Should -Match 'Test\.App'
            $script | Should -Match 'install'
        }

        It 'generates an Uninstall script' {
            $script = New-WinGetScript -AppId 'Test.App' -AppName 'Test App' -ScriptType 'Uninstall'
            $script | Should -Match 'uninstall'
        }

        It 'generates a Detection script' {
            $script = New-WinGetScript -AppId 'Test.App' -AppName 'Test App' -ScriptType 'Detection'
            $script | Should -Match 'upgrade'
        }

        It 'generates a Remediation script' {
            $script = New-WinGetScript -AppId 'Test.App' -AppName 'Test App' -ScriptType 'Remediation'
            $script | Should -Match 'upgrade'
        }

        It 'generates a DetectionRemediation script' {
            $script = New-WinGetScript -AppId 'Test.App' -AppName 'Test App' -ScriptType 'DetectionRemediation'
            $script | Should -Match 'list'
        }

        It 'escapes special characters in AppId' {
            $script = New-WinGetScript -AppId "Test's.App" -AppName 'Test App' -ScriptType 'Install'
            $script | Should -Not -BeNullOrEmpty
        }

        It 'includes winget bootstrap code' {
            $script = New-WinGetScript -AppId 'Test.App' -AppName 'Test App' -ScriptType 'Install'
            $script | Should -Match 'Install-WingetWith7Zip'
            $script | Should -Match 'WingetExe'
        }
    }
}

Describe 'Get-IntuneApplication' {
    InModuleScope WingetIntunePublisher {
        It 'escapes single quotes in AppName' {
            Mock -CommandName Invoke-GraphPaged { @() }

            Get-IntuneApplication -AppName "Test's App"

            Should -Invoke Invoke-GraphPaged -ParameterFilter {
                $Uri -match "Test%27%27s"
            } -Times 1
        }

        It 'uses OData filter when Filter parameter provided' {
            Mock -CommandName Invoke-GraphPaged { @() }

            Get-IntuneApplication -Filter "startswith(displayName,'Test')"

            Should -Invoke Invoke-GraphPaged -ParameterFilter {
                $Uri -match 'filter='
            } -Times 1
        }

        It 'returns all apps when no filter specified' {
            Mock -CommandName Invoke-GraphPaged { @() }

            Get-IntuneApplication

            Should -Invoke Invoke-GraphPaged -ParameterFilter {
                $Uri -eq 'beta/deviceAppManagement/mobileApps/'
            } -Times 1
        }
    }
}

Describe 'Module PublisherTag constant' {
    InModuleScope WingetIntunePublisher {
        It 'defines the PublisherTag variable' {
            $script:PublisherTag | Should -Not -BeNullOrEmpty
            $script:PublisherTag | Should -Match 'WingetIntunePublisher'
        }
    }
}

Describe 'Get-DefaultReturnCodes' {
    InModuleScope WingetIntunePublisher {
        It 'returns 5 default return codes' {
            $codes = Get-DefaultReturnCodes
            $codes.Count | Should -Be 5
        }

        It 'includes success code 0' {
            $codes = Get-DefaultReturnCodes
            ($codes | Where-Object { $_.returnCode -eq 0 }).type | Should -Be 'success'
        }

        It 'includes softReboot code 3010' {
            $codes = Get-DefaultReturnCodes
            ($codes | Where-Object { $_.returnCode -eq 3010 }).type | Should -Be 'softReboot'
        }
    }
}

Describe 'Connect-ToGraph parameter validation' {
    It 'has Tenant parameter' {
        $cmd = Get-Command Connect-ToGraph
        $cmd.Parameters.Keys | Should -Contain 'Tenant'
    }

    It 'has AppId parameter' {
        $cmd = Get-Command Connect-ToGraph
        $cmd.Parameters.Keys | Should -Contain 'AppId'
    }

    It 'has AppSecret parameter' {
        $cmd = Get-Command Connect-ToGraph
        $cmd.Parameters.Keys | Should -Contain 'AppSecret'
    }
}

Describe 'Install-RequiredModule' {
    It 'reports already-installed modules without error' {
        Install-RequiredModule -ModuleName 'Pester' -Confirm:$false
    }
}
