# Module stubs and import must be at script level (not in BeforeAll)
# because InModuleScope runs during Pester 5 discovery phase
$moduleNames = @(
    'Microsoft.Graph.Authentication',
    'SvRooij.ContentPrep.Cmdlet'
)

foreach ($name in $moduleNames) {
    if (-not (Get-Module -ListAvailable -Name $name)) {
        New-Module -Name $name -ScriptBlock {
            function Connect-MgGraph { param($Scopes, $TenantId, $ClientSecretCredential, [switch]$NoWelcome) }
            function Get-MgContext {}
            function Invoke-MgGraphRequest { param($Uri, $Method, $Body, $OutputType, [switch]$SkipHttpErrorCheck) }
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

Describe 'New-ProactiveRemediation duplicate check' {
    InModuleScope WingetIntunePublisher {
        It 'skips creation when remediation already exists' {
            Mock Invoke-MgGraphRequest {
                if ($Uri -like '*deviceHealthScripts?*') {
                    return @{ value = @(@{ id = 'existing-rem-123'; displayName = 'TestApp Proactive Update' }) }
                }
            }
            Mock New-WinGetScript { 'script-content' }

            $result = New-ProactiveRemediation -AppId 'Test.App' -AppName 'TestApp' -GroupId 'group-123'

            $result | Should -Be 'existing-rem-123'
            # Should only call GET (the existence check), never POST (creation)
            Should -Invoke Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' } -Times 0
        }

        It 'creates remediation when none exists' {
            Mock Invoke-MgGraphRequest {
                if ($Uri -like '*deviceHealthScripts?*' -and $Method -eq 'GET') {
                    return @{ value = @() }
                }
                if ($Uri -like '*deviceHealthScripts' -and $Method -eq 'POST') {
                    return @{ id = 'new-rem-456'; displayName = 'TestApp Proactive Update' }
                }
                if ($Uri -like '*/assign') {
                    return $null
                }
            }
            Mock New-WinGetScript { 'script-content' }

            $result = New-ProactiveRemediation -AppId 'Test.App' -AppName 'TestApp' -GroupId 'group-123'

            $result | Should -Be 'new-rem-456'
            Should -Invoke Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Uri -like '*deviceHealthScripts' -and $Uri -notlike '*/assign' } -Times 1
        }
    }
}

Describe 'Test-ExistingIntuneApp uses server-side filter' {
    InModuleScope WingetIntunePublisher {
        It 'passes AppName to Get-IntuneApplication for server-side filtering' {
            Mock Get-IntuneApplication { @(@{ displayName = 'Chrome'; description = 'Winget app' }) }

            $result = Test-ExistingIntuneApp -AppName 'Chrome'

            $result.Exists | Should -BeTrue
            Should -Invoke Get-IntuneApplication -ParameterFilter { $AppName -eq 'Chrome' } -Times 1
        }

        It 'returns false when no matching app found' {
            Mock Get-IntuneApplication { @() }

            $result = Test-ExistingIntuneApp -AppName 'NonExistent'

            $result.Exists | Should -BeFalse
        }
    }
}
